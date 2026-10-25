// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";

/// @notice GRAIL decay liveness: a keeper that calls `step()` only when `stepDue()` (web/scripts/keeper.mjs)
///         runs the whole decay schedule, across skipped intervals, several GRAILs, the probability
///         cap, newly funded GRAILs and outstanding acquisitions.
contract GrailRepriceTest is GameFixture {
    uint256 internal salt;

    function setUp() public override {
        super.setUp();
        _openAndActivate();
        // faster decay so the full schedule fits a unit test: 0.001 ETH per pull (launch: 0.00002)
        GrailVault.GrailConfig memory c = LaunchParams.grail();
        c.decayWeiPerPull = 0.001 ether;
        vault.setConfig(c);
    }

    // ------------------------------------------------------------------ helpers

    /// @dev Pulls `n` (batches of 20) and settles them with the controller only; the vault is never
    ///      stepped here.
    function _pullsNoStep(uint256 n) internal {
        while (n != 0) {
            uint256 k = n > 20 ? 20 : n;
            (, uint256 vrfId) = _pull(alice, k);
            _fulfill(vrfId, uint256(keccak256(abi.encode("rp", ++salt))));
            for (uint256 i; i < 30 && (controller.nextSequenceToBook() <= engine.lastIssuedSequence() || controller.queueLength() != 0); ++i) {
                controller.settle(50);
            }
            n -= k;
        }
    }

    /// @dev What the production keeper does: step only when due.
    function _keeperTick() internal returns (bool stepped) {
        if (vault.stepDue()) {
            vault.step();
            stepped = true;
        }
    }

    function _mintGrail() internal returns (GrailVault.GrailItem memory it) {
        vault.fundGrail{value: vault.nextTarget() + shapes.mintFee()}();
        _keeperTick();
        GrailVault.GrailItem[] memory items = vault.items();
        it = items[items.length - 1];
        // a staged listing becomes selectable with the next request
        _pullsNoStep(1);
    }

    function _notional(uint256 i) internal view returns (uint256) {
        return vault.items()[i].notional;
    }

    function _grailShareBps() internal view returns (uint256 w) {
        GrailVault.GrailItem[] memory items = vault.items();
        for (uint256 i; i < items.length; ++i) w += 1e36 / items[i].notional;
        w = w * 10_000 / engine.totalWeight();
    }

    function _status(uint256 listingId) internal view returns (DrawEngine.ListingStatus s) {
        (,,,,,,, s) = engine.listings(listingId);
    }

    // ------------------------------------------------------------------ tests

    /// The bug: with only repricing pending, stepDue() returned false and a gated keeper never decayed.
    function test_stepDue_reportsPendingDecay_andKeeperRunsFullSchedule() public {
        GrailVault.GrailItem memory it = _mintGrail();
        assertEq(uint256(_status(it.listingId)), uint256(DrawEngine.ListingStatus.Active));
        assertEq(it.notional, 0.4 ether, "listed at 80 %");
        assertFalse(vault.stepDue(), "nothing due right after listing");
        _pullsNoStep(20);
        assertTrue(vault.stepDue(), "decay alone makes the vault due");
        uint256 floor = it.backing * 5_000 / 10_000;
        uint256 ticks;
        for (uint256 r; r < 20 && _notional(0) > floor; ++r) {
            _pullsNoStep(20);
            if (_keeperTick()) ++ticks;
        }
        assertEq(_notional(0), floor, "a stepDue-gated keeper reaches the 50 % floor");
        assertGt(ticks, 3);
        _pullsNoStep(20);
        assertFalse(vault.stepDue(), "at the floor: never permanently due");
    }

    function test_skippedKeeperIntervals_catchUpInOneStep() public {
        _mintGrail();
        uint64 listedAt = vault.items()[0].listedAtPull;
        _pullsNoStep(60); // keeper offline for 60 pulls
        uint256 expect = 0.4 ether - 0.001 ether * (vault.pulls() - listedAt);
        assertTrue(vault.stepDue());
        vault.step();
        assertEq(_notional(0), expect, "full accrued decay applied at once");
        assertFalse(vault.stepDue());
    }

    /// Old behaviour skipped a GRAIL whose accrued decay would cross the cap, forever (the accrued
    /// decay only grows). Now it decays to the cap boundary and stops there.
    function test_probabilityCap_bindsAtBoundary_notStuck() public {
        GrailVault.GrailItem memory it = _mintGrail();
        // a 0.05 % cap: the opening GRAIL (0.4 ETH) is under it and the floor (0.25 ETH) is over it,
        // so the cap binds part-way through the schedule
        GrailVault.GrailConfig memory c = LaunchParams.grail();
        c.decayWeiPerPull = 0.001 ether;
        c.probCapBps = 5;
        assertLt((1e36 / it.notional) * 10_000, 5 * engine.totalWeight(), "starts under the cap");
        assertGt((1e36 / (it.backing / 2)) * 10_000, 5 * engine.totalWeight(), "floor would exceed it");
        vault.setConfig(c);
        _pullsNoStep(140); // a skipped interval whose accrued decay (0.14 ETH) crosses the cap
        assertTrue(vault.stepDue(), "cap boundary still reachable");
        vault.step();
        uint256 n = _notional(0);
        assertLt(n, it.notional, "decayed");
        assertGt(n, it.backing / 2, "stopped above the floor by the cap");
        uint256 w = 1e36 / n;
        assertLe(w * 10_000, uint256(c.probCapBps) * engine.totalWeight(), "share within cap");
        // the boundary moves only as the rest of the board changes: stepDue() is true exactly when
        // step() would change a price, and the share never exceeds the cap
        for (uint256 r; r < 6; ++r) {
            _pullsNoStep(20);
            bool due = vault.stepDue();
            uint256 before = _notional(0);
            vault.step();
            if (due) {
                assertLt(_notional(0), before, "due implies a real reprice");
                // the cap limits decay (as before): checked when a price moves; board churn can
                // move the share afterwards without any GRAIL price change
                assertLe((1e36 / _notional(0)) * 10_000, uint256(c.probCapBps) * engine.totalWeight(), "within cap");
            } else {
                assertEq(_notional(0), before, "not due implies no change");
            }
            assertGt(_notional(0), it.backing / 2, "the cap, not the floor, binds");
        }
    }

    function test_multipleGrails_decayTogether_combinedCap() public {
        _mintGrail();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _mintGrail();
        assertEq(vault.liveGrails(), 2);
        _pullsNoStep(40);
        assertTrue(vault.stepDue());
        uint256[] memory plan = vault.repricePlan();
        assertGt(plan[0], 0);
        assertGt(plan[1], 0);
        vault.step();
        assertLt(_notional(0), 0.4 ether);
        assertLt(_notional(1), 0.4 ether);
        assertLe(_grailShareBps(), 500, "combined GRAIL weight within the 5 % cap");
    }

    function test_newlyFundedGrail_stagedBlocksRepriceUntilSelectable() public {
        _mintGrail();
        _pullsNoStep(30);
        // funded and minted while a purchase is outstanding: the engine stages the new listing
        (, uint256 vrfId) = _pull(bob, 1);
        vault.fundGrail{value: vault.nextTarget() + shapes.mintFee()}();
        vault.step();
        GrailVault.GrailItem[] memory items = vault.items();
        assertEq(items.length, 2);
        assertEq(uint256(_status(items[1].listingId)), uint256(DrawEngine.ListingStatus.Staged));
        _fulfill(vrfId, 5);
        for (uint256 i; i < 5 && engine.unsettledAcquisitionCount() != 0; ++i) controller.settle(50);
        assertEq(engine.unsettledAcquisitionCount(), 0);
        assertEq(items[0].notional, 0.4 ether, "no reprice yet");
        assertFalse(vault.stepDue(), "a staged GRAIL blocks repricing: not due");
        _pullsNoStep(1); // the next request activates it
        assertEq(uint256(_status(items[1].listingId)), uint256(DrawEngine.ListingStatus.Active));
        assertTrue(vault.stepDue(), "accrued decay of the first GRAIL is pending again");
        vault.step();
        items = vault.items();
        assertLt(items[0].notional, 0.4 ether, "first GRAIL caught up");
        assertEq(items[1].notional, 0.4 ether, "new GRAIL starts at its list price");
    }

    function test_outstandingAcquisitions_blockWeightChanges() public {
        _mintGrail();
        _pullsNoStep(30);
        // a purchase waiting for its VRF word: weights must not move under it
        (, uint256 vrfId) = _pull(bob, 5);
        assertGt(engine.unsettledAcquisitionCount(), 0);
        assertFalse(vault.stepDue(), "no reprice while an acquisition is outstanding");
        uint256 before = _notional(0);
        uint256 version = engine.inventoryVersion();
        vault.step();
        assertEq(_notional(0), before, "step does not reprice under an outstanding draw");
        assertEq(engine.inventoryVersion(), version);
        _fulfill(vrfId, 99);
        for (uint256 i; i < 5 && engine.unsettledAcquisitionCount() != 0; ++i) controller.settle(50);
        assertTrue(vault.stepDue(), "due again once settled");
        vault.step();
        assertLt(_notional(0), before);
    }

    function test_pausedVault_notDueForReprice() public {
        _mintGrail();
        _pullsNoStep(30);
        vm.prank(guardian);
        vault.setPaused(true);
        assertFalse(vault.stepDue());
    }
}
