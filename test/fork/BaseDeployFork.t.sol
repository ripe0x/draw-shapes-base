// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Deployer} from "../../script/Deployer.sol";
import {IVRFCoordinatorV2Plus} from "../../src/vendor/chainlink/IVRFCoordinatorV2Plus.sol";
import {Swapper} from "../utils/Swapper.sol";

/// @notice Reproducible Base deployment rehearsal on a pinned Base mainnet fork: the production
///         `Deployer` against Base's canonical v4 PoolManager and Chainlink VRF v2.5 coordinator,
///         activation through the timelock, a real VRF request, a delivered pull and trading through
///         the canonical pool. Skipped without BASE_RPC_URL.
contract BaseDeployForkTest is Test, Deployer {
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant COORDINATOR = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;
    bytes32 constant KEY_HASH = 0x00b81b5a830cb0a4009fbd8904de511e28631e62ce5ad231373d3cdad373ccab;
    uint256 constant FORK_BLOCK = 53_000_000;

    function test_fork_deployActivatePlayTrade() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc, vm.envOr("BASE_FORK_BLOCK", FORK_BLOCK));
        vm.deal(address(this), 20 ether);
        address admin = makeAddr("adminSafe");

        IVRFCoordinatorV2Plus c = IVRFCoordinatorV2Plus(COORDINATOR);
        uint256 sub = c.createSubscription();
        c.fundSubscriptionWithNative{value: 0.02 ether}(sub);

        System memory s = _deploySystem(
            Config({
                poolManager: POOL_MANAGER,
                vrfCoordinator: COORDINATOR,
                vrfSubscriptionId: sub,
                vrfKeyHash: KEY_HASH,
                shapes: address(0),
                drawPacks: address(0),
                creator: makeAddr("creator"),
                tokenWorks: makeAddr("tokenWorks-unverified"),
                dev: makeAddr("dev"),
                adminSafe: admin,
                guardian: makeAddr("guardian"),
                keeper: makeAddr("keeper"),
                timelockDelay: 2 days,
                create2Deployer: address(this)
            }),
            address(this)
        );
        c.addConsumer(sub, address(s.engine));
        _fundAndBuild(s, 0.05 ether);
        _handOver(s);
        (address[] memory t, uint256[] memory v, bytes[] memory d) = activationBatch(s);
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), "activate", 2 days);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.prank(admin);
        s.timelock.executeBatch(t, v, d, bytes32(0), "activate");
        assertTrue(s.engine.activated() && s.liquidity.launched());
        console2.log("hook", address(s.hook));
        console2.log("engine", address(s.engine));

        // a real VRF request to the Base coordinator, fulfilled from the coordinator address
        address p = makeAddr("player");
        vm.deal(p, 5 ether);
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(3);
        vm.prank(p);
        uint256[] memory ids = s.engine.acquireBatch{value: total}(p, address(0), 3, 0, 0, 1_000, type(uint256).max, block.timestamp);
        assertTrue(c.pendingRequestExists(sub));
        uint256 vrfId = s.engine.vrfRequestOf(ids[0]);
        vm.roll(vm.getBlockNumber() + 3);
        uint256[] memory words = new uint256[](1);
        words[0] = 7;
        vm.prank(COORDINATOR);
        s.engine.rawFulfillRandomWords(vrfId, words);
        s.engine.processAcquisitions(3);
        s.controller.settle(50);
        assertEq(s.controller.nextSequenceToBook(), 4);
        assertEq(s.controller.listedCount(), 100, "restocked on Base");

        // trade through Base's canonical PoolManager and our hook
        Swapper sw = new Swapper(IPoolManager(POOL_MANAGER));
        PoolKey memory key = s.liquidity.poolKey();
        uint256 out = sw.buy{value: 0.1 ether}(key);
        assertGt(out, 0);
        assertEq(s.hook.totalFees(), 0.002 ether);
        s.hook.distribute();
        assertEq(s.treasury.totalReceived(), 0.00175 ether);
    }
}
