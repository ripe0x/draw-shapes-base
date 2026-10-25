// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {console2} from "forge-std/console2.sol";
import {GameFixture} from "../utils/GameFixture.sol";
contract GasProbeTest is GameFixture {
    function test_probe() public {
        _openAndActivate();
        for (uint256 n = 1; n <= 20; n = n == 1 ? 5 : n + 5) {
            (, uint256 vrfId) = _pull(alice, n);
            vm.roll(vm.getBlockNumber() + 3);
            uint256 g = gasleft();
            vrf.fulfill(vrfId, uint256(keccak256(abi.encode(n))));
            console2.log("batch", n, "callback total gas (fast path may not run)", g - gasleft());
            g = gasleft();
            engine.processAcquisitions(n);
            console2.log("  process gas per acq", (g - gasleft()) / n);
            g = gasleft();
            controller.settle(50);
            console2.log("  controller settle gas", g - gasleft());
        }
    }
}
