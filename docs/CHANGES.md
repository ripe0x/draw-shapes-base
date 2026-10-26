# Changes and decisions log

Running list of what has been decided and changed in the follow-up work, by status. Newest decisions
are folded into the right section rather than appended. Earlier milestones: docs/FINAL_REPORT.md
(M1–M3) and docs/FOLLOWUP.md (economics follow-up).

Status key: **Shipped** = committed and pushed · **Built, on hold** = written and tested, not
committed, waiting on you · **Building** = approved, in progress · **Agreed, not built** = direction
agreed, no code yet · **Open** = your decision.

## Shipped

| Change | Where | Commit |
| --- | --- | --- |
| Base Sepolia v2 live: engine `0xA12D…8418`, controller `0xdF14…880C`, PrizeRouter `0xab37…2BF5`; site redeployed to draw-shapes-base-sepolia.netlify.app; keeper running | deployments/, evidence/ | 1b83bd5 |
| Small testnet board: whole queue listed, 0.5 ETH pool; prize-router runner fix | script/, web/scripts/ | 36d1d07 |
| Terms of Use page and a clickwrap on first wallet connect (per chain and wallet); no country blocking; operator name and contact from env | site/app/terms, TermsGate.tsx, lib/legal.ts | fad91a5 |
| Migration: `DrawController.migrateCapital`, `GrailVault.migrate`, `Treasury.migrate` (timelock, 48 h, to any address). **To be replaced** by the custody vault below | src/game, src/treasury | 5168cca |
| Simulations: Base vs FWA custom pool with the ENGINE model; GRAIL funding from pulls vs 3 % trading fees; best player outcome on FWA | sim/fwa_compare.py, grail_funding.py, fwa_best.py | 39ca9a0, 5a43ee2, aa255d5, 5299411 |
| Economics Lab: inputs, levers and outputs, saved scenarios side by side; trading volume in USD; default comparison Base vs FWA lean with matched buy-and-burn | https://claude.ai/artifact/Kc1BpL6WC5V8dTiKPVrsg2 (not in the repo) | — |

## Built, on hold

**Genesis up to 21 days, shortenable, never extendable.** Your call: 21 days because the audience is
small and may take time to catch on. Waiting for your go-ahead.

- 21 daily epochs at the 14-day plan's rate (1,785,714 ENGINE a day): farm 37.5M, total supply 47.5M.
- Governance may end genesis early, one way only: not below 7 days, and the current day plus 2 full
  days always still run after the 48 h timelock. The ENGINE of cut days is burned.
- Buybacks start at the actual genesis end; the shortening batch also moves the surplus release start.
- Site, scripts and docs read the length from chain. 116 tests pass.
- Saved as git stash "genesis up to 21 days, one-way shorten (not approved yet)" and
  `scratchpad/genesis-21-days.patch` in the working container; both disappear with the container.

## Building

**Custody vault with pluggable game venues** (replaces the migrate-anywhere functions). Goal: you can
move the game off FWA, or to any new gacha, without being able to withdraw the ETH yourself.

1. A permanent vault holds the game's ETH and Shapes. No withdraw function for anyone. ETH leaves only
   as Shape backing (minted to the vault), to the ENGINE LP on shutdown, or to another vault with the
   exact same code (checked by code hash).
2. Venues (the FWA pool today, something else later) receive only Shapes to list. Adding a venue goes
   through the timelock plus a 14-day on-chain notice.
3. A new venue starts capped (about 10 % of inventory backing) and the cap steps up over weeks.
4. Removing a venue pulls its Shapes back to the vault (FWA: `retirePool`, then `withdrawListingsTo`).
5. Shutdown sends the vault's ETH and liquidated Shapes to the ENGINE LP.
6. Minting only replaces drawn prizes, so mint-fee churn cannot drain the vault.
7. No vault-code upgrade path (decided: no escape valve).

Known limits, accepted: you still choose venues and a bad one can take up to its cap; you hold every
key, so there is no outside veto; a future system that needs raw ETH instead of NFT inventory would
not be reachable.

## Agreed, not built

- **No owner ETH withdrawal anywhere**, and game upgrades must not touch the ETH (covered by the vault).
- **Shutdown fail-safe**: after retirement, permissionless liquidation of pool ETH and Shapes into the
  ENGINE LP, price-limited, with a permissionless fallback after a delay. Nothing to you.
- **Fees**: ENGINE trading fee 3 %, kept. You earn the Shapes mint fee (0.001 ETH per Shape) only; your
  settlement-fee share and the randomness margin go to the game and split like margin (3.5 buy-and-burn
  / 0.5 keeper / 3 GRAIL). On FWA: no markup, the player pays the randomness fee.
- **Launch order**: ENGINE trades for 48 h before the game opens (split market launch from activation).
- **Collection coin machine** (strategy coin whose fees buy NFTs into an FWA custom pool, paired with
  ENGINE; Bored Apes first): a factory for any collection, in a separate private repo, after Draw Shapes.
- **Front-running**: send collection buys as private transactions with a price cap.

## Open (your decisions)

- **Chain**: Base, or our own system on Ethereum mainnet (my recommendation, given your goals for
  ENGINE), or FWA. The vault design works for all three.
- **Make `ripe0x/draw-shapes-base` private.** It is public today.
- Genesis change above: ship as is, or adjust.
- Sepolia small-board refund options.
- Riso art pick.
- Operator name and contact for the Terms (`NEXT_PUBLIC_OPERATOR_NAME`, `NEXT_PUBLIC_CONTACT`); LLC or not.
- Keeper on Fly.io (needs `FLY_API_TOKEN` in the environment settings).
- Mainnet VRF subscription float.

## Ops reminders

- Base Sepolia: rerun the runner's `claims` step after genesis epoch 0 closes (about 04:15 UTC, Oct 27 2026).
