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

## 5. Keepers (permissionless; run two)

Daemon: `web/scripts/keeper.mjs` (library `keeper-lib.mjs`). Production configuration:
`ops/keeper/keeper.env.example`, `ops/keeper/draw-shapes-keeper.service` or `ops/keeper/Dockerfile`.
Alert rules: `ops/monitoring/alerts.md`.

Start:
`RPC_URLS=… KEEPER_KEY=… DEPLOYMENT=deployments/8453.json HEALTH_PORT=9464 node web/scripts/keeper.mjs`.

Recovery after any outage: start the keeper. It processes, books, restocks and steps everything due in its
first pass, and all calls are idempotent.

Testnet: `script/testnet/sepolia.sh` runs the whole Base Sepolia deployment and scenario suite. Mainnet:
`docs/MAINNET_DEPLOYMENT.md`.

| Task | Call | Cadence |
| --- | --- | --- |
| Settle and restock | `DrawController.settle(50)` | every block with new processed acquisitions; at least every 5 minutes |
| GRAIL | `GrailVault.step()` when `stepDue()` (true for a pending mint, relist, harvest **or decay**; never stays true when nothing can change) | every few minutes |
| Trading fees | `EngineHook.distribute()` | hourly |
| VRF | none: purchasers fund the subscription at purchase (`DrawEngine.vrfFeeFor`); watch `Lens.vrf()` (collected vs subscription balance) | daily |
| Buyback | `Buyback.buyAndBurn()` (anyone; bounty ≤ 0.5 % of ETH spent, capped at 0.00005 ETH; reverts below 0.005 ETH) | hourly after genesis |
| POL | `Treasury.deployPol(minSqrtPrice)` (keeper) | daily, price limit 3 % below spot |
| Backstop | `Treasury.backstop()` when restock waits | on alert |
| Farm | `GenesisFarm.retireUnearned()` | once after day 14 resolves |

Run **two independent keepers** (different hosts and RPC providers); `settle` refunds its gas plus a
0.00001 ETH tip from maintenance whenever it lists, so any third party can also keep the game live
at no cost to itself. Calls are idempotent (re-running settle / step / process is a no-op).

Alerts: engine `unsettledAcquisitionCount` > 100 or head pending > 10 min; controller
`queueLength() > 0` for > 15 min; **selectable ordinary listings < 70** (`Lens.game().activeListings`);
no `settle` transaction for 15 min; `cash` < 0.15 ETH; VRF subscription < 0.01 ETH; any
`AcquisitionRefundedSlippage` spike; `HarvestShortfall` event; `GrailVault.stepDue()` true for > 15 min.

### Block time and the VRF word deadline

The engine's word deadline is counted in blocks: `selectionTimeoutBlocks` 1,800, which is 1 h at Base
mainnet's 2 s blocks (engine maximum 7,200). Base Sepolia already produces blocks every 0.2 s, where 1,800 blocks is
6 minutes. The first live Sepolia word arrived 1,808 blocks after the request, just after the deadline, so that pull was refunded.
That delay was not oracle latency (next section).

If Base mainnet's block time changes, governance must reset the window to about 1 h of blocks, within the
7,200 maximum, through `DrawEngine.setVrfConfig`. That call needs the engine idle:
1. The guardian pauses acquisitions.
2. Keepers settle until `unsettledAcquisitionCount == 0`.
3. The timelock executes the new window.
4. Unpause.

`mainnet-preflight.mjs` checks the block time before deployment.

### VRF subscription balance: the node checks it at the lane's MAX gas price

Found live on Base Sepolia, and it matches Chainlink's documented "Max Cost" minimum balance
(docs.chain.link/vrf/v2-5/billing). Below that minimum, requests stay pending for up to 24 h. A Chainlink node fulfils a request only once the subscription's native balance
covers the fulfilment priced at the key lane's **maximum** gas price, times (1 + native premium). The
current gas price does not matter for this check. Until then the request just waits. Our words were late
only for this reason; another consumer on the same lane was served in 19 blocks.

| Request | Fulfilment gas | Needed at 30 gwei × 1.6 | Subscription | Outcome |
| --- | --- | --- | --- | --- |
| Single pull (in time) | 698k | 0.034 ETH | 0.030 → topped up to 0.045 | waited, then fulfilled about 1 min after the top-up |
| Ten pulls (in time) | about 2.5M | about 0.12 ETH | 0.045 | waited until the word was late (7,205 blocks), when the callback costs 256k (0.012 ETH) and passes |

The lane max is a ceiling, not the price paid. Actual Base Sepolia gas was 0.006 gwei, so the charge itself is at the real gas price: 0.0000077 ETH and 0.0000026 ETH for those two. The balance is
a standing float that is not spent. Purchaser fees top it up on every request, but they never create it.

| Network | Lane max | Premium | Worst case (2.5M callback + 0.2M verification) | Keep at least |
| --- | --- | --- | --- | --- |
| Base (`0x00b81b5a…`) | 2 gwei | 60 % | 0.0086 ETH | **0.02 ETH** (keeper `VRF_MIN_ETH` default, preflight) |
| Base Sepolia (`0x9e1344a1…`) | 30 gwei | 60 % | 0.130 ETH | **0.25 ETH** |

If mainnet basefee rises above the lane's 2 gwei cap, words wait until it falls, and requests past the
deadline refund. That is the trade-off for the cheaper lane. The 30 gwei lane (`0xdc2f8767…`) would need a
0.2+ ETH float.

### Keeper outage: what happens and how to recover (sim/results/grail-outage.md, KeeperOutage.t.sol)

Pulls keep settling inside the VRF callback during an outage; only booking, restocking and GRAIL
steps stop, so the board drains. Escrow and committed backing are never at risk.

| Outage at 1,500 pulls/day | Board | Refunded (fee + settlement returned) | Purchases reverted (empty board) |
| --- | --- | --- | --- |
| 15 min / 1 h | ≥ 29 of 100 | ≤ 0.24 % | 0 |
| 6 h | down to ~2 | ~3 % | 0 |
| 24 h | empty | ~7 % | ~7 % |

Recovery: any account calls `DrawController.settle(50)` repeatedly (3–9 calls, ≈ 0.0004–0.017 ETH
of gas at 0.002–0.1 gwei, refunded from maintenance) until `queueLength() == 0` and the board is
full, then `GrailVault.step()` if `stepDue()`. No pause is needed; pause acquisitions only if
cash cannot restock and the reserve is spent.

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
