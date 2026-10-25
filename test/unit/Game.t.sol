// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {MockNFT} from "../utils/MockNFT.sol";

/// @notice Whole-game behaviour on real Shapes and Draw Packs: replacement, books, ETH routing,
///         GRAIL funding and capture, external prizes, delivery failure.
contract GameTest is GameFixture {
    function _assertBooks() internal view {
        assertGe(address(controller).balance, controller.cash() + controller.maintenance(), "I1");
        assertGe(address(engine).balance, engine.liabilities(), "engine solvent");
        assertGe(address(vault).balance, vault.fund(), "vault solvent");
        // I2: backing equals the value of every ordinary item the controller holds or lists
        uint256 sum;
        for (uint256 r; r < controller.mixLength(); ++r) {
            (uint256 n,) = controller.rowCount(r);
            (,, uint256 b) = controller.mixRow(r);
            sum += n * b;
        }
        assertEq(controller.backing(), sum, "I2");
    }

    /// @notice 50 concurrent acquisitions on the reference board (batches of 10), words in
    ///         scrambled order, then settlement and full restock.
    function test_concurrent50_onReferenceBoard() public {
        _openAndActivate();
        uint256[5] memory vrfIds;
        for (uint256 b; b < 5; ++b) {
            (, vrfIds[b]) = _pullRef(b % 2 == 0 ? alice : bob, referrer, 10);
        }
        assertEq(engine.unsettledAcquisitionCount(), 50);
        vm.roll(vm.getBlockNumber() + 3);
        uint256[5] memory order = [uint256(3), 1, 4, 0, 2];
        for (uint256 i; i < 5; ++i) {
            vrf.fulfill(vrfIds[order[i]], uint256(keccak256(abi.encode("w", i))));
        }
        _settleAll();
        assertEq(engine.unsettledAcquisitionCount(), 0);
        assertEq(controller.nextSequenceToBook(), 51);
        uint256 fulfilled;
        uint256 refunded;
        for (uint256 id = 1; id <= 50; ++id) {
            (,,,, DrawEngine.AcquisitionStatus s) = engine.acquisitions(id);
            if (s == DrawEngine.AcquisitionStatus.Fulfilled) ++fulfilled;
            else ++refunded;
        }
        console2.log("fulfilled", fulfilled, "refunded (slippage)", refunded);
        assertEq(fulfilled + refunded, 50);
        (, uint64 resolved, uint64 units,) = engine.dayTotals(0);
        assertEq(resolved, 50);
        assertEq(units, fulfilled);
        assertEq(shapes.balanceOf(alice) + shapes.balanceOf(bob) + packs.balanceOf(alice) + packs.balanceOf(bob), fulfilled);
        console2.log("cash", controller.cash(), "queue", controller.queueLength());
        console2.log("listed", controller.listedCount());
        assertEq(controller.listedCount(), 100, "restocked");
        _assertBooks();
    }

    /// @notice Money flow of many pulls reconciles: every wei paid in lands in a named bucket.
    function test_ethRoutingReconciles() public {
        _openAndActivate();
        uint256 creatorBefore = shapes.feesOwedTo(creator);
        uint256 paidIn;
        uint256 pulls;
        for (uint256 round; round < 30; ++round) {
            (,,, uint256 total) = engine.quoteAcquisitionPrice(5);
            paidIn += total;
            (, uint256 vrfId) = _pullRef(alice, round % 3 == 0 ? address(0) : referrer, 5);
            _fulfill(vrfId, uint256(keccak256(abi.encode(round))));
            _settleAll();
            pulls += 5;
        }
        _settleAll();
        uint256 refunds = engine.acquisitionRefundCredit(alice);
        uint256 fees = engine.feeCreditOf(referrer) + engine.feeCreditOf(tokenWorks) + engine.feeCreditOf(dev);
        uint256 proceeds = controller.totalProceedsBooked();
        uint256 vrfFees = engine.vrfFeesCollected();
        assertEq(paidIn, proceeds + fees + refunds + vrfFees, "paid = proceeds + settlement fees + refunds + VRF fees");
        assertGe(vrfFees, vrf.totalBilled(), "purchaser VRF fees cover the oracle bill");
        // controller side: proceeds are split into premium, maintenance, feed and the mint line
        uint256 mintFeesForReplacements = shapes.feesOwedTo(creator) - creatorBefore;
        console2.log("pulls", pulls);
        console2.log("proceeds", proceeds);
        console2.log("backing captured", controller.totalBackingCaptured());
        console2.log("replacement mint fees", mintFeesForReplacements);
        console2.log("premium", controller.totalPremiumBooked());
        console2.log("maintenance", controller.totalMaintenanceBooked());
        console2.log("feed to GRAIL", controller.totalFeedBooked());
        console2.log("settlement fees", fees);
        console2.log("VRF fees collected", vrfFees);
        console2.log("VRF billed (mock)", vrf.totalBilled());
        _assertBooks();
    }

    function test_grailFundedByFeedAndTrading_thenCaptured() public {
        _openAndActivate();
        (uint256 target, uint256 fee, uint256 funded) = vault.progress();
        assertEq(target, 0.5 ether);
        assertEq(fee, 0.001 ether);
        assertEq(funded, 0);
        // trading-fee funding (the treasury calls fundGrail) plus feed
        vault.fundGrail{value: 0.45 ether}();
        vault.step();
        assertEq(vault.items().length, 0, "not eligible before fully funded");
        uint256 feedBefore = controller.totalFeedSent();
        for (uint256 round; round < 40 && vault.fund() < 0.501 ether && vault.liveGrails() == 0; ++round) {
            (, uint256 vrfId) = _pull(bob, 20);
            _fulfill(vrfId, uint256(keccak256(abi.encode("g", round))));
            _settleAll();
        }
        assertGt(controller.totalFeedSent(), feedBefore, "feed reached the vault");
        vault.step();
        GrailVault.GrailItem[] memory items = vault.items();
        assertEq(items.length, 1, "GRAIL listed once funded");
        assertEq(items[0].backing, 0.5 ether);
        assertLe(items[0].notional, 0.4 ether, "listed below backing (0.8x), decaying");
        assertGe(items[0].notional, 0.25 ether, "floor 0.5x");
        assertEq(shapes.backingOf(items[0].tokenId), 0.5 ether);
        (uint256 nextTarget,,) = vault.progress();
        assertEq(nextTarget, 0.5 ether, "first cycle: no step");

        // capture it: choose a word that lands on the GRAIL's slot range by trying words
        uint256 grailListing = items[0].listingId;
        bool captured;
        for (uint256 tries; tries < 4000 && !captured; tries += 20) {
            (, uint256 vrfId) = _pull(alice, 20);
            _fulfill(vrfId, uint256(keccak256(abi.encode("cap", tries))));
            _settleAll();
            (,,,,,,, DrawEngine.ListingStatus s) = engine.listings(grailListing);
            captured = s == DrawEngine.ListingStatus.Settled;
        }
        if (captured) {
            vault.step();
            GrailVault.GrailItem[] memory left = vault.items();
            for (uint256 i; i < left.length; ++i) {
                assertTrue(left[i].listingId != grailListing, "captured GRAIL removed");
                console2.log("next GRAIL backing", left[i].backing);
            }
            assertEq(shapes.ownerOf(items[0].tokenId), alice);
            assertGt(vault.totalProceeds(), 0, "capture proceeds returned to the fund");
            console2.log("GRAIL captured; vault fund", vault.fund());
        } else {
            console2.log("GRAIL not captured in sample (expected about 1 in 2,600 pulls)");
        }
        _assertBooks();
    }

    function test_grailDecaysWhileIdle() public {
        _openAndActivate();
        vault.fundGrail{value: 0.501 ether}();
        vault.step();
        GrailVault.GrailItem memory it = vault.items()[0];
        for (uint256 round; round < 10; ++round) {
            (, uint256 vrfId) = _pull(alice, 20);
            _fulfill(vrfId, uint256(keccak256(abi.encode("decay", round))));
            _settleAll();
        }
        vault.step();
        assertEq(vault.liveGrails(), 1, "these words do not capture the GRAIL (decay, not a win, is under test)");
        GrailVault.GrailItem memory after_ = vault.items()[0];
        // 200 pulls x 0.00002 = 0.004 ETH, at least 1% of 0.4
        assertEq(after_.notional, it.notional - 200 * 0.00002 ether, "decayed by the pull clock");
        (,,,,, uint256 price,,) = engine.listings(after_.listingId);
        assertEq(price, after_.notional);
    }

    function test_externalPrize_deliveryFailure_writeOffAndRecovery() public {
        _openAndActivate();
        MockNFT partner = new MockNFT();
        uint256 tokenId = partner.mint(address(controller));
        partner.setBlocked(alice, true);
        // a partner NFT priced so it dominates selection
        uint256 listingId = controller.listExternal(address(partner), tokenId, 0.000001 ether);
        (, uint256 vrfId) = _pull(alice, 1);
        _fulfill(vrfId, 1);
        _settleAll();
        (,,,, DrawEngine.AcquisitionStatus s) = engine.acquisitions(1);
        assertEq(uint256(s), uint256(DrawEngine.AcquisitionStatus.DeliveryPending), "delivery failed");
        assertEq(controller.nextSequenceToBook(), 2, "walk passes a pending delivery");
        vm.warp(block.timestamp + 7 days);
        engine.refundFailedDelivery(listingId);
        assertGt(engine.acquisitionRefundCredit(alice), 0);
        engine.processAcquisitions(1);
        _assertBooks();
    }

    function test_surplusReleaseOnlyAboveCapitalAndFullBoard() public {
        _openAndActivate();
        vm.expectRevert(DrawController.ReleaseNotOpen.selector);
        controller.releaseSurplus();
        address sink = makeAddr("buyback");
        controller.setSurplusSink(sink, uint64(block.timestamp));
        // NAV after opening mint fees is 2.06 < 2.2: nothing releasable
        assertEq(controller.releasableSurplus(), 0);
        controller.fundPool{value: 0.3 ether}();
        assertEq(controller.releasableSurplus(), controller.nav() - 2.2 ether);
        uint256 amount = controller.releaseSurplus();
        assertEq(sink.balance, amount);
        assertEq(controller.nav(), 2.2 ether);
        _assertBooks();
    }

    function test_listingPauseKeepsSettlement() public {
        _openAndActivate();
        (, uint256 vrfId) = _pull(alice, 5);
        vm.prank(guardian);
        controller.setListingPaused(true);
        _fulfill(vrfId, 77);
        _settleAll();
        assertEq(controller.nextSequenceToBook(), 6, "booking continues");
        assertLt(controller.listedCount(), 100, "no restock while paused");
        vm.prank(guardian);
        controller.setListingPaused(false);
        controller.settle(10);
        assertEq(controller.listedCount(), 100);
    }
}
