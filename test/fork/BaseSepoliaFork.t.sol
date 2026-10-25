// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Deployer} from "../../script/Deployer.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {IVRFCoordinatorV2Plus} from "../../src/vendor/chainlink/IVRFCoordinatorV2Plus.sol";

/// @notice Base Sepolia fork: the production deployer with the testnet allocation of
///         script/config/base-sepolia.json against the live PoolManager and VRF v2.5 coordinator.
///         Regression for the cold-state callback found by the Sepolia rehearsal: with the
///         coordinator's gas limit, the very first acquisition (cold storage, fresh purchaser,
///         referrer and fee credits) must settle inside the VRF callback, not wait for a keeper.
///         Skipped without BASE_SEPOLIA_RPC_URL.
contract BaseSepoliaForkTest is Test, Deployer {
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant COORDINATOR = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    bytes32 constant KEY_HASH = 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;

    function _fulfilAsCoordinator(System memory s, uint256 firstId, uint256 count, uint256 word) internal returns (uint256 settled) {
        uint256 vrfId = s.engine.vrfRequestOf(firstId);
        uint256 limit = s.engine.callbackGasLimitFor(count);
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vm.roll(vm.getBlockNumber() + 3);
        vm.prank(COORDINATOR);
        (bool ok,) = address(s.engine).call{gas: limit}(abi.encodeCall(DrawEngine.rawFulfillRandomWords, (vrfId, words)));
        assertTrue(ok, "callback within the coordinator gas limit");
        for (uint256 i; i < count; ++i) {
            (,,,, DrawEngine.AcquisitionStatus st) = s.engine.acquisitions(firstId + i);
            if (st != DrawEngine.AcquisitionStatus.Ready && st != DrawEngine.AcquisitionStatus.Pending) ++settled;
        }
    }

    function test_sepoliaFork_coldFirstPullSettlesInCallback() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        vm.deal(address(this), 10 ether);
        address admin = makeAddr("adminSafe");
        IVRFCoordinatorV2Plus c = IVRFCoordinatorV2Plus(COORDINATOR);
        uint256 sub = c.createSubscription();
        c.fundSubscriptionWithNative{value: 0.02 ether}(sub);
        System memory s = _deploySystem(
            Config({
                poolManager: POOL_MANAGER, vrfCoordinator: COORDINATOR, vrfSubscriptionId: sub, vrfKeyHash: KEY_HASH,
                shapes: address(0), drawPacks: address(0), creator: makeAddr("creator"), tokenWorks: makeAddr("tw"),
                dev: makeAddr("dev"), adminSafe: admin, guardian: makeAddr("guardian"), keeper: makeAddr("keeper"),
                timelockDelay: 600, create2Deployer: address(this),
                alloc: Allocation({ordinaryPool: 0.7 ether, treasuryReserve: 0.15 ether, backstopFloor: 0.1 ether,
                    marketLiquidity: 0.2 ether, boardItems: 25})
            }),
            address(this)
        );
        c.addConsumer(sub, address(s.engine));
        _fundAndBuild(s, 0.01 ether);
        _handOver(s);
        (address[] memory t, uint256[] memory v, bytes[] memory d) = activationBatch(s);
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), "activate", 600);
        vm.warp(vm.getBlockTimestamp() + 600);
        vm.prank(admin);
        s.timelock.executeBatch(t, v, d, bytes32(0), "activate");

        address p = makeAddr("freshPlayer");
        vm.deal(p, 2 ether);
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(1);
        vm.prank(p);
        uint256[] memory ids =
            s.engine.acquireBatch{value: total}(p, makeAddr("freshReferrer"), 1, 0, 0, 1_000, type(uint256).max, block.timestamp);
        assertEq(_fulfilAsCoordinator(s, ids[0], 1, 7), 1, "cold first pull settled inside the callback");

        (,,, total) = s.engine.quoteAcquisitionPrice(10);
        vm.prank(p);
        ids = s.engine.acquireBatch{value: total}(p, address(0), 10, 0, 0, 1_000, type(uint256).max, block.timestamp);
        uint256 settled = _fulfilAsCoordinator(s, ids[0], 10, 8);
        console2.log("10-pull batch settled inside the callback", settled);
        assertGe(settled, 5, "most of a batch settles inside the callback");
    }
}
