# ENGINE, the canonical market and the genesis farm (Milestone 2)

## What ENGINE is — and is not

ENGINE is an ordinary, transferable, fixed-supply ERC-20. It is a speculative asset. It is **not**
a claim on the game's ETH, the ETH inside prizes, the GRAIL fund or the treasury. Its only
permanent connection to the game is an executable money flow: after genesis, realised game surplus
buys ENGINE on the market and burns it (Milestone 3), and the canonical pool's trading fees fund
GRAILs. Neither flow guarantees a price, more players, or that buybacks raise the price. The
permanent buyback budget is a small part of game spending: the 3 % premium on backing, about
0.000385 ETH per pull on the reference board, less losses and reserve needs.

## Contracts

| Contract | Role |
| --- | --- |
| `src/token/EngineToken.sol` | Solady ERC-20, whole supply minted once in the constructor, no owner, no mint, no transfer hooks, holder `burn`. |
| `src/token/EngineHook.sol` | v4 hook of the canonical ETH/ENGINE pool. Takes the project fee in ETH: from the input on exact-input buys (`beforeSwap` delta), added to the payment on exact-output buys and taken from the output on exact-input sells (`afterSwap` delta). Exact-output sells revert. Fee and operator share are governance-set within `MAX_FEE_BPS = 500`; launch 200 bps total, 25 bps of volume to the operator, 175 to the treasury. `distribute()` pays out, permissionless. Only the protocol liquidity contract can initialise the pool, once, ETH/ENGINE with LP fee 0. |
| `src/token/ProtocolLiquidity.sol` | Initialises the pool and owns one full-range position. No remove function: launch liquidity and later protocol-owned additions are locked permanently. `addLiquidity` (treasury/governance) buys half fee-exempt under a price limit and adds both sides. |
| `src/token/GenesisFarm.sol` | The single finite distribution (below). No owner. |

The LP fee is 0, so the hook fee is this pool's whole fee and the protocol position has no LP fees to
collect or disclose. If a later decision adds an LP fee, it accrues to the locked position and
must be reported separately from hook fees.

## Genesis farm

- 14 fixed 24-hour epochs from the engine's `ledgerOrigin`, which is set by `DrawEngine.activate()`
  — the moment paid gameplay opens. There is no other start switch.
- Each epoch's allocation is `total / 14` (the last epoch takes the rounding remainder).
- A unit is earned by each acquisition that reaches `Fulfilled` (NFT verifiably delivered). The
  unit belongs to the epoch in which the request was **accepted**, so a delayed VRF word or a slow
  keeper never moves it. Expired, slippage-refunded, empty-pool and delivery-refunded acquisitions
  earn nothing.
- 85 % of the epoch is pro rata to units, 15 % pro rata to bonus weight. Each fulfilled acquisition
  carries a bonus weight of 25 (1 %), 5 (9 %) or 1 (90 %) derived from its own VRF selection word
  (`DrawEngine.bonusWeightOf`). It cannot be chosen, rerolled or selectively settled: settlement is
  strictly in sequence and the word is fixed by the VRF callback.
- An epoch can be claimed once it has ended and every acquisition accepted in it is terminal
  (`accepted == resolved`, the FWA V2 Rewards rule). Claims are pull-based, once per (epoch,
  purchaser), and never expire.
- Empty epochs: after all 14 epochs are final, `retireUnearned()` (anyone) burns the allocation of
  every epoch with no units. Earned rewards are never retired. Per-claimant rounding dust (a few wei)
  stays in the farm.
- After genesis there are no emissions: the farm has no allocation for epoch 14 or later and the
  token has no mint function.

## Supply and launch liquidity (recommendation)

| | Working maximum (brief) | **Recommended** |
| --- | --- | --- |
| Opening liquidity | 10M ENGINE + 2 ETH | **10M ENGINE + 2 ETH** |
| Genesis farm | up to 50M | **25M** |
| Total supply minted | 60M | **35M** |
| Team allocation | none | none |

