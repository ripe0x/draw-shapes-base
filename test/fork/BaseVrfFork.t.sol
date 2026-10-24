// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Shapes} from "shapes/Shapes.sol";
import {ShapeRenderer} from "shapes/ShapeRenderer.sol";
import {ShapePacks} from "draw-packs/ShapePacks.sol";
import {ShapePackRenderer} from "draw-packs/ShapePackRenderer.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";
import {IVRFCoordinatorV2Plus} from "../../src/vendor/chainlink/IVRFCoordinatorV2Plus.sol";

/// @notice Base mainnet fork: the game against the real Chainlink VRF v2.5 coordinator. A real
///         subscription is created and funded, the engine is its consumer, `acquireBatch` sends a
///         real `requestRandomWords`, and the fulfilment is delivered from the coordinator address
///         (the oracle's proof cannot be produced off-chain), measuring the callback gas that
///         Chainlink bills. Run with BASE_RPC_URL set; skipped otherwise.
contract BaseVrfForkTest is Test {
    address constant COORDINATOR = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;
    bytes32 constant KEY_HASH_2_GWEI = 0x00b81b5a830cb0a4009fbd8904de511e28631e62ce5ad231373d3cdad373ccab;
    uint256 constant FORK_BLOCK = 53_000_000;

    DrawEngine engine;
    DrawController controller;
    GrailVault vault;
    Shapes shapes;
    uint256 subId;
    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc, vm.envOr("BASE_FORK_BLOCK", FORK_BLOCK));
        forked = true;
        assertEq(block.chainid, 8453);

        IVRFCoordinatorV2Plus c = IVRFCoordinatorV2Plus(COORDINATOR);
        subId = c.createSubscription();
        c.fundSubscriptionWithNative{value: 0.05 ether}(subId);

        address creator = makeAddr("creator");
        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        ShapeRenderer r = new ShapeRenderer();
        shapes = new Shapes{value: 0.01 ether}(0.001 ether, creator, address(r), 0);
        ShapePacks packs = new ShapePacks(address(shapes), address(new ShapePackRenderer(address(shapes))), creator, "Draw Packs", "DRAW", 2);
        vm.stopPrank();

        engine = new DrawEngine(
            address(this),
            makeAddr("guardian"),
            LaunchParams.vrf(COORDINATOR, subId, KEY_HASH_2_GWEI),
            LaunchParams.limits(),
            LaunchParams.fees(makeAddr("tokenWorks"), makeAddr("dev"))
        );
        c.addConsumer(subId, address(engine));
        vault = new GrailVault(address(shapes), address(engine), address(this), makeAddr("guardian"), LaunchParams.grail(), LaunchParams.grailLadder());
        controller = new DrawController(
            LaunchParams.controller(address(shapes), address(packs), address(engine), address(this), makeAddr("guardian"), address(vault))
        );
        engine.setSupplier(address(controller), true);
        engine.setSupplier(address(vault), true);
        controller.fundPool{value: LaunchParams.ORDINARY_POOL}();
        for (uint256 i; i < 3; ++i) controller.build(40);
        engine.activate();
    }

    function test_fork_realCoordinatorRequestAndCallbackGas() public {
        if (!forked) return;
        address alice = makeAddr("alice");
        vm.deal(alice, 10 ether);
        for (uint256 n = 1; n <= 10; n = n == 1 ? 4 : n + 6) {
            (,,, uint256 total) = engine.quoteAcquisitionPrice(n);
            vm.recordLogs();
            vm.prank(alice);
            uint256[] memory ids = engine.acquireBatch{value: total}(alice, address(0), n, 0, 0, 1_000, type(uint256).max, block.timestamp);
            uint256 vrfId = engine.vrfRequestOf(ids[0]);
            assertTrue(IVRFCoordinatorV2Plus(COORDINATOR).pendingRequestExists(subId), "real request pending");
            (uint64 first, uint32 count,) = engine.vrfBatches(vrfId);
            assertEq(count, n);
            assertEq(first, ids[0]);
            uint32 gasLimit = uint32(LaunchParams.vrf(address(0), 0, 0).callbackGasBase + n * LaunchParams.vrf(address(0), 0, 0).callbackGasPerAcquisition);
            if (gasLimit > 2_500_000) gasLimit = 2_500_000;
            vm.roll(vm.getBlockNumber() + 3);
            uint256[] memory words = new uint256[](1);
            words[0] = uint256(keccak256(abi.encode(n)));
            vm.prank(COORDINATOR);
            uint256 g = gasleft();
            (bool ok,) = address(engine).call{gas: gasLimit}(abi.encodeCall(engine.rawFulfillRandomWords, (vrfId, words)));
            uint256 used = g - gasleft();
            assertTrue(ok, "callback within the requested gas limit");
            uint256 settledInCallback = engine.nextSequenceToProcess() - first;
            // Chainlink v2.5 bills (callback gas + verification + gasAfterPaymentCalculation 42,500) x gas
            // price x (1 + 60% native premium) plus the L1 data fee. Verification overhead measured
            // from live Base fulfilments is about 400k gas total for a minimal callback (evidence/vrf).
            uint256 billedGas = used + 300_000 + 42_500;
            uint256 estimate = billedGas * 0.00615 gwei * 160 / 100;
            console2.log("batch", n);
            console2.log("  callback gas used", used);
            console2.log("  settled inside callback", settledInCallback);
            console2.log("  estimated VRF charge at 0.00615 gwei (wei)", estimate);
            console2.log("  estimated VRF charge per acquisition (wei)", estimate / n);
            engine.processAcquisitions(20);
            controller.settle(50);
        }
    }
}
