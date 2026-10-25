// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

interface IPoolKeySource {
    function poolKey() external view returns (PoolKey memory);
}

interface ILedgerOrigin {
    function activated() external view returns (bool);
    function ledgerOrigin() external view returns (uint64);
}

interface IBurnableToken {
    function burn(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
}

/// @title Buyback
/// @notice Receives realised game surplus (the controller's `surplusSink`) and, from `startTime()`
///         (the engine's ledger origin plus `delay`: the end of genesis), spends it buying ENGINE on the canonical pool and burning it.
///         Permissionless and rate-limited: at most `maxPerCall` ETH per call, one call per
///         `minInterval`, and each buy stops at `maxImpactBps` of price movement. The caller earns
///         `bountyBps` of the ETH actually spent. Swaps are exempt from the hook fee (set on the hook).
/// @dev Slicing and the impact cap bound sandwich losses to roughly one slice's impact; an attacker
///      also pays the 2 % hook fee on both legs of a sandwich. The contract holds no ENGINE after a
///      call and can send ETH nowhere but the pool and the caller's bounty.
contract Buyback is IUnlockCallback, ReentrancyGuard {
    using StateLibrary for IPoolManager;

    uint256 internal constant BPS = 10_000;

    IPoolManager public immutable poolManager;
    IBurnableToken public immutable token;
    IPoolKeySource public immutable keySource;
    ILedgerOrigin public immutable ledger;
    uint256 public immutable delay;

    address public governance;
    address public guardian;
    bool public paused;
    uint256 public maxPerCall;
    uint256 public minInterval;
    uint16 public maxImpactBps;
    uint16 public bountyBps;
    uint256 public lastBuyAt;

    uint256 public totalEthSpent;
    uint256 public totalBurned;

    event Received(address indexed from, uint256 amount);
    event BoughtAndBurned(address indexed caller, uint256 ethIn, uint256 burned, uint256 bounty);
    event ParamSet(bytes4 indexed selector);

    error NotStarted();
    error TooSoon();
    error NothingToSpend();
    error IsPaused();
    error NotGovernance();
    error NotGuardian();
    error InvalidConfig();
    error NotPoolManager();

    constructor(
        IPoolManager manager,
        address token_,
        address keySource_,
        address ledger_,
        uint256 delay_,
        address governance_,
        address guardian_,
        uint256 maxPerCall_,
        uint256 minInterval_,
        uint16 maxImpactBps_,
        uint16 bountyBps_
    ) {
        poolManager = manager;
        token = IBurnableToken(token_);
        keySource = IPoolKeySource(keySource_);
        ledger = ILedgerOrigin(ledger_);
        delay = delay_;
        governance = governance_;
        guardian = guardian_;
        _set(maxPerCall_, minInterval_, maxImpactBps_, bountyBps_);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice First time buybacks may run: genesis end. `type(uint256).max` before the game opens.
    function startTime() public view returns (uint256) {
        if (!ledger.activated()) return type(uint256).max;
        return uint256(ledger.ledgerOrigin()) + delay;
    }

    /// @notice Buys ENGINE with up to `maxPerCall` ETH and burns all of it. Anyone.
    function buyAndBurn() external nonReentrant returns (uint256 burned) {
        if (paused) revert IsPaused();
        if (block.timestamp < startTime()) revert NotStarted();
        if (lastBuyAt != 0 && block.timestamp < lastBuyAt + minInterval) revert TooSoon();
        uint256 available = address(this).balance;
        if (available == 0) revert NothingToSpend();
        uint256 slice = available < maxPerCall ? available : maxPerCall;
        uint256 spend = slice - slice * bountyBps / BPS;
        lastBuyAt = block.timestamp;

        PoolKey memory key = keySource.poolKey();
        (uint160 price,,,) = poolManager.getSlot0(key.toId());
        // ETH in moves sqrtPrice (ENGINE per ETH) down; stop at sqrt(1 - impact) of the current price.
        uint160 limit = uint160(FP.fullMulDiv(price, FP.sqrt((BPS - maxImpactBps) * 1e18), FP.sqrt(BPS * 1e18)));
        bytes memory r = poolManager.unlock(abi.encode(key, spend, limit));
        (uint256 ethIn, uint256 out) = abi.decode(r, (uint256, uint256));
        burned = out;
        token.burn(out);
        uint256 bounty = ethIn * bountyBps / BPS;
        totalEthSpent += ethIn;
        totalBurned += out;
        if (bounty != 0) SafeTransferLib.forceSafeTransferETH(msg.sender, bounty);
        emit BoughtAndBurned(msg.sender, ethIn, out, bounty);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (PoolKey memory key, uint256 spend, uint160 limit) = abi.decode(data, (PoolKey, uint256, uint160));
        BalanceDelta d = poolManager.swap(
            key, SwapParams({zeroForOne: true, amountSpecified: -int256(spend), sqrtPriceLimitX96: limit}), ""
        );
        uint256 ethIn = uint256(int256(-d.amount0()));
        uint256 out = uint256(int256(d.amount1()));
        poolManager.settle{value: ethIn}();
        poolManager.take(key.currency1, address(this), out);
        return abi.encode(ethIn, out);
    }

    function setPaused(bool value) external {
        if (msg.sender != guardian && msg.sender != governance) revert NotGuardian();
        paused = value;
    }

    function setParams(uint256 maxPerCall_, uint256 minInterval_, uint16 maxImpactBps_, uint16 bountyBps_) external {
        if (msg.sender != governance) revert NotGovernance();
        emit ParamSet(msg.sig);
        _set(maxPerCall_, minInterval_, maxImpactBps_, bountyBps_);
    }

    function _set(uint256 maxPerCall_, uint256 minInterval_, uint16 maxImpactBps_, uint16 bountyBps_) internal {
        if (maxPerCall_ == 0 || maxImpactBps_ == 0 || maxImpactBps_ > 1_000 || bountyBps_ > 100) revert InvalidConfig();
        maxPerCall = maxPerCall_;
        minInterval = minInterval_;
        maxImpactBps = maxImpactBps_;
        bountyBps = bountyBps_;
    }
}
