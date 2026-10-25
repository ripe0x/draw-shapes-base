# Base Sepolia rehearsal on a local fork (NOT live evidence)

Chain 84532 forked locally with anvil. VRF words were delivered by impersonating the coordinator and the timelock delay was skipped with evm_increaseTime; hashes exist only on the local fork. This rehearses the exact live procedure; it is not testnet evidence.

## Contracts

| Contract | Address |
| --- | --- |
| shapes | `0xc2c63Bb8aa0f2e63Ba4De216DFbab1eB5A767609` |
| drawPacks | `0x6EDD1aF883d6D531Ad3E33E538d2710B55D1Fe4A` |
| timelock | `0x02C530868A845AD00c642912031e8f02540B715C` |
| engine | `0x5D35a5058726986Af56E2330B5C78133132856d3` |
| controller | `0x9Cd62e8c3DEc4964BF4E40db53F92Fb0a3724dD6` |
| grailVault | `0x6bd69ffdC10d166Dc8A804E6117ab4afc75805c2` |
| token | `0x2AC507072654D151dE510b7862A4B430dF113043` |
| hook | `0xDEf1f124E8240c21E1280AaC3fba23fEB9d860CC` |
| liquidity | `0x2e39B31f6CbB0E71501a2B0c97f97458e5107638` |
| farm | `0x1c7f642A4D2c45A1f5857ffCba5c9bDd95E10636` |
| treasury | `0x4d6fBFe02a68d506B334C8CB771e506aA86a5d39` |
| buyback | `0x2cB923220Bdf5cB4f059dCd158272B2389C1229b` |
| lens | `0x46124c5dC4feF35bd69F616C13b6867D15Fc5FF9` |

Deployment: 42 transactions, 68,870,829 gas, 0.068910 ETH. Opening allocation (testnet scale): pool 0.70 ETH, market 0.20 ETH, board 25 items. VRF subscription 105492294325630297195757723471493320216513636850918545864700060199243680130360.

## Activation through the timelock

Scheduled at 1792937602, executed at 1792938204: waited 602 s against a 600 s delay (time skipped on the fork). Engine activated: true; market launched: true; governance: timelock.

Post-activation batch (surplus sink for genesis end; testnet-only faster GRAIL decay): waited 601 s.

## Opening GRAIL (funded at launch with test ETH)

