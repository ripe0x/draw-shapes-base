// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";

/// @notice Keeper outage on the real contracts: no settle and no vault step while farmers keep
///         pulling in concurrent batches with out-of-order VRF callbacks, until the board is empty;
///         then a keeper returns and the game recovers. Escrow and committed backing stay whole.
contract KeeperOutageTest is GameFixture {
    function _assertSolvent() internal view {
        assertGe(address(engine).balance, engine.liabilities(), "engine escrow whole");
        assertGe(address(controller).balance, controller.cash() + controller.maintenance(), "controller cash whole");
        assertGe(address(vault).balance, vault.fund(), "vault fund whole");
    }

    function _try(address who, uint256 k) internal returns (bool ok, uint256 vrfId) {
        (,,, uint256 total) = engine.quoteAcquisitionPrice(k);
        vrfId = vrf.nextRequestId();
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(who);
        try engine.acquireBatch{value: total}(who, address(0), k, 0, 0, 1_000, any, block.timestamp) {
            ok = true;
            vrf.markGroup(vrfId, vrf.nextRequestId());
        } catch {}
    }

    function test_outage_boardDrains_pullsStaySafe_thenRecovers() public {
        _openAndActivate();
        vault.fundGrail{value: 0.501 ether}();
        vault.step();
        uint256 creditsBefore = engine.feeCreditOf(dev);
        uint256 accepted;
        uint256 reverted;
        uint256 round;
        // ---- outage: nobody calls controller.settle or vault.step
        while (round < 40) {
            ++round;
            (bool ok1, uint256 v1) = _try(alice, 10);
            (bool ok2, uint256 v2) = _try(bob, 10);
            (bool ok3, uint256 v3) = _try(alice, 5);
            vm.roll(vm.getBlockNumber() + 3);
            // callbacks arrive newest first: ordered processing still settles oldest first
            if (ok3) vrf.fulfillGroup(v3, uint256(keccak256(abi.encode("c", round))));
            if (ok2) vrf.fulfillGroup(v2, uint256(keccak256(abi.encode("b", round))));
            if (ok1) vrf.fulfillGroup(v1, uint256(keccak256(abi.encode("a", round))));
            accepted += (ok1 ? 10 : 0) + (ok2 ? 10 : 0) + (ok3 ? 5 : 0);
            reverted += (ok1 ? 0 : 1) + (ok2 ? 0 : 1) + (ok3 ? 0 : 1);
            _assertSolvent();
            if (!ok1 && !ok2 && !ok3) break;
        }
        // purchases left behind the callbacks' fast path are processed permissionlessly
        while (engine.unsettledAcquisitionCount() != 0) engine.processAcquisitions(50);
        assertEq(engine.activeListingCount(), 0, "board drained during the outage");
        assertGt(reverted, 0, "an empty board rejects new pulls (NoActiveListings) instead of taking ETH");
        (uint256 emptyFee,,,) = engine.quoteAcquisitionPrice(1);
        assertEq(emptyFee, 0, "an empty board quotes no price");
        _assertSolvent();
        uint256 refunds = engine.acquisitionRefundCredit(alice) + engine.acquisitionRefundCredit(bob);
        uint256 fulfilled;
        for (uint256 id = 1; id <= engine.lastIssuedSequence(); ++id) {
            (,,,, DrawEngine.AcquisitionStatus st) = engine.acquisitions(id);
            if (st == DrawEngine.AcquisitionStatus.Fulfilled) ++fulfilled;
        }
        console2.log("pulls accepted during outage", accepted);
        console2.log("pulls fulfilled (prize delivered)", fulfilled);
        console2.log("batches rejected (empty board)", reverted);
        console2.log("refund credit (wei)", refunds);
        console2.log("replacements queued before recovery", controller.queueLength());

        // ---- recovery: one keeper, settle(50) until the board is full again
        uint256 calls;
        uint256 gasUsed;
        while (
            (controller.nextSequenceToBook() <= engine.lastIssuedSequence() || controller.queueLength() != 0
                || controller.listedCount() < controller.boardItems()) && calls < 30
        ) {
            uint256 g = gasleft();
            controller.settle(50);
            gasUsed += g - gasleft();
            ++calls;
        }
        if (vault.stepDue()) vault.step();
        assertEq(controller.nextSequenceToBook(), engine.lastIssuedSequence() + 1, "every acquisition booked once");
        assertEq(controller.listedCount(), controller.boardItems(), "board full again");
        assertEq(controller.queueLength(), 0);
        assertGt(engine.feeCreditOf(dev), creditsBefore, "settlement fees credited");
        _assertSolvent();
        console2.log("recovery settle calls", calls);
        console2.log("recovery gas", gasUsed);
        console2.log("recovery cost at 0.01 gwei (wei)", gasUsed * 0.01 gwei);
        // pulls resume and refunds stay withdrawable
        (bool ok,) = _try(alice, 1);
        assertTrue(ok, "pulls resume");
        uint256 credit = engine.acquisitionRefundCredit(alice);
        if (credit != 0) {
            uint256 b = alice.balance;
            vm.prank(alice);
            engine.withdrawAcquisitionRefund();
            assertEq(alice.balance - b, credit, "refund withdrawable after the outage");
        }
    }
}
