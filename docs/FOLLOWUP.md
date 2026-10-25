# Follow-up: economics, purchaser-funded VRF, FWA V2 improvements, treasury policy — before / after

Status: production candidate on `claude/dreamy-allen-twdsex-followup`, **not deployed, not audited**.
Nothing was broadcast to Base mainnet; the deploy script was rehearsed only on a local anvil fork.
Simulation figures are model outputs under the assumptions stated in `sim/followup.py`. They do not
predict demand, and passing tests do not replace an audit.

Reproduce:
- `forge test` (set `BASE_RPC_URL` for the fork suites);
- `python3 sim/followup.py 200`, `python3 sim/farming.py`, `python3 sim/bankroll.py 2000`.

Raw outputs:
- `sim/results/followup.md`, `sim/results/bankroll.md`, `sim/results/farming.md`;
- `evidence/followup-tests.txt`, `evidence/rehearsal-genesis.txt`, `evidence/followup-sizes.txt`.

Preserved unchanged:
- 35M ENGINE supply, the 14-day genesis, the 2 % hook fee (0.25 % operator), the NFT inventory and mix;
- inverse-notional selection and harmonic-mean pricing;
- the 1 % settlement fee and the 0.001 ETH Shape mint fee.

Not added, as instructed: crowns, depositor emissions, floor oracles, blackouts, standing-bid cashouts,
transfer restrictions and Shape-to-ENGINE conversion.

## 1. Economics: exact values (reference board, integer wei as in the contracts)

| | previous (3 / 1 / 4, TW 10 %) | **proposed (4 / 0.5 / 2, TW 25 %)** | low-cost (3 / 0.5 / 1, TW 25 %) |
| --- | --- | --- | --- |
| Notionals 0.01 / 0.02 / 0.03 / 0.05 / 0.1 | 0.0118 / 0.0236 / 0.0354 / 0.055 / 0.109 | **0.01165 / 0.0233 / 0.03495 / 0.05425 / 0.1075** | 0.01145 / 0.0229 / 0.03435 / 0.05325 / 0.1055 |
| Acquisition fee (wei) | 15,070,286,533,069,302 | **14,878,540,357,338,322** | 14,622,878,261,581,451 |
| Settlement fee (wei) | 150,702,865,330,693 | **148,785,403,573,383** | 146,228,782,615,814 |
| Fee + settlement (reference price before VRF) | 0.015220989 ETH | **0.015027326 ETH** (15,027,325,760,911,705 wei) | 0.014769107 ETH |
| VRF fee (separate, per batch, 0.01 gwei) | 0 (paid from maintenance) | 1 pull 0.0000233; 4–20 pulls 0.0000556 ETH | same |
| Expected backing (wei) | 12,819,127,730,909,358 | **12,819,637,956,291,283** | 12,820,340,647,755,923 |
| Ordinary RTP (backing / fee + settlement) | 84.22 % | **85.31 %** | 86.81 % |
| RTP including a 10-pull batch's VRF share | 84.22 % | 85.28 % | 86.77 % |
| Per pull: mint line to creator / premium / maintenance / feed | 0.001226 / 0.000385 / 0.000128 / 0.000513 | 0.001226 / **0.000513 / 0.000064 / 0.000256** | 0.001226 / 0.000385 / 0.000064 / 0.000128 |
| Settlement split per pull: referrer / Token Works / dev | 0.0000754 / 0.0000151 / 0.0000603 | 0.0000744 / **0.0000372** / 0.0000372 | 0.0000731 / 0.0000366 / 0.0000366 |

Notes on the table:
- `ReferenceBoard.t.sol` asserts the proposed values to the wei.
- Token Works' 25 % comes out of the 1 % settlement fee and is not charged on top, so the player
  price is unchanged by the split.
- The reference price ≈ 0.015027 ETH and RTP ≈ 85.31 % from the brief are confirmed exactly.

### Impact, using the 14-day farming equilibrium and the Monte Carlo

Farming equilibrium (`sim/followup.py` section 5, 25M farm), at 0.7 ETH/day of outside buying:

| | previous | proposed | low-cost |
| --- | --- | --- | --- |
| Farmer loss per pull | 0.002422 | 0.002233 | 0.001974 |
| Pulls/day | 276 | 299 | 338 |
| Creator mint fees | 4.73 | 5.13 | 5.80 |
| Premium | 1.48 | 2.15 | 1.82 |
| GRAIL feed | 1.98 | 1.07 | 0.61 |
| Maintenance | 0.49 | 0.27 | 0.30 |
| Token Works | 0.058 | 0.156 | 0.173 |