Backing 0.500 ETH, listed at 0.400 ETH (listing 28, Shape #39) before activation.

## Pulls and VRF

| Scenario | Quote: fee / settlement / VRF (ETH) | Request tx | Fulfilment tx | Fulfilment gas | Oracle charge (ETH) | VRF fee − charge (ETH) | Latency | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Single pull (referred) | 0.015966 / 0.000160 / 0.0000136 | `0x9aaa9300…` | `0xac0141c5…` | 587321 | n/a (fork) | — | 0 s | 1 Fulfilled |
| Batch of ten | 0.016184 / 0.000162 / 0.0000288 | `0x309c4ffe…` | `0x1b9fff57…` | 1749250 | n/a (fork) | — | 0 s | 6 Fulfilled, 4 Ready |
| Batch of ten, zero negative slippage | 0.016926 / 0.000169 / 0.0000288 | `0x0d5b0ea8…` | `0x6a86dcf3…` | 1753589 | n/a (fork) | — | 0 s | 6 Fulfilled, 4 Ready |
| On behalf of another wallet | 0.016348 / 0.000163 / 0.0000136 | `0x2cc86e0c…` | `0x073b0a95…` | 527796 | n/a (fork) | — | 0 s | 1 Fulfilled |

Settled inside the VRF callback: 6 of 10 (the rest by the keeper).

### Deliveries (batch of ten)

| Acquisition | Prize | Notional (ETH) | Delivered to purchaser |
| --- | --- | --- | --- |
| 2 | Shape #16 | 0.01170 | true |
| 3 | Shape #2 | 0.01170 | true |
| 4 | Shape #9 | 0.01170 | true |
| 5 | Shape #10 | 0.01170 | true |
| 6 | Draw Pack #9 | 0.03510 | true |
| 7 | Shape #7 | 0.01170 | true |
| 8 | Shape #11 | 0.01170 | true |
| 9 | Shape #12 | 0.01170 | true |

## Keeper booking and restocking

Booked sequences 1 → 12; selectable listings 21 → 28; pool cash 0.1520 → 0.1526 ETH; maintenance 0.01183 ETH.

| Action | Tx | Gas |
| --- | --- | --- |
| settle | `0x2b106a43…` | 6721837 |
| grail-step | `0xeff4a7c9…` | 339067 |

Keeper net cost after the maintenance refund: -0.0000029 ETH.

## GRAIL listing, odds and repricing

| | Backing | Notional | Status | Odds per pull |
| --- | --- | --- | --- | --- |
| before | 0.500 | 0.3780 | Active (selectable) | 1 in 647 |
| after pulls + keeper step | 0.500 | 0.3680 | Active (selectable) | 1 in 609 |

Decay is accelerated on testnet only (0.002 ETH per pull, set through the timelock); selection of a GRAIL by the live VRF is a matter of chance at these odds.

## Refunds

Batch with zero negative slippage tolerance: 6 Fulfilled, 4 Ready; refund credit 0.032692 ETH, withdrawn in `0x2b0061e4…`. Expiry (no VRF word within 1,800 blocks) cannot be forced on a live coordinator; it is covered by Engine.t.sol.

## Referral and purchase on behalf

Referrer credit 0.0019826 ETH, withdrawn in `0xb2575d58…`; prize delivered to the beneficiary: true. Token Works / development credit (testnet: deployer) 0.0021461 ETH.

## ENGINE trading and fee routing

Buy 0.01 ETH and sell half through the canonical PoolManager (test router `0x6d757bb331b86fbae11dbed931125d4c94000cdd`): volume 0.015017 ETH, hook fees 0.0003003 ETH = 199 bps of volume; operator 0.0000375, treasury 0.0002628 ETH; after distribute the treasury received 0.0002628 ETH (GRAIL fund now 0.03554 ETH, POL pending 0.0000000 ETH).

## Genesis ledger

Epoch 0: 27 accepted, 27 resolved, 25 units, 29 bonus weight; test player 24 units. Claimed 1735248 ENGINE in `0x6df08918…` (after a fork time skip).

## Keeper outage and recovery (two keepers)

With keepers stopped, three batches settled in their callbacks: selectable listings 27 → 18, 9 sequences unbooked. Two keepers then ran at the same moment: keeper 1 [settle], keeper 2 [settle]; listings back to 27, books level: true.

## Prize redemption

Redeemed Shapes #16 (notional 0.01170 ETH): 0.01000 ETH of backing returned to the winner.

## Genesis end (fork only, time skipped)

Keeper actions: retire-unearned, buyback. Unearned allocation retired 23214286 ENGINE; buyback spent 0.003143 ETH and burned 147612 ENGINE; supply 35000000 → 11638102.

## All transactions

| Label | Tx | Status | Gas | Cost (ETH) |
| --- | --- | --- | --- | --- |
| vrf.createSubscription | `0x95954cb8…` | success | 109806 | 0.00011029 |
| vrf.fundSubscriptionWithNative | `0x78a69596…` | success | 56137 | 0.00005635 |
| vrf.addConsumer(engine) | `0x427cd469…` | success | 95278 | 0.00009528 |
| vault.fundGrail(opening GRAIL) | `0xd71acc91…` | success | 67321 | 0.00006732 |
| vault.step(mint + list opening GRAIL) | `0xe6a45b2d…` | success | 837995 | 0.00083800 |
| timelock.scheduleBatch(activation) | `0x8af67296…` | success | 93752 | 0.00009375 |
| timelock.executeBatch(activation) | `0x92d815ba…` | success | 480591 | 0.00048059 |
| timelock.scheduleBatch(setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only)) | `0xce36c4e8…` | success | 67856 | 0.00006786 |
| timelock.executeBatch(setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only)) | `0x607a8ddf…` | success | 92302 | 0.00009230 |
| fund player | `0x121f7b4c…` | success | 21000 |  |
| fund referrer | `0xdd04e266…` | success | 21000 |  |
| fund keeper-2 | `0xcf036328…` | success | 21000 |  |
| acquireBatch(1) with referrer | `0x9aaa9300…` | success | 481301 | 0.00048130 |
| vrf fulfilment 111592318136081007090872967745673373387233919425857811448935638968780416383764 (fork: coordinator impersonated) | `0xac0141c5…` | fork | 587321 |  |
| acquireBatch(10) | `0x309c4ffe…` | success | 1986525 | 0.00198653 |
| vrf fulfilment 80382782757280767859393662656460986540728554965189803949707627264082855557312 (fork: coordinator impersonated) | `0x1b9fff57…` | fork | 1749250 |  |
| settle | `0x2b106a43…` | success | 6721837 | 0.00000673 |
| grail-step | `0xeff4a7c9…` | success | 339067 | 0.00000034 |
| acquireBatch(5) for GRAIL decay | `0x20c21cd0…` | success | 1131282 | 0.00113128 |
| vrf fulfilment 59338213665806933520070854849476234254913090740425197683639592875922270363042 (fork: coordinator impersonated) | `0x3610e6eb…` | fork | 1437511 |  |
| settle | `0xd104f9a3…` | success | 4573527 | 0.00000457 |
| grail-step | `0x0f133f76…` | success | 319167 | 0.00000032 |
| acquireBatch(10, maxNegativeSlippage 0) | `0x0d5b0ea8…` | success | 1986501 | 0.00198650 |
| vrf fulfilment 64634548952919886444547884891494482578955172709299859232793124765573777743220 (fork: coordinator impersonated) | `0x6a86dcf3…` | fork | 1753589 |  |
| withdrawAcquisitionRefund | `0x2b0061e4…` | success | 36762 | 0.00003676 |
| settle | `0xe30dc3e6…` | success | 6535435 | 0.00000654 |
| grail-step | `0xf6f9ee54…` | success | 143464 | 0.00000014 |
| acquireBatch(1) paid by player for referrer | `0x2cc86e0c…` | success | 447101 | 0.00044710 |
| vrf fulfilment 95695361262610089088250021252392363339125103410840193616977991841775985968916 (fork: coordinator impersonated) | `0x073b0a95…` | fork | 527796 |  |
| settle | `0x41febae6…` | success | 1007559 | 0.00000101 |
| withdrawFeeCredit(referrer) | `0xb2575d58…` | success | 38216 | 0.00003822 |
| deploy Swapper (test router) | `0x966a089a…` |  | 726205 |  |
| swap: buy ENGINE with 0.01 ETH | `0xeddf4769…` | success | 213776 | 0.00021378 |
| approve router | `0x919e450f…` | success | 45958 | 0.00004596 |
| swap: sell half the ENGINE | `0x8355776d…` | success | 137105 | 0.00013711 |
| hook.distribute | `0xacaa2817…` | success | 175961 | 0.00017596 |
| outage acquireBatch(3) #1 | `0x2b3ac5cc…` | success | 789181 | 0.00078918 |
| vrf fulfilment 34940757999605054160779696926785960726202852942226116476926313888514960558347 (fork: coordinator impersonated) | `0x91d70eb8…` | fork | 983547 |  |
| outage acquireBatch(3) #2 | `0x0af320cf…` | success | 789181 | 0.00078918 |
| vrf fulfilment 20355205071560463655489935348291865438334950153560681851612454252901582341393 (fork: coordinator impersonated) | `0xd17b0006…` | fork | 942198 |  |
| outage acquireBatch(3) #3 | `0x09ef1420…` | success | 789181 | 0.00078918 |
| vrf fulfilment 81930253936869671377203591457478252871230430031888858137517952635013840555232 (fork: coordinator impersonated) | `0x8355354f…` | fork | 921737 |  |
| settle | `0xec793038…` | success | 6865235 | 0.00000687 |
| settle | `0x2ac64d6b…` | success | 80714 | 0.00000008 |
| redeem Shape #16 | `0xfb0e0eb2…` | success | 61989 | 0.00006199 |
| farm.claim([0]) | `0x6df08918…` | success | 154259 | 0.00015426 |
| retire-unearned | `0xb77ff083…` | success | 262600 | 0.00000026 |
| fund buyback (fork exercise) | `0xaaec2bb1…` | success | 22474 |  |
| buyback | `0x13bad765…` | success | 219730 | 0.00000022 |
