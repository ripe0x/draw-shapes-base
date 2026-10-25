# Slither 0.10.4 static analysis (src/ only)

Command: `slither . --foundry-compile-all --filter-paths "lib/|test/|script/" --exclude-informational --exclude-optimization --exclude naming-convention,solc-version,pragma,low-level-calls,assembly`

139 results. Counts by detector:

| Detector | Impact | Count |
|---|---|---|
| calls-loop | Low | 20 |
| reentrancy-benign | Low | 20 |
| missing-zero-check | Low | 15 |
| timestamp | Low | 12 |
| reentrancy-events | Low | 3 |
| events-access | Low | 2 |
| events-maths | Low | 2 |
| unused-return | Medium | 24 |
| uninitialized-local | Medium | 15 |
| reentrancy-no-eth | Medium | 11 |
| divide-before-multiply | Medium | 5 |
| incorrect-equality | Medium | 2 |
| write-after-write | Medium | 1 |
| reentrancy-eth | High | 5 |
| arbitrary-send-eth | High | 1 |
| uninitialized-state | High | 1 |

## Triage of High and Medium results

| Detector | Finding | Assessment |
|---|---|---|
| arbitrary-send-eth | `acquireBatch` forwards the optional VRF fee to `vrfCoordinator` | False positive: governance-configured Chainlink coordinator, fee is 0 at launch and capped. |
| reentrancy-eth (5) | `settle`, `releaseSurplus`, `_listBatch`, `GrailVault._mint`: state written after calls to Shapes, Draw Packs, the engine and the vault | Every external entry point involved is `nonReentrant`; callees are the project's own contracts and the pinned Shapes/Draw Packs. Shapes and Draw Packs call back only `onERC721Received`, which is `view` on the controller and vault. Unguarded functions reachable by a reentering callee (`fundPool`, `fundGrail`, `fundMaintenance`) only add ETH. No exploitable path found. |
| reentrancy-no-eth (11) | engine `retryNFTDelivery` / `recoverRefundedNFT` self-call; `_listNFT` transferFrom; vault and controller writes after engine calls | Engine self-calls are FWAClone's original design (bounded child frame, outer `nonReentrant`). A hostile prize collection reentering the engine hits the guard; reentering the controller hits its guard. Accepted. |
| uninitialized-state | `DrawController._heldByDenom` | False positive: a mapping populated by `_addItem`. |
| divide-before-multiply (5) | `1e36 / price` weights; farm allocation remainder; Lens odds | Intentional: FWA's integer weight definition; the farm gives the remainder to the last epoch so the sum is exact. |
| incorrect-equality (2) | `amount == 0`, `available == 0` | Intentional zero checks. |
| unused-return (24) | ignored tuple members of view calls and `listNFT`/`withdrawProceeds` returns | Reviewed; ignored values are not needed. |
| uninitialized-local (15) | locals relying on zero defaults | Intentional. |
| write-after-write | `feedReceivable` write-down then reset in `_harvest` | Intentional sequence (shortfall write-down, then transfer to the vault). |

Low-impact results (calls in loops over bounded sets, missing zero checks on governance setters, timestamp comparisons for schedules, benign reentrancy, event ordering) were reviewed and accepted. Static analysis does not replace an audit.
