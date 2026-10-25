# Base mainnet deployment, activation and emergency runbook

Nothing in this runbook may be executed on Base mainnet before the gates in section 1 are met and
the owner explicitly authorises the broadcast.

## 1. Gates (all required)

1. Independent audit of `src/` with every critical / high finding fixed and re-tested.
2. Legal review: paid chance-based play, referral compensation, ENGINE distribution and marketing copy.
3. Verified addresses in `script/config/base.json`: admin Safe and its signers, guardian, keeper,
   creator, development recipient, **Token Works recipient confirmed by Token Works**.
4. Base Sepolia rehearsal (section 2) completed, including a real VRF fulfilment and its measured cost.
5. `forge test` green on the frozen commit; Base fork tests green (`BASE_RPC_URL=… forge test --match-path "test/fork/*"`).
6. Bankroll and market results reviewed for the chosen parameters (`sim/results/`).
7. VRF subscription created by the admin Safe and funded with ≥ 0.05 ETH (native).

## 2. Base Sepolia rehearsal

1. Fill `script/config/base-sepolia.json` (Sepolia PoolManager and coordinator are pre-filled and verified).
2. Create and fund a VRF v2.5 subscription on Base Sepolia.
3. `forge script script/Deploy.s.sol --sig "run(string)" base-sepolia --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast`
   (needs ~5.3 Sepolia ETH: 2.2 pool, 0.5 reserve, 2 market, maintenance float, gas, 0.01 Shapes genesis).
4. Add the engine (`deployments/84532.json`) as subscription consumer.
5. Schedule and execute the activation batch from `deployments/84532-activation.json` through the Safe.
6. Pull from the frontend (`web/`, `VITE_RPC_URL=<sepolia rpc>`), wait for the real VRF callback,
   record the fulfilment transaction's subscription charge and gas in `evidence/vrf/`.
7. Run keepers for a day; claim epoch 0; trade; distribute fees.

## 3. Mainnet deployment (after authorisation)

```
export BASE_RPC_URL=...
export DRAW_SHAPES_MAINNET_CONFIRM="I have the audit, legal review and verified addresses"
forge script script/Deploy.s.sol --sig "run(string)" base --rpc-url $BASE_RPC_URL --broadcast --verify
```

The broadcaster needs ≈ 5.3 ETH + gas: 0.01 (Shapes genesis), 2.2 (ordinary pool), 0.5 (reserve),
the maintenance float, and 2 ETH sent to the timelock for the market. The script deploys Shapes v1,
Draw Packs, the timelock and all contracts, mines the hook address, funds and builds the 100-item
board with acquisitions closed, proposes the timelock, runs postflight checks (suppliers, not live,
handover pending, 100 listings, 1.65 ETH backing, 35M supply, 25M farm, 10M liquidity tokens, hook
and fee recipients, 2 ETH escrowed) and writes `deployments/8453.json` and
`deployments/8453-activation.json`. The operations budget (0.3 ETH) stays with the ops Safe.

After the script: add the engine as VRF consumer (Safe), verify sources, publish addresses.

## 4. Activation (game and ENGINE together)

1. From the admin Safe, `scheduleBatch` with the targets/values/datas of
   `deployments/8453-activation.json`, salt `"activate"`, delay 48 h.
2. During the delay: re-run postflight reads, confirm the board, confirm the frontend shows
   "Not open yet", publish the activation time.
3. `executeBatch`. In one transaction: governance is accepted on engine, controller, vault and hook;
   the liquidity launcher is pointed at the treasury; the ETH/ENGINE pool opens at 2e-7 ETH per ENGINE
   with 2 ETH and 10M ENGINE locked; the engine activates and genesis epoch 0 starts.
4. If execution reverts, nothing is live (tested). Diagnose, fix by a new scheduled batch; do not
   activate parts separately.
5. Within 2 days: schedule `DrawController.setSurplusSink(buyback, ledgerOrigin + 14 days)`.

## 5. Keepers (permissionless; run at least one)

| Task | Call | Cadence |
| --- | --- | --- |
| Settle and restock | `DrawController.settle(50)` | every block with new processed acquisitions; at least every 5 minutes |
| GRAIL | `GrailVault.step()` when `stepDue()` | every few minutes |
| Trading fees | `EngineHook.distribute()` | hourly |
| VRF | none: purchasers fund the subscription at purchase (`DrawEngine.vrfFeeFor`); watch `Lens.vrf()` (collected vs subscription balance) | daily |
| Buyback | `Buyback.buyAndBurn()` (anyone; bounty ≤ 0.5 % of ETH spent, capped at 0.00005 ETH; reverts below 0.005 ETH) | hourly after genesis |
| POL | `Treasury.deployPol(minSqrtPrice)` (keeper) | daily, price limit 3 % below spot |
| Backstop | `Treasury.backstop()` when restock waits | on alert |
| Farm | `GenesisFarm.retireUnearned()` | once after day 14 resolves |
| Buyback | `Buyback.buyAndBurn()` | hourly after genesis |

Alerts: engine `unsettledAcquisitionCount` > 100 or head pending > 10 min; controller
`queueLength() > 0` for > 15 min; `cash` < 0.15 ETH; VRF subscription < 0.01 ETH; any
`AcquisitionRefundedSlippage` spike; `HarvestShortfall` event.

## 6. Emergencies

| Situation | Action |
| --- | --- |
| Suspected bug in pricing, selection or a prize collection | Guardian: `DrawEngine.setPaused(true)` and `DrawController.setListingPaused(true)`. Settlement, delivery and refunds continue. |
| Chainlink outage | Nothing to do: requests expire after 1,800 blocks and refund. Optionally pause to stop new exposure. |
| Restock cannot keep up | `Treasury.backstop()`; if the reserve is exhausted, pause acquisitions until cash recovers. |
| Market manipulation around buybacks | Guardian: `Buyback.setPaused(true)`. |
| GRAIL logic issue | Guardian: `GrailVault.setPaused(true)` (no mint, relist or reprice; harvest continues). |
| Compromised guardian | Governance replaces it (`setGuardian`) — 48 h; meanwhile the guardian can only pause. |
| Compromised admin Safe | Public 48 h delay on every call; guardian pauses; users can still settle, withdraw refunds and claim. |
| Permanent shutdown | Governance `DrawEngine.retire()`; in-flight acquisitions settle; listed prizes remain redeemable by winners; the controller cannot withdraw listings while acquisitions are open. |
