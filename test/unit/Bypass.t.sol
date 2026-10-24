// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ProtocolLiquidity} from "../../src/token/ProtocolLiquidity.sol";
import {MarketFixture} from "../utils/MarketFixture.sol";

/// @notice Alternative-pool bypass: ENGINE is an ordinary ERC-20, so anyone can open a pool without
///         our hook. This shows what a fee-free rival pool does to fee collection.
contract BypassTest is MarketFixture {
    address internal lp = makeAddr("rivalLP");
    address internal trader = makeAddr("trader");
    address internal arb = makeAddr("arb");
    ProtocolLiquidity internal rival;
    PoolKey internal rivalKey;

    function setUp() public {
        _deployMarket(2 ether, 10_000_000 ether, 2_000_000 ether, lp);
        // a hookless, zero-fee ETH/ENGINE pool seeded by a third party at the same price
        vm.deal(lp, 10 ether);
        vm.startPrank(lp);
        rival = new ProtocolLiquidity(manager, address(token), address(0), lp);
        token.transfer(address(rival), 2_000_000 ether);
        rival.launch{value: 0.4 ether}(_sqrtPrice(2_000_000 ether, 0.4 ether));
        vm.stopPrank();
        rivalKey = rival.poolKey();
        vm.deal(trader, 100 ether);
        vm.deal(arb, 100 ether);
    }

    function _buyRival(address who, uint256 eth) internal returns (uint256 out) {
        vm.prank(who);
        out = swapper.buy{value: eth}(rivalKey);
    }

    function _sellRival(address who, uint256 amount) internal returns (uint256 out) {
        vm.startPrank(who);
        token.approve(address(swapper), amount);
        out = swapper.sell(rivalKey, amount);
        vm.stopPrank();
    }

    function _price(ProtocolLiquidity pl) internal view returns (uint256) {
        uint256 p = pl.sqrtPriceX96();
        return (p * p) >> 192; // ENGINE per ETH
    }

    /// @notice A small buyer gets more ENGINE from the fee-free pool; a large buyer may still prefer
    ///         the deeper canonical pool despite its fee.
    function test_routingChoice() public {
        uint256 snap = vm.snapshotState();
        uint256 viaHook = _buy(trader, 0.002 ether);
        vm.revertToState(snap);
        uint256 viaRival = _buyRival(trader, 0.002 ether);
        console2.log("0.002 ETH buy: canonical", viaHook / 1e18, "rival", viaRival / 1e18);
        assertGt(viaRival, viaHook, "small trades route to the fee-free pool");
        vm.revertToState(snap);
        viaHook = _buy(trader, 1 ether);
        vm.revertToState(snap);
        viaRival = _buyRival(trader, 1 ether);
        console2.log("1 ETH buy: canonical", viaHook / 1e18, "rival", viaRival / 1e18);
        assertGt(viaHook, viaRival, "a large trade prefers the deeper canonical pool");
    }

    /// @notice After a buyer uses only the rival pool, arbitrage restores prices: the arbitrageur
    ///         buys in the cheap pool and sells in the canonical one, and pays our fee on that leg.
    function test_arbitrageAcrossPools_feeCollected() public {
        _buyRival(trader, 0.3 ether); // rival price of ENGINE rises
        uint256 feesBefore = hook.totalFees();
        uint256 ethSpent;
        uint256 ethBack;
        for (uint256 i; i < 40; ++i) {
            uint256 snap = vm.snapshotState();
            uint256 got = _buy(arb, 0.01 ether);
            uint256 back = _sellRival(arb, got);
            vm.revertToState(snap);
            if (back <= 0.01 ether) break; // no profit left
            got = _buy(arb, 0.01 ether);
            ethBack += _sellRival(arb, got);
            ethSpent += 0.01 ether;
        }
        // the arbitrage that existed ran the other way: buy canonical? check both directions
        for (uint256 i; i < 40; ++i) {
            uint256 snap = vm.snapshotState();
            uint256 got = _buyRival(arb, 0.01 ether);
            uint256 back = _sell(arb, got);
            vm.revertToState(snap);
            if (back <= 0.01 ether) break;
            got = _buyRival(arb, 0.01 ether);
            ethBack += _sell(arb, got);
            ethSpent += 0.01 ether;
        }
        uint256 fees = hook.totalFees() - feesBefore;
        console2.log("arb ETH cycled", ethSpent, "profit", ethBack > ethSpent ? ethBack - ethSpent : 0);
        console2.log("canonical hook fee earned from arbitrage", fees);
        console2.log("canonical price", _price(liquidity), "rival price", _price(rival));
        // prices are re-aligned to within the 2% fee band
        uint256 pc = _price(liquidity);
        uint256 pr = _price(rival);
        uint256 gap = pc > pr ? (pc - pr) * 10_000 / pc : (pr - pc) * 10_000 / pr;
        assertLe(gap, 450, "within the round-trip fee band");
    }
}
