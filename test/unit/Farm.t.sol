// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {GameFixture} from "../utils/GameFixture.sol";
import {EngineToken} from "../../src/token/EngineToken.sol";
import {GenesisFarm} from "../../src/token/GenesisFarm.sol";
import {LaunchParams} from "../../script/config/LaunchParams.sol";

/// @notice Genesis farm on the real game: epochs keyed by acceptance, delayed fulfilment, claims,
///         duplicate protection, unearned retirement, fixed supply.
contract FarmTest is GameFixture {
    EngineToken internal engineToken;
    GenesisFarm internal farm;
    uint256 internal constant FARM = LaunchParams.FARM_TOKENS;
    uint256 internal constant LIQ = LaunchParams.LIQUIDITY_TOKENS;
    address internal carol = makeAddr("carol");

    function setUp() public override {
        super.setUp();
        // farm address is known before the token mints to it
        address farmAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        (to[0], amounts[0]) = (address(this), LIQ);
        (to[1], amounts[1]) = (farmAddr, FARM);
        engineToken = new EngineToken(to, amounts);
        farm = new GenesisFarm(address(engineToken), address(engine), FARM);
        assertEq(address(farm), farmAddr);
        _openAndActivate();
        vm.deal(carol, 1_000 ether);
    }

    function _pullAndSettle(address who, uint256 n, uint256 seed) internal {
        (, uint256 vrfId) = _pull(who, n);
        _fulfill(vrfId, seed);
        _settleAll();
    }

    function test_supplyFixed() public view {
        assertEq(engineToken.totalSupply(), LIQ + FARM);
        assertEq(engineToken.balanceOf(address(farm)), FARM);
        assertEq(farm.allocationOf(0) * 13 + farm.allocationOf(13), FARM);
        assertEq(farm.allocationOf(14), 0);
    }

    function test_proportionalAndBonusClaims() public {
        _pullAndSettle(alice, 10, 1);
        _pullAndSettle(bob, 5, 2);
        vm.expectRevert(abi.encodeWithSelector(GenesisFarm.EpochNotClosed.selector, 0));
        _claim(alice, 0);
        vm.warp(block.timestamp + 1 days);
        (,, uint64 units, uint64 bonus) = engine.dayTotals(0);
        (uint64 aUnits, uint64 aBonus) = engine.userDay(0, alice);
        uint256 alloc = farm.allocationOf(0);
        uint256 expectA = alloc * 8_500 / 10_000 * aUnits / units + (alloc - alloc * 8_500 / 10_000) * aBonus / bonus;
        assertEq(farm.rewardOf(0, alice), expectA);
        uint256 a = _claim(alice, 0);
        uint256 b = _claim(bob, 0);
        assertEq(a, expectA);
        assertLe(a + b, alloc);
        assertGe(a + b, alloc - 4, "only rounding dust stays");
        console2.log("epoch 0 units", units, "bonus weight", bonus);
        console2.log("alice", a, "bob", b);
        vm.expectRevert(abi.encodeWithSelector(GenesisFarm.AlreadyClaimed.selector, 0));
        _claim(alice, 0);
    }

    /// @notice A request accepted in epoch 0 and fulfilled in epoch 1 earns in epoch 0; epoch 0 is not
    ///         claimable while it is pending.
    function test_delayedFulfilmentKeepsAcceptanceEpoch() public {
        (, uint256 vrfId) = _pull(alice, 3);
        vm.warp(block.timestamp + 1 days + 1);
        // epoch 0 closed but still pending
        vm.expectRevert(abi.encodeWithSelector(GenesisFarm.EpochStillPending.selector, 0));
        _claim(alice, 0);
        _pull(bob, 2); // epoch 1 acquisition, not fulfilled yet
        _fulfill(vrfId, 9);
        _settleAll();
        (uint64 units0,) = engine.userDay(0, alice);
        (uint64 units1,) = engine.userDay(1, alice);
        assertEq(units0, 3, "units on the acceptance epoch");
        assertEq(units1, 0);
        assertGt(_claim(alice, 0), 0);
    }

    function test_refundedAcquisitionsEarnNothing() public {
        (, uint256 vrfId) = _pull(alice, 4);
        vrfId;
        vm.roll(vm.getBlockNumber() + engine.selectionTimeoutBlocks() + 1);
        engine.processAcquisitions(10);
        vm.warp(block.timestamp + 1 days);
        assertTrue(farm.isFinal(0));
        assertEq(farm.rewardOf(0, alice), 0);
        uint256[] memory e = new uint256[](1);
        vm.prank(alice);
        vm.expectRevert(GenesisFarm.NothingToClaim.selector);
        farm.claim(e);
    }

    function test_fullGenesis_retireOnlyUnearned() public {
        // play in epochs 0, 3, 7 and 13 only
        uint256 start = vm.getBlockTimestamp();
        uint256[4] memory active = [uint256(0), 3, 7, 13];
        for (uint256 i; i < 4; ++i) {
            vm.warp(start + active[i] * 1 days + 100);
            _pullAndSettle(i % 2 == 0 ? alice : carol, 5, 100 + i);
        }
        vm.expectRevert(GenesisFarm.GenesisNotResolved.selector);
        farm.retireUnearned();
        vm.warp(start + 14 days + 1);
        assertEq(farm.currentEpoch(), 14);
        // play after genesis earns nothing new: no epoch 14 allocation
        _pullAndSettle(alice, 2, 999);
        assertEq(farm.allocationOf(14), 0);

        uint256 supplyBefore = engineToken.totalSupply();
        uint256 burned = farm.retireUnearned();
        assertEq(burned, 10 * farm.allocationOf(0), "ten empty epochs retired");
        assertEq(engineToken.totalSupply(), supplyBefore - burned);
        vm.expectRevert(GenesisFarm.AlreadyRetired.selector);
        farm.retireUnearned();

        // earned rewards stay claimable after retirement, forever
        vm.warp(block.timestamp + 365 days);
        uint256[] memory ea = new uint256[](2);
        (ea[0], ea[1]) = (0, 7);
        vm.prank(alice);
        uint256 a = farm.claim(ea);
        uint256[] memory ec = new uint256[](2);
        (ec[0], ec[1]) = (3, 13);
        vm.prank(carol);
        uint256 c = farm.claim(ec);
        uint256 earned = 3 * farm.allocationOf(0) + farm.allocationOf(13);
        assertLe(a + c, earned);
        assertGe(a + c, earned - 8);
        // reconciliation: claimed + retired + dust = allocation
        assertEq(engineToken.balanceOf(address(farm)), FARM - burned - a - c);
        console2.log("dust left in farm (wei)", engineToken.balanceOf(address(farm)));
    }

    function _claim(address who, uint256 epoch) internal returns (uint256) {
        uint256[] memory e = new uint256[](1);
        e[0] = epoch;
        vm.prank(who);
        return farm.claim(e);
    }
}
