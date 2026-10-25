# Slither static analysis (src/ only)

Slither 0.11.6 on the current branch (launch fee split, cold-state callback fix, GRAIL repricing
planner). Automated static analysis with manual triage; **this is not an audit.**

Command: `slither . --foundry-compile-all --filter-paths "lib/|test/|script/" --exclude-informational --exclude-optimization --exclude naming-convention,solc-version,pragma,low-level-calls,assembly`

223 results (0.10.4 on the earlier tree reported 139; most of the increase is new detectors: `encode-packed-collision`,
more `divide-before-multiply` and `calls-loop` instances in the generated presentation renderers).

| Detector | Impact | Count |
|---|---|---|
| arbitrary-send-eth | High | 1 |
| encode-packed-collision | High | 11 |
| reentrancy-eth | High | 5 |
| uninitialized-state | High | 1 |
| divide-before-multiply | Medium | 23 |
| incorrect-equality | Medium | 2 |
| reentrancy-no-eth | Medium | 11 |
| uninitialized-local | Medium | 27 |
| unused-return | Medium | 28 |
| write-after-write | Medium | 1 |
| calls-loop | Low | 59 |
| events-access | Low | 2 |
| events-maths | Low | 2 |
| missing-zero-check | Low | 15 |
| reentrancy-benign | Low | 20 |
| reentrancy-events | Low | 3 |
| timestamp | Low | 12 |

## Triage of High and Medium results

| Detector | Location | Assessment |
|---|---|---|
| arbitrary-send-eth | `DrawEngine.acquireBatch` forwards the purchaser's VRF fee to `vrfCoordinator.fundSubscriptionWithNative` | By design. The coordinator is set by governance (timelock) and only while no request is outstanding; the amount is the purchaser's own quoted fee, capped at 0.002 ETH per batch. |
| encode-packed-collision (11) | `BaseShapeRenderer` / `BasePackRenderer` SVG and JSON builders | False positive: `abi.encodePacked` builds output strings that are never hashed, signed or used as keys. The renderers are the v1 sources with colour literals replaced (`Presentation.t.sol`). |
| reentrancy-eth (5) | `DrawController.settle` / `_listBatch` / `releaseSurplus`, `GrailVault._mint` | External calls go only to the engine, Shapes and Draw Packs deployed by the same deployer (fixed at construction) and the governance-set surplus sink; every entry point is `nonReentrant`; invariants I1–I6 (`GameInvariants.t.sol`, 6 × 4,096 calls) hold. `releaseSurplus` sends ETH last, after all writes. |
| uninitialized-state | `DrawController._fill` reads `_rowBackingWei` | False positive: written by `_setMix` in the constructor and on every mix change. |
| divide-before-multiply (23) | renderers (18), `Lens.game` / `Lens.board` (3), `DrawEngine.updatePrice`, `GenesisFarm.allocationOf` | Intentional. The engine's weight is the truncated `1e36 / notional` (FWA), and the Lens and pricing reproduce that truncation exactly so views equal on-chain selection (`ReferenceBoard.t.sol` reconciles to the wei); the farm gives the remainder to the last epoch (no dust); renderer geometry is integer pixel layout from v1. |
| incorrect-equality (2) | `DrawEngine._splitSettlementFee`, `Buyback.buyAndBurn` | Zero checks on amounts the contract computed itself (skip empty transfers); not manipulable balances. |
| unused-return (28) | v4 `PoolManager` deltas, `getSlot0`, engine view tuples | Values needed are read; the rest are tuple members not required. |
| uninitialized-local (27) | loop counters / accumulators starting at zero | False positive (Solidity zero-initialises). |
| reentrancy-no-eth (11) | controller / vault / treasury calls into the engine and Shapes | As reentrancy-eth: trusted fixed counterparties, `nonReentrant` entry points, state finalised before value moves. |
| write-after-write | `DrawController.feedReceivable` | Intentional reset-then-accumulate in harvest. |

Low results (`calls-loop`, `timestamp`, `missing-zero-check`, `reentrancy-benign/events`, `events-*`) were reviewed:
loops call the engine or Shapes with bounded counts (`MAX_SETTLE_ITEMS` 50, `MAX_LIST_PER_CALL` 40, at most 4 GRAILs);
timestamps are used for epochs, buyback spacing and the timelock (minute-level precision is enough); zero checks
apply to governance-only setters behind the 48 h timelock.

No finding was judged exploitable. The raw output is reproducible with the command above.
