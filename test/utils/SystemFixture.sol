// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Deployer} from "../../script/Deployer.sol";
import {MockVRFCoordinator} from "./MockVRFCoordinator.sol";
import {Swapper} from "./Swapper.sol";

/// @notice The production deployment (`script/Deployer.sol`) on a local PoolManager and VRF double,
///         activated through the timelock.
abstract contract SystemFixture is Test, Deployer {
    address internal admin = makeAddr("adminSafe");
    address internal guardianAddr = makeAddr("guardian");
    address internal creatorAddr = makeAddr("creator");
    address internal tw = makeAddr("tokenWorks");
    address internal devAddr = makeAddr("dev");
    address internal keeperAddr = makeAddr("keeper");
    address internal player = makeAddr("player");
    address internal buyer = makeAddr("buyer");

    MockVRFCoordinator internal vrf;
    IPoolManager internal manager;
    System internal s;
    Swapper internal swapper;
    PoolKey internal key;

    function setUp() public virtual {
        vm.deal(player, 1_000 ether);
        vm.deal(buyer, 1_000 ether);
        vm.deal(address(this), 100 ether);
        vrf = new MockVRFCoordinator();
        uint256 sub = vrf.createSubscription();
        vrf.fundSubscriptionWithNative{value: 0.02 ether}(sub);
        manager = IPoolManager(deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(admin)));
        s = _deploySystem(
            Config({
                poolManager: address(manager),
                vrfCoordinator: address(vrf),
                vrfSubscriptionId: sub,
                vrfKeyHash: keccak256("lane"),
                shapes: address(0),
                drawPacks: address(0),
                creator: creatorAddr,
                tokenWorks: tw,
                dev: devAddr,
                adminSafe: admin,
                guardian: guardianAddr,
                keeper: keeperAddr,
                timelockDelay: 2 days,
                create2Deployer: address(this),
                alloc: _allocation()
            }),
            address(this)
        );
        _fundAndBuild(s, 0.05 ether);
        _handOver(s);
        swapper = new Swapper(manager);
        key = s.liquidity.poolKey();
    }

    /// @dev The opening allocation the fixture deploys with (testnet suites override it).
    function _allocation() internal view virtual returns (Allocation memory) {
        return launchAllocation();
    }

    function _timelock(address[] memory t, uint256[] memory v, bytes[] memory d, bytes32 salt) internal {
        uint256 delay = s.timelock.getMinDelay();
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), salt, delay);
        vm.warp(vm.getBlockTimestamp() + delay);
        vm.prank(admin);
        s.timelock.executeBatch(t, v, d, bytes32(0), salt);
    }

    function _govern(address target, bytes memory data, bytes32 salt) internal {
        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        bytes[] memory d = new bytes[](1);
        (t[0], d[0]) = (target, data);
        _timelock(t, v, d, salt);
    }

    function _activate() internal {
        (address[] memory t, uint256[] memory v, bytes[] memory d) = activationBatch(s);
        _timelock(t, v, d, "activate");
    }

    function _pull(address who, uint256 n, uint256 word) internal returns (uint256[] memory ids) {
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(n);
        uint256 vrfId = vrf.nextRequestId();
        uint256 any = s.engine.ANY_INVENTORY_VERSION();
        vm.prank(who);
        ids = s.engine.acquireBatch{value: total}(who, address(0), n, 0, 0, 1_000, any, block.timestamp);
        vrf.markGroup(vrfId, vrf.nextRequestId());
        vm.roll(vm.getBlockNumber() + 3);
        vrf.fulfillGroup(vrfId, word);
    }

    function _settle() internal {
        for (uint256 i; i < 20; ++i) {
            s.controller.settle(50);
            s.vault.step();
            if (s.controller.nextSequenceToBook() > s.engine.lastIssuedSequence() && s.controller.queueLength() == 0) break;
        }
    }
}
