// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {GameFixture} from "../utils/GameFixture.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {DrawController} from "../../src/game/DrawController.sol";
import {GrailVault} from "../../src/game/GrailVault.sol";
import {Lens} from "../../src/Lens.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";

/// @notice Follow-up behaviour: purchaser-funded VRF, purchase on behalf of another wallet,
///         settlement receipts and replay safety, GRAIL replacement-first, the maintenance floor
///         and the in-callback settlement rate.
contract FollowupTest is GameFixture {
    Lens internal lens;

    function setUp() public override {
        super.setUp();
        lens = new Lens(
            Lens.Addresses({
                engine: address(engine),
                controller: address(controller),
                vault: address(vault),
                farm: address(0),
                hook: address(0),
                liquidity: address(0),
                treasury: address(0),
                buyback: address(0),
                token: address(0),
                poolManager: address(0)
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                         PURCHASER-FUNDED VRF
    //////////////////////////////////////////////////////////////*/

    function test_vrfFee_quotedSeparately_sharedAcrossBatch_fundsSubscription() public {
        _openAndActivate();
        vm.fee(0.01 gwei);
        DrawEngine.VrfFeeConfig memory c = LaunchParams.vrfFee();
        // formula: gas = (overhead + callback gas limit) x max(basefee, floor);
        // forwarded = gas x (1 + premium + buffer) + flat; margin = gas x marginBps (FWA service margin)
        uint256 gas1 = (uint256(c.overheadGas) + engine.callbackGasLimitFor(1)) * 0.01 gwei;
        uint256 expect1 = gas1 * (10_000 + c.premiumBps + c.bufferBps) / 10_000 + c.flatWei;
        (uint256 fwd1, uint256 margin1) = engine.vrfFeeParts(1);
        assertEq(fwd1, expect1, "forwarded VRF fee formula");
        assertEq(margin1, gas1 * c.marginBps / 10_000, "margin formula");
        assertEq(c.marginBps, 3_000, "launch margin: FWA V2's 30 %");
        assertEq(engine.vrfFeeFor(1), expect1 + margin1, "VRF fee = forwarded + margin");
        // one request per batch: per-pull VRF cost falls with batch size
        uint256 f1 = engine.vrfFeeFor(1);
        uint256 f10 = engine.vrfFeeFor(10);
        uint256 f20 = engine.vrfFeeFor(20);
        assertLt(f10 / 10, f1, "10-pull batch shares overhead");
        assertLt(f20 / 20, f10 / 10, "20-pull batch shares more");
        console2.log("VRF fee 1 / 10 / 20 pulls at 0.01 gwei", f1, f10, f20);
        // the basefee floor applies when the chain is quieter than the floor
        vm.fee(0);
        uint256 gasFloor = (uint256(c.overheadGas) + engine.callbackGasLimitFor(1)) * c.minGasPrice;
        assertEq(
            engine.vrfFeeFor(1),
            gasFloor * (10_000 + c.premiumBps + c.bufferBps) / 10_000 + c.flatWei + gasFloor * c.marginBps / 10_000
        );
        vm.fee(0.01 gwei);

        (, uint96 subBefore,,,) = vrf.getSubscription(subId);
        (uint256 fee, uint256 sfee, uint256 vf, uint256 total) = engine.quoteAcquisitionPrice(10);
        assertEq(vf, f10);
        assertEq(total, 10 * (fee + sfee) + vf, "VRF fee is separate from fee and settlement fee");
        (uint256 fwd10, uint256 margin10) = engine.vrfFeeParts(10);
        assertEq(fwd10 + margin10, vf);
        uint256 devCreditBefore = engine.feeCreditOf(engine.devRecipient());
        _pull(alice, 10);
        (, uint96 subAfter,,,) = vrf.getSubscription(subId);
        assertEq(subAfter - subBefore, fwd10, "forwarded VRF fee funds the subscription at purchase");
        assertEq(engine.vrfFeesCollected(), fwd10);
        assertEq(engine.feeCreditOf(engine.devRecipient()) - devCreditBefore, margin10, "margin credited to development");
        assertEq(address(engine).balance, engine.liabilities(), "VRF fee never enters backing or escrow");
        Lens.VrfView memory v = lens.vrf();
        assertEq(v.feesCollected, fwd10);
        assertEq(v.subscriptionBalance, subAfter);
    }

    /// @dev Collected >= billed at several basefees and batch sizes, with the oracle's gas price
    ///      up to 20 % above the basefee seen at purchase (Chainlink bills the fulfilment tx price).
    function test_vrfFee_coversOracleBill_acrossBasefeesAndBatchSizes() public {
        _openAndActivate();
        uint256[5] memory fees = [uint256(0.001 gwei), 0.005 gwei, 0.01 gwei, 0.05 gwei, 0.2 gwei];
        uint256[4] memory sizes = [uint256(1), 5, 10, 20];
        uint256 n;
        for (uint256 i; i < fees.length; ++i) {
            for (uint256 j; j < sizes.length; ++j) {
                vm.fee(fees[i]);
                uint256 collectedBefore = engine.vrfFeesCollected();
                uint256 billedBefore = vrf.totalBilled();
                (, uint256 vrfId) = _pull(i % 2 == 0 ? alice : bob, sizes[j]);
                uint256 oracleGasPrice = fees[i] < 0.005 gwei ? 0.005 gwei : fees[i];
                vrf.setBilling(oracleGasPrice * 12 / 10, 342_500, 0.0000005 ether);
                _fulfill(vrfId, uint256(keccak256(abi.encode(i, j))));
                _settleAll();
                uint256 collected = engine.vrfFeesCollected() - collectedBefore;
                uint256 billed = vrf.totalBilled() - billedBefore;
                assertGe(collected, billed, "collected >= billed");
                console2.log("basefee (wei) / batch", fees[i], sizes[j]);
                console2.log("  collected / billed (wei)", collected, billed);
                ++n;
            }
        }
        assertGe(engine.vrfFeesCollected(), vrf.totalBilled());
        (, uint96 bal,,,) = vrf.getSubscription(subId);
        // the subscription only grows: seed + collected - billed
        assertEq(bal, 1 ether + engine.vrfFeesCollected() - vrf.totalBilled(), "subscription reconciles");
    }

    function test_vrfFee_notRefundedOnSlippageOrExpiry_otherAmountsAre() public {
        _openAndActivate();
        (uint256 fee, uint256 sfee, uint256 vf, uint256 total) = engine.quoteAcquisitionPrice(3);
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(alice);
        engine.acquireBatch{value: total}(alice, referrer, 3, 0, 0, 1_000, any, block.timestamp);
        vm.roll(vm.getBlockNumber() + engine.selectionTimeoutBlocks() + 1);
        engine.processAcquisitions(10);
        assertEq(engine.acquisitionRefundCredit(alice), 3 * (fee + sfee), "fee + settlement fee refunded");
        (uint256 fwd, uint256 margin) = engine.vrfFeeParts(3);
        assertEq(fwd + margin, vf);
        assertEq(engine.vrfFeesCollected(), fwd, "VRF fee kept: it paid for the oracle request");
        assertEq(address(engine).balance, engine.liabilities(), "engine holds exactly its liabilities");
    }

    function test_vrfMargin_capKeepsSubscriptionShareFirst_andIsBounded() public {
        _openAndActivate();
        DrawEngine.VrfFeeConfig memory c = LaunchParams.vrfFee();
        uint256 max = engine.MAX_VRF_FEE_PER_BATCH();
        // high basefee: forwarded share alone exceeds the cap, so the margin is zero
        vm.fee(5 gwei);
        (uint256 fwd, uint256 margin) = engine.vrfFeeParts(20);
        assertEq(fwd, max);
        assertEq(margin, 0, "the subscription is never shorted for the margin");
        // in between: the margin fills only the room left under the cap
        vm.fee(0.35 gwei);
        (fwd, margin) = engine.vrfFeeParts(20);
        assertLt(fwd, max);
        assertEq(fwd + margin, max, "margin trimmed to the room under the cap");
        assertLt(margin, (fwd - c.flatWei) * c.marginBps / (10_000 + c.premiumBps + c.bufferBps), "margin trimmed");
        // governance bound and a zero margin
        c.marginBps = uint16(engine.MAX_VRF_MARGIN_BPS() + 1);
        vm.expectRevert(DrawEngine.InvalidConfig.selector);
        engine.setVrfFeeConfig(c);
        c.marginBps = 0;
        engine.setVrfFeeConfig(c);
        (, margin) = engine.vrfFeeParts(1);
        assertEq(margin, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         PURCHASE ON BEHALF
    //////////////////////////////////////////////////////////////*/

    function test_purchaseOnBehalf_payerOnlyGetsExcess_beneficiaryGetsEverythingElse() public {
        _openAndActivate();
        address payer = bob;
        address beneficiary = makeAddr("beneficiary");
        (,,, uint256 total) = engine.quoteAcquisitionPrice(2);
        uint256 vrfId = vrf.nextRequestId();
        uint256 any = engine.ANY_INVENTORY_VERSION();
        uint256 payerBefore = payer.balance;
        vm.prank(payer);
        uint256[] memory ids =
            engine.acquireBatch{value: total + 0.01 ether}(beneficiary, referrer, 2, 0, 0, 1_000, any, block.timestamp);
        assertEq(payerBefore - payer.balance, total, "payer gets the overpayment back");
        _fulfill(vrfId, 99);
        _settleAll();
        for (uint256 i; i < ids.length; ++i) {
            Lens.Receipt memory r = lens.receipt(ids[i]);
            assertEq(r.purchaser, beneficiary);
            assertEq(r.referrer, referrer);
            assertEq(IOwnerOf(r.collection).ownerOf(r.tokenId), beneficiary, "prize to the beneficiary");
        }
        (uint64 units,) = engine.userDay(0, beneficiary);
        assertEq(units, 2, "genesis units to the beneficiary");
        (uint64 payerUnits,) = engine.userDay(0, payer);
        assertEq(payerUnits, 0, "payer earns no genesis units");
        assertGt(engine.feeCreditOf(referrer), 0, "referrer is separate from payer and beneficiary");
    }

    function test_purchaseOnBehalf_refundGoesToBeneficiary() public {
        _openAndActivate();
        address beneficiary = makeAddr("beneficiary");
        (uint256 fee, uint256 sfee,, uint256 total) = engine.quoteAcquisitionPrice(1);
        uint256 any = engine.ANY_INVENTORY_VERSION();
        vm.prank(bob);
        engine.acquireBatch{value: total}(beneficiary, address(0), 1, 0, 0, 1_000, any, block.timestamp);
        vm.roll(vm.getBlockNumber() + engine.selectionTimeoutBlocks() + 1);
        engine.processAcquisitions(1);
        assertEq(engine.acquisitionRefundCredit(beneficiary), fee + sfee);
        assertEq(engine.acquisitionRefundCredit(bob), 0, "payer has no claim on the refund");
    }

    /*//////////////////////////////////////////////////////////////
                    RECEIPTS AND REPLAY-SAFE SYNC
    //////////////////////////////////////////////////////////////*/

    function test_receipts_durable_and_syncIsIdempotent() public {
        _openAndActivate();
        (uint256[] memory ids, uint256 vrfId) = _pullRef(alice, referrer, 5);
        Lens.Receipt memory pending = lens.receipt(ids[0]);
        assertFalse(pending.final_);
        assertFalse(pending.bookedByController);
        assertEq(pending.vrfRequestId, vrfId);
        _fulfill(vrfId, 1234);
        _settleAll();

        // snapshot every counter a replay could double
        Snap memory a = _snap();

        // replay every permissionless sync entry point
        for (uint256 k; k < 3; ++k) {
            assertEq(engine.processAcquisitions(20), 0, "nothing to reprocess");
            controller.settle(50);
            vault.step();
        }
        vm.expectRevert(bytes("bad request"));
        vrf.fulfill(vrfId, 5678); // the coordinator cannot deliver a second word
        uint256[] memory w = new uint256[](1);
        w[0] = 5678;
        vm.prank(address(vrf));
        engine.rawFulfillRandomWords(vrfId, w); // and a forced second callback is ignored

        Snap memory b = _snap();
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), "replay changed no credit, booking, GRAIL, refund or unit");

        for (uint256 i; i < ids.length; ++i) {
            Lens.Receipt memory r = lens.receipt(ids[i]);
            assertTrue(r.final_, "final");
            assertTrue(r.bookedByController, "booked exactly once");
            assertEq(r.randomWord, uint256(keccak256(abi.encode(uint256(1234), i))), "word derived from the batch word");
            assertEq(r.bonusWeight, engine.bonusWeightOf(r.randomWord));
            assertEq(r.acquisitionFee + r.settlementFee, r.acquisitionFee + r.acquisitionFee / 100);
            assertEq(r.depositor, address(controller));
        }
    }

    /*//////////////////////////////////////////////////////////////
                   GRAIL REPLACEMENT-FIRST AND RESERVES
    //////////////////////////////////////////////////////////////*/

    struct Snap {
        uint256 refCredit;
        uint256 twCredit;
        uint256 devCredit;
        uint256 booked;
        uint256 feed;
        uint256 queued;
        uint256 listed;
        uint256 vaultFund;
        uint256 refund;
        uint64 next;
        uint64 units;
        uint64 bonus;
    }

    function _snap() internal view returns (Snap memory x) {
        x.refCredit = engine.feeCreditOf(referrer);
        x.twCredit = engine.feeCreditOf(tokenWorks);
        x.devCredit = engine.feeCreditOf(dev);
        x.booked = controller.totalProceedsBooked();
        x.feed = controller.totalFeedSent();
        x.queued = controller.queueLength();
        x.listed = controller.listedCount();
        x.vaultFund = vault.fund();
        x.refund = engine.acquisitionRefundCredit(alice);
        x.next = controller.nextSequenceToBook();
        (x.units, x.bonus) = engine.userDay(0, alice);
    }

    /// @dev Board holding only GRAILs so every pull captures one.
    function test_grailVault_replacementFirstAfterAllAreWon() public {
        uint256 mf = shapes.mintFee();
        vault.fundGrail{value: 0.5 ether + mf}();
        vault.step();
        // the second GRAIL is funded within three days: the ladder steps up
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vault.fundGrail{value: 0.5 ether + mf}();
        vault.step();
        assertEq(vault.liveGrails(), 2);
        assertEq(vault.level(), 1);
        assertEq(vault.nextTarget(), 1 ether, "with GRAILs live the ladder rung applies");
        engine.activate();
        for (uint256 k; k < 2; ++k) {
            (, uint256 vrfId) = _pull(alice, 1);
            _fulfill(vrfId, k + 1);
            engine.processAcquisitions(1);
        }
        // before syncing: both won, so the next target is the smallest rung, not the 1 ETH step
        (,,,,,,, DrawEngine.ListingStatus s1) = engine.listings(1);
        (,,,,,,, DrawEngine.ListingStatus s2) = engine.listings(2);
        assertEq(uint256(s1), uint256(DrawEngine.ListingStatus.Settled));
        assertEq(uint256(s2), uint256(DrawEngine.ListingStatus.Settled));
        uint256 fundBefore = vault.fund();
        vault.step();
        // the 2 x 0.4 ETH capture proceeds immediately fund a 0.5 ETH replacement
        GrailVault.GrailItem[] memory live = vault.items();
        assertEq(live.length, 1, "replacement minted at once");
        assertEq(live[0].backing, 0.5 ether, "replacement first: smallest rung while none is live");
        assertEq(vault.fund(), fundBefore + 0.8 ether - 0.5 ether - mf);
        assertEq(vault.level(), 1, "a replacement does not move the ladder");
        assertEq(vault.nextTarget(), 1 ether, "next addition is the ladder rung");
    }

    function test_releaseSurplus_topsUpMaintenanceFloorFirst() public {
        _openAndActivate();
        controller.setSurplusSink(makeAddr("sink"), uint64(block.timestamp));
        controller.fundPool{value: 0.3 ether}();
        uint256 surplus = controller.releasableSurplus();
        uint256 maintBefore = controller.maintenance();
        uint256 floor = controller.maintenanceFloor();
        assertEq(floor, 0.05 ether);
        assertLt(maintBefore, floor);
        uint256 released = controller.releaseSurplus();
        assertEq(controller.maintenance(), floor, "operating reserve restored before release");
        assertEq(released, surplus - (floor - maintBefore), "only the rest leaves");
        assertEq(controller.totalSurplusReleased(), released, "the transfer to maintenance is not released surplus");
    }

    /*//////////////////////////////////////////////////////////////
                    AUTO-SETTLE IN THE VRF CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @dev How much of a batch the callback settles by itself at the launch gas schedule, and the
    ///      callback gas used, so keeper load can be read off directly.
    function test_measure_callbackSettlesBatches() public {
        _openAndActivate();
        uint256[5] memory sizes = [uint256(1), 3, 5, 10, 20];
        for (uint256 j; j < sizes.length; ++j) {
            uint64 headBefore = engine.nextSequenceToProcess();
            (, uint256 vrfId) = _pull(alice, sizes[j]);
            vm.roll(vm.getBlockNumber() + 3);
            uint256 g = gasleft();
            vrf.fulfill(vrfId, uint256(keccak256(abi.encode("cb", j))));
            uint256 used = g - gasleft();
            uint256 settled = engine.nextSequenceToProcess() - headBefore;
            console2.log("batch / settled in callback / callback gas", sizes[j], settled, used);
            if (sizes[j] <= 3) assertEq(settled, sizes[j], "small batches settle inside the callback");
            assertGe(settled, 1, "the callback always settles the head when gas allows");
            _settleAll();
        }
    }
}

interface IOwnerOf {
    function ownerOf(uint256) external view returns (address);
}
