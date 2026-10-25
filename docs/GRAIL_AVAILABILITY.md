# GRAIL availability, launch economics and keeper reliability

Status: production candidate on `claude/dreamy-allen-twdsex` (PR #3). **Not deployed, not audited.**
Simulation figures are model outputs under the assumptions in `sim/grail.py`, `sim/farming.py` and
`sim/bankroll.py`. They are not demand or revenue forecasts.

Reproduce:
- `forge test` (set `BASE_RPC_URL` for the fork suites);
- `python3 sim/grail.py 200 compare levers seed outage post`;
- `python3 sim/farming.py`;
- `BANKROLL_SPLIT=350,50,300 python3 sim/bankroll.py 2000` and `python3 sim/bankroll.py 2000`.

Raw outputs:
- `sim/results/grail-*.md`, `farming.md`, `bankroll.md`, `bankroll-350-50-300.md`;
- `evidence/grail-followup-tests.txt`.

## Answer to the central question

The ETH flowing into the GRAIL fund decides availability; the probability mechanics barely do. The
best simple way to keep a fully backed GRAIL on the board is:
- **(1) fund it faster per pull**, with the 3 % feed;
- **(2) cover the empty start**, with one GRAIL funded at launch from new capital (needs approval);
- **(3) keep keepers redundant.**

The repricing bug is fixed. It is a correctness fix, not an availability lever.

A live GRAIL also raises the price of every pull by about 1 %, and on ordinary captures that extra
goes to the ordinary pool. Availability therefore *helps* buybacks rather than competing with them.

## 1. GRAIL repricing liveness (fixed)

**Confirmed.**
- `stepDue()` returned true only for a harvest, sync, relist or mint. `_reprice()` ran only inside
  `step()`, and `DrawController.settle()` never steps the vault. The keeper calls `step()` only when
  `stepDue()` is true, so a listed GRAIL decayed only when a mint or a capture happened to occur.
- A second flaw: after skipped keeper intervals, a decay that would cross the probability cap was
  skipped entirely. Because the decay owed only grows, the GRAIL could stay stuck.

**Fix** (`GrailVault`):
- One view planner, `_repricePlan()` (public `repricePlan()`), drives both `step()` and `stepDue()`.
- It keeps the same decay formula, the 50 % floor, the 5 % cap and the 1 % minimum change.
- No reprice while any acquisition is unsettled, while a GRAIL is staged or awaiting relist, or while
  the vault is paused.
- A catch-up that would cross the cap now decays to the cap boundary. `stepDue()` is never true when
  `step()` would change nothing.

`test/unit/GrailReprice.t.sol` (7 tests) covers:
- a keeper that only steps when due running the full schedule to the floor;
- skipped intervals;
- the cap boundary, without getting stuck or being permanently due;
- multiple GRAILs under the combined cap;
- a newly funded staged GRAIL;
- outstanding acquisitions;
- paused.

Five of the six tests that compile against the old vault fail on it.

**Frontend and Lens** now separate:
- **selectable** (an Active listing, with odds);
- **fully funded but not yet selectable** (staged or awaiting relist; no odds shown);
- **funds accumulating** (`fund`).

They also show the next notional when a decay is pending.

**Effect on availability:** small. At 300/day with no trading, hours without a GRAIL are 218 fixed
vs 213 before (4 / 0.5 / 2), and 138 vs 148 (3.5 / 0.5 / 3).

The decay is slow by design. At 0.00002 ETH per pull, a 0.5 ETH GRAIL loses about 0.05 ETH over the
~2,700 pulls it typically lives. On a full board its odds (~0.037 %) are about 130× below the 5 % cap,
so the cap binds only when the ordinary board is nearly empty. The lifecycle works as intended, but
it is a mild effect.

## 2. 4 / 0.5 / 2 vs 3.5 / 0.5 / 3

### Exact values (reference board; asserted to the wei in `ReferenceBoard.t.sol`)

| | 4 / 0.5 / 2 (default) | 3.5 / 0.5 / 3 |
| --- | --- | --- |
| Notionals | 0.01165 / 0.0233 / 0.03495 / 0.05425 / 0.1075 | 0.0117 / 0.0234 / 0.0351 / 0.0545 / 0.108 |
| Acquisition fee (wei) | 14,878,540,357,338,322 | 14,942,455,786,105,613 |
| Fee + settlement | 0.015027326 ETH | 0.015091880 ETH (+0.43 %) |
| Player payment incl. 10-pull VRF share (0.01 gwei) | 0.0150329 | 0.0150974 (0.0150983 with the later 30 % VRF service margin) |
| Ordinary RTP (backing / fee + settlement) | 85.31 % | 84.94 % |
| Per pull: premium / GRAIL feed | 0.000513 / 0.000256 | 0.000449 / 0.000385 (+50 %) |

Keeping one GRAIL selectable costs the fund about **0.000186 ETH per pull** at 80 % list, and
**0.000298** at the 50 % floor. This is independent of GRAIL size: a bigger GRAIL is won
proportionally less often.
- The 2 % feed (0.000256) covers roughly one GRAIL in steady state, with nothing left to build
  inventory.
- The 3 % feed (0.000385) sustains about 1.3–2.

A listed 0.5 ETH GRAIL raises the harmonic-mean fee by **0.96 %** (`test_listedGrailRaisesFeeForEveryPull`).
That is +0.000145 per pull, against +0.000186 of GRAIL expected value per pull.

### 14-day genesis (Monte Carlo, 200 seeds, `grail-compare.md`)

Medians unless stated. GRAIL ETH is a transfer into the fund, not earnings.

| pulls/day, trading ETH/day | config | RTP total (ordinary) | premium | buyback p50 / p10 | GRAIL ETH feed / trading | first GRAIL h (p50 / p90) | hours w/o GRAIL p50 / p90 | mean selectable (backing) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 100, 0 | 4/0.5/2 | 85.9 % | 0.70 | 0.54 / 0.27 | 0.35 / 0 | never | 336 / 336 | 0 |
| 100, 0 | 3.5/0.5/3 | 85.8 % | 0.60 | 0.43 / 0.20 | 0.52 / 0 | 327 / never | 328 / 336 | 0.09 |
| 300, 0 | 4/0.5/2 | 86.4 % (85.8) | 2.14 | 1.94 / 1.43 | 1.07 / 0 | 173 / 242 | **218 / 307** | 0.38 (0.19) |
| 300, 0 | 3.5/0.5/3 | 86.2 % (85.1) | 1.99 | 1.81 / 1.38 | 1.70 / 0 | 113 / 164 | **138 / 230** | 0.73 (0.36) |
| 300, 3 | 4/0.5/2 | 86.4 % | 2.33 | 2.16 / 1.65 | 1.16 / 0.69 | 94 / 117 | 112 / 198 | 0.84 |
| 300, 3 | 3.5/0.5/3 | 86.3 % | 2.05 | 1.88 / 1.46 | 1.76 / 0.68 | 78 / 103 | 88 / 144 | 1.06 |
| 300, 10 | 4/0.5/2 | 86.9 % | 2.48 | 2.32 / 1.90 | 1.24 / 2.24 | 49 / 57 | 51 / 84 | 1.40 |
| 300, 10 | 3.5/0.5/3 | 86.5 % | 2.23 | 2.04 / 1.64 | 1.91 / 2.24 | 44 / 53 | 45 / 69 | 1.54 |
| 750, 0 | 4/0.5/2 | 86.6 % | 5.55 | 5.38 / 4.52 | 2.78 / 0 | 70 / 92 | **129 / 210** | 0.73 |
| 750, 0 | 3.5/0.5/3 | 86.3 % | 5.13 | 4.96 / 4.38 | 4.39 / 0 | 45 / 64 | **64 / 129** | 1.01 |

The 1 ETH/day trading rows and the daily inventory timeline (selectable / fully funded / accumulating)
are in `grail-compare.md`. At 300/day with no trading, mean selectable GRAILs at the end of day 7 /
day 14:
- 4 / 0.5 / 2: 0.40 / 0.90;
- 3.5 / 0.5 / 3: 0.81 / 1.41.

The fund accumulating toward the next GRAIL averages 0.25–0.30 ETH in both configurations.

**After genesis** (`grail-post.md`). Genesis at 300/day, then 28 days at 50–150 pulls/day and
1 ETH/day of trading:
- **Hours without a GRAIL, p90:** 243–272 h for 4 / 0.5 / 2 vs 113–124 h for 3.5 / 0.5 / 3 (no
  genesis trading).
- **Buyback over 42 days, p50:** 2.83 vs 2.54 ETH at 50/day, and 4.38 vs 4.08 at 150/day.
- **Buyback, p10:** 2.06 vs 2.11, and 3.60 vs 3.46.

**Solvency** (`bankroll.md` vs `bankroll-350-50-300.md`, 2,000 seeds). The alternative's higher total
markup (7 % vs 6.5 %) is *safer*. Pool-alone shortfall:

| Scenario | 4 / 0.5 / 2 | 3.5 / 0.5 / 3 |
| --- | --- | --- |
| 300/day | 0.20 % | 0.05 % |
| 1,500/day | 1.30 % | 0.85 % |
| 1,500/day, hourly keeper (with reserve) | 0.45 % | 0.15 % |
| 6-hourly keeper (with reserve) | 0.20 % | 0.05 % |

The acceptance gate (300/day, 5-minute keeper, with reserve) is 0 / 2,000 for both. The cost is
median NAV and premium about 4–10 % lower.

**Farming** (`farming.md`, 25M farm). Loss per pull is 0.002233 vs 0.002298. The alternative gets
about 3 % fewer farming pulls and about 3 % less creator mint revenue, for the same farmer ETH.

### Recommendation

**Adopt 3.5 / 0.5 / 3 for launch, subject to your approval.** It is a governance parameter
(`DrawController.setFeeSplit`), or a one-line change to `LaunchParams.feeSplit`. The code default
remains 4 / 0.5 / 2 as instructed.

Why:
- It cuts GRAIL downtime by **37 % at 300/day and 50 % at 750/day**.
- It roughly halves the worst-case gaps after genesis.
- It lowers shortfall risk.
- It costs about **7 % of median genesis buyback**, while the p10 buyback is almost unchanged (−3 %).

If players come for headline prizes, a game without one for nine of fourteen days loses more paid
demand than 7 % of buyback is worth.

Downsides:
- **3.5 / 0.5 / 3:**
  - Pulls cost 0.43 % more.
  - Ordinary RTP is 0.37 points lower (total RTP about −0.2 points).
  - About 3 % fewer farming pulls and less creator revenue.
  - Smaller buybacks: 0.13 ETH at 300/day over genesis, about 0.3 ETH over 42 days.
  - At 100 pulls/day and no trading it still has no GRAIL for most of genesis.
- **4 / 0.5 / 2:**
  - The game spends 65 % of genesis (300/day, no trading) without a selectable GRAIL, and its
    post-genesis p90 gaps exceed 10 days.
  - Its larger buyback is concentrated in scenarios where the headline prize is missing.
  - Higher pool-alone shortfall risk.

## 3. Availability levers (300/day; `grail-levers.md`, `grail-seed.md`)

| Lever | Hours w/o GRAIL (4 / 0.5 / 2, trading 0) | (3.5 / 0.5 / 3, trading 0) | Verdict |
| --- | --- | --- | --- |
| Baseline (fixed repricing, current policy) | 218 | 138 | — |
| Repricing bug (before) | 213 | 148 | correctness only |
| No decay at all | 212 | 141 | decay is not the constraint |
| Old treasury / vault policy (90 / 10 always, no replacement-first) | 204 | 145 | within noise without trading; current policy helps with trading (88 vs 96 h at 3 ETH/day) |
| No ladder step-up during genesis | 208 | 140 | within noise |
| Replacement buffer (hold 0.501 ETH back while one is live) | 214 | 134 | **worse inventory** (0.35 vs 0.38 selectable; idle fund up) — not adopted |
| Keeper every 60 min | 236 | 154 | keeper timing costs 10–20 h and 0.15 ETH of buyback |
| **Opening GRAIL funded at launch (0.501 ETH new capital)** | **79** | **12** | most effective; needs approval |

With the seed and 3 ETH/day of trading, the median time without a GRAIL falls to 12 h (4 / 0.5 / 2)
and 0 h (3.5 / 0.5 / 3). The seed raised the median genesis buyback (1.93 → 2.13, 1.79 → 1.98) through
the fee uplift above. Most of the seed goes to whoever wins that GRAIL.

**Idle funds.** The fund waits 0.25–0.30 ETH on average because a GRAIL is minted only when its whole
backing plus mint fee is in. That is the "fully funded" rule, not keeper timing: with 5-minute
keepers a funded GRAIL is minted within a tick.

No transfer from the ordinary bankroll, the reserve or committed funds is used or proposed.

## 4. Keeper reliability (`grail-outage.md`, `KeeperOutage.t.sol`)

During an outage, pulls keep settling inside the VRF callback; only booking, restocking and GRAIL
steps stop. Results (4 / 0.5 / 2, outage at hour 72, 200 seeds):

| pulls/day | outage | refunded | reverted (empty board) | min ordinary active p1 | margin during outage p1 / p50 | recovery |
| --- | --- | --- | --- | --- | --- | --- |
| 300 | 15 min / 1 h / 6 h / 24 h | 0 / 0 / 0.6 / 10.0 % | 0 | 79 / 70 / 22 / 2 | ≥ −0.08 / + | first keeper pass |
| 750 | same | 0 / 0 / 2.1 / 12.5 % | 0 | 65 / 51 / 9 / 1 | ≥ −0.41 / + | first keeper pass |
| 1,500 | same | 0.13 / 0.24 / 2.9 / 7.4 % | 0 / 0 / 0 / 6.6 % | 53 / 29 / 2 / 0 | ≥ −0.52 / + | 3–5 calls |

Across all scenarios:
- **Shortfall:** none, and the reserve was never exhausted.
- **Concurrency:** the model includes concurrent batches and out-of-order VRF callbacks.
- **Recovery cost** at 0.002 / 0.01 / 0.1 gwei: 0.0004 / 0.0017 / 0.017 ETH (24 h outage at
  1,500/day), refunded from maintenance.
- **Foundry check:** on the real contracts the outage test delivers all 101 prizes, refunds the 274
  excess pulls and recovers in 9 permissionless settle calls (≈ 0.0007 ETH).
- **Escrow and committed NFT backing** stay whole throughout.

**No new keeper framework or throttle.** `settle()` already pays its caller's gas plus a 0.00001 ETH
tip from maintenance whenever it lists, so it is permissionlessly incentivised. A board-depth throttle
would only turn refunds into reverts, saving about 0.000006 ETH of VRF fee per pull.

The runbook now requires two independent keepers, and alerts on: board depth below 70, no settle for
15 minutes, and `stepDue()` stuck for 15 minutes.

Note: the old bankroll model's high refund rates at slow keepers (40–89 %) were an artefact. It priced
every request in a keeper window at the window's opening board. The engine prices each batch on
arrival and settles it in the callback, so real refund rates are far lower (table above).

## 5. Farming assumptions (`farming.md`, sensitivity section)

The equilibrium assumes farmers spend all ETH their ENGINE realises on pulls. It is an equilibrium
assumption, not a forecast. With 25M farmed and 0.7 ETH/day of outside buying, under the current
config:

| Reinvested | Pulls/day | Creator mint fees (model) |
| --- | --- | --- |
| 100 % | 299 | 5.13 ETH |
| 75 % | 224 | 3.85 ETH |
| 50 % | 149 | 2.56 ETH |
| 25 % | 75 | 1.28 ETH |

Farmer ETH has two sources:
- **External speculative ETH:** 11.2 ETH bought over 16 days at 0.7 ETH/day.
- **Opening liquidity drained by emission sellers:** with no outside buying, all 1.40 ETH farmers
  realise is drained from the 2 ETH of opening liquidity. With buying ≥ 0.3 ETH/day the pool ends
  with more ETH than it started.

Creator revenue figures are model outputs. They exist only if outside buyers bring that ETH and
farmers spend it on pulls.

## 6. Tests

Complete suite with `BASE_RPC_URL`: **91 passed, 0 failed, 18 suites**, including:
- 6 invariants × 4,096 calls;
- both Base mainnet fork suites;
- the 14-day rehearsal.

Results are in `evidence/grail-followup-tests.txt`. `ReferenceBoard.t.sol` now also pins the
alternative's exact prices and the GRAIL fee uplift.

## 7. Decisions requiring approval

1. **Fee split:** 3.5 / 0.5 / 3 (recommended) or keep 4 / 0.5 / 2. Either way, maintenance stays 0.5 %.
2. **Opening GRAIL:** fund 0.501 ETH of new capital (outside the 5 ETH split) into `GrailVault.fundGrail`
   before activation, so a 0.5 ETH GRAIL is selectable from the first pull. Recommended if capital is
   available.
3. **Keepers:** two independent keepers and the alerting above. Operational, no code.

## Remaining risks

- The demand response to GRAIL availability is not modelled; the recommendation rests on the product
  premise that headline prizes drive paid pulls.
- At 100 pulls/day and no trading, neither configuration funds a GRAIL in genesis without the seed.
- After a 24 h outage at farming volume, about 7 % of attempted purchases revert and about 7 % are
  refunded.
- The GRAIL probability cap limits decay only. On a drained board GRAIL odds rise and it may be won
  at notional; the vault then receives about 0.4 ETH instead of about 0.015 ETH, so it is not a loss.
- An audit is still required, and the Token Works address is still unverified.
