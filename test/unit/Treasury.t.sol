// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SystemFixture} from "../utils/SystemFixture.sol";
import {Treasury} from "../../src/treasury/Treasury.sol";
import {Buyback} from "../../src/treasury/Buyback.sol";
import {DrawController} from "../../src/game/DrawController.sol";

/// @notice Treasury precedence (reserve, then 90 % GRAIL / 10 % POL), backstop, POL, buyback.
contract TreasuryTest is SystemFixture {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function test_reserveFirstThenGrailAndPol() public {
        assertEq(s.treasury.reserve(), 0.5 ether, "opening reserve");
        // drain the reserve target gap: raise the target so the next receipt refills first
        _govern(address(s.treasury), abi.encodeCall(Treasury.setParams, (0.6 ether, 0.3 ether, 9_000)), "p");
        uint256 vaultBefore = s.vault.fund();
        s.treasury.receiveTradingFees{value: 0.3 ether}();
        assertEq(s.treasury.reserve(), 0.6 ether, "0.1 to the reserve first");
        assertEq(s.vault.fund() - vaultBefore, 0.18 ether, "90% of the rest to the GRAIL fund");
        assertEq(s.treasury.polPending(), 0.02 ether, "10% of the rest to POL");
    }

    function test_tradingFeesFlowToGrail() public {
        vm.prank(buyer);
        swapper.buy{value: 1 ether}(key);
        s.hook.distribute();
        assertEq(creatorAddr.balance, 0.0025 ether, "operator 0.25%");
        assertEq(s.treasury.totalReceived(), 0.0175 ether);
        assertEq(s.vault.totalFunded(), 0.0175 ether * 9_000 / 10_000);
    }

    function test_backstopOnlyWhenRestockIsWaiting() public {
        vm.expectRevert(Treasury.NotNeeded.selector);
        s.treasury.backstop();
        // make restocking wait: the controller keeps 0.45 ETH unspent, more than its liquid cash
        _govern(address(s.controller), abi.encodeCall(DrawController.setBoard, (100, 0.45 ether)), "floor");
        _govern(address(s.treasury), abi.encodeCall(Treasury.setParams, (0.5 ether, 0.6 ether, 9_000)), "bf");
        _pull(player, 10, 1);
        _settle();
        assertGt(s.controller.queueLength(), 0, "replacements waiting");
        uint256 cash = s.controller.cash();
        uint256 sent = s.treasury.backstop();
        assertEq(sent, 0.6 ether - cash, "tops cash up to the backstop floor");
        assertEq(s.controller.cash(), 0.6 ether);
        assertEq(s.treasury.reserve(), 0.5 ether - sent);
    }

    function test_polDeploysIntoLockedPosition() public {
        s.treasury.receiveTradingFees{value: 1 ether}();
        uint128 before = s.liquidity.totalLiquidity();
        uint160 minPrice = s.liquidity.sqrtPriceX96() * 95 / 100;
        vm.prank(keeperAddr);
        s.treasury.deployPol(minPrice);
        assertGt(s.liquidity.totalLiquidity(), before);
        vm.prank(player);
        vm.expectRevert(Treasury.NotKeeper.selector);
        s.treasury.deployPol(minPrice);
    }

    function test_buybackWaitsForGenesisEnd_rateLimited_burns() public {
        (bool ok,) = address(s.buyback).call{value: 0.2 ether}("");
        assertTrue(ok);
        vm.expectRevert(Buyback.NotStarted.selector);
        s.buyback.buyAndBurn();
        vm.warp(s.buyback.startTime());
        uint256 supply = s.token.totalSupply();
        uint256 burned = s.buyback.buyAndBurn();
        assertEq(s.token.totalSupply(), supply - burned);
        uint256 spent = s.buyback.totalEthSpent();
        assertLe(spent, 0.05 ether, "at most one slice");
        assertGt(spent, 0);
        assertEq(s.hook.totalFees(), 0, "buyback is fee-exempt");
        // the 3% impact cap stopped the buy early: price moved by at most 3%
        assertApproxEqRel(uint256(s.liquidity.sqrtPriceX96()) ** 2 / 1e40, (uint256(referenceSqrtPrice()) ** 2 / 1e40) * 97 / 100, 0.001e18);
        vm.expectRevert(Buyback.TooSoon.selector);
        s.buyback.buyAndBurn();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        s.buyback.buyAndBurn();
        vm.prank(guardianAddr);
        s.buyback.setPaused(true);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.expectRevert(Buyback.IsPaused.selector);
        s.buyback.buyAndBurn();
    }

    function test_noWithdrawalPathsFromTreasury() public {
        // the treasury exposes no function that sends ETH to an arbitrary account
        (bool ok,) = address(s.treasury).call(abi.encodeWithSignature("withdraw(address,uint256)", player, 1));
        assertFalse(ok);
        (ok,) = address(s.treasury).call(abi.encodeWithSignature("sweep(address)", player));
        assertFalse(ok);
    }
}
