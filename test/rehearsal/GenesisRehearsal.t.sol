// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Deployer} from "../../script/Deployer.sol";
import {DrawEngine} from "../../src/engine/DrawEngine.sol";
import {GenesisFarm} from "../../src/token/GenesisFarm.sol";
import {Lens} from "../../src/Lens.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";
import {MockVRFCoordinator} from "../utils/MockVRFCoordinator.sol";
import {Swapper} from "../utils/Swapper.sol";

/// @notice Complete genesis rehearsal with the production deployment code: deploy, fund, build,
///         atomic activation through the timelock, 14 days of farming, trading and GRAIL funding,
///         farm finalisation, then post-genesis surplus release and buyback-and-burn. Everything
///         reconciles at the end.
contract GenesisRehearsalTest is Test, Deployer {
    address admin = makeAddr("adminSafe");
    address guardianAddr = makeAddr("guardian");
    address creatorAddr = makeAddr("creator");
    address tw = makeAddr("tokenWorks");
    address devAddr = makeAddr("dev");
    address keeperAddr = makeAddr("keeper");
    address site = makeAddr("referringSite");
    address[3] farmers;
    address buyer = makeAddr("buyer");

    MockVRFCoordinator vrf;
    IPoolManager manager;
    System s;
    Swapper swapper;
    PoolKey key;
    uint256 paidIn;
    uint256[] openVrf;

    uint256 constant PULLS_PER_DAY = 200;
    uint256 constant BUY_PER_DAY = 0.7 ether;

    function setUp() public {
        farmers = [makeAddr("f0"), makeAddr("f1"), makeAddr("f2")];
        for (uint256 i; i < 3; ++i) vm.deal(farmers[i], 1_000 ether);
        vm.deal(buyer, 1_000 ether);
        vm.deal(address(this), 100 ether);
        vrf = new MockVRFCoordinator();
        uint256 sub = vrf.createSubscription();
        manager = IPoolManager(deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(admin)));
        Config memory c = Config({
            poolManager: address(manager),
            vrfCoordinator: address(vrf),
            vrfSubscriptionId: sub,
            vrfKeyHash: keccak256("lane"),
            shapes: address(0),
            drawPacks: address(0),
            creator: creatorAddr,
            tokenWorks: tw,
            dev: devAddr,
            adminSafe: admin,
            guardian: guardianAddr,
            keeper: keeperAddr,
            timelockDelay: 2 days,
            create2Deployer: address(this),
                alloc: launchAllocation()
        });
        s = _deploySystem(c, address(this));
        vrf.fundSubscriptionWithNative{value: 0.02 ether}(sub);
        _fundAndBuild(s, 0.05 ether);
        _handOver(s);
        swapper = new Swapper(manager);
        key = s.liquidity.poolKey();
    }

    function test_deployFailsWithoutVerifiedTokenWorks() public {
        Config memory c;
        c.poolManager = address(manager);
        c.vrfCoordinator = address(vrf);
        c.vrfSubscriptionId = 1;
        c.creator = creatorAddr;
        vm.expectRevert(abi.encodeWithSelector(MissingAddress.selector, "tokenWorks (verify with Token Works)"));
        this.requireConfigExternal(c);
    }

    function requireConfigExternal(Config memory c) external pure {
        _requireConfig(c);
    }

    function _activate() internal {
        (address[] memory t, uint256[] memory v, bytes[] memory d) = activationBatch(s);
        // nothing is live before activation
        assertFalse(s.engine.activated());
        assertFalse(s.liquidity.launched());
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), bytes32("activate"), 2 days);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.prank(admin);
        s.timelock.executeBatch(t, v, d, bytes32(0), bytes32("activate"));
    }

    function test_activationIsAtomic() public {
        (address[] memory t, uint256[] memory v, bytes[] memory d) = activationBatch(s);
        // break one step: the engine call reverts, so the market must not open either
        d[6] = abi.encodeCall(DrawEngine.setPaused, (true));
        t[6] = address(s.engine);
        d[5] = abi.encodeWithSignature("launch(uint160)", uint160(1)); // invalid price reverts
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), bytes32("bad"), 2 days);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.prank(admin);
        vm.expectRevert();
        s.timelock.executeBatch(t, v, d, bytes32(0), bytes32("bad"));
        assertFalse(s.liquidity.launched(), "market not open");
        assertFalse(s.engine.activated(), "game not open");
        assertEq(s.engine.governance(), address(this), "governance not handed over");
    }

    function _pullBatch(address who, address ref, uint256 n) internal {
        (,,, uint256 total) = s.engine.quoteAcquisitionPrice(n);
        uint256 vrfId = vrf.nextRequestId();
        uint256 any = s.engine.ANY_INVENTORY_VERSION();
        vm.prank(who);
        s.engine.acquireBatch{value: total}(who, ref, n, 0, 0, 1_000, any, block.timestamp);
        paidIn += total;
        openVrf.push(vrfId);
    }

    function _fulfillAll(uint256 salt) internal {
        vm.roll(vm.getBlockNumber() + 3);
        for (uint256 i; i < openVrf.length; ++i) {
            vrf.fulfill(openVrf[i], uint256(keccak256(abi.encode(salt, i))));
        }
        delete openVrf;
    }

    function _settle() internal {
        for (uint256 i; i < 30; ++i) {
            s.controller.settle(50);
            s.vault.step();
            if (s.controller.nextSequenceToBook() > s.engine.lastIssuedSequence() && s.controller.queueLength() == 0) break;
        }
    }

    function _claimAndSell(uint256 epoch) internal {
        for (uint256 i; i < 3; ++i) {
            uint256 r = s.farm.rewardOf(epoch, farmers[i]);
            if (r == 0) continue;
            uint256[] memory e = new uint256[](1);
            e[0] = epoch;
            vm.startPrank(farmers[i]);
            s.farm.claim(e);
            s.token.approve(address(swapper), r);
            swapper.sell(key, r);
            vm.stopPrank();
        }
    }

    function test_fullGenesisRehearsal() public {
        _activate();
        uint256 origin = s.engine.ledgerOrigin();
        assertTrue(s.engine.activated() && s.liquidity.launched(), "game and market opened together");
        assertEq(origin, vm.getBlockTimestamp(), "genesis starts at activation");
        assertEq(s.engine.governance(), address(s.timelock));
        Lens.Quote memory q = s.lens.quote(10);
        assertTrue(q.purchasable);
        console2.log("opening quote per pull (wei)", q.total / 10);

        uint256 hourStep = 1 hours;
        for (uint256 day; day < 14; ++day) {
            for (uint256 h; h < 24; ++h) {
                vm.warp(origin + day * 1 days + h * hourStep + 60);
                // farmers: PULLS_PER_DAY in batches of 10, some through a referring site
                uint256 batches = PULLS_PER_DAY / 10 / 24 + (h < (PULLS_PER_DAY / 10) % 24 ? 1 : 0);
                for (uint256 b; b < batches; ++b) {
                    _pullBatch(farmers[(h + b) % 3], (h + b) % 2 == 0 ? site : address(0), 10);
                }
                // outside buyers
                vm.prank(buyer);
                swapper.buy{value: BUY_PER_DAY / 24}(key);
                _fulfillAll(day * 100 + h);
                _settle();
            }
            if (day >= 1) _claimAndSell(day - 1);
            s.hook.distribute();
            if (day % 4 == 3 && s.treasury.polPending() != 0) {
                uint160 minPrice = s.liquidity.sqrtPriceX96() * 97 / 100;
                vm.prank(keeperAddr);
                s.treasury.deployPol(minPrice);
            }
        }
        vm.warp(origin + 14 days + 60);
        _settle();
        _claimAndSell(13);
        assertEq(s.farm.currentEpoch(), 14);
        uint256 retired = s.farm.retireUnearned();
        assertEq(retired, 0, "every epoch had units");

        _reconcile();

        // ---- post-genesis: realised surplus buys and burns ENGINE
        (address[] memory t, uint256[] memory v, bytes[] memory d) = _one(
            address(s.controller), abi.encodeWithSignature("setSurplusSink(address,uint64)", address(s.buyback), uint64(vm.getBlockTimestamp()))
        );
        vm.prank(admin);
        s.timelock.scheduleBatch(t, v, d, bytes32(0), bytes32("sink"), 2 days);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.prank(admin);
        s.timelock.executeBatch(t, v, d, bytes32(0), bytes32("sink"));
        uint256 releasable = s.controller.releasableSurplus();
        console2.log("releasable surplus after genesis (wei)", releasable);
        console2.log("ordinary NAV (wei)", s.controller.nav());
        if (releasable != 0) {
            s.controller.releaseSurplus();
            uint256 supplyBefore = s.token.totalSupply();
            uint256 burned = s.buyback.buyAndBurn();
            assertGt(burned, 0);
            assertEq(s.token.totalSupply(), supplyBefore - burned, "bought ENGINE is burned");
            console2.log("ENGINE burned by first buyback", burned);
            vm.expectRevert();
            s.buyback.buyAndBurn(); // rate-limited
        }
        assertGe(s.controller.nav(), s.controller.capitalTarget() - 1, "release never dips below committed capital");
    }

    function _one(address target, bytes memory data)
        internal
        pure
        returns (address[] memory t, uint256[] memory v, bytes[] memory d)
    {
        t = new address[](1);
        v = new uint256[](1);
        d = new bytes[](1);
        (t[0], d[0]) = (target, data);
    }

    function _reconcile() internal view {
        DrawEngine e = s.engine;
        uint256 n = e.lastIssuedSequence();
        // every accepted acquisition is terminal and booked
        assertEq(e.unsettledAcquisitionCount(), 0, "all settled");
        assertEq(s.controller.nextSequenceToBook(), n + 1, "all booked");
        uint256 fulfilled;
        uint256 units;
        for (uint256 d; d < 14; ++d) {
            (uint64 a, uint64 r, uint64 u,) = e.dayTotals(d);
            assertEq(a, r, "day resolved");
            units += u;
        }
        for (uint256 id = 1; id <= n; ++id) {
            (,,,, DrawEngine.AcquisitionStatus st) = e.acquisitions(id);
            if (st == DrawEngine.AcquisitionStatus.Fulfilled) ++fulfilled;
        }
        assertEq(fulfilled, units, "units = fulfilled acquisitions");

        // player ETH: every wei paid is proceeds, settlement fees, refunds or the VRF fee
        uint256 refunds;
        for (uint256 i; i < 3; ++i) refunds += e.acquisitionRefundCredit(farmers[i]);
        uint256 fees = e.feeCreditOf(site) + e.feeCreditOf(tw) + e.feeCreditOf(devAddr);
        // referral attribution: the site earns half the settlement fee of its referred pulls only
        assertGt(e.feeCreditOf(site), 0);
        assertLt(e.feeCreditOf(site), fees / 2, "unreferred pulls send the referral share to development");
        console2.log("referrer credit", e.feeCreditOf(site));
        console2.log("token works credit", e.feeCreditOf(tw));
        console2.log("development credit", e.feeCreditOf(devAddr));
        uint256 grailProceeds = s.vault.totalProceeds() + e.proceedsOf(address(s.vault));
        uint256 vrfFees = e.vrfFeesCollected();
        assertEq(
            paidIn, s.controller.totalProceedsBooked() + grailProceeds + fees + refunds + vrfFees, "player ETH reconciles"
        );
        console2.log("VRF fees collected", vrfFees);
        console2.log("VRF billed (mock)", vrf.totalBilled());
        assertGe(vrfFees, vrf.totalBilled(), "purchaser VRF fees cover the oracle bill");
        console2.log("GRAIL capture proceeds", grailProceeds);
        assertGe(address(e).balance, e.liabilities(), "engine solvent");

        // farm: claimed + dust = allocation (no unearned epochs)
        assertEq(s.farm.totalClaimed() + s.token.balanceOf(address(s.farm)), LaunchParams.FARM_TOKENS);
        assertLe(s.token.balanceOf(address(s.farm)), 3 * 14 * 2, "only rounding dust");

        // trading fees: hook = operator + treasury; treasury = reserve top-up + GRAIL + POL
        assertEq(
            s.hook.totalFees(),
            creatorAddr.balance + s.treasury.totalReceived() + s.hook.operatorAccrued() + s.hook.treasuryAccrued(),
            "hook fees reconcile"
        );
        assertEq(s.treasury.totalReceived(), s.treasury.totalToGrail() + s.treasury.totalToPol(), "reserve was full");

        // GRAIL vault: everything in = fund + spent
        uint256 vaultIn = s.vault.totalFunded() + s.vault.totalProceeds();
        assertEq(vaultIn, s.vault.fund() + s.vault.totalBackingMinted() + s.vault.totalMintFeesPaid(), "vault reconciles");
        assertEq(s.vault.totalFunded(), s.controller.totalFeedSent() + s.treasury.totalToGrail(), "two GRAIL streams");

        // creator Shape mint fees: every Shape minted paid 0.001
        console2.log("pulls accepted", n);
        console2.log("pulls fulfilled", fulfilled);
        console2.log("player ETH in", paidIn);
        console2.log("settlement fees (ref+TW+dev)", fees);
        console2.log("creator mint fees accrued", IShapesFees(s.shapes).feesOwedTo(creatorAddr));
        console2.log("operator trading fees", creatorAddr.balance);
        console2.log("treasury trading receipts", s.treasury.totalReceived());
        console2.log("GRAIL funded: feed", s.controller.totalFeedSent());
        console2.log("GRAIL funded: trading", s.treasury.totalToGrail());
        console2.log("GRAILs minted backing", s.vault.totalBackingMinted());
        console2.log("ordinary NAV", s.controller.nav());
        console2.log("premium booked", s.controller.totalPremiumBooked());
        console2.log("POL liquidity", s.liquidity.totalLiquidity());
    }
}

interface IShapesFees {
    function feesOwedTo(address) external view returns (uint256);
}
