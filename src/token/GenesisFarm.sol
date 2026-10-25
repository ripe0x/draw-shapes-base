// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";

interface IParticipationLedger {
    function activated() external view returns (bool);
    function ledgerOrigin() external view returns (uint64);
    function dayTotals(uint256 day) external view returns (uint64 accepted, uint64 resolved, uint64 units, uint64 bonusWeight);
    function userDay(uint256 day, address purchaser) external view returns (uint64 units, uint64 bonusWeight);
}

interface IBurnable {
    function burn(uint256 amount) external;
}

/// @title GenesisFarm
/// @notice The single, finite ENGINE genesis distribution: 14 fixed 24-hour epochs starting when
///         paid gameplay opens (the engine's `ledgerOrigin`). Each epoch's allocation goes to the
///         purchasers of that epoch's successfully settled paid acquisitions: 85 % pro rata to units
///         (one per fulfilled acquisition) and 15 % pro rata to VRF-derived bonus weight.
/// @dev Accounting is the engine's participation ledger, keyed by the epoch in which a request was
///      accepted, so delayed VRF fulfilment never moves or loses a unit. An epoch is claimable once
///      it has ended and every acquisition accepted in it is terminal (FWA V2 Rewards'
///      `pendingAcquisitionsInEpoch` rule). Claims are pull-based, one per (epoch, purchaser), and
///      never expire. After the last epoch resolves, `retireUnearned` burns the allocation of every
///      epoch with no units; earned rewards stay claimable. The contract has no owner and no way to
///      move tokens other than claims and that burn.
contract GenesisFarm is ReentrancyGuard {
    uint256 public constant EPOCHS = 14;
    uint256 public constant EPOCH_LENGTH = 1 days;
    uint256 public constant PROPORTIONAL_BPS = 8_500;
    uint256 internal constant BPS = 10_000;

    address public immutable token;
    IParticipationLedger public immutable ledger;
    uint256 public immutable totalAllocation;

    mapping(uint256 epoch => mapping(address purchaser => bool)) public claimed;
    mapping(uint256 epoch => uint256) public claimedInEpoch;
    uint256 public totalClaimed;
    bool public retired;
    uint256 public retiredAmount;

    event Claimed(address indexed purchaser, uint256 indexed epoch, uint256 amount);
    event UnearnedRetired(uint256 amount, uint256 emptyEpochs);

    error NotStarted();
    error EpochNotClosed(uint256 epoch);
    error EpochStillPending(uint256 epoch);
    error InvalidEpoch(uint256 epoch);
    error AlreadyClaimed(uint256 epoch);
    error NothingToClaim();
    error AlreadyRetired();
    error GenesisNotResolved();

    constructor(address token_, address ledger_, uint256 totalAllocation_) {
        token = token_;
        ledger = IParticipationLedger(ledger_);
        totalAllocation = totalAllocation_;
    }

    /// @notice ENGINE allocated to `epoch`: an equal share, the last epoch taking the rounding remainder.
    function allocationOf(uint256 epoch) public view returns (uint256) {
        if (epoch >= EPOCHS) return 0;
        uint256 each = totalAllocation / EPOCHS;
        return epoch == EPOCHS - 1 ? totalAllocation - each * (EPOCHS - 1) : each;
    }

    /// @notice Current epoch index, or `EPOCHS` once genesis has ended. Reverts before gameplay opens.
    function currentEpoch() public view returns (uint256) {
        if (!ledger.activated()) revert NotStarted();
        uint256 e = (block.timestamp - ledger.ledgerOrigin()) / EPOCH_LENGTH;
        return e > EPOCHS ? EPOCHS : e;
    }

    /// @notice Genesis start and end timestamps (zero before gameplay opens).
    function schedule() external view returns (uint256 start, uint256 end) {
        if (!ledger.activated()) return (0, 0);
        start = ledger.ledgerOrigin();
        end = start + EPOCHS * EPOCH_LENGTH;
    }

    /// @notice True when `epoch` has ended and every acquisition accepted in it is terminal.
    function isFinal(uint256 epoch) public view returns (bool) {
        if (epoch >= EPOCHS || !ledger.activated()) return false;
        if (block.timestamp < ledger.ledgerOrigin() + (epoch + 1) * EPOCH_LENGTH) return false;
        (uint64 accepted, uint64 resolved,,) = ledger.dayTotals(epoch);
        return accepted == resolved;
    }

    /// @notice Reward of `purchaser` in `epoch` from the ledger as it stands (final once `isFinal`).
    function rewardOf(uint256 epoch, address purchaser) public view returns (uint256 reward) {
        if (epoch >= EPOCHS) return 0;
        (,, uint64 units, uint64 bonus) = ledger.dayTotals(epoch);
        if (units == 0) return 0;
        (uint64 myUnits, uint64 myBonus) = ledger.userDay(epoch, purchaser);
        uint256 alloc = allocationOf(epoch);
        uint256 proportional = alloc * PROPORTIONAL_BPS / BPS;
        reward = FP.fullMulDiv(proportional, myUnits, units);
        if (bonus != 0) reward += FP.fullMulDiv(alloc - proportional, myBonus, bonus);
    }

    /// @notice Unclaimed reward of `purchaser` across final epochs.
    function claimable(address purchaser) external view returns (uint256 total) {
        for (uint256 e; e < EPOCHS; ++e) {
            if (isFinal(e) && !claimed[e][purchaser]) total += rewardOf(e, purchaser);
        }
    }

    /// @notice Claims the caller's rewards of `epochs`, each final and unclaimed.
    function claim(uint256[] calldata epochs) external nonReentrant returns (uint256 total) {
        for (uint256 i; i < epochs.length; ++i) {
            uint256 e = epochs[i];
            if (e >= EPOCHS) revert InvalidEpoch(e);
            if (block.timestamp < ledger.ledgerOrigin() + (e + 1) * EPOCH_LENGTH || !ledger.activated()) {
                revert EpochNotClosed(e);
            }
            if (!isFinal(e)) revert EpochStillPending(e);
            if (claimed[e][msg.sender]) revert AlreadyClaimed(e);
            claimed[e][msg.sender] = true;
            uint256 amount = rewardOf(e, msg.sender);
            claimedInEpoch[e] += amount;
            total += amount;
            emit Claimed(msg.sender, e, amount);
        }
        if (total == 0) revert NothingToClaim();
        totalClaimed += total;
        SafeTransferLib.safeTransfer(token, msg.sender, total);
    }

    /// @notice Unearned allocation: the allocations of final epochs without a single unit.
    function unearned() public view returns (uint256 amount, uint256 emptyEpochs) {
        for (uint256 e; e < EPOCHS; ++e) {
            (,, uint64 units,) = ledger.dayTotals(e);
            if (units == 0) {
                amount += allocationOf(e);
                ++emptyEpochs;
            }
        }
    }

    /// @notice Burns the allocation of every epoch that earned nothing, once all 14 epochs are final.
    ///         Anyone may call it. Earned rewards are untouched and stay claimable forever.
    function retireUnearned() external nonReentrant returns (uint256 amount) {
        if (retired) revert AlreadyRetired();
        for (uint256 e; e < EPOCHS; ++e) {
            if (!isFinal(e)) revert GenesisNotResolved();
        }
        retired = true;
        uint256 empty;
        (amount, empty) = unearned();
        retiredAmount = amount;
        if (amount != 0) IBurnable(token).burn(amount);
        emit UnearnedRetired(amount, empty);
    }
}
