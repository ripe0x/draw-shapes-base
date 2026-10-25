# Draw Shapes on Base — final implementation report

Date: 2026-10-25. Status: integrated production candidate, **not deployed** to Base mainnet, **not
audited**. All results below are from tests and simulations in this repository; simulations are
scenario outputs under disclosed assumptions and do not demonstrate market demand.

## What was built

| Area | Delivered |
| --- | --- |
| Game engine | `DrawEngine`: fork of FWA's verified FWAClone, keeping its listing, staging/reservation, segment-tree inverse-notional selection, harmonic-mean pricing, ordered VRF settlement, slippage, delivery escrow and refund machinery; FWA's 5 % edge removed; 1 % settlement fee with 50/10/40 referrer / Token Works / development split; one Chainlink VRF v2.5 request per batch; participation ledger; multi-supplier listings and in-place hand-off; guardian pause vs timelock policy. |
| House | `DrawController` (port of Draw Shapes `Pool`): real Shapes v1 and Draw Packs minted and listed at notional `b × 1.08 + mint fees`; books walk; margin split premium / maintenance / GRAIL feed after the mint line; Draw Shapes replacement draw; VRF funding from maintenance; surplus release above committed capital; external prizes; wind-down. |
| GRAILs | `GrailVault`: minted only when fully funded (0.5 → 1 → 5 ETH ladder), listed at 80 % of backing, per-pull decay to 50 % under a 5 % probability cap; funded by the 4 % feed and 90 % of treasury trading receipts. |
| ENGINE and market | Fixed-supply ERC-20 (35M recommended: 10M liquidity, 25M farm); v4 hook taking a 2 % ETH fee (0.25 % operator, 1.75 % treasury, cap 5 %); permanently locked full-range protocol liquidity. |
| Genesis | `GenesisFarm`: 14 × 24 h epochs from game activation, 85 % pro rata to delivered pulls, 15 % to VRF bonus weight, pull claims, acceptance-epoch accounting, unearned-only burn. |
| Treasury | Reserve first, then 90 % GRAIL / 10 % POL; permissionless restock backstop; post-genesis buyback-and-burn with slicing and impact cap. |
| Deployment | Shared `Deployer` (tests = production wiring), config-driven `Deploy.s.sol` with mainnet confirmation guard and postflight checks, single atomic timelock activation batch. |
| Frontend | `web/`: live state, quotes, pulls with referral links, my pulls and refunds, GRAIL progress, board odds, genesis claims, ENGINE disclosure. |
| Evidence | `evidence/` (test outputs, VRF measurements, market CSVs, screenshots, Slither triage), `sim/results/`. |

## Test results (local)

`forge test`: 68 tests in 13 suites passing (unit, fuzz, invariant with 6 invariants × 4,096 calls,
14-day genesis rehearsal, extension, treasury, 26-scenario v4 market grid). Base mainnet fork suites
(`BASE_RPC_URL` set): real VRF coordinator request + callback gas, and full deployment / activation /
pull / trade on Base's canonical PoolManager — passing. `Deploy.s.sol` broadcast to a local anvil
fork of Base — succeeded with all postflight checks.

Key reconciled numbers:

- Reference board quote: 0.015070286533069302 ETH fee + 0.000150702865330693 settlement =
  **0.015220989398399995 ETH per pull**, expected backing 84.22 %; equals an independent recomputation to the wei.
- VRF on Base: live median charge 0.0000040 ETH per fulfilment (118 samples); our callback costs an
  estimated 0.0000022–0.0000093 ETH per pull — far below the 0.000128 ETH maintenance allocation.
- Rehearsal (200 pulls/day, 0.7 ETH/day outside buying): 2,800/2,800 pulls fulfilled; creator mint
  fees 3.70 ETH; GRAIL funding 1.56 ETH feed + 0.30 ETH trading; two GRAILs minted; ordinary NAV
  2.06 → 3.14 ETH; 0.94 ETH surplus released after genesis and bought/burned in slices.

## Recommendations (docs/MARKET.md, docs/M2_RESULTS.md)

- Launch liquidity 2 ETH + 10M ENGINE; **farm 25M** (not 50M); **total supply 35M**.
- **Fee 2 %**, not 5 %.
- Keep the 5 ETH split (2.2 / 2.0 / 0.3 / 0.5) — see the bankroll section of docs/M2_RESULTS.md.
- Keepers must settle at least every few minutes at farming volumes; slow settlement causes mass
  slippage refunds rather than insolvency.

## Remaining blockers before public mainnet

1. **GitHub push / PRs**: the remote returned HTTP 403 for this session; reconnect GitHub and install
   the Claude GitHub App on `ripe0x/draw-shapes-base`, then push the three branches and open the PRs.
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
- VRF is paid from maintenance (player VRF fee 0) so the quote equals fee + 1 %.
- Exact-output ENGINE sells revert on the canonical pool (fees are kept in ETH).
- The farm allocation is set to 25M, below the 50M working maximum, on the liquidity model.