**Farmer losses.** Competitive farmers lose exactly what their ENGINE realises. That is 9.34 ETH at
0.7 ETH/day in every configuration. A cheaper pull buys more pulls for the same loss: +8 % pulls
(proposed) and +22 % (low-cost).

**Creator mint revenue** scales with pulls: +8 % proposed, +23 % low-cost.

**Distributable surplus / buybacks** (Monte Carlo, 300 pulls/day, no trading, median realised
budget at genesis end, after the maintenance-floor top-up):

| previous | proposed | low-cost |
| --- | --- | --- |
| 1.53 ETH | **1.94 ETH** | 1.23 ETH |

The p10 values are 1.18 / 1.49 / 0.74 ETH. Nominal premium is not all distributable: NAV moves
with which prizes are won. In the low-cost configuration at 100 pulls/day, 8–9 % of runs end
genesis with **no** releasable surplus.

**GRAIL funding**: this is the cost of the proposal. The feed halves (4 % → 2 %):

| 300 pulls/day, no trading | previous | proposed | low-cost |
| --- | --- | --- | --- |
| First GRAIL (median) | 82 h | **171 h** | none in 14 days |
| Hours without a live GRAIL (median / p90) | 109 / 197 | 211 / 311 | 336 / 336 |
| GRAILs minted | 3 | 2 | 0 |

With 3 ETH/day of trading, the proposed config gets its first GRAIL at 95 h, with 115 / 205 hours
without one.

**Solvency.** Player escrow is unaffected by any of these changes: refunds still return fee +
settlement fee, and the engine holds exactly its liabilities in the tests. Bankroll stress under
the proposed markups is in section 6.

## 2. Purchaser-funded VRF (FWA V2 model, one request per batch)

How the fee works:
- **Quote.** `quoteAcquisitionPrice(n)` returns the fee, settlement fee and VRF fee separately.
  `Lens.quote` and the frontend show all three.
- **Formula.** `vrfFeeFor(n) = (overheadGas + callbackGasLimitFor(n)) × max(basefee, minGasPrice) ×
  (1 + premium + buffer) + flatWei`, capped at 0.002 ETH.
  - Launch values: 400,000 gas, 0.005 gwei, 60 % (Chainlink's native premium), 25 % buffer and
    0.000002 ETH.
  - Bounds: premium ≤ 200 %, buffer ≤ 50 %.
- **One fee per batch.** The 20-pull batch pays one fee: the callback limit caps at 2.5M gas, so
  4–20 pulls cost the same.

Collection and accounting:
- The fee is collected in `acquireBatch` and forwarded at once with `fundSubscriptionWithNative`.
- It is never part of backing, escrow, proceeds or earnings. `vrfFeesCollected` and the
  `VrfFeeCollected(firstSequence, count, amount)` event record it.
- **Refunds.** The VRF fee is not refunded on expiry, slippage or a failed delivery, because the
  oracle request was made. Fee + settlement fee are refunded as before.
  - `test_vrfFee_notRefundedOnSlippageOrExpiry_otherAmountsAre` checks this.
  - Overpayment is returned to the payer.
- **Removed:** `DrawController.topUpVrf`, `vrfTargetBalance` and `vrfFeePerBatch`.
- **Maintenance** now pays only keeper refunds and other non-VRF costs.

Reconciliation, collected versus billed against Chainlink's v2.5 native billing (callback gas +
342.5k overhead, × gas price × 1.6, + L1 fee):

| Evidence | Result |
| --- | --- |
| `Followup.t.sol` (basefee 0.001–0.2 gwei × batches 1 / 5 / 10 / 20, oracle price = basefee × 1.2) | collected ≥ billed in all 20 cases; 1.2–1.9× |
| `BaseVrfFork.t.sol` (real Base coordinator) | quoted fee covers the estimated bill for 1, 4 and 10-pull batches |
| Rehearsal (2,800 pulls) | 0.00807 ETH collected vs 0.00643 billed |
| Monte Carlo | collected ≈ 1.2× billed in every row |

The subscription accumulates the difference as a VRF reserve. Governance can lower `bufferBps` or
`overheadGas` once live fulfilments are measured on Base Sepolia/mainnet; `Lens.vrf()` shows
collected fees, the subscription balance and the current quotes.

