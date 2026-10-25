// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";

/// @notice Milestone 1 reference board: real Shapes and Draw Packs, exact notionals, the
///         harmonic-mean fee reconciled to the wei, the settlement fee and the quoted payment.
contract ReferenceBoardTest is GameFixture {
    function test_referenceBoard_inventoryAndCost() public {
        uint256 creatorFeesBefore = shapes.feesOwedTo(creator);
        _openBoard();

        assertEq(controller.listedCount(), 100, "listed");
        uint256[5] memory expectCount = [uint256(62), 26, 7, 4, 1];
        for (uint256 r; r < 5; ++r) {
            (uint256 n, uint256 q) = controller.rowCount(r);
            assertEq(n, expectCount[r], "row count");
            assertEq(q, 0, "queued");
        }
        assertEq(controller.backing(), 1.65 ether, "backing");
        // 62 + 52 + 21 + 4 + 1 = 140 Shapes minted at 0.001
        assertEq(shapes.feesOwedTo(creator) - creatorFeesBefore, 0.14 ether, "creator mint fees");
        assertEq(controller.totalMintFeesPaid(), 0.14 ether);
        assertEq(controller.cash(), 2.2 ether - 1.79 ether, "liquid pool");
        assertEq(controller.nav(), 2.2 ether - 0.14 ether, "nav after mint fees");
    }

    function test_referenceBoard_notionals() public view {
        assertEq(controller.rowNotional(0), 0.0118 ether);
        assertEq(controller.rowNotional(1), 0.0236 ether);
        assertEq(controller.rowNotional(2), 0.0354 ether);
        assertEq(controller.rowNotional(3), 0.055 ether);
        assertEq(controller.rowNotional(4), 0.109 ether);
    }

    function test_referenceBoard_priceReconcilesToTheWei() public {
        _openAndActivate();
        uint256[5] memory price = [uint256(0.0118 ether), 0.0236 ether, 0.0354 ether, 0.055 ether, 0.109 ether];
        uint256[5] memory count = [uint256(62), 26, 7, 4, 1];
        uint256 sumW;
        uint256 sumWP;
        for (uint256 r; r < 5; ++r) {
            uint256 w = 1e36 / price[r];
            sumW += count[r] * w;
            sumWP += count[r] * w * price[r];
        }
        assertEq(engine.totalWeight(), sumW, "weight");
        assertEq(engine.weightedBackingTotal(), sumWP, "weighted value");
        uint256 fee = sumWP / sumW;
        assertEq(engine.acquisitionFee(), fee, "fee wei-exact");
        (uint256 qFee, uint256 sFee, uint256 vrfFee, uint256 total) = engine.quoteAcquisitionPrice(1);
        assertEq(qFee, fee);
        assertEq(sFee, fee / 100, "1% settlement fee on the full fee");
        assertEq(vrfFee, 0);
        assertEq(total, fee + fee / 100);
        // reference numbers from the brief
        assertApproxEqAbs(fee, 0.015070 ether, 0.0000005 ether, "approx 0.015070");
        assertApproxEqAbs(total, 0.015221 ether, 0.0000005 ether, "approx 0.015221");

        // expected backing E[b] = Σ n b / p / Σ n / p
        uint256[5] memory b = [uint256(0.01 ether), 0.02 ether, 0.03 ether, 0.05 ether, 0.1 ether];
        uint256 num;
        for (uint256 r; r < 5; ++r) {
            num += count[r] * (1e36 / price[r]) * b[r];
        }
        uint256 eb = num / sumW;
        assertApproxEqAbs(eb, 0.012819 ether, 0.0000005 ether, "expected backing");
        console2.log("acquisition fee (wei)", fee);
        console2.log("settlement fee (wei)", sFee);
        console2.log("player payment (wei)", total);
        console2.log("expected backing (wei)", eb);
        console2.log("return on payment (bps)", eb * 10_000 / total);
        (,,, uint256 t10) = engine.quoteAcquisitionPrice(10);
        assertEq(t10, 10 * (fee + fee / 100));
    }

    function test_singlePull_endToEnd() public {
        _openAndActivate();
        uint256 fee = engine.acquisitionFee();
        uint256 sfee = fee / 100;
        (uint256[] memory ids, uint256 vrfId) = _pullRef(alice, referrer, 1);
        assertEq(ids[0], 1);
        _fulfill(vrfId, 42);
        // fast path delivered inside the callback
        (,,, uint256 listingId, DrawEngine.AcquisitionStatus st) = engine.acquisitions(1);
        assertEq(uint256(st), uint256(DrawEngine.AcquisitionStatus.Fulfilled), "fulfilled in callback");
        (address collection,,, uint256 tokenId,,,,) = engine.listings(listingId);
        assertEq(IOwner(collection).ownerOf(tokenId), alice, "delivered");

        // settlement fee split
        assertEq(engine.feeCreditOf(referrer), sfee / 2);
        assertEq(engine.feeCreditOf(tokenWorks), sfee / 10);
        assertEq(engine.feeCreditOf(dev), sfee - sfee / 2 - sfee / 10);
        assertEq(engine.proceedsOf(address(controller)), fee);

        _settleAll();
        assertEq(controller.nextSequenceToBook(), 2);
        assertEq(controller.totalProceedsBooked(), fee);
        assertEq(controller.listedCount(), 100, "replaced");
        assertEq(engine.proceedsOf(address(controller)), 0, "harvested");
        // ledger
        (uint64 accepted, uint64 resolved, uint64 units,) = engine.dayTotals(0);
        assertEq(accepted, 1);
        assertEq(resolved, 1);
        assertEq(units, 1);

        vm.prank(referrer);
        engine.withdrawFeeCredit(referrer);
        assertEq(referrer.balance, sfee / 2);
    }

    function test_selfReferralGoesToDev() public {
        _openAndActivate();
        uint256 sfee = engine.acquisitionFee() / 100;
        (, uint256 vrfId) = _pullRef(alice, alice, 1);
        _fulfill(vrfId, 7);
        assertEq(engine.feeCreditOf(alice), 0);
        assertEq(engine.feeCreditOf(dev), sfee - sfee / 10);
    }
}

interface IOwner {
    function ownerOf(uint256) external view returns (address);
}
