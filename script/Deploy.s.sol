// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Deployer} from "./Deployer.sol";

/// @title Deploy
/// @notice `forge script script/Deploy.s.sol --rpc-url <rpc> --broadcast --sig "run(string)" <env>`
///         with `script/config/<env>.json`. Deploys and wires everything, funds the opening
///         allocations (2.2 ETH pool, 0.5 ETH reserve, maintenance float, 2 ETH market liquidity to the
///         timelock), builds the board with acquisitions closed, proposes the timelock as governance,
///         and writes `deployments/<chainId>.json` plus the activation batch for the Safe. Nothing
///         opens to the public: activation is a separate, delayed timelock batch (docs/RUNBOOK.md).
/// @dev Refuses to run on Base mainnet unless `DRAW_SHAPES_MAINNET_CONFIRM` equals
///      "I have the audit, legal review and verified addresses". It never activates.
contract Deploy is Deployer {

    function run(string calldata env) external {
        string memory json = vm.readFile(string.concat("script/config/", env, ".json"));
        Config memory c;
        c.poolManager = vm.parseJsonAddress(json, ".poolManager");
        c.vrfCoordinator = vm.parseJsonAddress(json, ".vrfCoordinator");
        c.vrfKeyHash = vm.parseJsonBytes32(json, ".vrfKeyHash");
        c.vrfSubscriptionId = vm.parseJsonUint(json, ".vrfSubscriptionId");
        c.shapes = vm.parseJsonAddress(json, ".shapes");
        c.drawPacks = vm.parseJsonAddress(json, ".drawPacks");
        c.creator = vm.parseJsonAddress(json, ".creator");
        c.tokenWorks = vm.parseJsonAddress(json, ".tokenWorks");
        c.dev = vm.parseJsonAddress(json, ".dev");
        c.adminSafe = vm.parseJsonAddress(json, ".adminSafe");
        c.guardian = vm.parseJsonAddress(json, ".guardian");
        c.keeper = vm.parseJsonAddress(json, ".keeper");
        c.timelockDelay = vm.parseJsonUint(json, ".timelockDelay");
        c.create2Deployer = CREATE2_FACTORY;
        uint256 maintenanceFloat = vm.parseJsonUint(json, ".maintenanceFloat");
        _requireConfig(c);
        if (block.chainid == 8453) {
            require(
                keccak256(bytes(vm.envOr("DRAW_SHAPES_MAINNET_CONFIRM", string("")))) ==
                    keccak256("I have the audit, legal review and verified addresses"),
                "mainnet deployment not authorised"
            );
        }
        require(c.poolManager.code.length != 0 && c.vrfCoordinator.code.length != 0, "dependency missing");

        vm.startBroadcast();
        (, address me,) = vm.readCallers();
        System memory s = _deploySystem(c, me);
        _fundAndBuild(s, maintenanceFloat);
        _handOver(s);
        vm.stopBroadcast();

        _postflight(s, c);
        _record(s, env);
    }

    function _postflight(System memory s, Config memory c) internal view {
        require(s.engine.isSupplier(address(s.controller)) && s.engine.isSupplier(address(s.vault)), "suppliers");
        require(!s.engine.activated() && !s.liquidity.launched(), "must not be live");
        require(s.engine.pendingGovernance() == address(s.timelock), "engine handover");
        require(s.controller.listedCount() == s.controller.boardItems(), "board built");
        require(s.controller.backing() == 1.65 ether, "reference backing");
        require(s.token.totalSupply() == 35_000_000 ether, "supply");
        require(s.token.balanceOf(address(s.farm)) == 25_000_000 ether, "farm funded");
        require(s.token.balanceOf(address(s.liquidity)) == 10_000_000 ether, "liquidity tokens");
        require(s.hook.treasury() == address(s.treasury) && s.hook.operator() == c.creator, "hook recipients");
        require(s.engine.tokenWorksRecipient() == c.tokenWorks && s.engine.devRecipient() == c.dev, "fee recipients");
        require(address(s.timelock).balance >= 2 ether, "market liquidity escrowed");
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(1);
        console2.log("quoted payment per pull (wei)", total);
    }

    function _record(System memory s, string memory env) internal {
        string memory o = "d";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeString(o, "env", env);
        vm.serializeAddress(o, "shapes", s.shapes);
        vm.serializeAddress(o, "drawPacks", s.drawPacks);
        vm.serializeAddress(o, "timelock", address(s.timelock));
        vm.serializeAddress(o, "engine", address(s.engine));
        vm.serializeAddress(o, "controller", address(s.controller));
        vm.serializeAddress(o, "grailVault", address(s.vault));
        vm.serializeAddress(o, "token", address(s.token));
        vm.serializeAddress(o, "hook", address(s.hook));
        vm.serializeAddress(o, "liquidity", address(s.liquidity));
        vm.serializeAddress(o, "farm", address(s.farm));
        vm.serializeAddress(o, "treasury", address(s.treasury));
        vm.serializeAddress(o, "buyback", address(s.buyback));
        string memory out = vm.serializeAddress(o, "lens", address(s.lens));
        vm.writeJson(out, string.concat("deployments/", vm.toString(block.chainid), ".json"));

        (address[] memory t, uint256[] memory v, bytes[] memory d) = activationBatch(s);
        string memory b = "b";
        vm.serializeAddress(b, "timelock", address(s.timelock));
        vm.serializeAddress(b, "targets", t);
        vm.serializeUint(b, "values", v);
        string memory batch = vm.serializeBytes(b, "datas", d);
        vm.writeJson(batch, string.concat("deployments/", vm.toString(block.chainid), "-activation.json"));
    }
}
