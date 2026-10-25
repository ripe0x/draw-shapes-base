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

## Prelaunch review: security-sensitive edge cases (this round)

Automated tests, fork rehearsals and Slither (`evidence/slither.md`). **Not an independent audit.**

| Edge case | Finding | Status |
| --- | --- | --- |
| VRF callback under cold storage | A first acquisition needs ~620k gas inside the callback; the fixed 600k stipend failed it and blocked every later callback at the head until a keeper processed it. Liveness only, with no fund risk. | **Fixed.** Each attempt gets all gas above the 60k return reserve, and callback gas is 750k per acquisition. Regression: `BaseSepoliaFork.t.sol` under `FOUNDRY_PROFILE=fork` (isolate). |
| Warm-storage blind spot in tests | Single-transaction Foundry tests keep storage warm and hid the callback issue. | The fork profile runs fork suites isolated. The full suite under `--isolate` passes, apart from two VRF-fee tests whose `vm.fee` does not carry into isolated transactions (a harness limitation). |
| An attempt's failure consuming the callback | An attempt now receives all remaining gas. If it fails, the callback returns using the 60k reserve, and EIP-150 keeps 1/64 back. NFT delivery inside an attempt is capped at 150k and isolated (`DeliveryPending`). | Reviewed. |
| VRF fee quote vs execution basefee | The fee is computed at execution. A rise between quote and execution reverts with `InsufficientPayment`. | The app sends a 25 % margin and the engine refunds the excess to the payer. |
| Keeper refund vs priority fee | `settle` refunds `gas × basefee + tip`. A keeper paying a large priority fee subsidises the difference itself. | The keeper uses a 0.001 gwei priority fee by default; measured net cost was negative (the keeper earned the tip). |
| GRAIL odds on a drained board | The probability cap limits decay only. On a board drained by an outage, a GRAIL's share of the selection weight rises, and it can be won at its notional. The vault then receives ~0.4 ETH rather than ~0.015 ETH. | Accepted: no loss to the vault. Keeper alerts fire on board depth < 70 %. |
| Buyback minimum vs pool depth | A 3 % impact cap with a 0.005 ETH minimum stops buybacks if the pool's ETH side is below ~0.34 ETH. | Operational alert; governance can lower `minSpend`. |
| Testnet allocation reaching mainnet | Scaled allocations would weaken solvency. | `Deploy.s.sol` rejects `testnetAllocation` on chain 8453, and postflight requires the launch board (backing 1.65 ETH). |
| Placeholder recipients | The Token Works address is unknown. | Zero placeholders make `_requireConfig` revert. `mainnet-preflight.mjs` also requires written confirmation. |
| Frontend: unfunded / staged GRAIL shown as winnable | | Fixed: odds are shown only for selectable listings, and funded-but-staged and accumulating states are labelled. |
| Frontend: genesis claim | Claiming every past epoch reverted after the first claim. | Fixed: the app claims only final, unclaimed epochs with a reward. |
| Per-transaction gas cap (EIP-7825, 16,777,216) | Found live on Base Sepolia: `build(40)` needed 26.8M gas before refunds and was rejected by the chain. Anvil does not enforce the cap. A settle or list call over the cap would stall the keeper path. | **Fixed.** `MAX_SETTLE_ITEMS = 20` and `MAX_LIST_PER_CALL = 6`; the deployer builds in chunks; `TxGasCap.t.sol` asserts the worst case (gas used plus refunds) stays under the cap. The live testnet controller predates the constants, so its keeper settles in 20s. |
| VRF word deadline counted in blocks | `selectionTimeoutBlocks` 1,800 is 1 h at Base mainnet's 2 s blocks but 6 min at Base Sepolia's 0.2 s blocks. The first live pull's word arrived after 1,808 blocks and was correctly timed out and refunded (no fund loss). | Testnet widened to 7,200 blocks through the timelock. `mainnet-preflight.mjs` checks the block time; if Base shortens blocks, governance must raise the deadline (max 7,200) via `setVrfConfig`. See `docs/RUNBOOK.md`. |
| RPC log-range limits | The public Base Sepolia RPC rejects `eth_getLogs` over 200 blocks, which silently disabled fulfilment and refund-window detection. | Keeper and runner now scan logs in 200-block chunks; the runner reads engine state as the source of truth. |
| VRF subscription float vs lane max gas price | Found live on Base Sepolia. Chainlink nodes fulfil only once the subscription covers the fulfilment at the key lane's *max* gas price × (1 + premium). Below that, words wait until the deadline passes and the pulls refund. That stalls the game but loses no funds. | The keeper alerts below 0.02 ETH (mainnet, 2 gwei lane: worst case 0.0085 ETH). The preflight derives the floor from the lane on chain. Testnet needs 0.25 ETH. |
