# Milestone 3 — integrated production candidate: results

| Gate | Status | Evidence |
| --- | --- | --- |
| All contracts and frontend integrated | Pass | `script/Deployer.sol` deploys and wires every contract; `web/` reads the Lens and writes to the engine and farm; driven end to end on a Base fork (`evidence/web/01-live.png`, `02-after-pull.png`: connect, pull ×10 with `?ref=`, VRF delivery, prizes listed under "My pulls", epoch units). |
| Real referral and revenue-split flows | Pass | Rehearsal: 1,400 referred pulls credit the referring site; settlement fees reconcile to the wei (`GenesisRehearsal.t.sol`); `test_singlePull_endToEnd`, `test_selfReferralGoesToDev`, `test_feePolicySnapshottedAtRequest`. |
| GRAIL funding from game feed and token trading | Pass | Rehearsal asserts `vault.totalFunded = feed + treasury share`; 0.5 and 1 ETH GRAILs minted and one GRAIL captured in 14 days; `Treasury.t.sol::test_tradingFeesFlowToGrail`. |
| Treasury reserves and realised surplus accounting | Pass | `test_reserveFirstThenGrailAndPol`, `test_backstopOnlyWhenRestockIsWaiting`, `test_surplusReleaseOnlyAboveCapitalAndFullBoard`; rehearsal releases exactly NAV − 2.2 ETH. |
| Post-genesis buybacks and burns | Pass | Rehearsal: surplus 0.94 ETH released, first slice burns 150,878 ENGINE, supply falls by exactly that; `test_buybackWaitsForGenesisEnd_rateLimited_burns` (start gate, 1 h spacing, 3 % impact cap, fee exemption, pause). |
| Complete genesis rehearsal from deployment through finalisation | Pass | `GenesisRehearsal.t.sol::test_fullGenesisRehearsal`: production deployer → fund/build → atomic timelock activation → 14 days → farm finalisation → post-genesis buyback. |
| All accepted acquisitions and earned claims reconcile | Pass | Rehearsal assertions: 2,800 accepted = 2,800 terminal = units; player ETH = proceeds + GRAIL proceeds + settlement fees + refunds; claimed + dust = 25M. |
| Frontend distinguishes ETH backing from speculative ENGINE value | Pass | Board shows backing vs notional and expected backing per pull; ENGINE card carries the disclosure that ENGINE is not backed by and gives no claim on any game ETH. |
| Tested controller/collection extension path | Pass | `Extension.t.sol`: successor controller takes listings in place (blocked while a request is unresolved), new ERC-721 prize (ENGINE Pack), wind-down after retirement. |
| Reproducible Base fork deployments | Pass | `BaseDeployFork.t.sol` (pinned block 53,000,000, canonical PoolManager, real VRF coordinator); `Deploy.s.sol` broadcast to a local anvil fork of Base with postflight checks (`deployments/fork-base-53000000/`). |
| Mainnet activation and emergency runbooks | Pass | `docs/RUNBOOK.md`. |
| Documented admin authority and external dependencies | Pass | `docs/ADMIN.md`. |
| No unresolved critical security or solvency failures | Pass, with limits | No known critical issue. Slither triaged (`evidence/slither.md`). Bankroll: `docs/M2_RESULTS.md`. Not audited. |

## Findings fixed during integration

- Surplus release was blocked whenever the carried margin was negative or the mint line non-zero,
  which made it practically never callable. Release now depends only on NAV above committed capital,
  free cash, level books, an empty queue and a full board (found by the rehearsal).
- No path existed to turn unawarded listed prizes back into ETH after retirement. Added
  `DrawController.windDown` (anyone, only after `DrawEngine.retire`).
- Buyback bounty was computed on the slice, not on the ETH actually spent when the impact cap stops a
  buy early. Fixed.
- Frontend deadline used the local clock; it now uses chain time.

## Not done / blocked

- Pushing to GitHub and opening the milestone PRs: the remote returned 403 (no GitHub access for
  this repository from this session). All work is committed locally on
  `claude/dreamy-allen-twdsex-m1`, `-m2` and `claude/dreamy-allen-twdsex`.
- Base Sepolia rehearsal with a real VRF fulfilment (no authorised testnet wallet or subscription).
- Independent audit and legal review.
- Token Works' Base recipient address (must come from Token Works).
