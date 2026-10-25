// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {MockVRFCoordinator} from "../utils/MockVRFCoordinator.sol";

/// @notice Random sequences of pulls, out-of-order and missing VRF words, time skips, settles,
///         GRAIL funding and withdrawals.
contract GameHandler is Test {
    DrawEngine internal engine;
    DrawController internal controller;
    GrailVault internal vault;
    MockVRFCoordinator internal vrf;
    address[3] internal players;
    uint256[] public open;
    uint256 public paidIn;
    uint256 public withdrawnRefunds;

    constructor(DrawEngine e, DrawController c, GrailVault v, MockVRFCoordinator m) {
        (engine, controller, vault, vrf) = (e, c, v, m);
        players = [makeAddr("p0"), makeAddr("p1"), makeAddr("p2")];
        for (uint256 i; i < 3; ++i) {
            vm.deal(players[i], 10_000 ether);
        }
    }

    function pull(uint256 who, uint256 count, uint256 refSeed) external {
        count = bound(count, 1, 20);
        if (engine.unsettledAcquisitionCount() + count > engine.maxUnsettledAcquisitions()) return;
        if (engine.totalWeight() == 0) return;
        (,,, uint256 total) = engine.quoteAcquisitionPrice(count);
        address p = players[who % 3];
        address ref = refSeed % 2 == 0 ? address(0) : players[(who + 1) % 3];
        uint256 vrfId = vrf.nextRequestId();
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(p);
        engine.acquireBatch{value: total}(p, ref, count, 0, 0, 10_000, any, block.timestamp);
        paidIn += total;
        // one request per ACQUISITIONS_PER_VRF_REQUEST: each is fulfilled independently, in any order
        for (uint256 id = vrfId; id < vrf.nextRequestId(); ++id) open.push(id);
    }

    function fulfill(uint256 index, uint256 word) external {
        if (open.length == 0) return;
        index = index % open.length;
        uint256 id = open[index];
        open[index] = open[open.length - 1];
        open.pop();
        (,,,, uint256 blockNumber, bool done) = vrf.requests(id);
        if (done) return;
        if (vm.getBlockNumber() < blockNumber + 3) vm.roll(blockNumber + 3);
        vrf.fulfill(id, word);
    }

    function skipBlocks(uint256 n) external {
        vm.roll(vm.getBlockNumber() + bound(n, 1, 2_000));
        vm.warp(block.timestamp + bound(n, 1, 2_000) * 2);
    }

    function settle(uint256 n) external {
        controller.settle(bound(n, 1, 50));
    }

    function step() external {
        vault.step();
    }

    function fundGrail(uint256 amount) external {
        amount = bound(amount, 0, 0.2 ether);
        vm.deal(address(this), amount);
        vault.fundGrail{value: amount}();
    }

    function withdrawRefund(uint256 who) external {
        address p = players[who % 3];
        uint256 credit = engine.acquisitionRefundCredit(p);
        if (credit == 0) return;
        vm.prank(p);
        engine.withdrawAcquisitionRefund();
        withdrawnRefunds += credit;
    }

    function withdrawFees(uint256 who) external {
        address p = players[who % 3];
        if (engine.feeCreditOf(p) == 0) return;
        vm.prank(p);
        engine.withdrawFeeCredit(p);
    }
}

contract GameInvariants is GameFixture {
    GameHandler internal handler;

    function setUp() public override {
        super.setUp();
        _openAndActivate();
        handler = new GameHandler(engine, controller, vault, vrf);
        targetContract(address(handler));
    }

    function invariant_engineSolvent() public view {
        assertGe(address(engine).balance, engine.liabilities());
    }

    function invariant_controllerBuckets() public view {
        assertGe(address(controller).balance, controller.cash() + controller.maintenance());
        uint256 sum;
        for (uint256 r; r < controller.mixLength(); ++r) {
            (uint256 n,) = controller.rowCount(r);
            (,, uint256 b) = controller.mixRow(r);
            sum += n * b;
        }
        assertEq(controller.backing(), sum);
        assertLe(controller.nextSequenceToBook(), engine.nextSequenceToProcess());
    }

    function invariant_vaultSolvent() public view {
        assertGe(address(vault).balance, vault.fund());
    }

    function invariant_treeMatchesTotals() public view {
        assertEq(engine.treeRootWeight(), engine.totalWeight());
    }

    function invariant_ledgerConsistent() public view {
        uint256 lastDay = (block.timestamp - engine.ledgerOrigin()) / 1 days;
        uint256 accepted;
        for (uint256 d; d <= lastDay; ++d) {
            (uint64 a, uint64 r, uint64 u, uint64 b) = engine.dayTotals(d);
            assertLe(r, a);
            assertLe(u, r);
            assertGe(b, u);
            accepted += a;
        }
        assertEq(accepted, engine.lastIssuedSequence());
    }

    function invariant_unsettledCount() public view {
        assertEq(
            engine.unsettledAcquisitionCount(), engine.lastIssuedSequence() + 1 - engine.nextSequenceToProcess()
        );
    }
}
