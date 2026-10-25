// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {PricingLib} from "../../src/game/PricingLib.sol";

/// @title LaunchParams
/// @notice The launch economic configuration, shared by the deploy script and every test so the
///         tested numbers are the deployed numbers. Addresses are supplied by the caller.
library LaunchParams {
    uint256 internal constant MINT_FEE = 0.001 ether;

    // Opening capital (docs/ECONOMICS.md section 2)
    uint256 internal constant ORDINARY_POOL = 2.2 ether;
    uint256 internal constant MARKET_LIQUIDITY = 2 ether;
    uint256 internal constant OPERATIONS = 0.3 ether;
    uint256 internal constant TREASURY_RESERVE = 0.5 ether;

    // ENGINE supply (docs/MARKET.md): 10M opening liquidity + 25M genesis farm, nothing else.
    uint256 internal constant LIQUIDITY_TOKENS = 10_000_000 ether;
    uint256 internal constant FARM_TOKENS = 25_000_000 ether;
    uint16 internal constant HOOK_FEE_BPS = 200;
    uint16 internal constant OPERATOR_FEE_BPS = 25;

    /// @notice Purchaser VRF charge (docs/FOLLOWUP.md section 2): 400k gas of verification and
    ///         post-callback overhead, the callback at its requested limit, at least 0.005 gwei, Chainlink's
    ///         60 % native premium on Base, a 25 % fluctuation buffer and 0.000002 ETH for the L1 data fee.
    function vrfFee() internal pure returns (DrawEngine.VrfFeeConfig memory) {
        return DrawEngine.VrfFeeConfig({
            overheadGas: 400_000,
            minGasPrice: 0.005 gwei,
            premiumBps: 6_000,
            bufferBps: 2_500,
            flatWei: 0.000002 ether
        });
    }

    function limits() internal pure returns (DrawEngine.Limits memory) {
        return DrawEngine.Limits({
            maxAcquisitionsPerTx: 20,
            maxUnsettledAcquisitions: 250,
            maxActivationsPerAcquisition: 6,
            selectionSlippageBps: 1_000,
            inventoryChangeCooldown: 0
        });
    }

    function fees(address tokenWorks, address dev) internal pure returns (DrawEngine.Fees memory) {
        return DrawEngine.Fees({
            settlementFeeBps: 100,
            referrerBps: 5_000,
            tokenWorksBps: 2_500,
            tokenWorksRecipient: tokenWorks,
            devRecipient: dev
        });
    }

    function vrf(address coordinator, uint256 subId, bytes32 keyHash) internal pure returns (DrawEngine.VrfConfig memory) {
        return DrawEngine.VrfConfig({
            coordinator: coordinator,
            subscriptionId: subId,
            keyHash: keyHash,
            requestConfirmations: 3,
            callbackGasBase: 100_000,
            callbackGasPerAcquisition: 650_000,
            selectionTimeoutBlocks: 1_800
        });
    }

    /// @notice The reference 100-listing board: 62 x 0.01, 26 x 0.02 (two 0.01), 7 x 0.03 (three
    ///         0.01), 4 x 0.05 and 1 x 0.1, as mix shares of a 100-item board.
    function mix() internal pure returns (PricingLib.MixRow[] memory rows) {
        rows = new PricingLib.MixRow[](5);
        rows[0] = _row1(0, 6_200);
        uint8[] memory two = new uint8[](2);
        rows[1] = PricingLib.MixRow(two, 2_600);
        uint8[] memory three = new uint8[](3);
        rows[2] = PricingLib.MixRow(three, 700);
        rows[3] = _row1(1, 400);
        rows[4] = _row1(2, 100);
    }

    function _row1(uint8 rung, uint16 share) private pure returns (PricingLib.MixRow memory) {
        uint8[] memory r = new uint8[](1);
        r[0] = rung;
        return PricingLib.MixRow(r, share);
    }

    function controller(
        address shapes,
        address packs,
        address engine,
        address governance,
        address guardian,
        address grailVault
    ) internal pure returns (DrawController.Params memory p) {
        p.shapes = shapes;
        p.drawPacks = packs;
        p.engine = engine;
        p.governance = governance;
        p.guardian = guardian;
        p.feeSplit = DrawController.FeeSplit({premiumBps: 400, maintenanceBps: 50, feedBps: 200});
        p.mix = mix();
        p.boardItems = 100;
        p.cashFloor = 0;
        p.surpriseBps = 200;
        p.restoreK = 8;
        p.bandBps = 3_000;
        p.tipWei = 0.00001 ether;
        p.capitalTarget = ORDINARY_POOL;
        p.maintenanceFloor = 0.05 ether;
        p.grailVault = grailVault;
    }

    function grail() internal pure returns (GrailVault.GrailConfig memory) {
        return GrailVault.GrailConfig({
            listBps: 8_000,
            floorBps: 5_000,
            probCapBps: 500,
            stepUpSeconds: 3 days,
            stepDownSeconds: 14 days,
            decayWeiPerPull: 0.00002 ether
        });
    }

    /// @notice GRAIL ladder: 0.5, 1 and 5 ETH Shapes.
    function grailLadder() internal pure returns (uint8[] memory l) {
        l = new uint8[](3);
        l[0] = 3;
        l[1] = 4;
        l[2] = 5;
    }
}
