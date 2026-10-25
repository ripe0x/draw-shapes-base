# Base mainnet deployment procedure (prepared, not executed)

Nothing in this repository has been broadcast to Base mainnet.

Each step below names its command and the check that must pass before the next step. `Deploy.s.sol`
refuses chain 8453 unless `DRAW_SHAPES_MAINNET_CONFIRM` is set to the exact phrase *"I have the audit,
legal review and verified addresses"*, and it rejects any testnet allocation on mainnet.

## 0. Gates (all required)

- [ ] Independent security audit completed and findings resolved.
- [ ] Legal review of paid chance-based play, referral payments and ENGINE.
- [ ] Token Works has confirmed its Base recipient address in writing.
- [ ] Base Sepolia rehearsal completed with real VRF (`evidence/testnet/BASE_SEPOLIA.md`).
- [ ] Owner approval of the fee split (adopted: 3.5 / 0.5 / 3) and of the opening GRAIL funding (+0.501 ETH, recommended).

## 1. Inputs (`script/config/base.json`)

| Key | Value | Status |
| --- | --- | --- |
| `poolManager` | `0x498581fF718922c3f8e6A244956aF099B2652b2b` (Uniswap v4, Base) | verified on chain |
| `vrfCoordinator` | `0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634` (VRF v2.5, Base) | verified on chain |
| `vrfKeyHash` | `0x00b81b5a…3ccab` (2 gwei lane) | verified on chain |
| `vrfSubscriptionId` | created by the admin Safe (step 2) | **placeholder 0** |
| `creator` | Shapes fee recipient and ENGINE operator (0.25 %) | **placeholder** |
| `tokenWorks` | Token Works' confirmed Base address | **placeholder; requires Token Works** |
| `dev` | development settlement-fee recipient | **placeholder** |
| `adminSafe` | Safe, threshold ≥ 2; timelock proposer and executor | **placeholder** |
| `guardian` | fast-pause multisig (separate signers from the admin Safe where possible) | **placeholder** |
| `keeper` | Treasury POL keeper EOA (hot key, gas only) | **placeholder** |
| `timelockDelay` | 172800 (48 h) | set |
| `maintenanceFloat` | 0.05 ETH | set |

The zero placeholders make `Deployer._requireConfig` revert. Run the read-only preflight until it passes
every check:

```
RPC_URL=<base rpc> DEPLOYER=<deployer address> TOKEN_WORKS_CONFIRMED=1 node web/scripts/mainnet-preflight.mjs
```

The preflight checks:
- the chain;
- the placeholders;
- that the admin Safe is a contract with threshold ≥ 2, and that the guardian is a contract;
- that the admin Safe, guardian and keeper are distinct;
- the VRF subscription: exists, is owned by the admin Safe, and holds at least 0.02 ETH;
- the key hash and the coordinator gas limit;
- the block time (the 1,800-block VRF word deadline assumes 2 s blocks);
- the 48 h delay;
- the deployer balance.

## 2. VRF subscription (admin Safe)

1. Call `createSubscription()` on the coordinator from the Safe. Record the id in `base.json`.
2. Call `fundSubscriptionWithNative(id)` with 0.02–0.05 ETH from the operations float.

Purchasers fund every request after launch (`DrawEngine.vrfFeeFor`); the float only covers the start.

## 3. Deploy (deployer EOA, hardware wallet or encrypted keystore)

```
DRAW_SHAPES_MAINNET_CONFIRM="I have the audit, legal review and verified addresses" \
forge script script/Deploy.s.sol --sig "run(string)" base --rpc-url $BASE_RPC_URL \
  --broadcast --slow --verify --etherscan-api-key $BASESCAN_API_KEY --ledger   # or --keystore
```

The deployment:
- deploys Shapes v1 and Base Draw Packs with the Base presentation and metadata copy;
- deploys the engine, controller, GRAIL vault, ENGINE (35M), farm, hook (CREATE2-mined address), liquidity
  launcher, treasury, buyback and Lens;
- funds the opening allocation (pool 2.2, reserve 0.5, maintenance 0.05, market 2.0 to the timelock);
- builds the 100-item board with acquisitions closed;
- proposes the timelock as governance everywhere.

`_postflight` then checks:
- suppliers;
- not live;
- the governance hand-off;
- the board, with backing equal to 1.65 ETH;
- supply and token balances;
- fee and hook recipients;
- the escrowed liquidity.

Outputs: `deployments/8453.json` and `deployments/8453-activation.json`.

**Verification.** `--verify` submits every contract to Basescan. Afterwards, check that each address in
`deployments/8453.json` shows verified source. If verification failed, resubmit with
`forge verify-contract <address> <Contract> --chain base --watch`, using the constructor arguments recorded
in `broadcast/Deploy.s.sol/8453/run-latest.json`.

## 4. Before activation

