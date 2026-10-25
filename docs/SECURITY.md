# Security and threat model

Automated tests are not an audit. An independent audit of every contract in `src/` and legal
review of paid chance-based play, the referral payments and ENGINE are prerequisites for public
mainnet deployment.

## Assets and who must not be able to take them

| Asset | Where | Must hold |
| --- | --- | --- |
| Player escrow (acquisition + settlement fee) | `DrawEngine` | Released only to a depositor (on verified delivery) and fee recipients, or back to the purchaser as a refund credit. `balance ≥ liabilities()` (invariant-tested). |
| Prize NFTs and their ETH backing | `DrawEngine` (listed), controller (held), Shapes/Draw Packs (ETH) | A listed NFT leaves only to a purchaser on selection, or to its depositor by withdrawal / refund recovery. Backing is redeemable only by the NFT holder at Shapes. |
| Ordinary pool cash | `DrawController` | Spent only on Shape mints, keeper refunds (maintenance), surplus release above committed capital after the maintenance floor. VRF is funded by purchasers' separate VRF fee, never from pool cash. |
| GRAIL fund | `GrailVault` | Spent only on GRAIL backing and its mint fee. |
| Treasury reserve, POL share | `Treasury` | Leaves only into the controller (backstop), the GRAIL vault, or the locked LP position. No withdrawal function. |
| Protocol liquidity | `ProtocolLiquidity` | No remove-liquidity function exists. |
| Farm allocation and earned rewards | `GenesisFarm` | Only claims (by earners) and the one-time burn of epochs that earned nothing. No owner. |
| ENGINE supply | `EngineToken` | Fixed at construction; no mint, no owner. |

## Trust and authority

See docs/ADMIN.md. Summary: the timelock (admin Safe, 48 h) holds bounded policy powers; the
guardian can only pause new exposure (acquisitions, listing, GRAIL steps, buybacks); no contract
is upgradeable; immutable guarantees (supply, earned rewards, escrow) cannot be changed by any role.
Residual trust in governance: it can add an engine supplier, set fee policy and splits within hard
caps, change the mix and GRAIL parameters, point the controller's surplus sink, and list external
prizes. A malicious timelock could, for example, add a supplier that lists worthless NFTs at
attractive notionals; the 48 h delay is the defence and every such call is public in advance.

## Threats and mitigations

| Threat | Mitigation | Evidence |
| --- | --- | --- |
| Rerolling or selectively settling an unfavourable outcome | VRF word fixed at callback; ordered processing by sequence; duplicate callbacks ignored; no caller choice of order; bonus weight derived from the same word | `Engine.t.sol::test_duplicateAndForeignCallbacks`, `test_concurrent60_outOfOrder` |
| Inventory front-running a request | FWAClone's staging + request-time reservation retained; withdraw/reprice locked while unsettled; optional exact inventory version; fee and value guards | `test_stagedListingsReservedByLaterRequest`, `test_inventoryVersionGuard` |
| Board shifting between request and settlement | FWA slippage refund (10 % positive, purchaser-chosen negative); refunds include the settlement fee and earn no units or referral | `test_slippageRefund`, `test_expiryRefundsFeeAndSettlementFee_noUnits` |
| VRF never arrives / arrives late | Per-batch word deadline (1,800 blocks); expiry refunds; late words classified `TimedOut` | `test_expiry…`, `test_lateWordTimesOut` |
| Malicious prize collection blocks the queue | Delivery via bounded self-call; failure quarantines the NFT; anyone may retry; after 7 days anyone may convert to the purchaser's refund | `test_deliveryFailure_*`, `Game.t.sol::test_externalPrize_deliveryFailure…` |
| Callback gas griefing | Callback caches words first; fast path is isolated per item with a fixed stipend; failures leave items `Ready` | Base fork callback test |
| Reentrancy | Solady `nonReentrant` on all state-changing entry points that call out; transfers after effects; Shapes/Packs mint to the controller with `onERC721Received` restricted to known senders | code review |
| Treasury / controller drained by keepers | Keeper refunds only after a settle that listed items, capped by maintenance and `(gas + 30k) × basefee + tip (≤ 0.001 ETH)` | `DrawController._refundKeeper` |
| Surplus release starving restocking | Only NAV above `capitalTarget`, only from cash above `cashFloor`, only with the books level, an empty queue and a full board, only after the sink is set by governance | `test_surplusReleaseOnlyAboveCapitalAndFullBoard`, rehearsal |
| Buyback sandwiching | Slices ≤ 0.05 ETH, 1 h spacing, 3 % price-impact cap via `sqrtPriceLimitX96`, attackers pay the 2 % hook fee on both legs | `Treasury.t.sol::test_buybackWaitsForGenesisEnd…` |
| POL addition sandwiching | Keeper/governance only, caller-supplied price limit | `test_polDeploysIntoLockedPosition` |
| Hook pool squatting | Only `ProtocolLiquidity` may initialise, once, ETH/ENGINE with LP fee 0 | `Market.t.sol::test_onlyLauncherInitialisesOnce` |
| Farm double claims, claiming pending epochs, issuance after genesis | Per (epoch, purchaser) flag; `accepted == resolved` gate; no allocation for epoch ≥ 14; token has no mint | `Farm.t.sol` |
| Wash farming (self-pulls) | Accepted by design: every unit is a real paid pull with real expected loss (~0.0024 ETH) and real creator mint fees | docs/MARKET.md |
| Self-referral via a second wallet | Cannot be prevented; worth 0.5 % of the fee. Direct self-referral is routed to development | `test_selfReferralGoesToDev` |
| Alternative ENGINE pools bypassing fees | Accepted; documented and demonstrated | `Bypass.t.sol` |
| Activation partially completing | One timelock `executeBatch`; any failing call reverts all | `GenesisRehearsal.t.sol::test_activationIsAtomic` |
| Wrong recipient addresses | Deploy refuses zero addresses; Token Works address must be verified; mainnet deploy needs an explicit confirmation string | `test_deployFailsWithoutVerifiedTokenWorks`, `Deploy.s.sol` |

## Known limitations and residual risks

- `DrawController` has ~0.1 KB of EIP-170 headroom; any feature must go in a new contract.
- Slippage refunds occur at high concurrency (3 of 50 in a 50-in-flight test); farmers lose gas, not fees.
- GRAIL capture probability and ordinary pricing interact: a listed GRAIL raises every pull's price
  slightly (its notional enters the harmonic mean). This is retained Draw Shapes / FWA behaviour.
- Board composition drifts around the template (band 30 %): e.g. two 0.1 ETH items can be listed
  against a target of one, raising the price (observed 0.015443 vs 0.015070 ETH).
- Keeper liveness: settlement, restocking, GRAIL steps and fee distribution need someone to call
  them. All are permissionless; settle refunds gas from maintenance.
- Chainlink dependency: VRF outage stops new outcomes (requests expire and refund).
- No independent audit has been performed. Slither 0.10.4 was run on `src/` (139 results, triaged in `evidence/slither.md`; no exploitable finding identified).
