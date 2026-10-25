// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SystemFixture} from "../utils/SystemFixture.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";

/// @notice The scaled testnet allocation in `script/config/base-sepolia.json` deploys through the
///         production deployer with unchanged prices, mix, fees and rules, activates through the
///         timelock and plays. Base mainnet cannot use it (Deploy.s.sol).
contract TestnetAllocationTest is SystemFixture {
    function _allocation() internal pure override returns (Allocation memory) {
        return Allocation({
            ordinaryPool: 0.7 ether,
            treasuryReserve: 0.15 ether,
            backstopFloor: 0.1 ether,
            marketLiquidity: 0.2 ether,
            boardItems: 25
        });
    }

    function test_scaledAllocation_deploysActivatesAndPlays() public {
        assertEq(s.controller.boardItems(), 25);
        assertEq(s.controller.listedCount(), 27, "board built: 25 items, each row rounded up (16, 7, 2, 1, 1)");
        assertEq(s.controller.capitalTarget(), 0.7 ether);
        assertEq(s.treasury.reserve(), 0.15 ether);
        assertEq(s.treasury.reserveTarget(), 0.15 ether);
        assertEq(address(s.timelock).balance, 0.2 ether);
        // same per-row notionals as the launch board
        assertEq(s.controller.rowNotional(0), 0.0117 ether);
        assertEq(s.controller.rowNotional(4), 0.108 ether);
        assertFalse(_isLaunchAllocation(s.alloc));
        _activate();
        assertTrue(s.engine.activated() && s.liquidity.launched());
        // the market opens at 0.2 ETH / 10M ENGINE
        assertEq(s.liquidity.sqrtPriceX96(), referenceSqrtPrice(0.2 ether));
        assertEq(s.token.totalSupply(), 35_000_000 ether);
        _pull(player, 10, 7);
        _settle();
        assertEq(s.controller.nextSequenceToBook(), 11);
        assertEq(s.controller.listedCount(), 27, "restocked");
    }

    function test_launchAllocationMatchesLaunchParams() public pure {
        Allocation memory a = launchAllocation();
        assertEq(a.ordinaryPool, LaunchParams.ORDINARY_POOL);
        assertEq(a.marketLiquidity, LaunchParams.MARKET_LIQUIDITY);
        assertEq(a.treasuryReserve, LaunchParams.TREASURY_RESERVE);
        assertEq(a.boardItems, 100);
    }
}