Why 25M (sim/results/farming.md, all assumptions stated there):

- Farming demand is bought with outside ETH, not with tokens. Farmers can only realise the ETH that
  outside buyers bring (plus part of the 2 ETH opening liquidity). At 0.7 ETH/day of outside buying
  a 50M farm supports about 299 pulls/day, 25M about 276 (−8 %), 10M about 230 (−23 %).
- The same halving leaves the market much healthier at the end of genesis: end price 5.9e-7 vs
  3.5e-7 ETH per ENGINE, 3.44 vs 2.63 ETH in the pool, and 25M instead of 50M tokens of farmer
  overhang. With no outside buying at all, 50M drives the price to 1/36 of the opening reference and
  drains the pool to 0.33 ETH.
- 25M is 1.79M ENGINE a day, a nominal 0.36 ETH/day at the opening reference price.

First-order check (brief §10): sustainable pulls/day ≈ outside ETH/day ÷ loss per pull
(0.002422 ETH all-in): 0.3 ETH/day → ~124, 0.7 → ~289, 1.5 → ~619. The full model agrees within
about 10 % because farmers also extract part of the opening liquidity and price impact grows with
the allocation.

## Fee level: 2 % recommended

On the real v4 pool and hook (evidence/market/summary.csv) and the reconciled model:

- At equal outside buying, 5 % collects 2.4 × the treasury fees (0.97 vs 0.36 ETH over genesis,
  25M, 0.7 ETH/day) but farmers realise 6 % less ETH, so there are fewer pulls and fewer creator
  mint fees.
- ENGINE trades freely; a fee-free rival pool already undercuts the canonical pool for small trades
  (`Bypass.t.sol::test_routingChoice`: 0.002 ETH buys 9,950 ENGINE on a 0.4 ETH rival pool vs 9,790
  on the canonical pool). A 5 % fee widens that gap and invites rival liquidity and aggregator routing.
  If the higher fee costs 25 % of buying, 5 % yields fewer pulls (200/day vs 276) and less total
  creator + treasury ETH (4.2 vs 5.1 ETH).
- The objective is sustainable ETH revenue: creator mint fees (≈ 0.001226 ETH per pull) are the
  largest single flow, about 13 × the treasury's trading fees at 2 %. A lower fee that keeps flow and
  farming on the canonical pool serves that better.

## Alternative-pool bypass

Anyone can create an ETH/ENGINE pool without our hook (another v4 pool, v3, Aerodrome). The hook
cannot and does not try to tax those. Demonstrated in `test/unit/Bypass.t.sol`:

- **Routing**: small trades get more ENGINE from a fee-free rival pool; large trades still prefer
  the deeper canonical pool (1 ETH: 3.29M via canonical vs 1.43M via the 0.4 ETH rival).
- **Arbitrage**: when trades on the rival pool move its price, arbitrageurs buy on one pool and sell
  on the other until the gap is inside the round-trip fee band. Our hook earns its fee on the
  arbitrage leg through the canonical pool (0.003 ETH on 0.15 ETH cycled in the test) — so a rival
  pool still pays the treasury something whenever prices diverge, but far less than the trades it
  diverts.
- **Consequence**: hook revenue depends on the canonical pool remaining the deepest venue. Protocol
  liquidity is locked there and grows with the 10 % POL share of treasury receipts; that is the only
  defence used. No transfer restriction or wrapper is used, by decision, to keep ENGINE composable.

## Market simulation

`test/sim/MarketSim.t.sol` runs 26 scenarios for 16 days on the real v4 `PoolManager` (pinned
v4-core) and `EngineHook`: hourly outside buys and hourly farmer sales of each closed epoch, CSV per
scenario in `evidence/market/`. `sim/market.py` reproduces every run to ≤ 6e-15 relative
(`python3 sim/market.py`), and `sim/farming.py` adds the game side (pulls, creator fees, premium,
GRAIL funding). These are scenario outputs under disclosed buying assumptions; they do not show that
the market will provide that demand.
