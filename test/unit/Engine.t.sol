// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";
import {MockVRFCoordinator} from "../utils/MockVRFCoordinator.sol";
import {MockNFT} from "../utils/MockNFT.sol";

/// @notice Engine behaviour retained from FWAClone and the Base changes: batched VRF, concurrency,
///         out-of-order words, delivery failure, expiry, slippage, staging, fees, ledger, roles.
contract EngineTest is Test {
    DrawEngine internal engine;
    MockVRFCoordinator internal vrf;
    MockNFT internal nft;
    uint256 internal subId;
    address internal guardian = makeAddr("guardian");
    address internal tokenWorks = makeAddr("tokenWorks");
    address internal dev = makeAddr("dev");
    address internal ref = makeAddr("ref");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vrf = new MockVRFCoordinator();
        subId = vrf.createSubscription();
        vrf.fundSubscriptionWithNative{value: 1 ether}(subId);
        engine = new DrawEngine(
            address(this),
            guardian,
            LaunchParams.vrf(address(vrf), subId, keccak256("lane")),
            LaunchParams.vrfFee(),
            LaunchParams.limits(),
            LaunchParams.fees(tokenWorks, dev)
        );
        engine.setSupplier(address(this), true);
        nft = new MockNFT();
        nft.setApprovalForAll(address(engine), true);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ------------------------------------------------------------------ helpers

    function _list(uint256 n, uint256 price) internal returns (uint256[] memory ids) {
        ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = engine.listNFT(address(nft), nft.mint(address(this)), price);
        }
    }

    function _buy(address who, uint256 count) internal returns (uint256[] memory ids, uint256 vrfId) {
        (,,, uint256 total) = engine.quoteAcquisitionPrice(count);
        vrfId = vrf.nextRequestId();
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(who);
        ids = engine.acquireBatch{value: total}(who, ref, count, 0, 0, 10_000, any, block.timestamp);
    }

    function _roll(uint256 n) internal {
        vm.roll(vm.getBlockNumber() + n);
    }

    function _assertSolvent() internal view {
        assertGe(address(engine).balance, engine.liabilities(), "engine solvent");
    }

    function _status(uint256 id) internal view returns (DrawEngine.AcquisitionStatus s) {
        (,,,, s) = engine.acquisitions(id);
    }

    // ------------------------------------------------------------------ tests

    function test_notActivated() public {
        _list(3, 0.01 ether);
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.expectRevert(DrawEngine.NotActivated.selector);
        vm.prank(alice);
        engine.acquireBatch{value: 1 ether}(alice, address(0), 1, 0, 0, 0, any, block.timestamp);
    }

    function test_batchUsesOneVrfRequestAndIndependentWords() public {
        _list(30, 0.01 ether);
        engine.activate();
        (uint256[] memory ids, uint256 vrfId) = _buy(alice, 10);
        assertEq(vrf.openCount(), 1, "one request for the batch");
        assertEq(engine.unfulfilledVrfCount(), 1);
        _roll(3);
        vrf.fulfill(vrfId, 123);
        uint256 prev;
        for (uint256 i; i < ids.length; ++i) {
            (,,,,, uint256 w) = engine.acquisitionMeta(ids[i]);
            assertEq(w, uint256(keccak256(abi.encode(uint256(123), i))), "derived word");
            assertTrue(w != prev);
            prev = w;
        }
        engine.processAcquisitions(20);
        for (uint256 i; i < ids.length; ++i) {
            assertEq(uint256(_status(ids[i])), uint256(DrawEngine.AcquisitionStatus.Fulfilled));
        }
        assertEq(nft.balanceOf(alice), 10);
        assertEq(engine.unsettledAcquisitionCount(), 0);
        _assertSolvent();
    }

    /// @notice 60 concurrent acquisitions in three batches, words delivered in reverse order, settle
    ///         strictly in sequence; every acquisition reconciles.
    function test_concurrent60_outOfOrder() public {
        _list(80, 0.01 ether);
        engine.activate();
        uint256 fee = engine.acquisitionFee();
        (, uint256 margin20) = engine.vrfFeeParts(20); // VRF service margin, credited to dev at purchase
        (, uint256 v1) = _buy(alice, 20);
        (, uint256 v2) = _buy(bob, 20);
        (, uint256 v3) = _buy(alice, 20);
        assertEq(engine.unsettledAcquisitionCount(), 60);
        _roll(3);
        vrf.fulfill(v3, 3);
        vrf.fulfill(v2, 2);
        // nothing processes past the pending head
        assertEq(engine.processAcquisitions(60), 0, "head pending blocks the queue");
        vrf.fulfill(v1, 1);
        uint256 processed;
        for (uint256 i; i < 10 && engine.unsettledAcquisitionCount() != 0; ++i) {
            processed += engine.processAcquisitions(20);
        }
        assertEq(engine.unsettledAcquisitionCount(), 0);
        assertEq(nft.balanceOf(alice) + nft.balanceOf(bob), 60);
        assertEq(engine.activeListingCount(), 20);
        assertEq(engine.proceedsOf(address(this)), 60 * fee);
        assertEq(engine.feeCreditOf(ref) + engine.feeCreditOf(tokenWorks) + engine.feeCreditOf(dev), 60 * (fee / 100) + 3 * margin20);
        (uint64 accepted, uint64 resolved, uint64 units,) = engine.dayTotals(0);
        assertEq(accepted, 60);
        assertEq(resolved, 60);
        assertEq(units, 60);
        _assertSolvent();
    }

    function test_expiryRefundsFeeAndSettlementFee_noUnits() public {
        _list(5, 0.01 ether);
        engine.activate();
        (uint256[] memory ids,) = _buy(alice, 2);
        (uint256 f, uint256 sf, uint256 vf,) = engine.quoteAcquisitionPrice(2);
        // the purchaser's VRF fee paid for the oracle request and is not refundable
        uint256 total = (f + sf) * 2;
        assertGt(vf, 0);
        _roll(engine.selectionTimeoutBlocks() + 1);
        assertEq(engine.processAcquisitions(10), 2);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.Expired));
        assertEq(engine.acquisitionRefundCredit(alice), total);
        assertEq(engine.feeCreditOf(ref), 0, "no referral on refund");
        (, uint64 resolved, uint64 units,) = engine.dayTotals(0);
        assertEq(resolved, 2);
        assertEq(units, 0);
        uint256 before = alice.balance;
        vm.prank(alice);
        engine.withdrawAcquisitionRefund();
        assertEq(alice.balance - before, total);
        _assertSolvent();
    }

    function test_lateWordTimesOut() public {
        _list(5, 0.01 ether);
        engine.activate();
        (uint256[] memory ids, uint256 vrfId) = _buy(alice, 1);
        _roll(engine.selectionTimeoutBlocks() + 1);
        vrf.fulfill(vrfId, 9);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.TimedOut));
        engine.processAcquisitions(1);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.Expired));
    }

    function test_duplicateAndForeignCallbacks() public {
        _list(5, 0.01 ether);
        engine.activate();
        (, uint256 vrfId) = _buy(alice, 1);
        uint256[] memory words = new uint256[](1);
        vm.expectRevert(DrawEngine.OnlyCoordinator.selector);
        engine.rawFulfillRandomWords(vrfId, words);
        _roll(3);
        vrf.fulfill(vrfId, 5);
        (,,,,, uint256 w1) = engine.acquisitionMeta(1);
        // a second callback for the same request cannot overwrite the word (no reroll)
        vm.prank(address(vrf));
        words[0] = 6;
        engine.rawFulfillRandomWords(vrfId, words);
        (,,,,, uint256 w2) = engine.acquisitionMeta(1);
        assertEq(w1, w2);
    }

    function test_deliveryFailure_retry_and_refund() public {
        _list(1, 0.01 ether);
        engine.activate();
        nft.setBlocked(alice, true);
        (uint256[] memory ids, uint256 vrfId) = _buy(alice, 1);
        (uint256 f, uint256 sf,,) = engine.quoteAcquisitionPrice(1);
        uint256 total = f + sf;
        _roll(3);
        vrf.fulfill(vrfId, 1);
        engine.processAcquisitions(1);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.DeliveryPending));
        assertEq(engine.dayOpen(0), 1, "pending delivery keeps its day open");
        (,,, uint256 listingId,) = engine.acquisitions(ids[0]);
        vm.expectRevert();
        engine.retryNFTDelivery(listingId);
        vm.expectRevert(DrawEngine.DeliveryWindowNotElapsed.selector);
        engine.refundFailedDelivery(listingId);
        vm.warp(block.timestamp + 7 days);
        // anyone may trigger it; the credit goes to the purchaser
        vm.prank(bob);
        engine.refundFailedDelivery(listingId);
        assertEq(engine.acquisitionRefundCredit(alice), total);
        assertEq(engine.feeCreditOf(ref), 0);
        assertEq(engine.dayOpen(0), 0);
        engine.recoverRefundedNFT(listingId);
        assertEq(nft.ownerOf(1), address(this));
        _assertSolvent();
    }

    function test_deliveryFailure_retrySucceeds() public {
        _list(1, 0.01 ether);
        engine.activate();
        nft.setBlocked(alice, true);
        (uint256[] memory ids, uint256 vrfId) = _buy(alice, 1);
        _roll(3);
        vrf.fulfill(vrfId, 1);
        engine.processAcquisitions(1);
        (,,, uint256 listingId,) = engine.acquisitions(ids[0]);
        nft.setBlocked(alice, false);
        engine.retryNFTDelivery(listingId);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.Fulfilled));
        assertEq(nft.ownerOf(1), alice);
        (, , uint64 units,) = engine.dayTotals(0);
        assertEq(units, 1);
    }

    function test_slippageRefund() public {
        _list(1, 0.01 ether);
        _list(1, 1 ether);
        engine.activate();
        (uint256[] memory ids, uint256 vrfId) = _buy(alice, 2);
        (uint256 fee, uint256 sfee,,) = engine.quoteAcquisitionPrice(1);
        _roll(3);
        vrf.fulfill(vrfId, 0); // word 0 selects slot 1, the 0.01 listing
        engine.processAcquisitions(2);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.Fulfilled));
        // only the 1 ETH listing remains: the live fee rose far beyond the 10% tolerance
        assertEq(uint256(_status(ids[1])), uint256(DrawEngine.AcquisitionStatus.Refunded));
        assertEq(engine.acquisitionRefundCredit(alice), fee + sfee);
        assertEq(engine.activeListingCount(), 1, "would-be selection stays listed");
        _assertSolvent();
    }

    function test_stagedListingsReservedByLaterRequest() public {
        _list(5, 0.01 ether);
        engine.activate();
        (, uint256 v1) = _buy(alice, 1);
        // listed while an acquisition is unresolved: staged, outside selection
        _list(2, 0.01 ether);
        assertEq(engine.stagedCount(), 2);
        (,,, uint256 total) = engine.quoteAcquisitionPrice(1);
        (uint256[] memory ids2, uint256 v2) = _buy(bob, 1);
        assertEq(engine.reservedListingCount(uint64(ids2[0])), 2, "later request reserves the staged batch");
        assertTrue(total > 0);
        _roll(3);
        vrf.fulfill(v2, 2);
        vrf.fulfill(v1, 1);
        engine.processAcquisitions(5);
        assertEq(engine.activeListingCount(), 5);
        assertEq(engine.stagedCount(), 0);
    }

    function test_inventoryVersionGuard() public {
        _list(5, 0.01 ether);
        engine.activate();
        uint256 v = engine.inventoryVersion();
        (,,, uint256 total) = engine.quoteAcquisitionPrice(1);
        _list(1, 0.01 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DrawEngine.InventoryVersionMismatch.selector, v, v + 1));
        engine.acquireBatch{value: total}(alice, address(0), 1, 0, 0, 0, v, block.timestamp);
        vm.prank(alice);
        engine.acquireBatch{value: total}(alice, address(0), 1, 0, 0, 0, v + 1, block.timestamp);
    }

    function test_pauseBlocksNewExposureOnly() public {
        _list(5, 0.01 ether);
        engine.activate();
        (uint256[] memory ids, uint256 vrfId) = _buy(alice, 1);
        vm.prank(guardian);
        engine.setPaused(true);
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.expectRevert(DrawEngine.Paused.selector);
        vm.prank(alice);
        engine.acquireBatch{value: 1 ether}(alice, address(0), 1, 0, 0, 0, any, block.timestamp);
        _roll(3);
        vrf.fulfill(vrfId, 3);
        engine.processAcquisitions(1);
        assertEq(uint256(_status(ids[0])), uint256(DrawEngine.AcquisitionStatus.Fulfilled));
        engine.withdrawProceeds();
        vm.prank(dev);
        engine.withdrawFeeCredit(dev);
        // guardian has no policy power
        vm.prank(guardian);
        vm.expectRevert(DrawEngine.NotGovernance.selector);
        engine.setSupplier(guardian, true);
    }

    function test_governanceBounds() public {
        vm.expectRevert(DrawEngine.InvalidConfig.selector);
        engine.setFeePolicy(201, 5_000, 1_000);
        vm.expectRevert(DrawEngine.InvalidConfig.selector);
        DrawEngine.VrfFeeConfig memory vc = LaunchParams.vrfFee();
        vc.bufferBps = 5_001;
        engine.setVrfFeeConfig(vc);
        DrawEngine.Limits memory l = LaunchParams.limits();
        l.inventoryChangeCooldown = 2 hours;
        vm.expectRevert(DrawEngine.InvalidConfig.selector);
        engine.setLimits(l);
        vm.prank(alice);
        vm.expectRevert(DrawEngine.NotGovernance.selector);
        engine.setFeePolicy(100, 5_000, 1_000);
    }

    function test_feePolicySnapshottedAtRequest() public {
        _list(5, 0.01 ether);
        engine.activate();
        uint256 sfee = engine.acquisitionFee() / 100;
        (, uint256 vrfId) = _buy(alice, 1);
        engine.setFeePolicy(100, 0, 0); // later requests: everything to dev
        _roll(3);
        vrf.fulfill(vrfId, 3);
        assertEq(engine.feeCreditOf(ref), sfee / 2, "old policy applies to the old request");
    }

    /// @notice Controller replacement: listings hand off to a new supplier in place; proceeds of
    ///         later captures go to it.
    function test_transferListingsToSuccessor() public {
        uint256[] memory ids = _list(3, 0.01 ether);
        Successor next = new Successor();
        engine.setSupplier(address(next), true);
        engine.transferListings(ids, address(next));
        (, address depositor,,,,,,) = engine.listings(ids[0]);
        assertEq(depositor, address(next));
        engine.activate();
        (, uint256 vrfId) = _buy(alice, 1);
        // active listings cannot move while an acquisition is unresolved
        vm.prank(address(next));
        vm.expectRevert(DrawEngine.WithdrawLocked.selector);
        engine.transferListings(ids, address(this));
        _roll(3);
        vrf.fulfill(vrfId, 3);
        assertGt(engine.proceedsOf(address(next)), 0);
        assertEq(engine.proceedsOf(address(this)), 0);
    }

    function test_bonusWeightDistribution() public pure {
        uint256 big;
        uint256 mid;
        for (uint256 i; i < 10_000; ++i) {
            uint256 w = _bonus(i);
            if (w == 25) ++big;
            else if (w == 5) ++mid;
        }
        assertApproxEqAbs(big, 100, 40);
        assertApproxEqAbs(mid, 900, 120);
    }

    function _bonus(uint256 i) internal pure returns (uint256) {
        uint256 r = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(i))), "bonus"))) % 1_000;
        return r < 10 ? 25 : r < 100 ? 5 : 1;
    }

    function testFuzz_feeIsHarmonicMean(uint96[8] memory prices) public {
        uint256 sumW;
        uint256 sumWP;
        for (uint256 i; i < 8; ++i) {
            uint256 p = bound(prices[i], 1e12, 100 ether);
            engine.listNFT(address(nft), nft.mint(address(this)), p);
            sumW += 1e36 / p;
            sumWP += (1e36 / p) * p;
        }
        assertEq(engine.acquisitionFee(), sumWP / sumW);
        assertEq(engine.treeRootWeight(), engine.totalWeight());
    }
}

contract Successor {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
