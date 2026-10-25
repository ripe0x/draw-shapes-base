// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";
import {DrawEngine} from "./engine/DrawEngine.sol";
import {DrawController} from "./game/DrawController.sol";
import {GrailVault} from "./game/GrailVault.sol";
import {PricingLib} from "./game/PricingLib.sol";
import {GenesisFarm} from "./token/GenesisFarm.sol";
import {EngineHook} from "./token/EngineHook.sol";
import {ProtocolLiquidity} from "./token/ProtocolLiquidity.sol";
import {Treasury} from "./treasury/Treasury.sol";

/// @title Lens
/// @notice Read-only views for the frontend and keepers. Holds no state and no authority; it can be
///         replaced by deploying a new one.
contract Lens {
    using StateLibrary for IPoolManager;

    struct Addresses {
        address engine;
        address controller;
        address vault;
        address farm;
        address hook;
        address liquidity;
        address treasury;
        address buyback;
        address token;
        address poolManager;
    }

    struct Quote {
        uint256 fee;
        uint256 settlementFee;
        uint256 vrfFee;
        uint256 total;
        uint256 inventoryVersion;
        bool purchasable;
        string reason;
    }

    struct RowView {
        uint256 backing;
        uint256 notional;
        uint256 listed;
        uint256 queued;
        uint256 target;
        uint256 oddsPpm;
        uint8[] rungs;
    }

    struct GrailView {
        uint256 targetWei;
        uint256 mintFee;
        uint256 funded;
        uint256 cycleId;
        GrailVault.GrailItem[] items; // fully funded GRAILs held by the vault
        uint256[] oddsPpm; // per-pull odds, nonzero only while the listing is selectable (Active)
        uint8[] status; // DrawEngine.ListingStatus of each GRAIL's listing (0 = awaiting relist)
        uint256[] nextNotional; // notional the next vault step sets (0 = unchanged)
        uint256 selectable; // GRAILs a pull can draw now
    }

    struct GameView {
        bool activated;
        bool paused;
        uint256 activeListings;
        uint256 stagedListings;
        uint256 unsettled;
        uint64 nextToProcess;
        uint64 lastIssued;
        uint64 nextToBook;
        uint256 cash;
        uint256 backing;
        uint256 receivable;
        uint256 maintenance;
        uint256 nav;
        uint256 capitalTarget;
        uint256 expectedBackingPerPull;
    }

    struct GenesisView {
        bool started;
        uint256 start;
        uint256 end;
        uint256 currentEpoch;
        uint256 allocationPerEpoch;
        uint256 epochUnits;
        uint256 epochBonus;
        uint256 userUnits;
        uint256 userBonus;
        uint256 userClaimable;
        uint256 totalClaimed;
    }

    struct MarketView {
        uint160 sqrtPriceX96;
        uint256 ethPerEngineE18;
        uint256 feeBps;
        uint256 operatorBps;
        uint256 totalFees;
        uint256 totalVolume;
        uint256 treasuryReserve;
        uint256 treasuryPolPending;
        uint256 treasuryToGrail;
    }

    /// @notice Settlement receipt of one acquisition, assembled from the engine's own persistent
    ///         records (no duplicate storage): status, parties, fees, the prize and its ledger credit.
    struct Receipt {
        uint8 status; // DrawEngine.AcquisitionStatus
        address purchaser; // beneficiary: prize, units, refund credit
        address referrer;
        uint256 acquisitionFee;
        uint256 settlementFee;
        uint32 feePolicyId;
        uint256 listingId;
        address collection;
        uint256 tokenId;
        address depositor;
        uint256 notional;
        uint64 ledgerDay;
        uint256 randomWord;
        uint256 bonusWeight; // nonzero only once fulfilled
        uint256 vrfRequestId;
        bool final_; // fulfilled or refunded: no further transition
        bool bookedByController; // the controller's walk has passed it (exactly-once booking)
    }

    struct VrfView {
        uint256 feesCollected;
        uint256 subscriptionBalance;
        uint256 feeOne;
        uint256 feeTen;
        uint256 feeTwenty;
        uint256 basefee;
    }

    Addresses internal a;

    constructor(Addresses memory addrs) {
        a = addrs;
    }

    function addresses() external view returns (Addresses memory) {
        return a;
    }

    function quote(uint256 count) external view returns (Quote memory q) {
        DrawEngine e = DrawEngine(payable(a.engine));
        q.inventoryVersion = e.inventoryVersion();
        if (count == 0 || count > e.maxAcquisitionsPerTx()) return _no(q, "count out of range");
        (q.fee, q.settlementFee, q.vrfFee, q.total) = e.quoteAcquisitionPrice(count);
        if (!e.activated()) return _no(q, "not open yet");
        if (e.paused()) return _no(q, "paused");
        if (e.retired()) return _no(q, "retired");
        if (e.totalWeight() == 0) return _no(q, "board empty");
        if (e.unsettledAcquisitionCount() + count > e.maxUnsettledAcquisitions()) return _no(q, "too many pending");
        if (block.timestamp < e.purchasesResumeAt()) return _no(q, "inventory cooldown");
        q.purchasable = true;
    }

    function _no(Quote memory q, string memory reason) internal pure returns (Quote memory) {
        q.reason = reason;
        return q;
    }

    function board() external view returns (RowView[] memory rows) {
        DrawController c = DrawController(payable(a.controller));
        DrawEngine e = DrawEngine(payable(a.engine));
        uint256 total = e.totalWeight();
        uint256 n = c.mixLength();
        rows = new RowView[](n);
        for (uint256 i; i < n; ++i) {
            RowView memory r = rows[i];
            uint16 shareBps;
            (r.rungs, shareBps, r.backing) = c.mixRow(i);
            r.notional = c.rowNotional(i);
            (r.listed, r.queued) = c.rowCount(i);
            r.target = PricingLib.rowDepth(c.boardItems(), shareBps);
            if (total != 0) r.oddsPpm = FP.fullMulDiv(r.listed * (1e36 / r.notional), 1e6, total);
        }
    }

    function grail() external view returns (GrailView memory g) {
        GrailVault v = GrailVault(payable(a.vault));
        (g.targetWei, g.mintFee, g.funded) = v.progress();
        g.cycleId = v.cycleId();
        g.items = v.items();
        g.oddsPpm = new uint256[](g.items.length);
        g.status = new uint8[](g.items.length);
        g.nextNotional = v.repricePlan();
        DrawEngine e = DrawEngine(payable(a.engine));
        uint256 total = e.totalWeight();
        for (uint256 i; i < g.items.length; ++i) {
            if (g.items[i].listingId == 0) continue;
            (,,,,,,, DrawEngine.ListingStatus st) = e.listings(g.items[i].listingId);
            g.status[i] = uint8(st);
            if (st == DrawEngine.ListingStatus.Active && total != 0) {
                g.oddsPpm[i] = FP.fullMulDiv(1e36 / g.items[i].notional, 1e6, total);
                ++g.selectable;
            }
        }
    }

    function game() external view returns (GameView memory g) {
        DrawEngine e = DrawEngine(payable(a.engine));
        DrawController c = DrawController(payable(a.controller));
        g.activated = e.activated();
        g.paused = e.paused();
        g.activeListings = e.activeListingCount();
        g.stagedListings = e.stagedCount();
        g.unsettled = e.unsettledAcquisitionCount();
        g.nextToProcess = e.nextSequenceToProcess();
        g.lastIssued = e.lastIssuedSequence();
        g.nextToBook = c.nextSequenceToBook();
        g.cash = c.cash();
        g.backing = c.backing();
        g.receivable = c.receivable();
        g.maintenance = c.maintenance();
        g.nav = c.nav();
        g.capitalTarget = c.capitalTarget();
        // expected backing of one pull: Σ count·w·b / Σ w over ordinary rows (GRAILs add to it)
        uint256 total = e.totalWeight();
        if (total != 0) {
            uint256 num;
            for (uint256 i; i < c.mixLength(); ++i) {
                (uint256 listed,) = c.rowCount(i);
                (,, uint256 b) = c.mixRow(i);
                num += listed * (1e36 / c.rowNotional(i)) * b;
            }
            GrailVault.GrailItem[] memory items = GrailVault(payable(a.vault)).items();
            for (uint256 i; i < items.length; ++i) {
                if (items[i].listingId != 0) num += (1e36 / items[i].notional) * items[i].backing;
            }
            g.expectedBackingPerPull = num / total;
        }
    }

    function genesis(address user) external view returns (GenesisView memory v) {
        GenesisFarm f = GenesisFarm(a.farm);
        DrawEngine e = DrawEngine(payable(a.engine));
        v.started = e.activated();
        v.allocationPerEpoch = f.allocationOf(0);
        v.totalClaimed = f.totalClaimed();
        if (!v.started) return v;
        (v.start, v.end) = f.schedule();
        v.currentEpoch = f.currentEpoch();
        uint256 day = v.currentEpoch < f.EPOCHS() ? v.currentEpoch : f.EPOCHS() - 1;
        (,, uint64 units, uint64 bonus) = e.dayTotals(day);
        (v.epochUnits, v.epochBonus) = (units, bonus);
        (uint64 mu, uint64 mb) = e.userDay(day, user);
        (v.userUnits, v.userBonus) = (mu, mb);
        v.userClaimable = f.claimable(user);
    }

    function receipt(uint256 requestId) external view returns (Receipt memory r) {
        DrawEngine e = DrawEngine(payable(a.engine));
        uint256 paid;
        DrawEngine.AcquisitionStatus st;
        (r.purchaser,, paid, r.listingId, st) = e.acquisitions(requestId);
        r.status = uint8(st);
        r.acquisitionFee = paid;
        uint96 sfee;
        (r.referrer, sfee, r.feePolicyId) = e.settlementTerms(requestId);
        r.settlementFee = sfee;
        (,, r.ledgerDay,,, r.randomWord) = e.acquisitionMeta(requestId);
        r.vrfRequestId = e.vrfRequestOf(requestId);
        if (r.listingId != 0) {
            (r.collection, r.depositor,, r.tokenId,, r.notional,,) = e.listings(r.listingId);
        }
        r.final_ = st == DrawEngine.AcquisitionStatus.Fulfilled || st == DrawEngine.AcquisitionStatus.Expired
            || st == DrawEngine.AcquisitionStatus.Refunded || st == DrawEngine.AcquisitionStatus.DeliveryRefunded;
        if (st == DrawEngine.AcquisitionStatus.Fulfilled) r.bonusWeight = e.bonusWeightOf(r.randomWord);
        r.bookedByController = DrawController(payable(a.controller)).nextSequenceToBook() > requestId;
    }

    function vrf() external view returns (VrfView memory v) {
        DrawEngine e = DrawEngine(payable(a.engine));
        v.feesCollected = e.vrfFeesCollected();
        (, uint96 nativeBalance,,,) = e.vrfCoordinator().getSubscription(e.vrfSubscriptionId());
        v.subscriptionBalance = nativeBalance;
        v.feeOne = e.vrfFeeFor(1);
        v.feeTen = e.vrfFeeFor(10);
        v.feeTwenty = e.vrfFeeFor(20);
        v.basefee = block.basefee;
    }

    function market() external view returns (MarketView memory m) {
        EngineHook h = EngineHook(payable(a.hook));
        ProtocolLiquidity l = ProtocolLiquidity(payable(a.liquidity));
        if (l.launched()) {
            m.sqrtPriceX96 = l.sqrtPriceX96();
            uint256 p = m.sqrtPriceX96;
            if (p != 0) m.ethPerEngineE18 = FP.fullMulDiv(1 << 192, 1e18, p) / p;
        }
        m.feeBps = h.feeBps();
        m.operatorBps = h.operatorBps();
        m.totalFees = h.totalFees();
        m.totalVolume = h.totalVolume();
        Treasury t = Treasury(payable(a.treasury));
        m.treasuryReserve = t.reserve();
        m.treasuryPolPending = t.polPending();
        m.treasuryToGrail = t.totalToGrail();
    }
}
