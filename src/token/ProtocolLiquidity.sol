// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

/// @title ProtocolLiquidity
/// @notice Opens the canonical ETH/ENGINE Uniswap v4 pool and owns its protocol liquidity: a single
///         full-range position. There is no function that removes liquidity, so the opening
///         liquidity and every later protocol-owned addition are locked permanently.
/// @dev The pool's LP fee is 0; the hook's ETH fee is the pool's whole fee, so the position earns
///      nothing to collect. `addLiquidity` (treasury or governance) buys half of the ETH sent into
///      ENGINE fee-exempt and adds both, bounded by a caller-supplied price limit.
contract ProtocolLiquidity is IUnlockCallback, ReentrancyGuard {
    using StateLibrary for IPoolManager;

    int24 public constant TICK_SPACING = 200;
    int24 public constant TICK_LOWER = -887_200;
    int24 public constant TICK_UPPER = 887_200;

    IPoolManager public immutable poolManager;
    address public immutable token;
    address public immutable hook;
    address public governance;
    address public treasury;
    bool public launched;
    uint128 public totalLiquidity;

    event Launched(uint160 sqrtPriceX96, uint256 eth, uint256 tokens, uint128 liquidity);
    event LiquidityAdded(uint256 ethIn, uint256 ethSwapped, uint256 tokensBought, uint128 liquidity);

    error NotAuthorized();
    error AlreadyLaunched();
    error NotLaunched();
    error NotPoolManager();
    error PriceLimit();

    enum Action {
        Seed,
        Add
    }

    constructor(IPoolManager manager, address token_, address hook_, address governance_) {
        poolManager = manager;
        token = token_;
        hook = hook_;
        governance = governance_;
    }

    function setTreasury(address treasury_) external {
        if (msg.sender != governance) revert NotAuthorized();
        treasury = treasury_;
    }

    function poolKey() public view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(token),
            fee: 0,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });
    }

    /// @notice Spot price of the pool as `sqrtPriceX96`.
    function sqrtPriceX96() public view returns (uint160 price) {
        (price,,,) = poolManager.getSlot0(poolKey().toId());
    }

    /// @notice Initialises the pool at `price` and adds `msg.value` ETH and every ENGINE this contract
    ///         holds as full-range liquidity. Governance, once.
    function launch(uint160 price) external payable nonReentrant returns (uint128 liquidity) {
        if (msg.sender != governance) revert NotAuthorized();
        if (launched) revert AlreadyLaunched();
        launched = true;
        poolManager.initialize(poolKey(), price);
        uint256 tokens = SafeTransferLib.balanceOf(token, address(this));
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            price, TickMath.getSqrtPriceAtTick(TICK_LOWER), TickMath.getSqrtPriceAtTick(TICK_UPPER), msg.value, tokens
        );
        poolManager.unlock(abi.encode(Action.Seed, liquidity, uint256(0), uint160(0)));
        emit Launched(price, msg.value, tokens, liquidity);
    }

    /// @notice Adds `msg.value` ETH to the protocol position: about half buys ENGINE (fee-exempt)
    ///         without moving `sqrtPriceX96` below `minSqrtPriceX96`, then both sides are added.
    function addLiquidity(uint160 minSqrtPriceX96) external payable nonReentrant returns (uint128 liquidity) {
        if (msg.sender != treasury && msg.sender != governance) revert NotAuthorized();
        if (!launched) revert NotLaunched();
        bytes memory r = poolManager.unlock(abi.encode(Action.Add, uint128(0), msg.value, minSqrtPriceX96));
        liquidity = abi.decode(r, (uint128));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (Action action, uint128 liquidity, uint256 ethIn, uint160 limit) = abi.decode(data, (Action, uint128, uint256, uint160));
        PoolKey memory key = poolKey();
        uint256 tokensBought;
        uint256 ethSwapped;
        if (action == Action.Add) {
            ethSwapped = ethIn / 2;
            (uint160 before,,,) = poolManager.getSlot0(key.toId());
            if (limit >= before || limit <= TickMath.MIN_SQRT_PRICE) revert PriceLimit();
            // ETH in, ENGINE out: the price (ENGINE per ETH) falls; `limit` bounds how far.
            BalanceDelta s = poolManager.swap(
                key, SwapParams({zeroForOne: true, amountSpecified: -int256(ethSwapped), sqrtPriceLimitX96: limit}), ""
            );
            ethSwapped = uint256(int256(-s.amount0()));
            tokensBought = uint256(int256(s.amount1()));
            (uint160 p,,,) = poolManager.getSlot0(key.toId());
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                p,
                TickMath.getSqrtPriceAtTick(TICK_LOWER),
                TickMath.getSqrtPriceAtTick(TICK_UPPER),
                ethIn - ethSwapped,
                tokensBought + SafeTransferLib.balanceOf(token, address(this))
            );
        }
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: TICK_LOWER, tickUpper: TICK_UPPER, liquidityDelta: int256(uint256(liquidity)), salt: 0}),
            ""
        );
        totalLiquidity += liquidity;
        // Settle the combined debts of the swap and the position.
        int256 eth = delta.amount0() - int256(ethSwapped);
        int256 tok = delta.amount1() + int256(tokensBought);
        if (eth < 0) poolManager.settle{value: uint256(-eth)}();
        else if (eth > 0) poolManager.take(key.currency0, address(this), uint256(eth));
        if (tok < 0) {
            poolManager.sync(key.currency1);
            SafeTransferLib.safeTransfer(token, address(poolManager), uint256(-tok));
            poolManager.settle();
        } else if (tok > 0) {
            poolManager.take(key.currency1, address(this), uint256(tok));
        }
        if (action == Action.Add) emit LiquidityAdded(ethIn, ethSwapped, tokensBought, liquidity);
        return abi.encode(liquidity);
    }

    receive() external payable {}
}
