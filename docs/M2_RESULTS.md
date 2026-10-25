# Milestone 2 — ENGINE market and genesis farming: results

Reproduce: `forge test --match-path "test/unit/{Market,Farm,Bypass}.t.sol"`,
`forge test --match-contract MarketSimTest`, `python3 sim/market.py`, `python3 sim/farming.py`,
`python3 sim/bankroll.py 2000`.

## Acceptance gates

| Gate | Status | Evidence |
| --- | --- | --- |
| Correct fixed token supply | Pass | `Market.t.sol::test_fixedSupplyAndNoMint`, `Farm.t.sol::test_supplyFixed`; `EngineToken` has no mint function or owner |
| Correct market-fee splits | Pass | `test_buyExactIn_fee2pct_split` (2 % of ETH in; 0.25 % / 1.75 % of volume), `test_sellExactIn_feeOnEthOut`, `test_buyExactOut_feeOnTop`, `test_feeBounds` |
| Alternative-pool bypass behaviour and cost | Pass | `Bypass.t.sol`: routing choice by size, arbitrage across pools, fee earned on the arbitrage leg (docs/MARKET.md) |
| Daily epoch accounting | Pass | `test_proportionalAndBonusClaims` (85 / 15 split to the wei, dust ≤ 4 wei) |
| No duplicate farming claims | Pass | `AlreadyClaimed` in `test_proportionalAndBonusClaims` |
| No loss of earned rewards from delayed fulfilment | Pass | `test_delayedFulfilmentKeepsAcceptanceEpoch` (accepted epoch 0, fulfilled in epoch 1, earns in 0; epoch gated until resolved) |
| No unauthorised issuance | Pass | no mint path; no allocation for epoch ≥ 14 (`test_fullGenesis_retireOnlyUnearned`) |
| Correct retirement of unearned allocations | Pass | 10 empty epochs burned exactly; earned epochs claimable a year later; claimed + burned + dust = allocation |
| Real v4 simulation with disclosed buying assumptions | Pass | `test/sim/MarketSim.t.sol` on the real PoolManager + hook, 26 scenarios (`evidence/market/`); model reconciles to ≤ 6e-15 |
| Farmer-selling stress over all fourteen days | Pass | grid × sell 100 % / 50 % / 25 % (`sim/results/farming.md`) |
| Realisable farmer returns and creator fee revenue | Pass | `sim/results/farming.md` |

## Recommendation

- **Liquidity**: 2 ETH + 10M ENGINE, full range, permanently locked.
- **Farm**: 25M ENGINE (total supply 35M). Halving 50M costs ~8 % of farming pulls but ends genesis
  with a ~1.7× higher price, ~31 % more ETH in the pool and half the farmer overhang.
- **Fee**: 2 %. 5 % only wins if outside buying is almost insensitive to the fee, which the bypass
  results make unlikely.

| Outside buying (assumption) | Pulls/day (25M) | Farmer ETH realised | Creator mint fees | GRAIL funding | Operator 0.25 % | End price |
| --- | --- | --- | --- | --- | --- | --- |
| 0 ETH/day | 41 | 1.40 | 0.71 | 0.32 | 0.004 | 1.6e-8 |
| 0.3 ETH/day | 133 | 4.50 | 2.28 | 1.10 | 0.023 | 2.2e-7 |
| 0.7 ETH/day | 276 | 9.34 | 4.73 | 2.31 | 0.052 | 5.9e-7 |
| 1.5 ETH/day | 579 | 19.62 | 9.93 | 4.85 | 0.110 | 1.5e-6 |

Over 14 days, competitive farmers with zero required margin; ETH values. The farming program can
only pay out what outside buyers bring; with no outside buying the 25M allocation buys about 41
pulls a day and most of the opening liquidity ends with farmers.

## Bankroll stress (sim/results/bankroll.md, 2,000 seeds per row)

**Acceptance threshold.** At the target volume (300 paid pulls a day, the farming model's level at
0.7 ETH/day of outside buying) with a keeper settling at least every 5 minutes: probability below
0.5 % that, at any time in the 14 days, the ordinary pool and the treasury reserve together cannot
fund the next replacement. Rationale: a shortfall is not insolvency — player escrow is untouched and
the next proceeds refill cash — but it thins the board and changes odds, so it should be rare and
covered by the reserve.

| Scenario (keeper 5 min unless stated) | Any shortfall, pool alone | With 0.5 ETH reserve backstop | Worst board depth before restock | NAV p1 / p50 | Refund rate |
| --- | --- | --- | --- | --- | --- |
| 100/day | 0.25 % | — | 70 | 2.23 / 2.57 | 0 % |
| 300/day (target) | 0.10 % | **0 / 2,000** | 60 | 3.12 / 3.73 | 0.01 % |
| 750/day | 0.30 % | 0 / 2,000 | 50 | 5.19 / 6.11 | 0.05 % |
| 1,500/day | 0.50 % | 0 / 2,000 | 40 | 8.51 / 9.86 | 0.24 % |
| 300/day, keeper 60 min | 0.60 % | 0 / 2,000 | 30 | 2.91 / 3.43 | 2 % |
| 1,500/day, keeper 60 min | 3.75 % | 0 / 2,000 (p99 use 0.29 ETH) | 6 | 4.08 / 5.02 | 40 % |
| 1,500/day, keeper 6 h | 4.80 % | 0 / 2,000 | 4–6 | 2.05 / 2.52 | 89 % |
| 1,500/day, pool 2.0 ETH | 30 % | — | 38 | 8.32 / 9.62 | 0.2 % |
| 1,500/day, pool 1.9 ETH | 94 % | — | 40 | 8.15 / 9.52 | 0.3 % |

Reading:

- **The proposed 5 ETH allocation is adequate; no change.** With the reserve backstop no run in
  any scenario (2,000 seeds each, including no trading income and slow keepers) hit an uncovered
  shortfall (95 % upper bound ≈ 0.15 %). Without the reserve the pool alone stays at ≤ 0.5 % with a
  5-minute keeper. 2.2 ETH is the smallest pool tested that works alone: at 2.0 ETH the shortfall
  probability at 1,500/day jumps to 30 %.
- Ordinary NAV at the 1st percentile stayed above the 2.06 ETH left after opening mint fees in every
  row except the 6-hour-keeper rows (p1 2.00–2.05 ETH); the premium accumulates (0.53 ETH at 100/day, 1.70 at 300/day over 14 days, median).
- **Keeper cadence is the operational risk**: slow settlement does not threaten solvency, but the
  board empties between restocks and the 10 % slippage guard refunds most pulls (40 % at 1,500/day
  with an hourly keeper, 89 % with a 6-hour one). Run keepers every block to every few minutes.
- Trading income does not help the ordinary pool directly (it funds GRAILs); the reserve backstop
  is what covers restock tails.

Limits of the model: slippage tolerance is applied symmetrically at 10 %; VRF latency, delivery
failures and gas are not modelled; arrival is Poisson in batches of 10; `p_below95` in the raw table
is a batch artefact (see the note there).
