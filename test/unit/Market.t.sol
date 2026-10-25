// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {EngineToken} from "../../src/token/EngineToken.sol";
import {EngineHook} from "../../src/token/EngineHook.sol";
import {ProtocolLiquidity} from "../../src/token/ProtocolLiquidity.sol";
import {MarketFixture} from "../utils/MarketFixture.sol";

contract MarketTest is MarketFixture {
    address alice = makeAddr("alice");

    function setUp() public {
        _deployMarket(2 ether, 10_000_000 ether, 0, address(0));
        vm.deal(alice, 100 ether);
    }

    function test_fixedSupplyAndNoMint() public view {
        assertEq(token.totalSupply(), 10_000_000 ether);
        assertEq(token.balanceOf(address(manager)) + token.balanceOf(address(liquidity)), 10_000_000 ether);
        assertLt(token.balanceOf(address(liquidity)), 1e6, "seeded except rounding dust");
    }

    function test_spotPriceReference() public view {
        // 2 ETH / 10M ENGINE = 2e-7 ETH per ENGINE
        uint256 p = liquidity.sqrtPriceX96();
        uint256 enginePerEth = (p * p) >> 192;
        assertApproxEqRel(enginePerEth, 5_000_000, 1e12);
    }

    function test_onlyLauncherInitialisesOnce() public {
        PoolKey memory other = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 0, 60, IHooks(address(hook)));
        uint160 p = liquidity.sqrtPriceX96();
        vm.expectRevert();
        manager.initialize(other, p);
        vm.expectRevert(ProtocolLiquidity.AlreadyLaunched.selector);
        liquidity.launch(p);
    }

    function test_buyExactIn_fee2pct_split() public {
        uint256 out = _buy(alice, 1 ether);
        assertGt(out, 0);
        assertEq(hook.totalFees(), 0.02 ether, "2% of ETH in");
        assertEq(hook.operatorAccrued(), 0.0025 ether, "0.25% of volume");
        assertEq(hook.treasuryAccrued(), 0.0175 ether, "1.75% of volume");
        assertEq(address(hook).balance, 0.02 ether);
        hook.distribute();
        assertEq(operator.balance, 0.0025 ether);
        assertEq(treasurySink.received(), 0.0175 ether);
    }

    function test_sellExactIn_feeOnEthOut() public {
        uint256 bought = _buy(alice, 1 ether);
        uint256 feesBefore = hook.totalFees();
        uint256 ethOut = _sell(alice, bought);
        uint256 fee = hook.totalFees() - feesBefore;
        // fee is 2% of gross ETH out; the seller receives gross - fee
        assertApproxEqAbs(fee * 10_000 / (ethOut + fee), 200, 1);
        // round trip loses about 4% in fees plus price impact
        console2.log("round trip ETH back from 1 ETH", ethOut);
    }

    function test_buyExactOut_feeOnTop() public {
        vm.prank(alice);
        uint256 paid = swapper.buyExactOut{value: 1 ether}(key, 100_000 ether);
        assertEq(token.balanceOf(alice), 100_000 ether);
        assertGt(hook.totalFees(), 0);
        assertApproxEqAbs(hook.totalFees() * 10_000 / (paid), 196, 2);
    }

    function test_sellExactOutReverts() public {
        _buy(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(swapper), type(uint256).max);
        vm.expectRevert();
        swapper.sellExactOut(key, 0.1 ether);
        vm.stopPrank();
    }

    function test_exemptSenderPaysNoFee() public {
        hook.setFeeExempt(address(swapper), true);
        _buy(alice, 1 ether);
        assertEq(hook.totalFees(), 0);
    }

    function test_feeBounds() public {
        vm.expectRevert(EngineHook.InvalidConfig.selector);
        hook.setFees(501, 25);
        vm.expectRevert(EngineHook.InvalidConfig.selector);
        hook.setFees(200, 201);
        vm.prank(alice);
        vm.expectRevert(EngineHook.NotGovernance.selector);
        hook.setFees(100, 25);
        hook.setFees(500, 25);
        _buy(alice, 1 ether);
        assertEq(hook.totalFees(), 0.05 ether);
    }

    function test_protocolLiquidityIsPermanent_andGrows() public {
        uint128 l0 = liquidity.totalLiquidity();
        liquidity.setTreasury(address(this));
        uint160 p = liquidity.sqrtPriceX96();
        liquidity.addLiquidity{value: 0.2 ether}(p * 99 / 100);
        assertGt(liquidity.totalLiquidity(), l0);
        // there is no remove function: the ABI exposes none
        (bool ok,) = address(liquidity).call(abi.encodeWithSignature("removeLiquidity(uint128)", uint128(1)));
        assertFalse(ok);
    }
}