Residual risk:
- A basefee spike of more than ~1.5× between request and fulfilment on a single batch can
  under-collect for that batch. The accumulated reserve covers this.
- An empty subscription only delays fulfilment. Unanswered requests expire and refund.

### Maintenance at 0.25 % (benchmarked, not adopted)

Per pull, for a 10-pull batch, keeper cost is (250k + 690k × 10 + 30k gas) × basefee + 0.00001 ETH tip:

| basefee (gwei) | keeper cost / pull | 0.5 % maintenance covers | 0.25 % covers |
| --- | --- | --- | --- |
| 0.005 | 0.0000046 | 14.0× | 7.0× |
| 0.01 | 0.0000082 | 7.8× | 3.9× |
| 0.05 | 0.0000369 | 1.7× | 0.9× |
| 0.2 | 0.0001446 | 0.4× | 0.2× |

At 0.25 % the allocation fails at 0.05 gwei, a level Base reaches in busy periods. The extra RTP is
small: 85.49 % vs 85.31 % before VRF.
**Kept at 0.5 %.** Revisit with measured mainnet keeper costs.

## 3. FWA V2 improvements

| Item | Status | What changed | Evidence |
| --- | --- | --- | --- |
| A. Auto-settle on VRF fulfilment | Already present; measured | Word cached first. Then bounded, isolated `processAcquisitions(1)` self-calls (600k stipend, 60k reserve); a failing item cannot revert the callback. The purchaser pays for the callback gas through the VRF fee. | Base fork, real coordinator: 1 → 1, 4 → 4, 10 → 7 settled inside the callback. Local: 1 / 3 / 5 / 10 / 20 → 1 / 3 / 5 / 9 / 7 (`test_measure_callbackSettlesBatches`). Keepers only book and restock, which cuts the pending window and slippage refunds. |
| B. Permissionless buyback incentive | Added bounds | Bounty = 0.5 % of ETH actually spent, capped at `maxBounty` (0.00005 ETH, governance ≤ 0.001). Reverts below `minSpend` (0.005 ETH) both before and after the swap, so dust and impact-starved calls earn nothing. The 1 h spacing stops repeats. Paid only from the buyback balance. | `test_buyback_antiDust_boundedBounty_gas`: 233k gas ≈ 0.0000023 ETH at 0.01 gwei. A 0.00005 ETH cap ≈ 20× gas at 0.01 gwei and ≈ 2× at 0.1 gwei. |
| C. Durable settlement receipts, replay-safe sync | Added a view over existing records | `Lens.receipt(id)` assembles status, purchaser, referrer, fee, settlement fee, fee policy, listing / collection / token / depositor / notional, ledger day, word, bonus weight, VRF request id, finality and whether the controller has booked it. No new storage. | `test_receipts_durable_and_syncIsIdempotent`: re-running process / settle / step and a second VRF callback leaves referrals, Token Works and dev credits, bookings, GRAIL fund, replacements, refunds and genesis units unchanged. |
| D. Purchase on behalf | Already supported; payer now in the event | `msg.sender` pays and gets only overpayment back. `purchaser` (beneficiary) gets the prize, genesis units and refund credit. `referrer` is separate. `AcquisitionRequested` now carries `payer`. | `test_purchaseOnBehalf_payerOnlyGetsExcess_beneficiaryGetsEverythingElse`, `test_purchaseOnBehalf_refundGoesToBeneficiary` |

## 4. Treasury and GRAIL policy

Changes:
- **Treasury priority.** `Treasury.receiveTradingFees` still refills the reserve first. Then, while
  the vault holds **no** GRAIL (before the first, or after one has been won), 100 % goes to the
  GRAIL fund. With a GRAIL live, 90 / 10 to POL is restored.
- **Vault: replacement first.** While no GRAIL is live, `nextTarget()` is the smallest rung
  (0.5 ETH). A replacement mint does not move the ladder, so capture proceeds (≈ 0.4 ETH per won
  GRAIL, returned to the fund) re-list a headline prize at once.
  - `test_grailVault_replacementFirstAfterAllAreWon` checks this: two won GRAILs fund a 0.5 ETH
    replacement immediately, and the ladder stays at 1 ETH for the next addition.
- **Premium stays in the ordinary pool.** After genesis, `releaseSurplus` first restores
  maintenance to 0.05 ETH (an operating-reserve transfer, not counted as released surplus); only
  the rest goes to buy-and-burn.
  - `test_releaseSurplus_topsUpMaintenanceFloorFirst` checks this.