1. Add the engine as a VRF consumer from the Safe: `addConsumer(id, engine)`.
2. Opening GRAIL, if approved: `GrailVault.fundGrail{value: 0.501 ether}()`, then `GrailVault.step()`
   (anyone). Check that `Lens.grail().items.length == 1` and that the GRAIL is listed.
3. Verify ownership and addresses (section 8).
4. Generate the activation Safe files:
   `node web/scripts/safe-batch.mjs activation 8453` writes `deployments/8453-safe-activation-{schedule,execute}.json`
   for the Safe Transaction Builder.

## 5. Activation (timelock, 48 h)

1. The Safe imports and signs `8453-safe-activation-schedule.json`. This publicly schedules the atomic batch:
   - accept governance;
   - wire the liquidity launcher;
   - open the ETH/ENGINE pool at 2e-7 ETH per ENGINE with 2 ETH and 10M ENGINE;
   - activate the game (genesis epoch 0 starts).
2. Wait 48 h. Confirm `TimelockController.isOperationReady(<operation id>)`; the generator prints the id.
3. The Safe signs `8453-safe-activation-execute.json`. If it reverts, nothing is live; fix it with a new
   scheduled batch. Never activate parts separately.
4. Immediately: start both keepers (section 6) and the frontend with `VITE_NETWORK=base` and
   `web/src/deployment.base.json`.
5. Within 2 days, schedule the surplus sink for genesis end. Take `ledgerOrigin` from
   `DrawEngine.ledgerOrigin()`, then run `node web/scripts/safe-batch.mjs surplus-sink 8453 <ledgerOrigin>`.
   Sign the schedule file now and execute it 48 h later.

## 6. Keepers and monitoring

Run two keepers on independent hosts and RPC providers. Use `ops/keeper/keeper.env.example` with
`ops/keeper/draw-shapes-keeper.service` or `ops/keeper/Dockerfile`. Set `POL_KEEPER=1` only on the
`Treasury.keeper` key.

Point uptime monitoring at `/health` on both, and route alerts to the team (`ops/monitoring/alerts.md`).

`settle` refunds the caller's gas at basefee plus a 0.00001 ETH tip from maintenance, so any third party can
also keep the game live.

## 7. Genesis and after

| When | Action |
| --- | --- |
| Each epoch end (24 h) | The epoch becomes claimable once every acquisition accepted in it has settled. Players claim in the app. |
| Day 14 | The keeper releases realised surplus to the buyback (after restoring maintenance to 0.05 ETH), runs `buyAndBurn` hourly in ≤ 0.05 ETH slices under a 3 % impact cap, and calls `GenesisFarm.retireUnearned()` once all 14 epochs are final. |
| Ongoing | The treasury routes trading fees: reserve, then the GRAIL fund (100 % while none is live), then POL (the keeper calls `deployPol` daily). |

## 8. Address and ownership checklist (after deployment, before activation)

- [ ] Every contract in `deployments/8453.json` is verified on Basescan and matches this commit.
- [ ] `engine.pendingGovernance`, `vault.pendingGovernance`, `controller.pendingGovernance` and
  `hook.pendingGovernance` equal the timelock. The current governance is the deployer, which only
  proposed the hand-off.
- [ ] Timelock proposer and executor = admin Safe only, min delay 172800, no other admin.
- [ ] `ProtocolLiquidity.governance` = timelock, and `Treasury.governance` = timelock. Liquidity and
  treasury governance were set at construction.
- [ ] `engine.guardian`, `vault.guardian`, `controller.guardian` and `buyback.guardian` = guardian multisig.
- [ ] `engine.tokenWorksRecipient` = Token Works' confirmed address; `engine.devRecipient` = development.
- [ ] `hook.operator` = creator; `hook.treasury` = treasury; the fee is 200 bps with a 25 bps operator share;
  fee exemptions cover only liquidity, buyback and treasury.
- [ ] `Shapes.feeRecipient` = creator. `Shapes.admin` is the deployer after deployment: either
  `transferAdmin(adminSafe)` or `lockPresentation()` (which freezes renderer and metadata copy). Base Draw
  Packs' admin is the creator. These admins control only presentation and the mint fee recipient,
  never backing, prizes or game state.
- [ ] Token balances: liquidity 10,000,000 ENGINE; farm 25,000,000; total supply 35,000,000; deployer 0.
- [ ] `controller.listedCount() == 100`, `backing == 1.65 ETH`, `cash == 0.41 ETH`, `maintenance == 0.05 ETH`;
  `treasury.reserve == 0.5 ETH`; timelock balance 2 ETH.
- [ ] VRF subscription consumers = [engine]; owner = admin Safe.
- [ ] After activation and the Shapes admin transfer, the deployer EOA holds no role anywhere.

## 9. Emergency

See `docs/RUNBOOK.md` section 6.
- **Guardian pauses:** acquisitions, listing, GRAIL steps and buybacks. Settlement, delivery, refunds and
  claims always continue.
- **Every policy change** goes through the 48 h timelock.
- **No role** can withdraw escrow, refunds, fee credits, prizes or the GRAIL fund.
