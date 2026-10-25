// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {SystemFixture} from "../utils/SystemFixture.sol";

/// @notice Every keeper and deployment transaction fits the EIP-7825 per-transaction gas cap
///         (2^24 = 16,777,216), enforced on Base Sepolia and coming to Base mainnet. Found by the
///         live Base Sepolia deployment: build(40) needed 26.8M gas. Meaningful under isolated
///         transactions (cold storage): `forge test --isolate --match-contract TxGasCapTest`.
contract TxGasCapTest is SystemFixture {
    uint256 constant CAP = 16_777_216;

    /// @dev Gas the transaction must be given: execution before refunds (the cap limits the gas limit).
    function _needed() internal view returns (uint256) {
        int64 refunded = vm.lastCallGas().gasRefunded;
        return uint256(vm.lastCallGas().gasTotalUsed) + (refunded > 0 ? uint256(uint64(refunded)) : 0);
    }

    function setUp() public override {
        super.setUp();
        _activate();
    }

    function test_recoveryAfterDrain_everySettleFitsTheCap() public {
        // a long outage: the whole board is captured, nothing is booked or restocked
        for (uint256 i; i < 6; ++i) _pull(player, 20, uint256(keccak256(abi.encode("drain", i))));
        uint256 maxGas;
        uint256 calls;
        while ((s.controller.nextSequenceToBook() <= s.engine.lastIssuedSequence() || s.controller.queueLength() != 0) && calls < 40) {
            s.controller.settle(50);
            uint256 used = _needed();
            if (used > maxGas) maxGas = used;
            ++calls;
        }
        console2.log("recovery settle calls", calls);
        console2.log("largest settle gas before refunds", maxGas);
        assertEq(s.controller.queueLength(), 0, "fully restocked");
        assertLt(maxGas, CAP * 9 / 10, "every settle leaves 10 % headroom under the per-transaction cap");
    }

    function test_buildChunkFitsTheCap() public {
        // empty part of the board and rebuild it with the deployer's chunk size
        for (uint256 i; i < 2; ++i) _pull(player, 20, uint256(keccak256(abi.encode("b", i))));
        s.controller.settle(50);
        assertLt(_needed(), CAP * 9 / 10);
        s.controller.build(s.controller.MAX_LIST_PER_CALL());
        console2.log("build(MAX_LIST_PER_CALL) gas before refunds", _needed());
        assertLt(_needed(), CAP * 9 / 10, "a full listing batch fits the cap");
    }
}