Monte Carlo, medians over 200 seeds, 14 days:
- GRAIL ETH figures are transfers into the fund and are **not** counted as earnings.
- "Time w/o GRAIL" is the median / p90 of hours with no GRAIL on the board.
- RTP total includes GRAIL wins.

| 300 pulls/day | trading 0 | trading 1 ETH/day | trading 3 | trading 10 |
| --- | --- | --- | --- | --- |
| previous: GRAILs minted / time w/o GRAIL / RTP total / buyback | 3 / 109 / 197 h / 85.9 % / 1.53 | 3 / 89 / 172 h / 85.6 % / 1.59 | 4 / 76 / 170 h / 85.6 % / 1.63 | 3 / 43 / 116 h / 85.6 % / 1.69 |
| **proposed** | 2 / 211 / 311 h / 86.4 % / 1.94 | 2 / 162 / 261 h / 86.4 % / 2.06 | 3 / 115 / 205 h / 86.5 % / 2.18 | 4 / 51 / 84 h / 86.9 % / 2.36 |
| proposed with the old policy (90 / 10 always, no replacement-first) | 2 / 216 / 310 h / 86.3 % / 1.93 | — | 3 / 126 / 221 h / 86.6 % / 2.13 | — |
| low-cost | 0 / 336 / 336 h / 87.7 % / 1.23 | 1 / 265 / 327 h / 87.7 % / 1.33 | 2 / 166 / 278 h / 87.8 % / 1.51 | 4 / 58 / 102 h / 88.1 % / 1.73 |

Other measured values:
- **GRAIL odds per pull:** 0.01–0.06 %.
- **GRAIL inventory over time** (mean live GRAILs at each day's end) is in
  `sim/results/followup.md` section 4.
  - Proposed, no trading: 0 until day 4, then 0.25 at day 6 and 0.89 at day 14.
  - Previous: 0.29 at day 3, 1.47 at day 14.
- **At 750 pulls/day** the new policy cuts time without a GRAIL from 161 to 112 h (no trading).
  At 300/day the gain is small, because the binding limit there is the feed rate, not the split.

**Reading.**
- The proposal increases the buyback budget by ~25 % and lifts player RTP by about one point.
- It roughly halves GRAIL funding from gameplay. With little trading, the first GRAIL arrives
  around day 7 instead of day 3–4.
- The new treasury and replacement policy reduces the gap but cannot replace the lost feed.
- The low-cost alternative usually ends genesis with no GRAIL unless trading is ≥ 3 ETH/day, and it
  has the smallest buyback budget.
- If an early headline GRAIL matters more than the extra buyback budget, a 3 % feed (e.g. 3.5 / 0.5
  / 3) is the obvious middle ground. That is a governance parameter (`setFeeSplit`), not a code
  change.

## 5. Tests

Complete suite with `BASE_RPC_URL`: **81 passed, 0 failed, 16 suites**, including the Base mainnet
fork suites, 6 invariants × 4,096 calls and the 14-day rehearsal (`evidence/followup-tests.txt`).

New tests in `test/unit/Followup.t.sol`:
- VRF quote and formula; sharing across a batch; subscription funding.
- Collected ≥ billed across basefees and batch sizes.
- VRF non-refund.
- On-behalf purchase: payer vs beneficiary.
- Receipts and idempotent replay.
- GRAIL replacement-first.
- Maintenance floor.
- Callback settlement measurement.

New tests in `test/unit/Treasury.t.sol`:
- GRAIL priority, then 90 / 10.
- Buyback anti-dust, bounty cap and gas.

Updated tests:
- Exact reference values, 50 / 25 / 25 split, VRF-inclusive reconciliation identities.
- The fork VRF test now checks the fee against the bill.

Contract sizes (EIP-170 headroom):

| Contract | Size | Headroom |
| --- | --- | --- |
| DrawController | 23,823 B | 753 B |
| DrawEngine | 23,682 B | 894 B |

`Deploy.s.sol` was rehearsed on a local anvil fork of Base at block 53,000,000, and all postflight
checks passed. The script logged a quoted payment of 0.015040 ETH per pull including the VRF share.

## 6. Bankroll stress under the proposed markups

See `sim/results/bankroll.md` (2,000 seeds per row, regenerated with premium 4 / maintenance 0.5 /
feed 2). The before table is in git history.
