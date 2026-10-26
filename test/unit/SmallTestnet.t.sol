// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SystemFixture} from "../utils/SystemFixture.sol";

/// @notice The small testnet allocation (script/config/base-sepolia.json): a 12-item board on a
///         0.5 ETH pool deploys through the production deployer, activates and plays.
contract SmallTestnetTest is SystemFixture {
    function _allocation() internal pure override returns (Allocation memory) {
        return Allocation({ordinaryPool: 0.5 ether, treasuryReserve: 0.03 ether, backstopFloor: 0.02 ether, marketLiquidity: 0.05 ether, boardItems: 12});
    }

    function test_smallAllocation_deploysActivatesPlaysRestocks() public {
        emit log_named_uint("listed", s.controller.listedCount());
        assertGe(s.controller.listedCount(), 12, "board built");
        assertEq(s.controller.queueLength(), 0, "nothing left queued (Deploy.s.sol postflight)");
        emit log_named_uint("board backing (wei)", s.controller.backing());
        emit log_named_uint("cash after build (wei)", s.controller.cash());
        _activate();
        for (uint256 r; r < 6; ++r) {
            _pull(player, 10, uint256(keccak256(abi.encode("small", r))));
            _settle();
        }
        emit log_named_uint("listed after 60 pulls", s.controller.listedCount());
        emit log_named_uint("cash after 60 pulls (wei)", s.controller.cash());
        emit log_named_uint("board backing after (wei)", s.controller.backing());
        emit log_named_uint("receivable after (wei)", s.controller.receivable());
        emit log_named_uint("pool value (nav) after (wei)", s.controller.nav());
        emit log_named_uint("treasury reserve after (wei)", s.treasury.reserve());
        assertEq(s.controller.nextSequenceToBook(), 61, "every pull booked");
        assertGe(s.controller.listedCount(), 12, "board restocked");
    }
}
