# Milestone 1 — working NFT gacha on Base: results

Reproduce: `forge test --match-path "test/unit/*"`, `forge test --match-path "test/invariant/*"`,
`BASE_RPC_URL=<base rpc> forge test --match-contract BaseVrfFork -vv`,
`python3 script/measure/vrf_cost_base.py`. Raw outputs are in `evidence/`.

## Acceptance gates

| Gate | Status | Evidence |
| --- | --- | --- |
| Actual funded Shapes and Packs in inventory | Pass | `ReferenceBoard.t.sol::test_referenceBoard_inventoryAndCost` — 100 listings from real Shapes v1 and Draw Packs, 1.65 ETH backing, 0.14 ETH creator mint fees (140 Shapes) |
| Backing and notional calculations | Pass | `test_referenceBoard_notionals` — 0.0118 / 0.0236 / 0.0354 / 0.055 / 0.109 exact |
| Inverse-notional selection and harmonic-mean price | Pass | `test_referenceBoard_priceReconcilesToTheWei`, `Engine.t.sol::testFuzz_feeIsHarmonicMean` (256 runs) |
| Creator and settlement fees | Pass | `test_singlePull_endToEnd`, `test_selfReferralGoesToDev`, `test_feePolicySnapshottedAtRequest`, `test_ethRoutingReconciles` |
| ≥ 50 concurrent acquisition requests | Pass | `Engine.t.sol::test_concurrent60_outOfOrder` (60), `Game.t.sol::test_concurrent50_onReferenceBoard` (50 on the real board) |
| Out-of-order randomness fulfilment | Pass | both concurrency tests deliver words in scrambled / reverse order; processing stays in sequence |
| Failed NFT delivery and refund | Pass | `test_deliveryFailure_retry_and_refund`, `test_deliveryFailure_retrySucceeds`, `Game.t.sol::test_externalPrize_deliveryFailure_writeOffAndRecovery` |
| Inventory and ETH accounting invariants | Pass | `GameInvariants` — 6 invariants × 64 runs × 64 depth (engine solvency, controller buckets I1/I2, vault solvency, tree = totals, ledger consistency, unsettled count) |
| Batched draws use the intended VRF model | Pass | `test_batchUsesOneVrfRequestAndIndependentWords` — one request per batch, `keccak256(word, i)` per acquisition; Base fork test sends real `requestRandomWords` to the Base coordinator |
| Real Chainlink cost measured on Base Sepolia | **Not met (blocked)** | No authorised Base Sepolia wallet, ETH or subscription was available to this session. Substitutes: (1) live measurement of 118 real Base **mainnet** VRF v2.5 native fulfilments (`evidence/vrf/base-mainnet-fulfilments.md`), (2) Base mainnet fork with the real coordinator, real subscription and real request; callback delivered from the coordinator address because the oracle proof cannot be produced locally (`evidence/vrf/base-fork-callback-gas.txt`). A Base Sepolia rehearsal remains a pre-launch gate (docs/RUNBOOK.md). |

## Quoted player payment (reference board)

| | wei | ETH |
| --- | --- | --- |
| Acquisition fee | 15,070,286,533,069,302 | 0.015070 |
| Settlement fee (1 %) | 150,702,865,330,693 | 0.000151 |
| Total per pull | 15,220,989,398,399,995 | 0.015221 |
| Expected backing | 12,819,127,730,909,358 | 0.012819 (84.22 %) |

Wallet gas is additional. The settlement fee splits 75,351,432,665,347 to the referrer,
15,070,286,533,069 to Token Works and the remainder to development per fulfilled pull.

## VRF (Chainlink v2.5, Base)

Verified on chain (Base mainnet): coordinator `0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634` has
proving keys `0x00b81b5a…3ccab` (2 gwei max) and `0xdc2f8767…44d70` (30 gwei max); config
`maxGasLimit` 2,500,000, `gasAfterPaymentCalculation` 42,500, flat native fee 0, native premium
60 %. Base Sepolia coordinator `0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE` has key
`0x9e1344a1…44bf71` (30 gwei).

Live mainnet fulfilments (other consumers, 40,000 blocks): median subscription charge
0.00000401 ETH (p90 0.00000434) for ~407k gas at 0.00615 gwei.

Our callback (fork, cold storage, includes settling and delivering inside the callback):

| Batch | Callback gas | Settled in callback | Estimated charge | Per pull |
| --- | --- | --- | --- | --- |
| 1 | 603,471 | 1 | 0.0000093 ETH | 0.0000093 |
| 4 | 1,294,002 | 4 | 0.0000161 ETH | 0.0000040 |
| 10 | 1,897,170 | 6 (rest by keeper) | 0.0000220 ETH | 0.0000022 |

Estimate = (callback gas + 300k verification + 42.5k) × 0.00615 gwei × 1.6. Even a single pull
costs < 8 % of the 0.000128 ETH maintenance allocation per pull, which funds the subscription
(`DrawController.topUpVrf`). Launch therefore sets `vrfFeePerBatch = 0`.

## Gas (local, warm)

| Operation | Gas |
| --- | --- |
| Engine processing per acquisition (select, deliver, ledger) | ~350,000 |
| Controller `settle` restocking 1 / 20 items (mint + list) | ~0.96M / ~13M |

At Base's measured 0.006 gwei, restocking 20 items costs about 0.00008 ETH.

## Contract sizes

```
| DrawController     | 24,515           | 28,202            | 61                 | 20,950              |
| DrawEngine         | 22,713           | 24,646            | 1,863              | 24,506              |
| GrailVault         | 10,486           | 12,219            | 14,090             | 36,933              |
| ShapePacks         | 17,715           | 20,319            | 6,861              | 28,833              |
| Shapes             | 22,460           | 24,897            | 2,116              | 24,255              |
```

`DrawController` has 61 bytes of EIP-170 headroom; any further controller code must move to a
separate contract (as the GRAIL already did).

## Known limitations at this milestone

- Slippage refunds: with 50 requests in flight on a 100-item board, 3 of 50 were refunded because
  earlier captures moved the live fee by more than 10 % (FWA's retained protection). Farmers should
  expect occasional refunds at high concurrency; refunds include the settlement fee and earn no units.
- Self-referral through a second wallet cannot be prevented; it returns at most 0.5 % of the fee.
- Base Sepolia live VRF cost measurement is outstanding (see gates).
