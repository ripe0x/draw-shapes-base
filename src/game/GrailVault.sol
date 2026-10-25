// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IShapes} from "shapes/interfaces/IShapes.sol";
import {Denominations} from "shapes/lib/Denominations.sol";
import {PricingLib} from "./PricingLib.sol";
import {DrawEngine} from "../engine/DrawEngine.sol";

/// @title GrailVault
/// @notice Holds the GRAIL fund and lists fully funded GRAILs on the engine as its own supplier.
///         A GRAIL is one Shape of the ladder rung being funded. It is minted only when the fund
///         covers its whole backing and mint fee, listed at `listBps` of its backing (below its
///         backing, as in Draw Shapes), and its notional decays per processed pull to a floor while
///         the GRAIL selection weight stays under `probCapBps`.
/// @dev Funding: the controller's feed share of every harvest, the treasury's trading-fee share and
///      `fundGrail` from anyone. The proceeds of a captured GRAIL return to the fund. The fund pays
///      only GRAIL backing and mint fees. Ported from the Draw Shapes `PoolListing` GRAIL engine
///      (commit 4a13a09) without its 1 ETH piece / merge builder: Base targets are native rungs.
contract GrailVault is ReentrancyGuard {
    struct GrailConfig {
        uint16 listBps;
        uint16 floorBps;
        uint16 probCapBps;
        uint32 stepUpSeconds;
        uint32 stepDownSeconds;
        uint256 decayWeiPerPull;
    }

    struct GrailItem {
        uint256 tokenId;
        uint256 backing;
        uint256 notional;
        uint256 listingId;
        uint64 listedAtPull;
    }

    uint256 internal constant BPS = 10_000;
    uint256 public constant MAX_GRAILS = 4;

    IShapes public immutable shapes;
    DrawEngine public immutable engine;

    address public governance;
    address public pendingGovernance;
    address public guardian;
    bool public paused;

    GrailConfig public config;
    uint8[] internal _ladder;
    uint8 public level;
    uint64 public cycleId = 1;
    uint64 public cycleStartedAt;

    uint256 public fund;
    GrailItem[] internal _items;

    uint256 public totalFunded;
    uint256 public totalProceeds;
    uint256 public totalBackingMinted;
    uint256 public totalMintFeesPaid;
    uint256 public totalBackingCaptured;

    event Funded(address indexed from, uint256 amount);
    event GrailMinted(uint256 indexed tokenId, uint256 backing, uint256 cost);
    event GrailListed(uint256 indexed listingId, uint256 tokenId, uint256 backing, uint256 notional);
    event GrailCaptured(uint256 indexed listingId, uint256 tokenId, uint256 backing);
    event GrailRecovered(uint256 indexed listingId, uint256 tokenId);
    event GrailCycleCompleted(uint256 indexed cycleId, uint256 nextTargetWei);
    event ProceedsHarvested(uint256 amount);
    event ParamSet(bytes4 indexed selector);

    error NotGovernance();
    error NotGuardian();
    error ConfigInvalid();
    error UnexpectedSender();

    constructor(
        address shapes_,
        address engine_,
        address governance_,
        address guardian_,
        GrailConfig memory c,
        uint8[] memory ladder_
    ) {
        if (shapes_ == address(0) || engine_ == address(0) || governance_ == address(0) || guardian_ == address(0)) {
            revert ConfigInvalid();
        }
        shapes = IShapes(shapes_);
        engine = DrawEngine(payable(engine_));
        governance = governance_;
        guardian = guardian_;
        _setConfig(c);
        _setLadder(ladder_);
        IERC721(shapes_).setApprovalForAll(engine_, true);
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        emit ParamSet(msg.sig);
        _;
    }

    receive() external payable {
        if (msg.sender != address(engine) && msg.sender != address(shapes)) revert UnexpectedSender();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(shapes)) revert UnexpectedSender();
        return this.onERC721Received.selector;
    }

    /// @notice Adds `msg.value` to the GRAIL fund.
    function fundGrail() external payable {
        fund += msg.value;
        totalFunded += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Engine sequences processed so far: the pull clock of the decay.
    function pulls() public view returns (uint64) {
        return engine.nextSequenceToProcess() - 1;
    }

    /// @notice Backing of the GRAIL being funded, its mint fee, and the fund toward them.
    function progress() external view returns (uint256 targetWei, uint256 mintFee, uint256 funded) {
        targetWei = nextTarget();
        mintFee = shapes.mintFee();
        funded = fund + engine.proceedsOf(address(this));
    }

    /// @notice Backing of the next GRAIL. While no GRAIL is live it is the smallest rung, so a
    ///         captured headline prize is replaced as fast as possible; otherwise the current rung.
    function nextTarget() public view returns (uint256) {
        return Denominations.amountAt(_ladder[_items.length == 0 ? 0 : level]);
    }

    /// @notice Number of GRAILs currently held (listed or awaiting relist).
    function liveGrails() external view returns (uint256) {
        return _items.length;
    }

    function items() external view returns (GrailItem[] memory) {
        return _items;
    }

    function ladder() external view returns (uint8[] memory) {
        return _ladder;
    }

    /// @notice Syncs captured and refunded GRAILs, harvests proceeds into the fund, relists, mints a
    ///         GRAIL when fully funded and decays listed prices while the engine is idle. Anyone.
    function step() external nonReentrant returns (bool changed) {
        changed = _sync();
        uint256 proceeds = engine.proceedsOf(address(this));
        if (proceeds != 0) {
            engine.withdrawProceeds();
            fund += proceeds;
            totalProceeds += proceeds;
            emit ProceedsHarvested(proceeds);
        }
        if (paused) return changed;
        if (_relist()) changed = true;
        if (_mint()) changed = true;
        if (_reprice()) changed = true;
    }

    /// @notice True when `step` would change inventory or harvest.
    function stepDue() external view returns (bool) {
        if (engine.proceedsOf(address(this)) != 0) return true;
        for (uint256 i; i < _items.length; ++i) {
            uint256 id = _items[i].listingId;
            if (id == 0) return !paused;
            DrawEngine.ListingStatus s = _status(id);
            if (s == DrawEngine.ListingStatus.Settled || s == DrawEngine.ListingStatus.DeliveryRefunded) return true;
        }
        if (paused) return false;
        uint256 target = nextTarget();
        if (fund >= target + shapes.mintFee() && _items.length < MAX_GRAILS) return true;
        uint256[] memory next = _repricePlan();
        for (uint256 i; i < next.length; ++i) {
            if (next[i] != 0) return true;
        }
        return false;
    }

    /// @notice Notionals the next `step` would set, per held GRAIL (0 = unchanged).
    function repricePlan() external view returns (uint256[] memory) {
        return _repricePlan();
    }

    function _status(uint256 listingId) internal view returns (DrawEngine.ListingStatus status) {
        (,,,,,,, status) = engine.listings(listingId);
    }

    function _sync() internal returns (bool changed) {
        for (uint256 i = _items.length; i != 0; --i) {
            GrailItem storage it = _items[i - 1];
            if (it.listingId == 0) continue;
            DrawEngine.ListingStatus s = _status(it.listingId);
            if (s == DrawEngine.ListingStatus.Settled) {
                emit GrailCaptured(it.listingId, it.tokenId, it.backing);
                totalBackingCaptured += it.backing;
                _items[i - 1] = _items[_items.length - 1];
                _items.pop();
                changed = true;
            } else if (s == DrawEngine.ListingStatus.DeliveryRefunded) {
                engine.recoverRefundedNFT(it.listingId);
                emit GrailRecovered(it.listingId, it.tokenId);
                it.listingId = 0;
                changed = true;
            }
        }
    }

    function _relist() internal returns (bool listed) {
        for (uint256 i; i < _items.length; ++i) {
            GrailItem storage it = _items[i];
            if (it.listingId != 0) continue;
            it.listingId = engine.listNFT(address(shapes), it.tokenId, it.notional);
            it.listedAtPull = pulls();
            emit GrailListed(it.listingId, it.tokenId, it.backing, it.notional);
            listed = true;
        }
    }

    function _mint() internal returns (bool) {
        uint256 fee = shapes.mintFee();
        uint256 target = nextTarget();
        if (fund < target + fee || _items.length >= MAX_GRAILS) return false;
        // replacing a won GRAIL (none live, not the first cycle) does not move the ladder
        bool replacement = _items.length == 0 && cycleId != 1;
        fund -= target + fee;
        totalBackingMinted += target;
        totalMintFeesPaid += fee;
        uint256 id = shapes.mintBatchTo{value: target + fee}(target, 1, address(this));
        emit GrailMinted(id, target, target + fee);
        uint256 notional = PricingLib.grailNotional(target, config.listBps);
        uint256 listingId = engine.listNFT(address(shapes), id, notional);
        _items.push(GrailItem(id, target, notional, listingId, pulls()));
        emit GrailListed(listingId, id, target, notional);

        uint64 started = cycleStartedAt;
        if (started != 0 && !replacement) {
            uint256 elapsed = block.timestamp - started;
            if (elapsed < config.stepUpSeconds && level + 1 < _ladder.length) ++level;
            else if (elapsed > config.stepDownSeconds && level != 0) --level;
        }
        emit GrailCycleCompleted(cycleId++, Denominations.amountAt(_ladder[level]));
        cycleStartedAt = uint64(block.timestamp);
        return true;
    }

    function _reprice() internal returns (bool changed) {
        uint256[] memory next = _repricePlan();
        uint64 now_ = pulls();
        for (uint256 i; i < next.length; ++i) {
            if (next[i] == 0) continue;
            GrailItem storage it = _items[i];
            engine.updatePrice(it.listingId, next[i]);
            it.notional = next[i];
            it.listedAtPull = now_;
            emit GrailListed(it.listingId, it.tokenId, it.backing, next[i]);
            changed = true;
        }
    }

    /// @notice Notionals `step` would set now, per held GRAIL (0 = unchanged). Empty unless the engine
    ///         has no unsettled acquisition (weights never move under an outstanding draw) and every
    ///         held GRAIL is active. Each GRAIL decays by `decayWeiPerPull` per processed pull since it
    ///         was last priced, to `floorBps` of backing, and never below the notional at which the
    ///         combined GRAIL weight would exceed `probCapBps` of the engine weight; a change under
    ///         1 % waits (the decay keeps accruing).
    function _repricePlan() internal view returns (uint256[] memory next) {
        uint256 n = _items.length;
        next = new uint256[](n);
        if (paused || n == 0 || engine.unsettledAcquisitionCount() != 0) return next;
        uint256 weight;
        for (uint256 i; i < n; ++i) {
            if (_items[i].listingId == 0 || _status(_items[i].listingId) != DrawEngine.ListingStatus.Active) {
                return new uint256[](n);
            }
            weight += PricingLib.weightOf(_items[i].notional);
        }
        uint256 total = engine.totalWeight();
        uint64 now_ = pulls();
        uint256 cap = config.probCapBps;
        for (uint256 i; i < n; ++i) {
            GrailItem storage it = _items[i];
            uint256 old = it.notional;
            uint256 target = PricingLib.decayedNotional(
                old, config.decayWeiPerPull, now_ - it.listedAtPull, it.backing * config.floorBps / BPS
            );
            if (target >= old) continue;
            uint256 oldWeight = PricingLib.weightOf(old);
            // largest weight this GRAIL may take with the others unchanged:
            // (others + w) * BPS <= cap * (rest + w)  =>  w <= (cap * rest - BPS * others) / (BPS - cap)
            uint256 others = weight - oldWeight;
            uint256 rest = total - oldWeight;
            if (cap * rest <= BPS * others) continue;
            uint256 maxWeight = cap >= BPS ? type(uint256).max : (cap * rest - BPS * others) / (BPS - cap);
            if (maxWeight <= oldWeight) continue;
            uint256 capNotional = PricingLib.NUM / maxWeight + 1;
            if (target < capNotional) target = capNotional;
            if (target >= old || old - target < old / 100) continue;
            uint256 nextWeight = PricingLib.weightOf(target);
            (weight, total) = (others + nextWeight, rest + nextWeight);
            next[i] = target;
        }
    }

    // ------------------------------------------------------------------ administration

    function setPaused(bool value) external {
        if (msg.sender != guardian && msg.sender != governance) revert NotGuardian();
        paused = value;
    }

    function setGuardian(address next) external onlyGovernance {
        if (next == address(0)) revert ConfigInvalid();
        guardian = next;
    }

    function proposeGovernance(address next) external onlyGovernance {
        pendingGovernance = next;
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernance || msg.sender == address(0)) revert NotGovernance();
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    function setConfig(GrailConfig calldata c) external onlyGovernance {
        _setConfig(c);
    }

    function setLadder(uint8[] calldata ladder_) external onlyGovernance {
        _setLadder(ladder_);
    }

    function _setConfig(GrailConfig memory c) internal {
        if (
            c.listBps == 0 || c.listBps > BPS || c.floorBps == 0 || c.floorBps > c.listBps || c.probCapBps == 0
                || c.probCapBps > BPS || c.stepUpSeconds >= c.stepDownSeconds
        ) revert ConfigInvalid();
        config = c;
    }

    function _setLadder(uint8[] memory ladder_) internal {
        if (ladder_.length == 0 || ladder_.length > Denominations.COUNT) revert ConfigInvalid();
        for (uint256 i; i < ladder_.length; ++i) {
            if (ladder_[i] >= Denominations.COUNT || (i != 0 && ladder_[i] <= ladder_[i - 1])) revert ConfigInvalid();
        }
        _ladder = ladder_;
        if (level >= ladder_.length) level = uint8(ladder_.length - 1);
    }
}
