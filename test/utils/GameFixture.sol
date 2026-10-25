// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Shapes} from "shapes/Shapes.sol";
import {ShapeRenderer} from "shapes/ShapeRenderer.sol";
import {ShapePacks} from "draw-packs/ShapePacks.sol";
import {ShapePackRenderer} from "draw-packs/ShapePackRenderer.sol";

import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";
import {MockVRFCoordinator} from "./MockVRFCoordinator.sol";

/// @notice Real Shapes v1 and Draw Packs (pinned submodules), the engine, GRAIL vault and controller
///         with the launch parameters, and a VRF v2.5 coordinator double. Governance is this test.
abstract contract GameFixture is Test {
    address internal creator = makeAddr("creator"); // Shapes fee recipient and admin
    address internal guardian = makeAddr("guardian");
    address internal tokenWorks = makeAddr("tokenWorks");
    address internal dev = makeAddr("dev");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal referrer = makeAddr("referrer");

    Shapes internal shapes;
    ShapePacks internal packs;
    MockVRFCoordinator internal vrf;
    DrawEngine internal engine;
    GrailVault internal vault;
    DrawController internal controller;
    uint256 internal subId;

    function setUp() public virtual {
        vm.startPrank(creator);
        ShapeRenderer renderer = new ShapeRenderer();
        vm.deal(creator, 1 ether);
        shapes = new Shapes{value: 0.01 ether}(LaunchParams.MINT_FEE, creator, address(renderer), 0);
        packs = new ShapePacks(
            address(shapes), address(new ShapePackRenderer(address(shapes))), creator, "Draw Packs", "DRAW", 2
        );
        vm.stopPrank();

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
        vault = new GrailVault(
            address(shapes), address(engine), address(this), guardian, LaunchParams.grail(), LaunchParams.grailLadder()
        );
        controller = new DrawController(
            LaunchParams.controller(
                address(shapes), address(packs), address(engine), address(this), guardian, address(vault)
            )
        );
        engine.setSupplier(address(controller), true);
        engine.setSupplier(address(vault), true);

        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
    }

    /// @dev Funds the ordinary pool with the launch allocation and lists the whole board.
    function _openBoard() internal {
        controller.fundPool{value: LaunchParams.ORDINARY_POOL}();
        for (uint256 i; i < 30 && controller.listedCount() < controller.boardItems(); ++i) {
            controller.build(40); // lists at most MAX_LIST_PER_CALL per call
        }
    }

    function _openAndActivate() internal {
        _openBoard();
        engine.activate();
    }

    function _pull(address who, uint256 count) internal returns (uint256[] memory ids, uint256 vrfId) {
        return _pullRef(who, address(0), count);
    }

    function _pullRef(address who, address ref, uint256 count) internal returns (uint256[] memory ids, uint256 vrfId) {
        (,,, uint256 total) = engine.quoteAcquisitionPrice(count);
        vrfId = vrf.nextRequestId();
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(who);
        ids = engine.acquireBatch{value: total}(who, ref, count, 0, 0, 1_000, any, block.timestamp);
    }

    function _fulfill(uint256 vrfId, uint256 word) internal {
        vm.roll(vm.getBlockNumber() + 3);
        vrf.fulfill(vrfId, word);
    }

    /// @dev Processes and books everything outstanding.
    function _settleAll() internal {
        for (uint256 i; i < 50; ++i) {
            controller.settle(50);
            vault.step();
            // booked and fully restocked (settle lists at most MAX_LIST_PER_CALL per call)
            if (controller.nextSequenceToBook() > engine.lastIssuedSequence() && controller.queueLength() == 0) break;
        }
    }

    receive() external payable {}
}
