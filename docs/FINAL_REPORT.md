# Draw Shapes on Base — final implementation report

Date: 2026-10-25. Status: integrated production candidate, **not deployed** to Base mainnet, **not
audited**. All results below are from tests and simulations in this repository; simulations are
scenario outputs under disclosed assumptions and do not demonstrate market demand.

## What was built

| Area | Delivered |
| --- | --- |
| Game engine | `DrawEngine`: fork of FWA's verified FWAClone, keeping its listing, staging/reservation, segment-tree inverse-notional selection, harmonic-mean pricing, ordered VRF settlement, slippage, delivery escrow and refund machinery; FWA's 5 % edge removed; 1 % settlement fee with 50/25/25 referrer / Token Works / development split; one Chainlink VRF v2.5 request per batch, paid by the purchaser as a separate per-batch VRF fee that funds the subscription; purchase on behalf of another wallet; participation ledger; multi-supplier listings and in-place hand-off; guardian pause vs timelock policy. |
| House | `DrawController` (port of Draw Shapes `Pool`): real Shapes v1 and Draw Packs minted and listed at notional `b × 1.065 + mint fees`; books walk; margin split premium 4 % / maintenance 0.5 % / GRAIL feed 2 % after the mint line; Draw Shapes replacement draw; keeper refunds from maintenance; surplus release above committed capital after a 0.05 ETH maintenance floor; external prizes; wind-down. |
| GRAILs | `GrailVault`: minted only when fully funded (0.5 → 1 → 5 ETH ladder), listed at 80 % of backing, per-pull decay to 50 % under a 5 % probability cap; replacement first (smallest rung while none is live); funded by the 3 % feed and treasury trading receipts (100 % while no GRAIL is live, else 90 %). |
| ENGINE and market | Fixed-supply ERC-20 (35M recommended: 10M liquidity, 25M farm); v4 hook taking a 2 % ETH fee (0.25 % operator, 1.75 % treasury, cap 5 %); permanently locked full-range protocol liquidity. |
| Genesis | `GenesisFarm`: 14 × 24 h epochs from game activation, 85 % pro rata to delivered pulls, 15 % to VRF bonus weight, pull claims, acceptance-epoch accounting, unearned-only burn. |
| Treasury | Reserve first, then all to the GRAIL fund while no GRAIL is live, else 90 % GRAIL / 10 % POL; permissionless restock backstop; post-genesis buyback-and-burn with slicing, impact cap, minimum buy and a capped caller bounty. |
| Deployment | Shared `Deployer` (tests = production wiring), config-driven `Deploy.s.sol` with mainnet confirmation guard and postflight checks, single atomic timelock activation batch. |
| Frontend | `web/`: live state, quotes, pulls with referral links, my pulls and refunds, GRAIL progress, board odds, genesis claims, ENGINE disclosure. |
| Evidence | `evidence/` (test outputs, VRF measurements, market CSVs, screenshots, Slither triage), `sim/results/`. |

## Test results (local)

`forge test` with `BASE_RPC_URL` set: 71 tests in 15 suites passing (unit, fuzz, invariant with 6 invariants × 4,096 calls, presentation,
14-day genesis rehearsal, extension, treasury, 26-scenario v4 market grid). Base mainnet fork suites
(`BASE_RPC_URL` set): real VRF coordinator request + callback gas, and full deployment / activation /
pull / trade on Base's canonical PoolManager — passing. `Deploy.s.sol` broadcast to a local anvil
fork of Base — succeeded with all postflight checks.

Key reconciled numbers:

- Reference board quote (follow-up configuration): 0.014878540357338322 ETH fee + 0.000148785403573383
  settlement = **0.015027325760911705 ETH per pull before VRF**, expected backing 85.31 %; equals an
  independent recomputation to the wei. Purchaser VRF fee per batch at 0.01 gwei: 0.0000233 ETH for 1
  pull, 0.0000556 ETH for 4–20 pulls (≈ 0.0000056 per pull in a 10-pull batch).
- VRF on Base: live median charge 0.0000040 ETH per fulfilment (118 samples); on the Base fork the
  quoted fee covers the estimated bill for 1, 4 and 10-pull batches; collected ≥ billed at every
  tested basefee (0.001–0.2 gwei) and batch size (1–20) against Chainlink's billing formula.
- Rehearsal (200 pulls/day, 0.7 ETH/day outside buying): 2,800/2,800 pulls fulfilled; creator mint
  fees 3.69 ETH; GRAIL funding 0.70 ETH feed + 0.31 ETH trading; two 0.5 ETH GRAILs minted; ordinary
  NAV 2.06 → 3.44 ETH; 1.24 ETH releasable after genesis (0.05 ETH of it restores maintenance first),
  bought/burned in slices. Before/after report: docs/FOLLOWUP.md.

## GRAIL availability and launch economics (docs/GRAIL_AVAILABILITY.md)

- GRAIL decay liveness bug fixed (`stepDue()` now reports pending decay; decay clamps at the cap).
- Recommended for approval: fee split 3.5 / 0.5 / 3 (GRAIL downtime −37 % at 300/day for ~7 % less
  median buyback, lower shortfall risk) and a 0.501 ETH opening GRAIL from new capital. Code default
  remains 4 / 0.5 / 2.
- Keeper outages degrade gracefully (no shortfall up to a 24 h outage at 1,500/day; recovery in the
  first keeper pass); run two independent keepers.

## Recommendations (docs/MARKET.md, docs/M2_RESULTS.md)

- Launch liquidity 2 ETH + 10M ENGINE; **farm 25M** (not 50M); **total supply 35M**.
- **Fee 2 %**, not 5 %.
- Keep the 5 ETH split (2.2 / 2.0 / 0.3 / 0.5) — see the bankroll section of docs/M2_RESULTS.md.
- Keepers must settle at least every few minutes at farming volumes; slow settlement causes mass
  slippage refunds rather than insolvency.

## Remaining blockers before public mainnet

1. (resolved) GitHub access; milestone PRs are open.
2. Independent security audit.
3. Legal review (paid chance-based play, referral payments, ENGINE).
4. Token Works' Base recipient address, confirmed by Token Works.
5. Admin Safe, guardian, keeper, creator and development addresses.
6. Base Sepolia rehearsal with a real VRF fulfilment and measured cost (no authorised testnet
   resources in this session).
7. VRF subscription created and funded by the admin Safe.

## Deviations from the brief (decided and documented)

- The Draw Shapes 1 ETH piece / merge GRAIL builder is not ported; Base GRAILs are single native Shapes.
- `DrawEngine` accepts `ANY_INVENTORY_VERSION` as an opt-out of the exact-version check (fee and value guards remain).
- Anyone (not only the purchaser) may convert a stuck delivery to the purchaser's refund after 7 days.
- VRF: originally paid from maintenance; the follow-up moved it to a separate purchaser-paid per-batch fee.
- Exact-output ENGINE sells revert on the canonical pool (fees are kept in ETH).
- The farm allocation is set to 25M, below the 50M working maximum, on the liquidity model.
