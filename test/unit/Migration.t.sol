// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SystemFixture} from "../utils/SystemFixture.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {Treasury} from "../../src/treasury/Treasury.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";

/// @dev Successor stand-in: records what arrives through each funding entry point.
contract SuccessorDouble {
    uint256 public pool;
    uint256 public grail;

    function fundPool() external payable {
        pool += msg.value;
    }

    function fundGrail() external payable {
        grail += msg.value;
    }
}

/// @notice Protocol-owned ETH (controller cash and maintenance, the GRAIL fund and unawarded GRAILs,
///         the treasury reserve and pending POL) moves to a successor through the timelock, only
///         once no issued pull can still need it; player funds stay in the engine.
contract MigrationTest is SystemFixture {
    address internal successor = makeAddr("successor");

    function _allocation() internal pure override returns (Allocation memory) {
        return Allocation({ordinaryPool: 0.5 ether, treasuryReserve: 0.03 ether, backstopFloor: 0.02 ether, marketLiquidity: 0.05 ether, boardItems: 12});
    }

    function _playAndRetire() internal {
        _activate();
        s.vault.fundGrail{value: 0.6 ether}();
        s.vault.step();
        assertEq(s.vault.liveGrails(), 1, "a GRAIL is listed");
        _pull(player, 10, 7);
        _settle();
        _govern(address(s.engine), abi.encodeCall(DrawEngine.retire, ()), "retire");
        uint256[] memory ids = new uint256[](s.controller.listedCount());
        uint256 n;
        for (uint256 id = 1; n < ids.length; ++id) {
            if (s.controller.listedItem(id).value != 0) ids[n++] = id;
        }
        s.controller.windDown(ids);
    }

    function test_migrateEverything_afterRetirement_throughTimelock() public {
        _playAndRetire();
        uint256 controllerCapital = s.controller.cash() + s.controller.maintenance();
        uint256 vaultBalance = address(s.vault).balance;
        uint256 grailBacking = s.vault.items()[0].backing;
        uint256 treasuryBalance = address(s.treasury).balance;
        uint256 engineBalance = address(s.engine).balance;
        assertGt(controllerCapital, 0);

        address[] memory t = new address[](3);
        uint256[] memory v = new uint256[](3);
        bytes[] memory d = new bytes[](3);
        (t[0], d[0]) = (address(s.controller), abi.encodeCall(DrawController.migrateCapital, (successor, false)));
        (t[1], d[1]) = (address(s.vault), abi.encodeCall(GrailVault.migrate, (successor, false)));
        (t[2], d[2]) = (address(s.treasury), abi.encodeCall(Treasury.migrate, (successor)));
        _timelock(t, v, d, "migrate");

        assertEq(successor.balance, controllerCapital + vaultBalance + grailBacking + treasuryBalance, "all protocol ETH moved");
        assertEq(address(s.controller).balance, 0);
        assertEq(s.controller.cash() + s.controller.maintenance() + s.controller.backing(), 0);
        assertTrue(s.controller.listingPaused());
        assertEq(address(s.vault).balance, 0);
        assertEq(s.vault.liveGrails(), 0, "unawarded GRAIL redeemed");
        assertTrue(s.vault.paused());
        assertEq(address(s.treasury).balance, 0);
        assertEq(s.treasury.reserve() + s.treasury.polPending(), 0);
        assertEq(address(s.engine).balance, engineBalance, "player escrow and credits untouched");
    }

    function test_migrateToSuccessorContracts() public {
        _playAndRetire();
        SuccessorDouble next = new SuccessorDouble();
        uint256 controllerCapital = s.controller.cash() + s.controller.maintenance();
        uint256 vaultValue = address(s.vault).balance + s.vault.items()[0].backing;
        vm.startPrank(address(s.timelock));
        s.controller.migrateCapital(address(next), true);
        s.vault.migrate(address(next), true);
        vm.stopPrank();
        assertEq(next.pool(), controllerCapital, "controller capital lands as successor cash");
        assertEq(next.grail(), vaultValue, "GRAIL fund and backing land in the successor fund");
    }

    function test_prizesStayRedeemableAfterMigration() public {
        _playAndRetire();
        vm.startPrank(address(s.timelock));
        s.controller.migrateCapital(successor, false);
        s.vault.migrate(successor, false);
        vm.stopPrank();
        // the winner of the first pull still redeems its prize for the ETH inside it
        (,,, uint256 listingId,) = s.engine.acquisitions(1);
        (address collection,,, uint256 tokenId,,,,) = s.engine.listings(listingId);
        uint256 before = player.balance;
        vm.prank(player);
        (bool ok,) = collection.call(abi.encodeWithSignature("burn(uint256)", tokenId));
        assertTrue(ok, "redeem");
        assertGt(player.balance, before, "backing paid to the winner");
    }

    function test_blockedWhileAPullIsUnresolved() public {
        _activate();
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(1);
        uint256 any = s.engine.ANY_INVENTORY_VERSION();
        vm.prank(player);
        s.engine.acquireBatch{value: total}(player, address(0), 1, 0, 0, 1_000, any, block.timestamp);
        vm.startPrank(address(s.timelock));
        vm.expectRevert(DrawController.BooksBehind.selector);
        s.controller.migrateCapital(successor, false);
        vm.expectRevert(GrailVault.AcquisitionsOpen.selector);
        s.vault.migrate(successor, false);
        vm.stopPrank();
    }

    function test_controllerBlockedWhileItemsAreListed() public {
        _activate();
        _pull(player, 3, 5);
        _settle();
        vm.prank(address(s.timelock));
        vm.expectRevert(DrawController.StillListed.selector);
        s.controller.migrateCapital(successor, false);
    }

    function test_onlyGovernance() public {
        _activate();
        vm.startPrank(player);
        vm.expectRevert(DrawController.NotGovernance.selector);
        s.controller.migrateCapital(player, false);
        vm.expectRevert(GrailVault.NotGovernance.selector);
        s.vault.migrate(player, false);
        vm.expectRevert(Treasury.NotGovernance.selector);
        s.treasury.migrate(player);
        vm.stopPrank();
    }
}
