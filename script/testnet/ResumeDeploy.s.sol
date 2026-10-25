// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Deploy} from "../Deploy.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {EngineToken} from "../../src/token/EngineToken.sol";
import {EngineHook} from "../../src/token/EngineHook.sol";
import {ProtocolLiquidity} from "../../src/token/ProtocolLiquidity.sol";
import {GenesisFarm} from "../../src/token/GenesisFarm.sol";
import {Treasury} from "../../src/treasury/Treasury.sol";
import {Buyback} from "../../src/treasury/Buyback.sol";
import {Lens} from "../../src/Lens.sol";

/// @notice Testnet only: finishes a Deploy.s.sol run that stopped after its contracts were deployed and
///         the pool funded (the first Base Sepolia run hit the EIP-7825 per-transaction gas cap at
///         build(40)). Performs the remaining deployer steps in cap-sized chunks, then the same postflight
///         and records as Deploy.s.sol.
///   forge script script/testnet/ResumeDeploy.s.sol --sig "resume(string,string)" base-sepolia-live <addresses.json> ...
contract ResumeDeploy is Deploy {
    function resume(string calldata env, string calldata addressesPath) external {
        require(block.chainid != 8453, "testnet only");
        string memory json = vm.readFile(string.concat("script/config/", env, ".json"));
        Config memory c;
        c.creator = vm.parseJsonAddress(json, ".creator");
        c.tokenWorks = vm.parseJsonAddress(json, ".tokenWorks");
        c.dev = vm.parseJsonAddress(json, ".dev");
        uint256 maintenanceFloat = vm.parseJsonUint(json, ".maintenanceFloat");
        c.alloc.ordinaryPool = vm.parseJsonUint(json, ".testnetAllocation.ordinaryPool");
        c.alloc.treasuryReserve = vm.parseJsonUint(json, ".testnetAllocation.treasuryReserve");
        c.alloc.backstopFloor = vm.parseJsonUint(json, ".testnetAllocation.backstopFloor");
        c.alloc.marketLiquidity = vm.parseJsonUint(json, ".testnetAllocation.marketLiquidity");
        c.alloc.boardItems = vm.parseJsonUint(json, ".testnetAllocation.boardItems");

        string memory a = vm.readFile(addressesPath);
        System memory s;
        s.shapes = vm.parseJsonAddress(a, ".shapes");
        s.drawPacks = vm.parseJsonAddress(a, ".drawPacks");
        s.timelock = TimelockController(payable(vm.parseJsonAddress(a, ".timelock")));
        s.engine = DrawEngine(payable(vm.parseJsonAddress(a, ".engine")));
        s.vault = GrailVault(payable(vm.parseJsonAddress(a, ".grailVault")));
        s.controller = DrawController(payable(vm.parseJsonAddress(a, ".controller")));
        s.token = EngineToken(vm.parseJsonAddress(a, ".token"));
        s.hook = EngineHook(payable(vm.parseJsonAddress(a, ".hook")));
        s.liquidity = ProtocolLiquidity(payable(vm.parseJsonAddress(a, ".liquidity")));
        s.farm = GenesisFarm(vm.parseJsonAddress(a, ".farm"));
        s.treasury = Treasury(payable(vm.parseJsonAddress(a, ".treasury")));
        s.buyback = Buyback(payable(vm.parseJsonAddress(a, ".buyback")));
        s.lens = Lens(vm.parseJsonAddress(a, ".lens"));
        s.alloc = c.alloc;
        require(s.controller.cash() + s.controller.backing() >= c.alloc.ordinaryPool - 0.2 ether, "pool not funded");

        vm.startBroadcast();
        // the remaining steps of Deployer._fundAndBuild and _handOver, each transaction under the cap
        for (uint256 i; i < 20 && s.controller.listedCount() < s.controller.boardItems(); ++i) s.controller.build(8);
        if (s.treasury.reserve() == 0) s.treasury.fundReserve{value: c.alloc.treasuryReserve}();
        if (s.controller.maintenance() == 0 && maintenanceFloat != 0) s.controller.fundMaintenance{value: maintenanceFloat}();
        if (address(s.timelock).balance < c.alloc.marketLiquidity) {
            (bool ok,) = address(s.timelock).call{value: c.alloc.marketLiquidity - address(s.timelock).balance}("");
            require(ok, "fund timelock");
        }
        _handOver(s);
        vm.stopBroadcast();

        _postflight(s, c);
        _record(s, env);
    }
}
