// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IGrailFund {
    function fundGrail() external payable;
    function liveGrails() external view returns (uint256);
}

interface IPoolFund {
    function fundPool() external payable;
    function cash() external view returns (uint256);
    function queueLength() external view returns (uint256);
}

interface IProtocolLiquidity {
    function addLiquidity(uint160 minSqrtPriceX96) external payable returns (uint128);
}

/// @title Treasury
/// @notice Receives the treasury share of ENGINE trading fees and routes it by fixed precedence:
///         1. the restock reserve is refilled to `reserveTarget`;
///         2. while the vault holds no GRAIL (before the first one, or after one was won), all of
///            the rest to the GRAIL fund; otherwise the rest is split `grailBps` to the GRAIL fund
///            and the remainder to protocol-owned liquidity (launch 90 % / 10 %).
///         The reserve exists only to keep the ordinary pool restockable: `backstop()` (anyone) moves
///         reserve ETH into the controller's cash when its replacement queue is waiting and its cash
///         is below `backstopFloor`.
/// @dev ETH leaves into the game (controller cash, GRAIL fund), into the locked protocol liquidity,
///      or, through `migrate` (governance, behind the timelock delay), to a successor. Governance
///      tunes the bounded split and thresholds; POL deployment needs a price limit and is
///      governance/keeper only.
contract Treasury is ReentrancyGuard {
    uint256 internal constant BPS = 10_000;

    IPoolFund public immutable controller;
    IGrailFund public immutable grailVault;
    IProtocolLiquidity public immutable liquidity;

    address public governance;
    address public pendingGovernance;
    address public keeper;

    uint256 public reserve;
    uint256 public polPending;
    uint256 public reserveTarget;
    uint256 public backstopFloor;
    uint16 public grailBps;

    uint256 public totalReceived;
    uint256 public totalToGrail;
    uint256 public totalToPol;
    uint256 public totalBackstopped;

    event TradingFeesReceived(uint256 amount, uint256 toReserve, uint256 toGrail, uint256 toPol);
    event ReserveFunded(address indexed from, uint256 amount);
    event Backstopped(uint256 amount);
    event PolDeployed(uint256 amount, uint128 liquidity);
    event Migrated(address indexed to, uint256 amount);
    event ParamSet(bytes4 indexed selector);

    error NotGovernance();
    error NotKeeper();
    error InvalidConfig();
    error NotNeeded();

    constructor(
        address controller_,
        address grailVault_,
        address liquidity_,
        address governance_,
        address keeper_,
        uint256 reserveTarget_,
        uint256 backstopFloor_,
        uint16 grailBps_
    ) {
        if (controller_ == address(0) || grailVault_ == address(0) || liquidity_ == address(0) || governance_ == address(0)) {
            revert InvalidConfig();
        }
        controller = IPoolFund(controller_);
        grailVault = IGrailFund(grailVault_);
        liquidity = IProtocolLiquidity(liquidity_);
        governance = governance_;
        keeper = keeper_;
        _set(reserveTarget_, backstopFloor_, grailBps_);
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        emit ParamSet(msg.sig);
        _;
    }

    /// @notice Opening reserve contribution (and any later top-up). Anyone.
    function fundReserve() external payable {
        reserve += msg.value;
        emit ReserveFunded(msg.sender, msg.value);
    }

    /// @notice Trading-fee entry point used by `EngineHook.distribute`. Anyone may send.
    function receiveTradingFees() external payable nonReentrant {
        uint256 amount = msg.value;
        totalReceived += amount;
        uint256 toReserve;
        if (reserve < reserveTarget) {
            toReserve = reserveTarget - reserve;
            if (toReserve > amount) toReserve = amount;
            reserve += toReserve;
        }
        uint256 rest = amount - toReserve;
        // While no GRAIL is held (before the first, or after one was won) every discretionary wei
        // funds the next one; with a GRAIL on the board the split returns to grailBps / POL.
        uint256 toGrail = grailVault.liveGrails() == 0 ? rest : rest * grailBps / BPS;
        uint256 toPol = rest - toGrail;
        polPending += toPol;
        totalToPol += toPol;
        totalToGrail += toGrail;
        emit TradingFeesReceived(amount, toReserve, toGrail, toPol);
        if (toGrail != 0) grailVault.fundGrail{value: toGrail}();
    }

    /// @notice Moves reserve ETH into the ordinary pool when replacements are waiting and the pool's
    ///         cash is below `backstopFloor`. Anyone.
    function backstop() external nonReentrant returns (uint256 amount) {
        uint256 cash = controller.cash();
        if (controller.queueLength() == 0 || cash >= backstopFloor) revert NotNeeded();
        amount = backstopFloor - cash;
        if (amount > reserve) amount = reserve;
        if (amount == 0) revert NotNeeded();
        reserve -= amount;
        totalBackstopped += amount;
        emit Backstopped(amount);
        controller.fundPool{value: amount}();
    }

    /// @notice Adds the pending POL share to the locked protocol position, not letting the buy move
    ///         the price below `minSqrtPriceX96`. Keeper or governance.
    function deployPol(uint160 minSqrtPriceX96) external nonReentrant returns (uint128 added) {
        if (msg.sender != keeper && msg.sender != governance) revert NotKeeper();
        uint256 amount = polPending;
        if (amount == 0) revert NotNeeded();
        polPending = 0;
        added = liquidity.addLiquidity{value: amount}(minSqrtPriceX96);
        emit PolDeployed(amount, added);
    }

    /// @notice Moves the reserve and pending POL (the whole balance) to `to`: a successor treasury,
    ///         whose `receive` books it as reserve, or another destination. Point the hook's treasury
    ///         recipient at the successor in the same batch. Governance (timelock).
    function migrate(address to) external onlyGovernance nonReentrant returns (uint256 amount) {
        amount = address(this).balance;
        reserve = 0;
        polPending = 0;
        emit Migrated(to, amount);
        SafeTransferLib.safeTransferETH(to, amount);
    }

    function setParams(uint256 reserveTarget_, uint256 backstopFloor_, uint16 grailBps_) external onlyGovernance {
        _set(reserveTarget_, backstopFloor_, grailBps_);
    }

    function setKeeper(address keeper_) external onlyGovernance {
        keeper = keeper_;
    }

    function proposeGovernance(address next) external onlyGovernance {
        pendingGovernance = next;
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernance || msg.sender == address(0)) revert NotGovernance();
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    function _set(uint256 reserveTarget_, uint256 backstopFloor_, uint16 grailBps_) internal {
        if (grailBps_ > BPS || backstopFloor_ > 5 ether || reserveTarget_ > 50 ether) revert InvalidConfig();
        reserveTarget = reserveTarget_;
        backstopFloor = backstopFloor_;
        grailBps = grailBps_;
    }

    receive() external payable {
        reserve += msg.value;
        emit ReserveFunded(msg.sender, msg.value);
    }
}
