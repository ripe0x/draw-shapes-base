// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {PrizeRouter} from "../../src/game/PrizeRouter.sol";
import {console2} from "forge-std/console2.sol";

interface IValue {
    function valueOf(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Playing winnings: pull with prizes (plus ETH), cash prizes out, all in one transaction.
contract PrizeRouterTest is GameFixture {
    PrizeRouter internal router;
    uint256[] internal shapeIds;
    uint256[] internal packIds;
    uint256 internal prizeWei;

    function setUp() public override {
        super.setUp();
        _openAndActivate();
        router = new PrizeRouter(address(engine), address(shapes), address(packs));
        // alice wins a batch of prizes
        (uint256[] memory ids, uint256 vrfId) = _pull(alice, 10);
        _fulfill(vrfId, 42);
        _settleAll();
        for (uint256 i; i < ids.length; ++i) {
            (,,, uint256 listingId, DrawEngine.AcquisitionStatus st) = engine.acquisitions(ids[i]);
            assertEq(uint256(st), uint256(DrawEngine.AcquisitionStatus.Fulfilled));
            (address collection,,, uint256 tokenId,,,,) = engine.listings(listingId);
            if (collection == address(packs)) packIds.push(tokenId);
            else shapeIds.push(tokenId);
            prizeWei += IValue(collection).valueOf(tokenId);
        }
        assertGt(shapeIds.length, 0, "won Shapes");
        assertGt(packIds.length, 0, "won Draw Packs");
    }

    function _approve(address who) internal {
        vm.startPrank(who);
        shapes.setApprovalForAll(address(router), true);
        packs.setApprovalForAll(address(router), true);
        vm.stopPrank();
    }

    function _pullWith(address who, uint256 count, uint256 value) internal returns (uint256[] memory ids) {
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(who);
        ids = router.pullWithPrizes{value: value}(shapeIds, packIds, referrer, count, 0, 1_000, any, block.timestamp);
    }

    function test_pullWithPrizesOnly_changeReturned_routerEmpty() public {
        _approve(alice);
        // the prizes cover a few pulls on their own
        uint256 count = 3;
        (,,, uint256 total) = engine.quoteAcquisitionPrice(count);
        assertGe(prizeWei, total, "prizes cover the pulls");
        uint256 before = alice.balance;
        uint256 g = gasleft();
        uint256[] memory ids = _pullWith(alice, count, 0);
        console2.log("pullWithPrizes gas, prizes / pulls", shapeIds.length + packIds.length, count, g - gasleft());
        assertEq(ids.length, count);
        for (uint256 i; i < ids.length; ++i) {
            (address purchaser,,,,) = engine.acquisitions(ids[i]);
            assertEq(purchaser, alice, "pulls are the player's");
        }
        assertEq(alice.balance - before, prizeWei - total, "exact change: prizes at face minus the price");
        assertEq(address(router).balance, 0, "router keeps nothing");
        for (uint256 i; i < shapeIds.length; ++i) {
            vm.expectRevert();
            shapes.ownerOf(shapeIds[i]); // redeemed: burned
        }
        // the new pulls deliver to the player as usual
        _fulfill(vrf.nextRequestId() - (count + 4) / 5, 7);
        _settleAll();
        (,,,, DrawEngine.AcquisitionStatus st) = engine.acquisitions(ids[0]);
        assertEq(uint256(st), uint256(DrawEngine.AcquisitionStatus.Fulfilled));
    }

    function test_pullWithPrizesAndEth_topUp() public {
        _approve(alice);
        uint256 count = 10;
        (,,, uint256 total) = engine.quoteAcquisitionPrice(count);
        assertLt(prizeWei, total, "prizes alone do not cover ten pulls");
        uint256 topUp = total - prizeWei + 0.01 ether;
        uint256 before = alice.balance;
        _pullWith(alice, count, topUp);
        assertEq(before - alice.balance, total - prizeWei, "the wallet pays only the shortfall");
        assertEq(address(router).balance, 0);
    }

    function test_cashOut_allPrizesAtFace() public {
        _approve(alice);
        address to = makeAddr("cold");
        vm.prank(alice);
        uint256 amount = router.cashOut(shapeIds, packIds, to);
        assertEq(amount, prizeWei);
        assertEq(to.balance, prizeWei, "every prize redeemed at face");
        assertEq(address(router).balance, 0);
    }

    function test_cannotSpendSomeoneElsesPrizes() public {
        _approve(alice);
        _approve(bob);
        vm.deal(bob, 1 ether);
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(bob);
        vm.expectRevert();
        router.pullWithPrizes(shapeIds, packIds, address(0), 1, 0, 1_000, any, block.timestamp);
        vm.prank(bob);
        vm.expectRevert();
        router.cashOut(shapeIds, packIds, bob);
    }

    function test_noApproval_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        router.cashOut(shapeIds, packIds, alice);
    }

    function test_failedPull_leavesPrizesUntouched() public {
        _approve(alice);
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(alice);
        vm.expectRevert(DrawEngine.InsufficientPayment.selector);
        router.pullWithPrizes(shapeIds, packIds, address(0), 20, 0, 1_000, any, block.timestamp);
        assertEq(shapes.ownerOf(shapeIds[0]), alice, "atomic: nothing redeemed");
        assertEq(packs.ownerOf(packIds[0]), alice);
    }

    function test_forcedEth_isNeverSpentOrPaidOut() public {
        _approve(alice);
        vm.deal(address(router), 1 ether);
        uint256 count = 3;
        (,,, uint256 total) = engine.quoteAcquisitionPrice(count);
        uint256 before = alice.balance;
        _pullWith(alice, count, 0);
        assertEq(alice.balance - before, prizeWei - total, "change excludes stray ETH");
        assertEq(address(router).balance, 1 ether, "stray ETH stays put");
    }
}
