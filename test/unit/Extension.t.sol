// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SystemFixture} from "../utils/SystemFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";

/// @notice A successor controller: an engine supplier that receives listings in place and their proceeds.
contract SuccessorController {
    DrawEngine public immutable engine;

    constructor(DrawEngine e) {
        engine = e;
    }

    function withdraw() external returns (uint256) {
        return engine.withdrawProceeds();
    }

    receive() external payable {}
}

/// @notice An ENGINE Pack: an ERC-721 that holds ENGINE and releases it to the holder on `open`.
contract EnginePack is ERC721 {
    address public immutable token;
    mapping(uint256 => uint256) public amountOf;
    uint256 public next = 1;

    constructor(address token_) {
        token = token_;
    }

    function name() public pure override returns (string memory) {
        return "ENGINE Pack";
    }

    function symbol() public pure override returns (string memory) {
        return "EPACK";
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function wrap(uint256 amount, address to) external returns (uint256 id) {
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        id = next++;
        amountOf[id] = amount;
        _mint(to, id);
    }

    function open(uint256 id) external {
        require(ownerOf(id) == msg.sender, "owner");
        uint256 a = amountOf[id];
        delete amountOf[id];
        _burn(id);
        SafeTransferLib.safeTransfer(token, msg.sender, a);
    }
}

/// @notice Extension paths without migrating the engine: a successor controller takes listings
///         in place; a new ERC-721 prize collection (an ENGINE Pack) is listed by governance.
contract ExtensionTest is SystemFixture {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function test_successorControllerTakesListingsInPlace() public {
        SuccessorController next = new SuccessorController(s.engine);
        _govern(address(s.engine), abi.encodeCall(DrawEngine.setSupplier, (address(next), true)), "sup");
        // pick five listed 0.01 Shapes from the controller's books
        uint256[] memory ids = new uint256[](5);
        uint256 found;
        for (uint256 id = 1; found < 5; ++id) {
            DrawController.Item memory it = s.controller.listedItem(id);
            if (it.value == 0.01 ether) ids[found++] = id;
        }
        uint256 backingBefore = s.controller.backing();
        // an unresolved acquisition blocks the hand-off (it must settle to the depositor it saw)
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(1);
        uint256 any = s.engine.ANY_INVENTORY_VERSION();
        vm.prank(player);
        s.engine.acquireBatch{value: total}(player, address(0), 1, 0, 0, 1_000, any, block.timestamp);
        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        bytes[] memory d = new bytes[](1);
        (t[0], d[0]) = (address(s.controller), abi.encodeCall(DrawController.handOffListings, (ids, address(next))));
        uint256 delay = s.timelock.getMinDelay();
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), "h", delay);
        vm.warp(vm.getBlockTimestamp() + delay);
        vm.prank(admin);
        vm.expectRevert();
        s.timelock.executeBatch(t, v, d, bytes32(0), "h");
        // settle (word arrives late: the request expires and is refunded), then hand off
        vm.roll(vm.getBlockNumber() + s.engine.selectionTimeoutBlocks() + 1);
        _settle();
        vm.prank(admin);
        s.timelock.executeBatch(t, v, d, bytes32(0), "h");
        assertEq(s.controller.backing(), backingBefore - 0.05 ether, "left the old books at backing");
        for (uint256 i; i < 5; ++i) {
            (, address depositor,,,,,, DrawEngine.ListingStatus st) = s.engine.listings(ids[i]);
            assertEq(depositor, address(next));
            assertEq(uint256(st), uint256(DrawEngine.ListingStatus.Active), "NFT and price unchanged");
        }
        // play until a handed-off listing is captured: proceeds go to the successor
        for (uint256 r; r < 60 && s.engine.proceedsOf(address(next)) == 0; ++r) {
            _pull(player, 10, 1000 + r);
            _settle();
        }
        assertGt(s.engine.proceedsOf(address(next)), 0, "successor earns its captures");
        assertGe(address(s.controller).balance, s.controller.cash() + s.controller.maintenance());
        next.withdraw();
    }

    function test_newCollectionPrize_enginePack() public {
        EnginePack pack = new EnginePack(address(s.token));
        // a sponsor buys ENGINE on the market and wraps 100k of it into a pack held by the controller
        swapper.buy{value: 0.1 ether}(key);
        s.token.approve(address(pack), 100_000 ether);
        uint256 packId = pack.wrap(100_000 ether, address(s.controller));
        _govern(
            address(s.controller),
            abi.encodeCall(DrawController.listExternal, (address(pack), packId, 0.000001 ether)),
            "pack"
        );
        // its tiny notional makes it the likely draw
        _pull(player, 1, 3);
        _settle();
        assertEq(pack.ownerOf(packId), player, "prize delivered");
        vm.prank(player);
        pack.open(packId);
        assertEq(s.token.balanceOf(player), 100_000 ether);
    }

    /// @notice Shutdown: after governance retires the engine, anyone can turn unawarded prizes back
    ///         into ordinary-pool ETH; in-flight acquisitions settle first.
    function test_windDownAfterRetire() public {
        _pull(player, 5, 11);
        _settle();
        vm.expectRevert(DrawController.ReleaseNotOpen.selector);
        s.controller.windDown(new uint256[](0));
        _govern(address(s.engine), abi.encodeCall(DrawEngine.retire, ()), "retire");
        uint256 any = s.engine.ANY_INVENTORY_VERSION();
        vm.prank(player);
        vm.expectRevert();
        s.engine.acquireBatch{value: 1 ether}(player, address(0), 1, 0, 0, 0, any, block.timestamp);
        uint256[] memory ids = new uint256[](20);
        uint256 n;
        uint256 value;
        for (uint256 id = 1; n < 20; ++id) {
            DrawController.Item memory it = s.controller.listedItem(id);
            if (it.value != 0) {
                ids[n++] = id;
                value += it.value;
            }
        }
        uint256 cash = s.controller.cash();
        uint256 backing = s.controller.backing();
        s.controller.windDown(ids);
        assertEq(s.controller.cash(), cash + value, "redeemed into cash");
        assertEq(s.controller.backing(), backing - value);
        assertGe(address(s.controller).balance, s.controller.cash() + s.controller.maintenance());
    }

    receive() external payable {}
}
