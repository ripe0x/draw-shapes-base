# Monitoring and alert rules

The keeper evaluates these every tick, posts them to `ALERT_WEBHOOK` (once per condition per 30 min)
and serves `GET /health` (HTTP 503 when any alert is active or the last tick is older than 5 min).
Point an external uptime monitor at `/health` of **both** keepers, so a dead keeper alerts too.

| Alert | Condition | First response |
| --- | --- | --- |
| `unsettled` | engine `unsettledAcquisitionCount` > 100 | Check VRF fulfilment (Chainlink status, subscription balance); run `settle` |
| `head-stall` | the same head acquisition unprocessed for 10 min while acquisitions are pending | Check VRF; `processAcquisitions(50)` |
| `queue-stall` | replacements queued for 15 min | Check pool cash; `Treasury.backstop()`; restock with `settle` |
| `board-depth` | selectable listings < 70 % of the board | Settle; if cash is short, backstop; if it persists, guardian pauses pulls |
| `cash` | pool cash < 0.15 ETH | Backstop from the reserve; watch the replacement queue |
| `vrf` | VRF subscription native balance < 0.01 ETH | Purchasers fund it per batch; top it up from the ops float if traffic has been near zero |
| `step-due` | `GrailVault.stepDue()` true for 15 min | Run `GrailVault.step()`; check the vault is not paused |
| `settle-stall` | work pending and no successful settle for 15 min | Keeper liveness: check both keepers, RPC, gas price cap |
| `refund-rate` | > 5 % of acquisitions resolved in the last ~1 h were refunded (min 20) | Check keeper cadence and board depth; consider pausing pulls |

Also watch outside the keeper: guardian / admin Safe transactions (any `ParamSet` event), timelock
`CallScheduled` events (public 48 h notice), `HarvestShortfall` on the controller, and the ETH/ENGINE
pool's ETH side (buybacks pause if it falls below ~0.34 ETH; see docs/LAUNCH_CONFIG.md).
