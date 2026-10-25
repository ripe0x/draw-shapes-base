// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";

import {Shapes} from "shapes/Shapes.sol";
import {ShapePacks} from "draw-packs/ShapePacks.sol";
import {BaseShapeRenderer} from "../src/presentation/BaseShapeRenderer.sol";
import {BaseShapeCollection} from "../src/presentation/BaseShapeCollection.sol";
import {BasePackRenderer} from "../src/presentation/BasePackRenderer.sol";

import {DrawEngine} from "../src/engine/DrawEngine.sol";
import {DrawController} from "../src/game/DrawController.sol";
import {GrailVault} from "../src/game/GrailVault.sol";
import {EngineToken} from "../src/token/EngineToken.sol";
import {EngineHook} from "../src/token/EngineHook.sol";
import {ProtocolLiquidity} from "../src/token/ProtocolLiquidity.sol";
import {GenesisFarm} from "../src/token/GenesisFarm.sol";
import {Treasury} from "../src/treasury/Treasury.sol";
import {Buyback} from "../src/treasury/Buyback.sol";
import {Lens} from "../src/Lens.sol";
import {LaunchParams} from "./config/LaunchParams.sol";

/// @title Deployer
/// @notice Deploys and wires the whole system in a fixed order, used by `Deploy.s.sol` and by the
///         rehearsal tests so the tested wiring is the deployed wiring. The broadcaster acts as
///         temporary governance during setup and proposes the timelock everywhere; the activation
///         batch (`activationBatch`) accepts governance, opens the market and opens the game in one
///         atomic timelock transaction.
abstract contract Deployer is Script {
    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    struct Config {
        address poolManager;
        address vrfCoordinator;
        uint256 vrfSubscriptionId;
        bytes32 vrfKeyHash;
        address shapes; // zero: deploy Shapes v1 + renderer + collection (the broadcaster is artist/admin)
        address drawPacks; // zero: deploy Draw Packs
        address creator; // Shapes fee recipient (0.001 ETH per minted Shape) and ENGINE operator (0.25 %)
        address tokenWorks; // settlement-fee recipient; must be verified with Token Works
        address dev; // development settlement-fee recipient
        address adminSafe; // timelock proposer and executor
        address guardian; // fast pause authority
        address keeper; // POL deployment keeper
        uint256 timelockDelay;
        address create2Deployer; // address that executes `new X{salt}` (script: CREATE2 factory; test: this)
    }

    struct System {
        address shapes;
        address drawPacks;
        TimelockController timelock;
        DrawEngine engine;
        GrailVault vault;
        DrawController controller;
        EngineToken token;
        EngineHook hook;
        ProtocolLiquidity liquidity;
        GenesisFarm farm;
        Treasury treasury;
        Buyback buyback;
        Lens lens;
    }

    error MissingAddress(string name);

    function _requireConfig(Config memory c) internal pure {
        if (c.poolManager == address(0)) revert MissingAddress("poolManager");
        if (c.vrfCoordinator == address(0)) revert MissingAddress("vrfCoordinator");
        if (c.vrfSubscriptionId == 0) revert MissingAddress("vrfSubscriptionId");
        if (c.creator == address(0)) revert MissingAddress("creator");
        if (c.tokenWorks == address(0)) revert MissingAddress("tokenWorks (verify with Token Works)");
        if (c.dev == address(0)) revert MissingAddress("dev");
        if (c.adminSafe == address(0)) revert MissingAddress("adminSafe");
        if (c.guardian == address(0)) revert MissingAddress("guardian");
    }

    /// @dev Deploys everything with `me` (the broadcaster) as temporary governance.
    function _deploySystem(Config memory c, address me) internal returns (System memory s) {
        _requireConfig(c);
        // ---- governance
        address[] memory admins = new address[](1);
        admins[0] = c.adminSafe;
        s.timelock = new TimelockController(c.timelockDelay, admins, admins, address(0));

        // ---- prize collections: Shapes v1 and Draw Packs token contracts unchanged; Base-blue
        //      presentation contracts (src/presentation, colours only) as their renderers
        if (c.shapes == address(0)) {
            BaseShapeRenderer renderer = new BaseShapeRenderer();
            Shapes shapes = new Shapes{value: 0.01 ether}(LaunchParams.MINT_FEE, c.creator, address(renderer), 0);
            BaseShapeCollection collection = new BaseShapeCollection(renderer, shapes);
            shapes.setCollection(address(collection));
            s.shapes = address(shapes);
        } else {
            s.shapes = c.shapes;
        }
        if (c.drawPacks == address(0)) {
            s.drawPacks = address(
                new ShapePacks(s.shapes, address(new BasePackRenderer(s.shapes)), c.creator, "Draw Packs", "DRAW", 2)
            );
        } else {
            s.drawPacks = c.drawPacks;
        }

        // ---- game
        s.engine = new DrawEngine(
            me,
            c.guardian,
            LaunchParams.vrf(c.vrfCoordinator, c.vrfSubscriptionId, c.vrfKeyHash),
            LaunchParams.vrfFee(),
            LaunchParams.limits(),
            LaunchParams.fees(c.tokenWorks, c.dev)
        );
        s.vault = new GrailVault(
            s.shapes, address(s.engine), me, c.guardian, LaunchParams.grail(), LaunchParams.grailLadder()
        );
        s.controller = new DrawController(
            LaunchParams.controller(s.shapes, s.drawPacks, address(s.engine), me, c.guardian, address(s.vault))
        );
        s.engine.setSupplier(address(s.controller), true);
        s.engine.setSupplier(address(s.vault), true);

        // ---- ENGINE: 10M to protocol liquidity, 25M to the farm. Both addresses are fixed first.
        address farmAddr = vm.computeCreateAddress(me, vm.getNonce(me) + 1);
        // the token is deployed next (nonce n), the farm after it (n + 1)
        {
            address[] memory to = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            (to[0], amounts[0]) = (me, LaunchParams.LIQUIDITY_TOKENS);
            (to[1], amounts[1]) = (farmAddr, LaunchParams.FARM_TOKENS);
            s.token = new EngineToken(to, amounts);
        }
        s.farm = new GenesisFarm(address(s.token), address(s.engine), LaunchParams.FARM_TOKENS);
        require(address(s.farm) == farmAddr, "farm address");

        // ---- market: hook at a flag-encoded CREATE2 address; liquidity launcher; treasury; buyback
        address liquidityAddr = vm.computeCreateAddress(me, vm.getNonce(me));
        bytes memory hookArgs = abi.encode(
            IPoolManager(c.poolManager),
            address(s.token),
            liquidityAddr,
            me,
            c.creator,
            address(0xdead), // replaced by the treasury below
            LaunchParams.HOOK_FEE_BPS,
            LaunchParams.OPERATOR_FEE_BPS
        );
        (address hookAddr, bytes32 salt) = HookMiner.find(c.create2Deployer, HOOK_FLAGS, type(EngineHook).creationCode, hookArgs);
        s.liquidity = new ProtocolLiquidity(IPoolManager(c.poolManager), address(s.token), hookAddr, address(s.timelock));
        require(address(s.liquidity) == liquidityAddr, "liquidity address");
        s.hook = new EngineHook{salt: salt}(
            IPoolManager(c.poolManager),
            address(s.token),
            liquidityAddr,
            me,
            c.creator,
            address(0xdead),
            LaunchParams.HOOK_FEE_BPS,
            LaunchParams.OPERATOR_FEE_BPS
        );
        require(address(s.hook) == hookAddr, "hook address");
        s.treasury = new Treasury(
            address(s.controller), address(s.vault), address(s.liquidity), address(s.timelock), c.keeper, 0.5 ether, 0.3 ether, 9_000
        );
        s.buyback = new Buyback(
            IPoolManager(c.poolManager),
            address(s.token),
            address(s.liquidity),
            address(s.engine),
            14 days, // buybacks start when genesis ends
            address(s.timelock),
            c.guardian,
            0.05 ether,
            1 hours,
            300,
            50,
            0.005 ether, // minimum buy
            0.00005 ether // bounty cap
        );
        s.hook.setRecipients(c.creator, address(s.treasury));
        s.hook.setFeeExempt(address(s.liquidity), true);
        s.hook.setFeeExempt(address(s.buyback), true);
        s.hook.setFeeExempt(address(s.treasury), true);
        s.token.transfer(address(s.liquidity), LaunchParams.LIQUIDITY_TOKENS);

        s.lens = new Lens(
            Lens.Addresses({
                engine: address(s.engine),
                controller: address(s.controller),
                vault: address(s.vault),
                farm: address(s.farm),
                hook: address(s.hook),
                liquidity: address(s.liquidity),
                treasury: address(s.treasury),
                buyback: address(s.buyback),
                token: address(s.token),
                poolManager: c.poolManager
            })
        );
    }

    /// @dev Funds the opening allocations held by contracts and builds the board (acquisitions stay
    ///      closed until activation): 2.2 ETH ordinary pool, 0.5 ETH treasury reserve, the
    ///      maintenance float, and the 2 ETH market liquidity held by the timelock for `launch`.
    function _fundAndBuild(System memory s, uint256 maintenanceFloat) internal {
        s.controller.fundPool{value: LaunchParams.ORDINARY_POOL}();
        for (uint256 i; i < 5 && s.controller.listedCount() < s.controller.boardItems(); ++i) {
            s.controller.build(40);
        }
        s.treasury.fundReserve{value: LaunchParams.TREASURY_RESERVE}();
        if (maintenanceFloat != 0) s.controller.fundMaintenance{value: maintenanceFloat}();
        (bool ok,) = address(s.timelock).call{value: LaunchParams.MARKET_LIQUIDITY}("");
        require(ok, "fund timelock");
    }

    /// @dev Proposes the timelock as governance of every contract the broadcaster configured.
    function _handOver(System memory s) internal {
        address t = address(s.timelock);
        s.engine.proposeGovernance(t);
        s.vault.proposeGovernance(t);
        s.controller.proposeGovernance(t);
        s.hook.proposeGovernance(t);
    }

    /// @notice The single atomic activation batch the timelock executes: accept governance, wire the
    ///         liquidity launcher to the treasury, open the market at the reference price with 2 ETH
    ///         and 10M ENGINE, and open the game (which starts genesis). Any failure reverts it all.
    function activationBatch(System memory s)
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory datas)
    {
        targets = new address[](7);
        values = new uint256[](7);
        datas = new bytes[](7);
        (targets[0], datas[0]) = (address(s.engine), abi.encodeCall(DrawEngine.acceptGovernance, ()));
        (targets[1], datas[1]) = (address(s.vault), abi.encodeCall(GrailVault.acceptGovernance, ()));
        (targets[2], datas[2]) = (address(s.controller), abi.encodeCall(DrawController.acceptGovernance, ()));
        (targets[3], datas[3]) = (address(s.hook), abi.encodeCall(EngineHook.acceptGovernance, ()));
        (targets[4], datas[4]) = (address(s.liquidity), abi.encodeCall(ProtocolLiquidity.setTreasury, (address(s.treasury))));
        (targets[5], values[5], datas[5]) = (
            address(s.liquidity),
            LaunchParams.MARKET_LIQUIDITY,
            abi.encodeCall(ProtocolLiquidity.launch, (referenceSqrtPrice()))
        );
        (targets[6], datas[6]) = (address(s.engine), abi.encodeCall(DrawEngine.activate, ()));
    }

    /// @notice sqrtPriceX96 of 10M ENGINE per 2 ETH (2e-7 ETH per ENGINE).
    function referenceSqrtPrice() public pure returns (uint160) {
        return uint160(FP.sqrt(FP.fullMulDiv(LaunchParams.LIQUIDITY_TOKENS, 1 << 192, LaunchParams.MARKET_LIQUIDITY)));
    }
}
