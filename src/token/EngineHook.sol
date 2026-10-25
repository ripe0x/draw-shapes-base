// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

interface ITradingFeeReceiver {
    function receiveTradingFees() external payable;
}

/// @title EngineHook
/// @notice Uniswap v4 hook of the canonical ETH/ENGINE pool. It charges a project fee in ETH on every
///         swap (launch: 2.00 % of the swap's ETH amount, of which 0.25 % of volume is the operator's
///         and 1.75 % the treasury's), accrues it, and pays it out permissionlessly.
/// @dev Fee placement, all in ETH (currency0):
///      - buy, exact input (ETH specified): `beforeSwap` takes the fee from the ETH input;
///      - buy, exact output (ENGINE specified): `afterSwap` adds the fee to the ETH the swapper pays;
///      - sell, exact input (ENGINE specified): `afterSwap` takes the fee from the ETH output;
///      - sell, exact output (ETH specified): reverts `ExactOutputSellUnsupported`.
///      The pool's LP fee is 0, so the hook fee is the whole fee of this pool. Only `launcher` may
///      initialise a pool with this hook, once, for ETH/`token`. Fee-exempt senders (treasury,
///      buyback) avoid paying the project's fee to itself.
///      Structure adapted from token-works/fwa-relaunch `FWATokenHook` (MIT); its transfer gating is
///      not used: ENGINE is an ordinary ERC-20 and other pools can exist (docs/MARKET.md).
contract EngineHook is BaseHook, ReentrancyGuard {
    uint256 internal constant BPS = 10_000;
    /// @notice Hard ceiling on the total project fee, in bps of the swap's ETH amount.
    uint256 public constant MAX_FEE_BPS = 500;

    address public immutable token;
    address public immutable launcher;

    address public governance;
    address public pendingGovernance;
    address public operator;
    address public treasury;
    /// @notice Total project fee and the operator's part of it, both in bps of ETH volume.
    uint16 public feeBps;
    uint16 public operatorBps;
    bool public initialized;

    uint256 public operatorAccrued;
    uint256 public treasuryAccrued;
    uint256 public totalFees;
    uint256 public totalVolume;
    mapping(address => bool) public feeExempt;

    event FeeCharged(address indexed sender, bool buy, uint256 ethVolume, uint256 fee);
    event Distributed(uint256 toOperator, uint256 toTreasury);
    event FeesSet(uint256 feeBps, uint256 operatorBps);
    event RecipientsSet(address operator, address treasury);
    event ExemptSet(address indexed account, bool exempt);
    event GovernanceTransferred(address indexed previous, address indexed next);

    error NotGovernance();
    error NotLauncher();
    error AlreadyInitialized();
    error WrongPool();
    error ExactOutputSellUnsupported();
    error InvalidConfig();

    constructor(
        IPoolManager manager,
        address token_,
        address launcher_,
        address governance_,
        address operator_,
        address treasury_,
        uint16 feeBps_,
        uint16 operatorBps_
    ) BaseHook(manager) {
        if (token_ == address(0) || launcher_ == address(0) || governance_ == address(0)) revert InvalidConfig();
        token = token_;
        launcher = launcher_;
        governance = governance_;
        _setRecipients(operator_, treasury_);
        _setFees(feeBps_, operatorBps_);
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address sender, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (sender != launcher) revert NotLauncher();
        if (initialized) revert AlreadyInitialized();
        if (!key.currency0.isAddressZero() || Currency.unwrap(key.currency1) != token || key.fee != 0) {
            revert WrongPool();
        }
        initialized = true;
        return BaseHook.beforeInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool exactIn = params.amountSpecified < 0;
        if (!params.zeroForOne && !exactIn) revert ExactOutputSellUnsupported();
        if (feeExempt[sender] || !params.zeroForOne || !exactIn) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        // Buy with exact ETH input: the fee is part of the input, the rest is swapped.
        uint256 ethIn = uint256(-params.amountSpecified);
        uint256 fee = ethIn * feeBps / BPS;
        if (fee != 0) {
            poolManager.take(Currency.wrap(address(0)), address(this), fee);
            _accrue(sender, true, ethIn, fee);
        }
        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(int256(fee)), 0), 0);
    }

    function _afterSwap(address sender, PoolKey calldata, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        if (feeExempt[sender]) return (BaseHook.afterSwap.selector, 0);
        bool exactIn = params.amountSpecified < 0;
        uint256 fee;
        if (params.zeroForOne && !exactIn) {
            // Buy with exact ENGINE output: ETH is unspecified; the fee is added to what is paid.
            uint256 ethIn = uint256(int256(-delta.amount0()));
            fee = ethIn * feeBps / BPS;
            if (fee != 0) _accrue(sender, true, ethIn + fee, fee);
        } else if (!params.zeroForOne && exactIn) {
            // Sell with exact ENGINE input: ETH is unspecified; the fee comes out of the output.
            uint256 ethOut = uint256(int256(delta.amount0()));
            fee = ethOut * feeBps / BPS;
            if (fee != 0) _accrue(sender, false, ethOut, fee);
        }
        if (fee != 0) poolManager.take(Currency.wrap(address(0)), address(this), fee);
        return (BaseHook.afterSwap.selector, int128(int256(fee)));
    }

    function _accrue(address sender, bool buy, uint256 volume, uint256 fee) internal {
        uint256 toOperator = volume * operatorBps / BPS;
        if (toOperator > fee) toOperator = fee;
        operatorAccrued += toOperator;
        treasuryAccrued += fee - toOperator;
        totalFees += fee;
        totalVolume += volume;
        emit FeeCharged(sender, buy, volume, fee);
    }

    /// @notice Pays the accrued operator share to `operator` and the treasury share to `treasury`.
    ///         Anyone may call it.
    function distribute() external nonReentrant returns (uint256 toOperator, uint256 toTreasury) {
        toOperator = operatorAccrued;
        toTreasury = treasuryAccrued;
        operatorAccrued = 0;
        treasuryAccrued = 0;
        if (toOperator != 0) SafeTransferLib.forceSafeTransferETH(operator, toOperator);
        if (toTreasury != 0) ITradingFeeReceiver(treasury).receiveTradingFees{value: toTreasury}();
        emit Distributed(toOperator, toTreasury);
    }

    receive() external payable {}

    // ------------------------------------------------------------------ administration

    function setFees(uint16 feeBps_, uint16 operatorBps_) external onlyGovernance {
        _setFees(feeBps_, operatorBps_);
    }

    function setRecipients(address operator_, address treasury_) external onlyGovernance {
        _setRecipients(operator_, treasury_);
    }

    function setFeeExempt(address account, bool exempt) external onlyGovernance {
        feeExempt[account] = exempt;
        emit ExemptSet(account, exempt);
    }

    function proposeGovernance(address next) external onlyGovernance {
        pendingGovernance = next;
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernance || msg.sender == address(0)) revert NotGovernance();
        emit GovernanceTransferred(governance, msg.sender);
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    function _setFees(uint16 feeBps_, uint16 operatorBps_) internal {
        if (feeBps_ > MAX_FEE_BPS || operatorBps_ > feeBps_) revert InvalidConfig();
        feeBps = feeBps_;
        operatorBps = operatorBps_;
        emit FeesSet(feeBps_, operatorBps_);
    }

    function _setRecipients(address operator_, address treasury_) internal {
        if (operator_ == address(0) || treasury_ == address(0)) revert InvalidConfig();
        operator = operator_;
        treasury = treasury_;
        emit RecipientsSet(operator_, treasury_);
    }
}
