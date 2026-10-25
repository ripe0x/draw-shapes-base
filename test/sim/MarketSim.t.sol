// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {MarketFixture} from "../utils/MarketFixture.sol";

/// @notice Fourteen-day genesis market on the real v4 PoolManager and EngineHook: hourly external
///         buys and farmer sales of each closed epoch's rewards. Writes evidence/market/*.csv.
/// @dev Assumptions are inputs, not predictions: external buying per day, the share of rewards
///      farmers sell, and that they sell evenly over the day after their epoch closes.
contract MarketSimTest is MarketFixture {
    struct Scenario {
        string name;
        uint256 farm;
        uint256 buyPerDay;
        uint16 feeBps;
        uint16 sellBps;
    }

    address internal farmer = makeAddr("farmers");
    address internal buyer = makeAddr("buyers");

    function _run(Scenario memory s) internal returns (string memory row) {
        _deployMarket(2 ether, 10_000_000 ether, s.farm, farmer);
        hook.setFees(s.feeBps, 25);
        vm.deal(buyer, 1_000 ether);
        uint256 perEpoch = s.farm / 14;
        string memory path = string.concat("evidence/market/", s.name, ".csv");
        vm.writeFile(path, "day,price_eth_per_engine_e18,pool_eth,farmer_tokens_sold,farmer_eth,buyer_eth,hook_fees,operator_fees,treasury_fees\n");
        uint256 farmerEthTotal;
        uint256 sold;
        uint256 lastPrice;
        for (uint256 day; day < 16; ++day) {
            uint256 release = (day >= 1 && day <= 14) ? perEpoch : 0;
            uint256 toSell = release * s.sellBps / 10_000;
            uint256 dayEth;
            for (uint256 h; h < 24; ++h) {
                if (s.buyPerDay != 0) _buy(buyer, s.buyPerDay / 24);
                if (toSell != 0) {
                    uint256 chunk = toSell / 24;
                    dayEth += _sell(farmer, chunk);
                    sold += chunk;
                }
            }
            farmerEthTotal += dayEth;
            lastPrice = _ethPerEngine();
            vm.writeLine(
                path,
                string.concat(
                    vm.toString(day), ",", vm.toString(lastPrice), ",", vm.toString(address(manager).balance), ",",
                    vm.toString(sold), ",", vm.toString(dayEth), ",", vm.toString(s.buyPerDay), ",",
                    vm.toString(hook.totalFees()), ",", vm.toString(hook.operatorAccrued()), ",",
                    vm.toString(hook.treasuryAccrued())
                )
            );
        }
        row = string.concat(
            s.name, ",", vm.toString(s.farm / 1e18), ",", vm.toString(s.buyPerDay), ",", vm.toString(s.feeBps), ",",
            vm.toString(s.sellBps), ",", vm.toString(farmerEthTotal), ",", vm.toString(sold), ",",
            vm.toString(lastPrice), ",", vm.toString(address(manager).balance), ",", vm.toString(hook.totalFees()), ",",
            vm.toString(hook.operatorAccrued()), ",", vm.toString(hook.treasuryAccrued())
        );
    }

    function _ethPerEngine() internal view returns (uint256) {
        uint256 p = liquidity.sqrtPriceX96();
        // currency1 per currency0 = (p / 2^96)^2 ; ETH per ENGINE (1e18 scale) = 2^192 * 1e18 / p^2
        return (uint256(1) << 192) / (p * p / 1e18);
    }

    function test_sim_grid() public {
        uint256[3] memory farms = [uint256(50_000_000 ether), 25_000_000 ether, 10_000_000 ether];
        uint256[4] memory buys = [uint256(0), 0.3 ether, 0.7 ether, 1.5 ether];
        uint16[2] memory fees = [uint16(200), 500];
        string memory summary = "evidence/market/summary.csv";
        vm.writeFile(summary, "scenario,farm_engine,buy_per_day_wei,fee_bps,sell_bps,farmer_eth,tokens_sold,final_price_eth_per_engine_e18,final_pool_eth,hook_fees,operator_fees,treasury_fees\n");
        for (uint256 f; f < 3; ++f) {
            for (uint256 b; b < 4; ++b) {
                for (uint256 k; k < 2; ++k) {
                    uint256 snap = vm.snapshotState();
                    string memory name = string.concat(
                        "farm", vm.toString(farms[f] / 1e24), "M_buy", vm.toString(buys[b] / 1e16), "c_fee", vm.toString(fees[k])
                    );
                    vm.writeLine(summary, _run(Scenario(name, farms[f], buys[b], fees[k], 10_000)));
                    vm.revertToState(snap);
                }
            }
        }
        // farmers who sell half
        uint256 s2 = vm.snapshotState();
        vm.writeLine(summary, _run(Scenario("farm50M_buy70c_fee200_sell50", 50_000_000 ether, 0.7 ether, 200, 5_000)));
        vm.revertToState(s2);
        vm.writeLine(summary, _run(Scenario("farm25M_buy70c_fee200_sell50", 25_000_000 ether, 0.7 ether, 200, 5_000)));
    }
}
