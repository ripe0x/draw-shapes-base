// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IShapes} from "shapes/interfaces/IShapes.sol";
import {IERC721Value} from "shapes/interfaces/IERC721Value.sol";
import {Denominations} from "shapes/lib/Denominations.sol";
import {IShapePacks} from "draw-packs/interfaces/IShapePacks.sol";
import {PricingLib} from "./PricingLib.sol";
import {DrawEngine} from "../engine/DrawEngine.sol";

interface GrailVaultLike {
    function fundGrail() external payable;
}

/// @dev A successor controller funded by `migrateCapital`.
interface ControllerLike {
    function fundPool() external payable;
}

/// @title DrawController
/// @notice The protocol-owned house of Draw Shapes on Base. It mints ETH-backed Shapes and Draw
///         Packs, lists them on the `DrawEngine` at their notional price, books every settled
///         acquisition, replaces captured items from the mix table, splits the realised margin
///         between the ordinary pool, maintenance and the GRAIL fund, and builds and lists GRAILs.
/// @dev Ported from ripe0x/draw-shapes `Pool`/`PoolBooks`/`PoolListing` (commit 4a13a09). Removed:
///      depositors, shares, claims, entry fees, the volume cap, depositor exits, the FWA edge
///      arithmetic and the 1 ETH piece / merge GRAIL builder. Kept: the booking walk, margin split
///      with the replacement mint line, deficit / surprise / band replacement draw, fill by held
///      Shape, mint or Draw Pack, and GRAIL listing below backing with per-pull decay and a
///      probability cap. Protocol capital moves to a successor through `migrateCapital`.
///
///      Buckets. Every wei the controller holds is in `cash` or `maintenance`, besides
///      the feed in flight; `receivable`, `maintenanceReceivable` and `feedReceivable` are engine
///      proceeds booked but not yet withdrawn. `backing` is the ETH inside ordinary items held or
///      listed. Ordinary NAV = `cash + backing + receivable`.
///
///      Invariants (test/invariant): I1 `balance >= cash + maintenance`; I2 `backing` equals the
///      summed value of ordinary items held or listed; I3 maintenance pays only keeper refunds (VRF
///      is purchaser-funded in the engine). GRAILs live in `GrailVault`, a separate engine supplier.
contract DrawController is ReentrancyGuard {
    using SafeCastLib for uint256;

    // ------------------------------------------------------------------ types

    struct Item {
        address collection;
        uint16 row;
        uint256 tokenId;
        uint256 value;
        uint256 listingId;
    }

    struct FeeSplit {
        uint16 premiumBps;
        uint16 maintenanceBps;
        uint16 feedBps;
    }

    /// @dev A prize from another collection placed by governance (sponsorship, partner NFTs, ENGINE
    ///      packs). It has no ETH backing on the controller's books: capture proceeds are pure margin.
    struct ExternalItem {
        address collection;
        uint256 tokenId;
        uint256 notional;
    }

    // ------------------------------------------------------------------ constants

    uint256 internal constant BPS = 10_000;
    uint256 public constant MAX_FEE_SPLIT_BPS = 1_500;
    uint256 public constant MAX_SETTLE_ITEMS = 20;
    /// @dev Listings per call: each mints and lists (0.86-1.36M gas with cold storage), so 8 keeps settle(50) and build
    ///      the EIP-7825 per-transaction cap of 16,777,216 gas (Base Sepolia; coming to Base mainnet).
    uint256 public constant MAX_LIST_PER_CALL = 6;
    uint256 public constant MAX_TIP = 0.001 ether;
    uint256 public constant MAX_RESTORE_K = 100;
    uint256 public constant MAX_BAND_BPS = 100_000;
    uint256 public constant MAX_ROWS = 16;
    uint256 internal constant REFUND_GAS_OVERHEAD = 30_000;

    // ------------------------------------------------------------------ immutables

    IShapes public immutable shapes;
    IShapePacks public immutable drawPacks;
    DrawEngine public immutable engine;

    // ------------------------------------------------------------------ roles

    address public governance;
    address public pendingGovernance;
    address public guardian;
    /// @notice Guardian switch: stops minting and listing. Booking, harvest and settlement continue.
    bool public listingPaused;

    // ------------------------------------------------------------------ buckets

    uint256 public cash;
    uint256 public backing;
    uint256 public receivable;
    uint256 public maintenance;
    uint256 public maintenanceReceivable;
    /// @notice Feed share of booked margin, not yet withdrawn from the engine.
    uint256 public feedReceivable;

    // ------------------------------------------------------------------ parameters

    FeeSplit public feeSplit;
    /// @notice Receives the feed share of every harvest. It lists GRAILs as its own engine supplier.
    GrailVaultLike public immutable grailVault;
    PricingLib.MixRow[] internal _mix;
    uint256[] internal _rowBackingWei;
    /// @notice Target number of ordinary items on the board.
    uint256 public boardItems;
    /// @notice Cash the controller keeps unspent by mints.
    uint256 public cashFloor;
    uint256 public surpriseBps;
    uint256 public restoreK;
    uint256 public bandBps;
    uint256 public tipWei;
    /// @notice Ordinary NAV that is committed game capital and never released as surplus.
    uint256 public capitalTarget;
    /// @notice Recipient of realised surplus (the buyback) and the time from which release is allowed.
    address public surplusSink;
    uint64 public surplusReleaseStart;
    /// @notice Operating reserve: before surplus leaves, it first tops maintenance up to this level.
    uint256 public maintenanceFloor;

    // ------------------------------------------------------------------ registry

    uint256[] internal _rowCount;
    uint256[] internal _queuedByRow;
    uint256[][] internal _listedByRow;
    mapping(uint256 listingId => uint256) internal _listedIndex;
    mapping(uint256 listingId => Item) internal _listed;
    Item[] internal _held;
    mapping(address collection => mapping(uint256 tokenId => uint256)) internal _heldPos;
    mapping(uint8 denom => uint256[]) internal _heldByDenom;
    mapping(uint256 tokenId => uint256) internal _denomPos;
    uint256 internal _heldPacks;
    uint256 public listedCount;

    uint16[] internal _replacementQueue;
    uint256 public replacementHead;

    mapping(uint256 listingId => ExternalItem) public externalItems;

    /// @notice First engine sequence not yet booked.
    uint64 public nextSequenceToBook = 1;
    int256 internal _margin;
    uint256 internal _mintLineOwed;

    /// @notice Cumulative totals for reconciliation.
    uint256 public totalProceedsBooked;
    uint256 public totalBackingCaptured;
    uint256 public totalMintFeesPaid;
    uint256 public totalSurplusReleased;
    uint256 public totalPremiumBooked;
    uint256 public totalMaintenanceBooked;
    uint256 public totalFeedBooked;
    uint256 public totalFeedSent;

    // ------------------------------------------------------------------ events

    event Booked(uint64 nextSequence);
    event Captured(uint256 indexed requestId, uint256 indexed listingId, uint256 row, uint256 value, uint256 proceeds);
    event ExternalCaptured(uint256 indexed requestId, uint256 indexed listingId, uint256 proceeds);
    event ReplacementChosen(uint256 indexed requestId, uint256 capturedRow, uint256 chosenRow, bool surprise);
    event WrittenOff(uint256 indexed requestId, uint256 indexed listingId, uint256 value);
    event MarginSplit(uint256 mintLine, uint256 premium, uint256 maintenance, uint256 feed);
    event SurplusBooked(uint256 amount);
    event Harvested(uint256 received);
    event HarvestShortfall(uint256 received, uint256 expected);
    event Listed(uint256 count);
    event Funded(bytes32 indexed bucket, address indexed from, uint256 amount);
    event SurplusReleased(address indexed to, uint256 amount);
    event KeeperRefund(address indexed keeper, uint256 amount);
    event VrfFunded(uint256 amount);
    event ParamSet(bytes4 indexed selector);
    event GovernanceTransferred(address indexed previous, address indexed next);
    event ListingPausedSet(bool paused);
    event RefundedRecovered(uint256 indexed listingId, uint256 value);
    event CapitalMigrated(address indexed to, uint256 cash, uint256 maintenance);

    // ------------------------------------------------------------------ errors

    error ZeroAddress();
    error NotGovernance();
    error NotGuardian();
    error FeeSplitTooHigh();
    error LimitOutOfRange();
    error RowInUse();
    error UnknownListing(uint256 listingId);
    error PackValueMismatch();
    error BooksBehind();
    error NothingToRelease();
    error ReleaseNotOpen();
    error UnexpectedToken();
    error RedeemMismatch();
    error NotRefunded();
    error StillListed();

    // ------------------------------------------------------------------ construction

    struct Params {
        address shapes;
        address drawPacks;
        address engine;
        address governance;
        address guardian;
        FeeSplit feeSplit;
        PricingLib.MixRow[] mix;
        uint256 boardItems;
        uint256 cashFloor;
        uint256 surpriseBps;
        uint256 restoreK;
        uint256 bandBps;
        uint256 tipWei;
        uint256 capitalTarget;
        uint256 maintenanceFloor;
        address grailVault;
    }

    constructor(Params memory p) {
        if (
            p.shapes == address(0) || p.drawPacks == address(0) || p.engine == address(0)
                || p.governance == address(0) || p.guardian == address(0) || p.grailVault == address(0)
        ) revert ZeroAddress();
        shapes = IShapes(p.shapes);
        drawPacks = IShapePacks(p.drawPacks);
        engine = DrawEngine(payable(p.engine));
        governance = p.governance;
        guardian = p.guardian;
        _setFeeSplit(p.feeSplit);
        _setMix(p.mix);
        _setBoard(p.boardItems, p.cashFloor);
        _setReplacement(p.surpriseBps, p.restoreK, p.bandBps);
        _setTip(p.tipWei);
        capitalTarget = p.capitalTarget;
        maintenanceFloor = p.maintenanceFloor;
        grailVault = GrailVaultLike(p.grailVault);
        IERC721(p.shapes).setApprovalForAll(p.engine, true);
        IERC721(p.drawPacks).setApprovalForAll(p.engine, true);
        IERC721(p.shapes).setApprovalForAll(p.drawPacks, true);
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        emit ParamSet(msg.sig);
        _;
    }

    // ------------------------------------------------------------------ funding

    /// @notice Adds `msg.value` to the ordinary pool's cash. Anyone; the treasury backstop uses it.
    function fundPool() external payable {
        cash += msg.value;
        emit Funded("pool", msg.sender, msg.value);
    }

    /// @notice Adds `msg.value` to the GRAIL fund. Anyone; the treasury routes trading fees here.
    function fundGrail() external payable {
        grailVault.fundGrail{value: msg.value}();
        emit Funded("grail", msg.sender, msg.value);
    }

    /// @notice Adds `msg.value` to maintenance (keeper refunds and VRF funding).
    function fundMaintenance() external payable {
        maintenance += msg.value;
        emit Funded("maintenance", msg.sender, msg.value);
    }

    /// @dev Accepts ETH only from the engine (proceeds), Shapes and Draw Packs (redemptions), whose
    ///      callers account for it.
    receive() external payable {
        if (msg.sender != address(engine) && msg.sender != address(shapes) && msg.sender != address(drawPacks)) {
            revert UnexpectedToken();
        }
    }

    // ------------------------------------------------------------------ keeper paths

    /// @notice Builds the board before activation and refills it after: queues every row's missing
    ///         items against its target depth, then fills and lists up to `maxItems`. Anyone.
    function build(uint256 maxItems) external nonReentrant returns (uint256 listed) {
        _queueMissing();
        listed = _listBatch(maxItems > MAX_LIST_PER_CALL ? MAX_LIST_PER_CALL : maxItems);
    }

    /// @notice Processes up to `maxCount` engine acquisitions, books them, harvests proceeds, lists
    ///         replacements, steps the GRAIL and pays the caller's gas from maintenance when the call
    ///         changed inventory. Anyone.
    function settle(uint256 maxCount) external nonReentrant returns (uint256 listed) {
        uint256 gasStart = gasleft();
        if (maxCount > MAX_SETTLE_ITEMS) maxCount = MAX_SETTLE_ITEMS;
        engine.processAcquisitions(maxCount);
        _walk(maxCount);
        _harvest();
        listed = _listBatch(MAX_LIST_PER_CALL);
        if (listed != 0) _refundKeeper(gasStart);
    }

    /// @notice Sends realised surplus, ordinary NAV above `capitalTarget`, to `surplusSink` from cash,
    ///         after topping maintenance up to `maintenanceFloor`.
    ///         Requires the books level with the engine, an empty replacement queue and a full
    ///         board, so released ETH is never needed for restocking. Anyone, from `surplusReleaseStart`.
    function releaseSurplus() external nonReentrant returns (uint256 amount) {
        if (surplusSink == address(0) || surplusReleaseStart == 0 || block.timestamp < surplusReleaseStart) {
            revert ReleaseNotOpen();
        }
        if (nextSequenceToBook != engine.nextSequenceToProcess()) revert BooksBehind();
        _harvest();
        amount = releasableSurplus();
        if (amount == 0) revert NothingToRelease();
        cash -= amount;
        // operating reserve first: top maintenance up to its floor (a transfer, not earnings)
        if (maintenance < maintenanceFloor) {
            uint256 top = maintenanceFloor - maintenance;
            if (top > amount) top = amount;
            maintenance += top;
            amount -= top;
            if (amount == 0) return 0;
        }
        totalSurplusReleased += amount;
        emit SurplusReleased(surplusSink, amount);
        SafeTransferLib.safeTransferETH(surplusSink, amount);
    }

    /// @notice Surplus `releaseSurplus` would send now.
    function releasableSurplus() public view returns (uint256) {
        if (receivable != 0 || _replacementQueue.length != replacementHead || _boardCount() < boardItems) return 0;
        uint256 value = nav();
        if (value <= capitalTarget) return 0;
        uint256 surplus = value - capitalTarget;
        uint256 free = cash > cashFloor ? cash - cashFloor : 0;
        return surplus < free ? surplus : free;
    }

    /// @notice Takes back a token whose delivery the engine refunded after it was written off and
    ///         redeems it into cash. Anyone.
    function recoverRefunded(uint256 listingId) external nonReentrant {
        (address collection,,, uint256 tokenId,,,, DrawEngine.ListingStatus status) = engine.listings(listingId);
        if (status != DrawEngine.ListingStatus.DeliveryRefunded) revert NotRefunded();
        engine.recoverRefundedNFT(listingId);
        if (collection != address(shapes) && collection != address(drawPacks)) return;
        uint256 value = IERC721Value(collection).valueOf(tokenId);
        uint256 before = address(this).balance;
        IERC721Value(collection).burn(tokenId);
        _creditRedeemed(listingId, value, before);
    }

    /// @notice After the engine is retired, withdraws ordinary listings and redeems them into cash,
    ///         turning unawarded prizes back into ETH of the ordinary pool. Anyone; up to 20 per call.
    function windDown(uint256[] calldata listingIds) external nonReentrant {
        if (!engine.retired()) revert ReleaseNotOpen();
        Item[] memory items = new Item[](listingIds.length);
        for (uint256 i; i < listingIds.length; ++i) {
            items[i] = _removeListed(listingIds[i]);
        }
        engine.withdrawListingsTo(listingIds, address(this));
        for (uint256 i; i < items.length; ++i) {
            _redeemToCash(items[i]);
        }
    }

    /// @notice Moves the controller's capital (cash and maintenance) to `to` once nothing here is
    ///         owed or on the board: no engine acquisition unresolved, the books level and harvested,
    ///         and every ordinary listing wound down (after `DrawEngine.retire`) or handed off to a
    ///         successor. Held items are redeemed into cash first, and listing stays paused here.
    ///         `asController` funds a successor controller's cash through `fundPool` (its maintenance
    ///         refills from margin); otherwise the ETH is a plain transfer. Player funds never pass through the controller.
    ///         Governance (timelock).
    function migrateCapital(address to, bool asController) external onlyGovernance nonReentrant {
        if (engine.unsettledAcquisitionCount() != 0 || nextSequenceToBook != engine.nextSequenceToProcess()) {
            revert BooksBehind();
        }
        _harvest();
        if (listedCount | receivable | maintenanceReceivable | feedReceivable != 0) revert StillListed();
        while (_held.length != 0) {
            _redeemToCash(_removeHeld(_held.length - 1));
        }
        listingPaused = true;
        (uint256 c, uint256 m) = (cash, maintenance);
        (cash, maintenance) = (0, 0);
        emit CapitalMigrated(to, c, m);
        if (asController) ControllerLike(to).fundPool{value: c + m}();
        else SafeTransferLib.safeTransferETH(to, c + m);
    }

    /// @dev Burns an ordinary item the controller holds and books its ETH backing as cash.
    function _redeemToCash(Item memory it) internal {
        uint256 before = address(this).balance;
        IERC721Value(it.collection).burn(it.tokenId);
        if (address(this).balance - before != it.value) revert RedeemMismatch();
        cash += it.value;
    }

    function _creditRedeemed(uint256 listingId, uint256 value, uint256 before) internal {
        if (address(this).balance - before != value) revert RedeemMismatch();
        cash += value;
        _margin += value.toInt256();
        _splitMargin();
        emit RefundedRecovered(listingId, value);
    }

    // ------------------------------------------------------------------ views

    /// @notice Ordinary NAV: `cash + backing + receivable`.
    function nav() public view returns (uint256) {
        return cash + backing + receivable;
    }

    function mixLength() external view returns (uint256) {
        return _mix.length;
    }

    function mixRow(uint256 i) external view returns (uint8[] memory rungs, uint16 shareBps, uint256 backingWei) {
        return (_mix[i].rungs, _mix[i].shareBps, _rowBackingWei[i]);
    }

    function rowCount(uint256 row) external view returns (uint256 listedOrHeld, uint256 queued) {
        return (_rowCount[row], _queuedByRow[row]);
    }

    function queueLength() external view returns (uint256) {
        return _replacementQueue.length - replacementHead;
    }

    function listedItem(uint256 listingId) external view returns (Item memory) {
        return _listed[listingId];
    }

    /// @notice Notional the controller assigns to one item of `row` at the current mint fee.
    function rowNotional(uint256 row) public view returns (uint256) {
        FeeSplit memory s = feeSplit;
        return PricingLib.listingPrice(
            _rowBackingWei[row], s.premiumBps, s.maintenanceBps, s.feedBps, shapes.mintFee() * _mix[row].rungs.length
        );
    }

    // ------------------------------------------------------------------ books

    /// @dev Books up to `maxItems` engine acquisitions in sequence order (PoolBooks._walk). A
    ///      fulfilled ordinary capture leaves `backing`, its proceeds join `receivable` and `margin`,
    ///      and a replacement row is queued. A fulfilled GRAIL capture credits the GRAIL receivable.
    ///      A delivery still pending is written off; its proceeds, if delivery later completes,
    ///      arrive as surplus.
    function _walk(uint256 maxItems) internal {
        uint64 seq = nextSequenceToBook;
        uint64 end = engine.nextSequenceToProcess();
        if (seq >= end) {
            _bookSurplus();
            return;
        }
        uint256 mintFee = shapes.mintFee();
        for (uint256 n; seq < end && n < maxItems; ++n) {
            (,, uint256 paid, uint256 listingId, DrawEngine.AcquisitionStatus status) = engine.acquisitions(seq);
            if (status == DrawEngine.AcquisitionStatus.Fulfilled) {
                _capture(seq, listingId, paid, mintFee);
            } else if (status == DrawEngine.AcquisitionStatus.DeliveryPending) {
                _writeOff(seq, listingId);
            } else if (status == DrawEngine.AcquisitionStatus.DeliveryRefunded) {
                _writeOff(seq, listingId);
            }
            ++seq;
        }
        nextSequenceToBook = seq;
        emit Booked(seq);
        if (seq == end) _bookSurplus();
    }

    function _capture(uint256 requestId, uint256 listingId, uint256 paid, uint256 mintFee) internal {
        if (_listed[listingId].value == 0 && externalItems[listingId].collection == address(0)) return;
        if (externalItems[listingId].collection != address(0)) {
            delete externalItems[listingId];
            totalProceedsBooked += paid;
            receivable += paid;
            _margin += paid.toInt256();
            emit ExternalCaptured(requestId, listingId, paid);
            _splitMargin();
            return;
        }
        Item memory item = _removeListed(listingId);
        totalProceedsBooked += paid;
        totalBackingCaptured += item.value;
        receivable += paid;
        _margin += paid.toInt256() - item.value.toInt256();
        _mintLineOwed += mintFee * _mix[item.row].rungs.length;
        (uint256 row, bool surprise) = _chooseRow(requestId, item.row);
        if (row != type(uint256).max) {
            _enqueue(row);
            emit ReplacementChosen(requestId, item.row, row, surprise);
        }
        emit Captured(requestId, listingId, item.row, item.value, paid);
        _splitMargin();
    }

    function _writeOff(uint256 requestId, uint256 listingId) internal {
        if (_listed[listingId].value == 0 && externalItems[listingId].collection == address(0)) return;
        if (externalItems[listingId].collection != address(0)) {
            delete externalItems[listingId];
            return;
        }
        Item memory item = _removeListed(listingId);
        _margin -= item.value.toInt256();
        emit WrittenOff(requestId, listingId, item.value);
    }

    /// @dev Row that replaces a capture, drawn from `keccak256(abi.encode(randomWord, requestId))`.
    function _chooseRow(uint256 requestId, uint256 capturedRow) internal view returns (uint256, bool) {
        (,,,,, uint256 word) = engine.acquisitionMeta(requestId);
        uint256 n = _mix.length;
        PricingLib.RowState[] memory rows = new PricingLib.RowState[](n);
        uint256 items = boardItems;
        for (uint256 i; i < n; ++i) {
            uint256 share = _mix[i].shareBps;
            rows[i] = PricingLib.RowState(
                share,
                _rowCount[i] + _queuedByRow[i],
                PricingLib.rowDepth(items, share),
                _rowBackingWei[i],
                _mix[i].rungs.length == 1
            );
        }
        return PricingLib.chooseRow(
            keccak256(abi.encode(word, requestId)), rows, restoreK, surpriseBps, bandBps, capturedRow
        );
    }

    function _enqueue(uint256 row) internal {
        _replacementQueue.push(uint16(row));
        ++_queuedByRow[row];
    }

    /// @dev PoolBooks._splitMargin: positive margin repays the mint line, then divides
    ///      premium : maintenance : feed. Negative margin carries forward.
    function _splitMargin() internal {
        int256 signedMargin = _margin;
        if (signedMargin <= 0) return;
        uint256 amount = uint256(signedMargin);
        uint256 cover = amount < _mintLineOwed ? amount : _mintLineOwed;
        _mintLineOwed -= cover;
        uint256 rest = amount - cover;
        FeeSplit memory split = feeSplit;
        uint256 totalBps = uint256(split.premiumBps) + split.maintenanceBps + split.feedBps;
        uint256 maintenanceShare;
        uint256 feedShare;
        if (totalBps != 0) {
            maintenanceShare = rest * split.maintenanceBps / totalBps;
            feedShare = rest * split.feedBps / totalBps;
        }
        receivable -= maintenanceShare + feedShare;
        maintenanceReceivable += maintenanceShare;
        feedReceivable += feedShare;
        _margin = 0;
        totalPremiumBooked += rest - maintenanceShare - feedShare;
        totalMaintenanceBooked += maintenanceShare;
        totalFeedBooked += feedShare;
        emit MarginSplit(cover, rest - maintenanceShare - feedShare, maintenanceShare, feedShare);
    }

    function _bookedReceivables() internal view returns (uint256) {
        return receivable + maintenanceReceivable + feedReceivable;
    }

    /// @dev Books engine proceeds above the booked receivables (late deliveries of written-off
    ///      items) as margin. Runs only while the walk is level.
    function _bookSurplus() internal {
        uint256 actual = engine.proceedsOf(address(this));
        uint256 booked = _bookedReceivables();
        if (actual <= booked) return;
        uint256 surplus = actual - booked;
        receivable += surplus;
        totalProceedsBooked += surplus;
        _margin += surplus.toInt256();
        _splitMargin();
        emit SurplusBooked(surplus);
    }

    /// @dev Withdraws engine proceeds into the buckets when the walk is level.
    function _harvest() internal {
        if (nextSequenceToBook != engine.nextSequenceToProcess()) return;
        uint256 available = engine.proceedsOf(address(this));
        if (available == 0) return;
        uint256 expected = _bookedReceivables();
        uint256 received = engine.withdrawProceeds();
        if (received < expected) {
            uint256 gap = expected - received;
            uint256 cut = gap < receivable ? gap : receivable;
            receivable -= cut;
            gap -= cut;
            cut = gap < maintenanceReceivable ? gap : maintenanceReceivable;
            maintenanceReceivable -= cut;
            gap -= cut;
            feedReceivable -= gap < feedReceivable ? gap : feedReceivable;
            emit HarvestShortfall(received, expected);
        }
        cash += receivable;
        maintenance += maintenanceReceivable;
        uint256 feed = feedReceivable;
        receivable = 0;
        maintenanceReceivable = 0;
        feedReceivable = 0;
        emit Harvested(received);
        if (feed != 0) {
            totalFeedSent += feed;
            grailVault.fundGrail{value: feed}();
        }
    }

    // ------------------------------------------------------------------ board

    function _boardCount() internal view returns (uint256 n) {
        for (uint256 r; r < _mix.length; ++r) {
            n += _rowCount[r] + _queuedByRow[r];
        }
    }

    function _queueMissing() internal {
        uint256 items = boardItems;
        for (uint256 r; r < _mix.length; ++r) {
            uint256 target = PricingLib.rowDepth(items, _mix[r].shareBps);
            while (_rowCount[r] + _queuedByRow[r] < target) {
                _enqueue(r);
            }
        }
    }

    /// @dev Fills queued replacements in order and lists them, then lists held items, at most `max`.
    function _listBatch(uint256 max) internal returns (uint256 n) {
        if (listingPaused || max == 0) return 0;
        uint256 fee = shapes.mintFee();
        Item[] memory batch = new Item[](max);
        uint256 head = replacementHead;
        uint256 length = _replacementQueue.length;
        while (head < length && n < max) {
            uint256 row = _replacementQueue[head];
            (Item memory it, bool ok) = _fill(row, fee);
            if (!ok) break;
            batch[n++] = it;
            --_queuedByRow[row];
            ++head;
        }
        replacementHead = head;
        while (n < max && _held.length != 0) {
            batch[n++] = _removeHeld(_held.length - 1);
        }
        _listItems(batch, n, fee);
        if (n != 0) emit Listed(n);
    }

    function _spendable() internal view returns (uint256) {
        return cash > cashFloor ? cash - cashFloor : 0;
    }

    /// @dev PoolListing._fill: a Shape row takes a held Shape of its rung, else mints one; a pack row
    ///      takes a held pack of equal backing, else creates one from held Shapes and fresh mints.
    function _fill(uint256 row, uint256 fee) internal returns (Item memory it, bool ok) {
        uint8[] storage rungs = _mix[row].rungs;
        uint256 n = rungs.length;
        uint256 value = _rowBackingWei[row];
        it.row = uint16(row);
        it.value = value;
        if (n == 1) {
            uint256[] storage held = _heldByDenom[rungs[0]];
            if (held.length != 0) {
                it = _removeHeld(_heldPos[address(shapes)][held[held.length - 1]] - 1);
                it.row = uint16(row);
                return (it, true);
            }
            if (_spendable() < value + fee) return (it, false);
            cash -= value + fee;
            totalMintFeesPaid += fee;
            it.collection = address(shapes);
            it.tokenId = shapes.mintBatchTo{value: value + fee}(value, 1, address(this));
            return (it, true);
        }

        if (_heldPacks != 0) {
            for (uint256 i = _held.length; i != 0; --i) {
                Item storage candidate = _held[i - 1];
                if (candidate.collection == address(drawPacks) && candidate.value == value) {
                    it = _removeHeld(i - 1);
                    it.row = uint16(row);
                    return (it, true);
                }
            }
        }
        uint256[] memory used = new uint256[](Denominations.COUNT);
        bool[] memory fromHeld = new bool[](n);
        uint32[] memory counts = new uint32[](Denominations.COUNT);
        uint256 cost;
        uint256 minted;
        for (uint256 i; i < n; ++i) {
            uint8 d = rungs[i];
            if (_heldByDenom[d].length > used[d]) {
                ++used[d];
                fromHeld[i] = true;
            } else {
                ++counts[d];
                ++minted;
                cost += Denominations.amountAt(d) + fee;
            }
        }
        if (cost != 0 && _spendable() < cost) return (it, false);
        cash -= cost;
        totalMintFeesPaid += fee * minted;
        uint256[] memory ids = new uint256[](n - minted);
        uint256 k;
        for (uint256 i; i < n; ++i) {
            if (!fromHeld[i]) continue;
            uint256[] storage held = _heldByDenom[rungs[i]];
            uint256 id = held[held.length - 1];
            _removeHeld(_heldPos[address(shapes)][id] - 1);
            ids[k++] = id;
        }
        it.collection = address(drawPacks);
        it.tokenId = drawPacks.createPack{value: cost}(ids, counts);
        if (IERC721Value(address(drawPacks)).valueOf(it.tokenId) != value) revert PackValueMismatch();
        return (it, true);
    }

    function _listItems(Item[] memory batch, uint256 n, uint256 fee) internal {
        if (n == 0) return;
        uint256 chunk = engine.MAX_INVENTORY_BATCH();
        FeeSplit memory split = feeSplit;
        for (uint256 start; start < n; start += chunk) {
            uint256 m = n - start < chunk ? n - start : chunk;
            DrawEngine.ListingInput[] memory inputs = new DrawEngine.ListingInput[](m);
            for (uint256 i; i < m; ++i) {
                Item memory it = batch[start + i];
                inputs[i] = DrawEngine.ListingInput(
                    it.collection,
                    it.tokenId,
                    PricingLib.listingPrice(
                        it.value, split.premiumBps, split.maintenanceBps, split.feedBps, fee * _mix[it.row].rungs.length
                    )
                );
            }
            uint256[] memory ids = engine.listNFTs(inputs);
            for (uint256 i; i < m; ++i) {
                Item memory it = batch[start + i];
                it.listingId = ids[i];
                _addItem(it);
            }
        }
    }

    // ------------------------------------------------------------------ registry

    function _addItem(Item memory it) internal {
        if (it.listingId == 0) {
            _held.push(it);
            _heldPos[it.collection][it.tokenId] = _held.length;
            if (it.collection == address(shapes)) {
                uint256[] storage ids = _heldByDenom[uint8(Denominations.requireIndexOf(it.value))];
                ids.push(it.tokenId);
                _denomPos[it.tokenId] = ids.length;
            } else {
                ++_heldPacks;
            }
        } else {
            _listed[it.listingId] = it;
            ++listedCount;
            uint256[] storage ids = _listedByRow[it.row];
            _listedIndex[it.listingId] = ids.length;
            ids.push(it.listingId);
        }
        backing += it.value;
        ++_rowCount[it.row];
    }

    function _removeHeld(uint256 index) internal returns (Item memory it) {
        uint256 last = _held.length - 1;
        it = _held[index];
        if (index != last) {
            Item memory moved = _held[last];
            _held[index] = moved;
            _heldPos[moved.collection][moved.tokenId] = index + 1;
        }
        _held.pop();
        delete _heldPos[it.collection][it.tokenId];
        if (it.collection == address(shapes)) {
            uint256[] storage ids = _heldByDenom[uint8(Denominations.requireIndexOf(it.value))];
            uint256 pos = _denomPos[it.tokenId] - 1;
            uint256 lastId = ids[ids.length - 1];
            ids[pos] = lastId;
            _denomPos[lastId] = pos + 1;
            ids.pop();
            delete _denomPos[it.tokenId];
        } else {
            --_heldPacks;
        }
        backing -= it.value;
        --_rowCount[it.row];
    }

    function _removeListed(uint256 listingId) internal returns (Item memory it) {
        it = _listed[listingId];
        if (it.value == 0) revert UnknownListing(listingId);
        delete _listed[listingId];
        uint256[] storage ids = _listedByRow[it.row];
        uint256 lastId = ids[ids.length - 1];
        uint256 index = _listedIndex[listingId];
        ids[index] = lastId;
        _listedIndex[lastId] = index;
        ids.pop();
        backing -= it.value;
        --_rowCount[it.row];
        --listedCount;
    }

    function _refundKeeper(uint256 gasStart) internal {
        uint256 cost = (gasStart - gasleft() + REFUND_GAS_OVERHEAD) * block.basefee + tipWei;
        uint256 amount = cost < maintenance ? cost : maintenance;
        if (amount == 0) return;
        maintenance -= amount;
        emit KeeperRefund(msg.sender, amount);
        SafeTransferLib.forceSafeTransferETH(msg.sender, amount);
    }

    /// @dev The controller receives Shapes it mints and Draw Packs it creates; anything else reverts.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(shapes) && msg.sender != address(drawPacks) && msg.sender != address(engine)) {
            revert UnexpectedToken();
        }
        return this.onERC721Received.selector;
    }

    // ------------------------------------------------------------------ administration

    /// @notice Guardian or governance stops or resumes minting and listing.
    function setListingPaused(bool value) external {
        if (msg.sender != guardian && msg.sender != governance) revert NotGuardian();
        listingPaused = value;
        emit ListingPausedSet(value);
    }

    function setGuardian(address next) external onlyGovernance {
        if (next == address(0)) revert ZeroAddress();
        guardian = next;
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

    function setFeeSplit(FeeSplit calldata s) external onlyGovernance {
        _setFeeSplit(s);
    }

    function setMix(PricingLib.MixRow[] calldata rows) external onlyGovernance {
        _setMix(rows);
    }

    function setBoard(uint256 items, uint256 floorWei) external onlyGovernance {
        _setBoard(items, floorWei);
    }

    function setReplacement(uint256 surprise, uint256 restore, uint256 band) external onlyGovernance {
        _setReplacement(surprise, restore, band);
    }

    function setTip(uint256 tip) external onlyGovernance {
        _setTip(tip);
    }

    function setTargets(uint256 capital, uint256 maintenanceFloor_) external onlyGovernance {
        capitalTarget = capital;
        maintenanceFloor = maintenanceFloor_;
    }

    function setSurplusSink(address sink, uint64 releaseStart) external onlyGovernance {
        surplusSink = sink;
        surplusReleaseStart = releaseStart;
    }

    /// @notice Lists an NFT of another collection, already owned by the controller (a sponsorship or
    ///         partner prize), at `notional`. Captures book their proceeds as margin. Governance.
    function listExternal(address collection, uint256 tokenId, uint256 notional)
        external
        onlyGovernance
        nonReentrant
        returns (uint256 listingId)
    {
        if (collection == address(shapes) || collection == address(drawPacks)) revert UnexpectedToken();
        IERC721(collection).approve(address(engine), tokenId);
        listingId = engine.listNFT(collection, tokenId, notional);
        externalItems[listingId] = ExternalItem(collection, tokenId, notional);
    }

    /// @notice Hands ordinary listings to a successor supplier (a new controller) without moving
    ///         their NFTs. They leave this controller's books at their backing. Governance; the
    ///         engine allows it only while no acquisition is unresolved.
    function handOffListings(uint256[] calldata listingIds, address successor) external onlyGovernance nonReentrant {
        for (uint256 i; i < listingIds.length; ++i) {
            _removeListed(listingIds[i]);
        }
        engine.transferListings(listingIds, successor);
    }

    function _setFeeSplit(FeeSplit memory s) internal {
        if (uint256(s.premiumBps) + s.maintenanceBps + s.feedBps > MAX_FEE_SPLIT_BPS) revert FeeSplitTooHigh();
        feeSplit = s;
    }

    function _setBoard(uint256 items, uint256 floorWei) internal {
        if (items == 0 || items > 1_000) revert LimitOutOfRange();
        boardItems = items;
        cashFloor = floorWei;
    }

    function _setReplacement(uint256 surprise, uint256 restore, uint256 band) internal {
        if (surprise > BPS || restore > MAX_RESTORE_K || band > MAX_BAND_BPS) revert LimitOutOfRange();
        surpriseBps = surprise;
        restoreK = restore;
        bandBps = band;
    }

    function _setTip(uint256 tip) internal {
        if (tip > MAX_TIP) revert LimitOutOfRange();
        tipWei = tip;
    }

    /// @dev PoolStorage._setMix: a row that holds items keeps its rungs; no row with items or queued
    ///      replacements may be dropped. The table may grow.
    function _setMix(PricingLib.MixRow[] memory rows) internal {
        uint256 n = rows.length;
        if (n == 0 || n > MAX_ROWS) revert PricingLib.EmptyRow();
        for (uint256 i; i < _mix.length; ++i) {
            if (_rowCount[i] == 0 && _queuedByRow[i] == 0) continue;
            uint8[] storage old = _mix[i].rungs;
            if (i >= n || old.length != rows[i].rungs.length) revert RowInUse();
            for (uint256 j; j < old.length; ++j) {
                if (old[j] != rows[i].rungs[j]) revert RowInUse();
            }
        }
        delete _mix;
        delete _rowBackingWei;
        for (uint256 i; i < n; ++i) {
            if (rows[i].rungs.length > 1) {
                // Draw Packs need at least MIN_PACK_VALUE; PricingLib.rowBacking checks the rungs.
                if (PricingLib.rowBacking(rows[i]) < drawPacks.MIN_PACK_VALUE()) revert LimitOutOfRange();
            }
            _rowBackingWei.push(PricingLib.rowBacking(rows[i]));
            if (_rowCount.length < n) {
                _rowCount.push();
                _queuedByRow.push();
                _listedByRow.push();
            }
            _mix.push();
            PricingLib.MixRow storage row = _mix[i];
            row.shareBps = rows[i].shareBps;
            for (uint256 j; j < rows[i].rungs.length; ++j) {
                row.rungs.push(rows[i].rungs[j]);
            }
        }
    }
}
