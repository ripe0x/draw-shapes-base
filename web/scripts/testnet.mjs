// Base Sepolia end-to-end runner: VRF subscription, production deployment (script/Deploy.s.sol),
// consumer registration, optional launch-funded GRAIL, timelock activation with the real delay, and
// the live scenarios (single pull, batch of ten, real VRF fulfilment, delivery, keeper booking and
// restocking, GRAIL funding / listing / decay, slippage refunds, ENGINE trading and fee routing,
// referral credits, genesis ledger, keeper outage and recovery, two concurrent keepers).
// Every transaction, gas figure and measured cost is written to evidence/testnet/<chainId>-run.json and
// summarised in evidence/testnet/BASE_SEPOLIA.md. Steps are resumable: rerun the same command.
//
//   DEPLOYER_KEY=0x... RPC_URL=https://sepolia.base.org node web/scripts/testnet.mjs
//   (script/testnet/sepolia.sh decrypts the local keystore into the environment of this process only)
//
// FORK=1 runs the identical flow against a local anvil fork of Base Sepolia for rehearsal: VRF words
// are delivered by impersonating the coordinator and the timelock delay is skipped with
// evm_increaseTime. Fork evidence is labelled as such and never mixed with live evidence.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import {
  createPublicClient, createWalletClient, http, parseEther, formatEther, keccak256, encodePacked,
  decodeEventLog, parseAbi, toHex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ops, snapshot, act, health } from "./keeper-lib.mjs";

const ROOT = new URL("../../", import.meta.url).pathname;
const FORK = process.env.FORK === "1";
const RPC = process.env.RPC_URL ?? (FORK ? "http://127.0.0.1:8547" : "https://sepolia.base.org");
const KEY = process.env.DEPLOYER_KEY;
if (!KEY) throw new Error("DEPLOYER_KEY is required (testnet key only)");
const SEED_GRAIL = process.env.SEED_GRAIL !== "0";
// without the 0.5 ETH opening GRAIL, a testnet-only ladder (0.05 -> 0.1 ETH, set through the timelock)
// still exercises GRAIL funding, minting, listing, decay and selection on a faucet-sized budget
const SMALL_GRAIL = !SEED_GRAIL && process.env.SMALL_GRAIL !== "0";
const CONFIG = process.env.CONFIG ?? "base-sepolia";
const coordinatorAbi = parseAbi([
  "function createSubscription() returns (uint256)",
  "function fundSubscriptionWithNative(uint256 subId) payable",
  "function addConsumer(uint256 subId, address consumer)",
  "function getSubscription(uint256 subId) view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] consumers)",
  "event SubscriptionCreated(uint256 indexed subId, address owner)",
  "event RandomWordsFulfilled(uint256 indexed requestId, uint256 outputSeed, uint256 indexed subId, uint96 payment, bool nativePayment, bool success, bool onlyPremium)",
]);

const base = JSON.parse(readFileSync(`${ROOT}script/config/${CONFIG}.json`));
const pub0 = createPublicClient({ transport: http(RPC) });
const chainId = await pub0.getChainId();
if (chainId === 8453) throw new Error("refusing to run on Base mainnet");
const chain = { id: chainId, name: "base-sepolia", nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } };
const pub = createPublicClient({ chain, transport: http(RPC) });
const deployer = privateKeyToAccount(KEY);
// helper accounts derived from the deployer key (deterministic, never printed or stored)
const derive = (tag) => privateKeyToAccount(keccak256(encodePacked(["bytes32", "string"], [KEY, tag])));
const player = derive("draw-shapes/testnet/player");
const referrer = derive("draw-shapes/testnet/referrer");
const keeper2 = derive("draw-shapes/testnet/keeper-2");
const wallet = (acct) => createWalletClient({ chain, transport: http(RPC), account: acct });

const evDir = `${ROOT}evidence/testnet`;
mkdirSync(evDir, { recursive: true });
const statePath = `${evDir}/${chainId}${FORK ? "-fork" : ""}-run.json`;
const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath)) : { chainId, fork: FORK, rpc: FORK ? "local anvil fork of Base Sepolia" : RPC, steps: {}, txs: [] };
// a resumed run must match the chain: a restarted fork (or a different network) starts over
if (state.steps["vrf-subscription"]?.done) {
  const ok = await pub.readContract({ address: base.vrfCoordinator, abi: parseAbi(["function getSubscription(uint256) view returns (uint96,uint96,uint64,address,address[])"]),
    functionName: "getSubscription", args: [BigInt(state.steps["vrf-subscription"].subId)] }).then(() => true).catch(() => false);
  if (!ok) { console.log("saved state does not match this chain; starting over"); state.steps = {}; state.txs = []; }
}
const save = () => writeFileSync(statePath, JSON.stringify(state, (_, v) => (typeof v === "bigint" ? v.toString() : v), 2));
const say = (...a) => console.log(new Date().toISOString(), ...a);

async function tx(label, acct, { address, abi, functionName, args = [], value = 0n }) {
  const { request } = await pub.simulateContract({ address, abi, functionName, args, value, account: acct });
  // a 30 % margin over the estimate: settle, step and the VRF callback size their work by gasleft()
  const gas = await pub.estimateContractGas({ address, abi, functionName, args, value, account: acct });
  const hash = await wallet(acct).writeContract({ ...request, gas: (gas * 13n) / 10n });
  const r = await pub.waitForTransactionReceipt({ hash, timeout: 300_000 });
  const rec = { label, hash, from: acct.address, block: Number(r.blockNumber), status: r.status, gasUsed: r.gasUsed,
    effectiveGasPrice: r.effectiveGasPrice, costWei: r.gasUsed * r.effectiveGasPrice, valueWei: value };
  state.txs.push(rec);
  save();
  say(label, hash, r.status, `gas ${r.gasUsed}`);
  if (r.status !== "success") throw new Error(`${label} reverted`);
  return r;
}
const sendEth = async (label, to, value) => {
  const hash = await wallet(deployer).sendTransaction({ to, value });
  const r = await pub.waitForTransactionReceipt({ hash });
  state.txs.push({ label, hash, from: deployer.address, to, block: Number(r.blockNumber), status: r.status, gasUsed: r.gasUsed, valueWei: value });
  save();
};
const rd = (address, abi, functionName, args = []) => pub.readContract({ address, abi, functionName, args });
async function step(name, fn) {
  if (state.steps[name]?.done) return state.steps[name];
  if (process.env.STOP_BEFORE === name) { say("stopping before", name); save(); process.exit(0); }
  say("==>", name);
  const out = (await fn()) ?? {};
  state.steps[name] = { done: true, at: new Date().toISOString(), ...out };
  save();
  return state.steps[name];
}
const rpc = (method, params) => pub.request({ method, params });

// ------------------------------------------------------------------ 0. preflight
await step("preflight", async () => {
  // fork rehearsal of a specific budget: FORK_BALANCE=1.495 sets the deployer's balance
  if (FORK && process.env.FORK_BALANCE) await rpc("anvil_setBalance", [deployer.address, toHex(parseEther(process.env.FORK_BALANCE))]);
  const bal = await pub.getBalance({ address: deployer.address });
  const need = parseEther(SEED_GRAIL ? "2.0" : "1.45");
  say("deployer", deployer.address, "balance", formatEther(bal), "ETH; needs about", formatEther(need));
  if (bal < need) throw new Error(`deployer ${deployer.address} holds ${formatEther(bal)} ETH; fund it with ${formatEther(need - bal)} more Base Sepolia ETH`);
  const code = await pub.getCode({ address: base.vrfCoordinator });
  if (!code || code === "0x") throw new Error("VRF coordinator missing");
  return { deployer: deployer.address, player: player.address, referrer: referrer.address, keeper2: keeper2.address, balanceWei: bal };
});

// ------------------------------------------------------------------ 1. VRF subscription
const vrf = await step("vrf-subscription", async () => {
  const r = await tx("vrf.createSubscription", deployer, { address: base.vrfCoordinator, abi: coordinatorAbi, functionName: "createSubscription" });
  const log = r.logs.map((l) => { try { return decodeEventLog({ abi: coordinatorAbi, ...l }); } catch { return null; } }).find((x) => x?.eventName === "SubscriptionCreated");
  const subId = log.args.subId;
  await tx("vrf.fundSubscriptionWithNative", deployer, { address: base.vrfCoordinator, abi: coordinatorAbi, functionName: "fundSubscriptionWithNative", args: [subId], value: parseEther("0.03") });
  return { subId: subId.toString() };
});

// ------------------------------------------------------------------ 2. deployment (production deployer)
const liveCfg = `${CONFIG}-live${FORK ? "-fork" : ""}`;
const dep = await step("deploy", async () => {
  const cfg = {
    ...base,
    _comment: "Generated by web/scripts/testnet.mjs. Testnet roles are the testnet deployer EOA; never use for mainnet.",
    vrfSubscriptionId: vrf.subId, // 256-bit: keep it an exact decimal string (parseJsonUint accepts it)
    creator: deployer.address, tokenWorks: deployer.address, dev: deployer.address,
    adminSafe: deployer.address, guardian: deployer.address, keeper: deployer.address,
  };
  writeFileSync(`${ROOT}script/config/${liveCfg}.json`, JSON.stringify(cfg, null, 2));
  const args = ["script", "script/Deploy.s.sol", "--sig", "run(string)", liveCfg, "--rpc-url", RPC, "--broadcast", "--slow"];
  // live runs sign with the encrypted keystore (the key never appears on a command line); only fork
  // rehearsals with anvil's public test key pass it directly
  if (process.env.KEYSTORE) args.push("--keystore", process.env.KEYSTORE, "--password-file", process.env.KEYSTORE_PASSWORD_FILE);
  else if (FORK) args.push("--private-key", KEY);
  else throw new Error("live deployment needs KEYSTORE and KEYSTORE_PASSWORD_FILE (script/testnet/sepolia.sh)");
  execFileSync(`${process.env.HOME}/.foundry/bin/forge`, args, { cwd: ROOT, stdio: ["ignore", "ignore", "inherit"] });
  const d = JSON.parse(readFileSync(`${ROOT}deployments/${chainId}.json`));
  const batch = JSON.parse(readFileSync(`${ROOT}deployments/${chainId}-activation.json`));
  const run = JSON.parse(readFileSync(`${ROOT}broadcast/Deploy.s.sol/${chainId}/run-latest.json`));
  let gas = 0n, cost = 0n;
  for (const r of run.receipts) { gas += BigInt(r.gasUsed); cost += BigInt(r.gasUsed) * BigInt(r.effectiveGasPrice); }
  return { ...d, activation: batch, deployTxs: run.receipts.length, deployGas: gas, deployCostWei: cost,
    deployHashes: run.receipts.map((r) => r.transactionHash) };
});
const A = dep;

// ------------------------------------------------------------------ 3. consumer, opening GRAIL
await step("vrf-consumer", async () => {
  await tx("vrf.addConsumer(engine)", deployer, { address: base.vrfCoordinator, abi: coordinatorAbi, functionName: "addConsumer", args: [BigInt(vrf.subId), A.engine] });
  const s = await rd(base.vrfCoordinator, coordinatorAbi, "getSubscription", [BigInt(vrf.subId)]);
  return { consumers: s[4], nativeBalance: s[1] };
});
if (SEED_GRAIL) {
  await step("opening-grail", async () => {
    const target = await rd(A.grailVault, ops.vault, "nextTarget");
    const fee = await rd(A.shapes, ops.shapes, "mintFee");
    await tx("vault.fundGrail(opening GRAIL)", deployer, { address: A.grailVault, abi: ops.vault, functionName: "fundGrail", value: target + fee });
    await tx("vault.step(mint + list opening GRAIL)", deployer, { address: A.grailVault, abi: ops.vault, functionName: "step" });
    const items = await rd(A.grailVault, ops.vault, "items");
    return { backing: items[0].backing, notional: items[0].notional, listingId: items[0].listingId, tokenId: items[0].tokenId };
  });
}

// ------------------------------------------------------------------ 4. timelock activation (real delay)
async function timelock(label, targets, values, datas, salt) {
  const delay = await rd(A.timelock, ops.timelock, "getMinDelay");
  const s = await tx(`timelock.scheduleBatch(${label})`, deployer, { address: A.timelock, abi: ops.timelock, functionName: "scheduleBatch", args: [targets, values, datas, toHex(0, { size: 32 }), salt, delay] });
  const t0 = (await pub.getBlock({ blockNumber: s.blockNumber })).timestamp;
  if (FORK) { await rpc("evm_increaseTime", [toHex(Number(delay) + 1)]); await rpc("evm_mine", []); }
  else {
    say(`waiting ${delay}s of real chain time for the timelock`);
    for (;;) { const b = await pub.getBlock(); if (b.timestamp >= t0 + delay) break; await new Promise((r) => setTimeout(r, 15_000)); }
  }
  const e = await tx(`timelock.executeBatch(${label})`, deployer, { address: A.timelock, abi: ops.timelock, functionName: "executeBatch", args: [targets, values, datas, toHex(0, { size: 32 }), salt] });
  const t1 = (await pub.getBlock({ blockNumber: e.blockNumber })).timestamp;
  return { delay, scheduledAt: t0, executedAt: t1, waitedSec: t1 - t0, timeSkippedOnFork: FORK };
}
await step("activation", async () => {
  const b = A.activation;
  const r = await timelock("activation", b.targets, b.values.map(BigInt), b.datas, keccak256(toHex("draw-shapes/activate")));
  const [activated, launched, gov] = await Promise.all([rd(A.engine, ops.engine, "activated"), rd(A.liquidity, ops.liquidity, "launched"), rd(A.engine, ops.engine, "governance")]);
  if (!activated || !launched || gov.toLowerCase() !== A.timelock.toLowerCase()) throw new Error("activation incomplete");
  return { ...r, activated, launched, governance: gov };
});
// post-activation governance batch through the timelock: the production step that schedules the
// surplus sink for genesis end, plus (testnet only) faster GRAIL decay so repricing shows in a few pulls
await step("post-activation-governance", async () => {
  const { encodeFunctionData } = await import("viem");
  const c = await rd(A.grailVault, ops.vault, "config");
  const cfg = { listBps: c[0], floorBps: c[1], probCapBps: c[2], stepUpSeconds: c[3], stepDownSeconds: c[4], decayWeiPerPull: parseEther("0.002") };
  const origin = await rd(A.engine, ops.engine, "ledgerOrigin");
  const releaseAt = origin + 14n * 86_400n;
  const targets = [A.controller, A.grailVault], values = [0n, 0n];
  const datas = [encodeFunctionData({ abi: ops.controller, functionName: "setSurplusSink", args: [A.buyback, releaseAt] }),
    encodeFunctionData({ abi: ops.vault, functionName: "setConfig", args: [cfg] })];
  if (SMALL_GRAIL) { targets.push(A.grailVault); values.push(0n); datas.push(encodeFunctionData({ abi: ops.vault, functionName: "setLadder", args: [[1, 2]] })); }
  const r = await timelock(`setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only)${SMALL_GRAIL ? " + vault.setLadder(0.05, 0.1 ETH, testnet only)" : ""}`,
    targets, values, datas, keccak256(toHex("draw-shapes/post-activation")));
  return { ...r, surplusSink: await rd(A.controller, ops.controller, "surplusSink"), surplusReleaseStart: releaseAt };
});

if (SMALL_GRAIL) {
  await step("testnet-grail-funded", async () => {
    const target = await rd(A.grailVault, ops.vault, "nextTarget");
    const fee = await rd(A.shapes, ops.shapes, "mintFee");
    await tx("vault.fundGrail(testnet GRAIL backing + mint fee)", deployer, { address: A.grailVault, abi: ops.vault, functionName: "fundGrail", value: target + fee });
    await tx("vault.step(mint + list GRAIL)", deployer, { address: A.grailVault, abi: ops.vault, functionName: "step" });
    const items = await rd(A.grailVault, ops.vault, "items");
    const g = await rd(A.lens, ops.lens, "grail");
    return { backing: items[0].backing, notional: items[0].notional, listingId: items[0].listingId, tokenId: items[0].tokenId, status: g.status, oddsPpm: g.oddsPpm };
  });
}

// ------------------------------------------------------------------ helpers for pulls
await step("fund-accounts", async () => {
  // the player gets what the deployer can spare (prizes are redeemed between scenarios to recycle ETH)
  const bal = await pub.getBalance({ address: deployer.address });
  const forPlayer = bal - parseEther("0.03");
  if (forPlayer < parseEther("0.2")) throw new Error(`only ${formatEther(bal)} ETH left for scenarios`);
  await sendEth("fund player", player.address, forPlayer > parseEther("0.7") ? parseEther("0.7") : forPlayer);
  await sendEth("fund referrer", referrer.address, parseEther("0.003"));
  await sendEth("fund keeper-2", keeper2.address, parseEther("0.01"));
  return {};
});
const vrfAbiEvents = coordinatorAbi;
async function pull(label, count, { ref = referrer.address, negSlippage = 1000n, payer = player, beneficiary = player.address } = {}) {
  const [fee, sfee, vrfFee, total] = await rd(A.engine, ops.engine, "quoteAcquisitionPrice", [BigInt(count)]);
  const subBefore = await rd(base.vrfCoordinator, coordinatorAbi, "getSubscription", [BigInt(vrf.subId)]);
  const block = await pub.getBlock();
  const r = await tx(label, payer, { address: A.engine, abi: ops.engine, functionName: "acquireBatch",
    args: [beneficiary, ref, BigInt(count), fee, 0n, negSlippage, 2n ** 256n - 1n, block.timestamp + 600n], value: total + vrfFee / 4n });
  const ids = r.logs.map((l) => { try { return decodeEventLog({ abi: ops.engine, ...l }); } catch { return null; } })
    .filter((x) => x?.eventName === "AcquisitionRequested").map((x) => x.args.requestId);
  const requestId = await rd(A.engine, ops.engine, "vrfRequestOf", [ids[0]]);
  return { ids, requestId, quote: { fee, sfee, vrfFee, total }, requestTx: r.transactionHash, requestGas: r.gasUsed, subBefore: subBefore[1] };
}
async function awaitFulfilment(p) {
  let fulfil = null;
  if (FORK) {
    await rpc("anvil_impersonateAccount", [base.vrfCoordinator]);
    await rpc("anvil_setBalance", [base.vrfCoordinator, toHex(parseEther("1"))]);
    for (let i = 0; i < 3; i++) await rpc("evm_mine", []);
    const limit = await rd(A.engine, ops.engine, "callbackGasLimitFor", [BigInt(p.ids.length)]);
    const hash = await pub.request({ method: "eth_sendTransaction", params: [{ from: base.vrfCoordinator, to: A.engine, gas: toHex(limit + 100_000n),
      data: (await import("viem")).encodeFunctionData({ abi: ops.engine, functionName: "rawFulfillRandomWords", args: [p.requestId, [BigInt(keccak256(toHex(p.requestTx)))]] }) }] });
    const r = await pub.waitForTransactionReceipt({ hash });
    fulfil = { hash, gasUsed: r.gasUsed, simulated: true, payment: null, latencySec: 0 };
  } else {
    const t0 = Date.now();
    const ev = coordinatorAbi.find((x) => x.name === "RandomWordsFulfilled");
    const from = (await pub.getBlockNumber()) - 5n;
    for (let i = 0; i < 120 && !fulfil; i++) {
      const logs = await pub.getLogs({ address: base.vrfCoordinator, event: ev, args: { requestId: p.requestId }, fromBlock: from }).catch(() => []);
      if (logs.length) {
        const l = logs[0];
        const r = await pub.getTransactionReceipt({ hash: l.transactionHash });
        fulfil = { hash: l.transactionHash, payment: l.args.payment, success: l.args.success, gasUsed: r.gasUsed, effectiveGasPrice: r.effectiveGasPrice, latencySec: (Date.now() - t0) / 1000 };
      } else await new Promise((r) => setTimeout(r, 5_000));
    }
    if (!fulfil) throw new Error(`no VRF fulfilment for request ${p.requestId} within 10 min`);
  }
  state.txs.push({ label: `vrf fulfilment ${p.requestId}${FORK ? " (fork: coordinator impersonated)" : ""}`, ...fulfil });
  const statuses = [];
  for (const id of p.ids) statuses.push(Number((await rd(A.engine, ops.engine, "acquisitions", [id]))[4]));
  const subAfter = await rd(base.vrfCoordinator, coordinatorAbi, "getSubscription", [BigInt(vrf.subId)]);
  return { fulfil, statuses, subscriptionDelta: BigInt(p.subBefore) + p.quote.vrfFee - subAfter[1] };
}
const ownerAbi = parseAbi(["function ownerOf(uint256) view returns (address)"]);
async function deliveries(ids) {
  const out = [];
  for (const id of ids) {
    const a = await rd(A.engine, ops.engine, "acquisitions", [id]);
    const st = Number(a[4]);
    if (st !== 2) { out.push({ id, status: st }); continue; }
    const l = await rd(A.engine, ops.engine, "listings", [a[3]]);
    const owner = await rd(l[0], ownerAbi, "ownerOf", [l[3]]);
    out.push({ id, status: st, collection: l[0], tokenId: l[3], notional: l[5], deliveredTo: owner, toBeneficiary: owner.toLowerCase() === a[0].toLowerCase() });
  }
  return out;
}
// redeems the player's delivered prizes for their ETH backing (recycles test ETH; also exercises redemption)
async function recycle(ids, label) {
  let returned = 0n, n = 0;
  for (const d of await deliveries(ids)) {
    if (d.status !== 2 || !d.toBeneficiary) continue;
    const owner = await rd(d.collection, ownerAbi, "ownerOf", [d.tokenId]).catch(() => null);
    if (!owner || owner.toLowerCase() !== player.address.toLowerCase()) continue;
    const isShapes = d.collection.toLowerCase() === A.shapes.toLowerCase();
    const before = await pub.getBalance({ address: player.address });
    const r = await tx(`redeem ${isShapes ? "Shape" : "Draw Pack"} #${d.tokenId} (${label})`, player, { address: d.collection, abi: isShapes ? ops.shapes : ops.packs, functionName: "redeem", args: [d.tokenId] });
    returned += (await pub.getBalance({ address: player.address })) - before + r.gasUsed * r.effectiveGasPrice;
    n++;
  }
  return { redeemed: n, ethReturnedWei: returned };
}
const keeperCtx = (acct) => ({ pub, wallet: wallet(acct), account: acct, dep: { ...A, grailVault: A.grailVault }, log: (o) => state.txs.push({ keeper: acct.address, ...o }),
  distributeMinWei: 0n, isPolKeeper: acct.address === deployer.address, thresholds: { unsettled: 100, headStallSec: 600, queueStallSec: 900, boardDepthShare: 0.7,
  cashMinWei: parseEther("0.05"), vrfMinWei: parseEther("0.005"), stepDueStallSec: 900, settleStallSec: 900, refundRate: 0.05 } });
async function keeperTick(acct) {
  const ctx = keeperCtx(acct);
  const before = await pub.getBalance({ address: acct.address });
  const s = await snapshot(ctx);
  const actions = await act(ctx, s);
  const after = await pub.getBalance({ address: acct.address });
  return { actions, alerts: health(ctx, s), netCostWei: before - after };
}

// ------------------------------------------------------------------ 5. scenarios
await step("single-pull", async () => {
  const p = await pull("acquireBatch(1) with referrer", 1);
  const f = await awaitFulfilment(p);
  return { ...p, ...f, deliveries: await deliveries(p.ids) };
});
await step("batch-of-ten", async () => {
  const p = await pull("acquireBatch(10)", 10);
  const f = await awaitFulfilment(p);
  const head = await rd(A.engine, ops.engine, "nextSequenceToProcess");
  return { ...p, ...f, settledInCallback: f.statuses.filter((x) => x !== 1 && x !== 5).length, headAfter: head, deliveries: await deliveries(p.ids) };
});
await step("keeper-booking-restock", async () => {
  const before = await rd(A.lens, ops.lens, "game");
  const k = await keeperTick(deployer);
  const after = await rd(A.lens, ops.lens, "game");
  const delivered = await deliveries(state.steps["batch-of-ten"].ids.map(BigInt));
  return { keeper: k, before: { nextToBook: before.nextToBook, active: before.activeListings, cash: before.cash }, after: { nextToBook: after.nextToBook, active: after.activeListings, cash: after.cash, maintenance: after.maintenance }, deliveries: delivered };
});
await step("redeem-prize-for-backing", async () => {
  // every won Shape or Draw Pack holds its ETH backing: redeem the batch's prizes and measure the ETH returned
  const ids = [...state.steps["single-pull"].ids, ...state.steps["batch-of-ten"].ids].map(BigInt);
  const won = (await deliveries(ids)).filter((d) => d.status === 2);
  const r = await recycle(ids, "batch prizes");
  return { ...r, notionalWei: won.reduce((a, d) => a + BigInt(d.notional), 0n) };
});
await step("grail-decay-and-selection", async () => {
  const g0 = await rd(A.lens, ops.lens, "grail");
  const p = await pull("acquireBatch(5) for GRAIL decay", 5);
  await awaitFulfilment(p);
  state.grailPullIds = p.ids;
  await keeperTick(deployer); // books; vault step runs when stepDue (decay included)
  const due = await rd(A.grailVault, ops.vault, "stepDue");
  if (due) await keeperTick(deployer);
  const g1 = await rd(A.lens, ops.lens, "grail");
  return { before: { items: g0.items, oddsPpm: g0.oddsPpm, status: g0.status, funded: g0.funded, selectable: g0.selectable },
    after: { items: g1.items, oddsPpm: g1.oddsPpm, status: g1.status, funded: g1.funded, selectable: g1.selectable } };
});
await step("slippage-refund-probe", async () => {
  // zero negative tolerance: any price drop before an item is processed refunds it (fee + settlement fee)
  await recycle((state.grailPullIds ?? []).map(BigInt), "GRAIL scenario");
  const p = await pull("acquireBatch(8, maxNegativeSlippage 0)", 8, { negSlippage: 0n });
  const f = await awaitFulfilment(p);
  const refunded = f.statuses.filter((s) => s === 4).length;
  const credit = await rd(A.engine, ops.engine, "acquisitionRefundCredit", [player.address]);
  let withdraw = null;
  if (credit > 0n) withdraw = (await tx("withdrawAcquisitionRefund", player, { address: A.engine, abi: ops.engine, functionName: "withdrawAcquisitionRefund" })).transactionHash;
  await keeperTick(deployer);
  return { ...p, ...f, refunded, refundCreditWei: credit, withdraw };
});
await step("on-behalf-and-referral", async () => {
  const p = await pull("acquireBatch(1) paid by player for referrer", 1, { beneficiary: referrer.address, ref: deployer.address });
  const f = await awaitFulfilment(p);
  await keeperTick(deployer);
  const refCredit = await rd(A.engine, ops.engine, "feeCreditOf", [referrer.address]);
  let w = null;
  if (refCredit > 0n) w = (await tx("withdrawFeeCredit(referrer)", referrer, { address: A.engine, abi: ops.engine, functionName: "withdrawFeeCredit", args: [referrer.address] })).transactionHash;
  return { ...p, ...f, deliveries: await deliveries(p.ids), referrerCreditWei: refCredit, referrerWithdraw: w,
    tokenWorksCreditWei: await rd(A.engine, ops.engine, "feeCreditOf", [deployer.address]) };
});
await step("engine-trading-and-fees", async () => {
  const hash = await wallet(deployer).deployContract({ abi: ops.swapper, bytecode: ops.swapperBytecode, args: [base.poolManager] });
  const rec = await pub.waitForTransactionReceipt({ hash });
  state.txs.push({ label: "deploy Swapper (test router)", hash, gasUsed: rec.gasUsed });
  const swapper = rec.contractAddress;
  const key = await rd(A.liquidity, ops.liquidity, "poolKey");
  const opBefore = await pub.getBalance({ address: deployer.address });
  await tx("swap: buy ENGINE with 0.01 ETH", player, { address: swapper, abi: ops.swapper, functionName: "buy", args: [key], value: parseEther("0.01") });
  const bal = await rd(A.token, ops.token, "balanceOf", [player.address]);
  await tx("approve router", player, { address: A.token, abi: ops.token, functionName: "approve", args: [swapper, bal] });
  await tx("swap: sell half the ENGINE", player, { address: swapper, abi: ops.swapper, functionName: "sell", args: [key, bal / 2n] });
  const [opAcc, trAcc, totalFees, volume] = await Promise.all(["operatorAccrued", "treasuryAccrued", "totalFees", "totalVolume"].map((f) => rd(A.hook, ops.hook, f)));
  const trBefore = await rd(A.treasury, ops.treasury, "totalReceived");
  await tx("hook.distribute", keeper2, { address: A.hook, abi: ops.hook, functionName: "distribute" });
  const trAfter = await rd(A.treasury, ops.treasury, "totalReceived");
  return { swapper, engineBought: bal, hookFeesWei: totalFees, volumeWei: volume, feeBpsOfVolume: Number((totalFees * 10_000n) / volume),
    operatorAccruedWei: opAcc, treasuryAccruedWei: trAcc, treasuryReceivedWei: trAfter - trBefore,
    vaultFundAfter: await rd(A.grailVault, ops.vault, "fund"), polPending: await rd(A.treasury, ops.treasury, "polPending") };
});
await step("genesis-ledger", async () => {
  const day = 0n;
  const [totals, mine, epoch, sched] = await Promise.all([
    rd(A.engine, ops.engine, "dayTotals", [day]), rd(A.engine, ops.engine, "userDay", [day, player.address]),
    rd(A.farm, ops.farm, "currentEpoch"), rd(A.farm, ops.farm, "schedule")]);
  return { epoch, accepted: totals[0], resolved: totals[1], units: totals[2], bonus: totals[3], playerUnits: mine[0], playerBonus: mine[1],
    epoch0ClosesAt: sched[0] + 86_400n, note: "Claims open once epoch 0 has ended and resolved (24 h of real time); rerun to claim." };
});
await step("outage-and-recovery", async () => {
  // keepers stopped: three batches settle in their callbacks, nothing restocks
  const before = await rd(A.lens, ops.lens, "game");
  await recycle(state.steps["slippage-refund-probe"].ids.map(BigInt), "slippage scenario");
  const outIds = [];
  for (let i = 0; i < 3; i++) { const p = await pull(`outage acquireBatch(3) #${i + 1}`, 3); await awaitFulfilment(p); outIds.push(...p.ids); }
  const during = await rd(A.lens, ops.lens, "game");
  const queue = await rd(A.controller, ops.controller, "queueLength");
  // two keepers return at the same time: idempotent, nothing is booked twice
  const [k1, k2] = await Promise.all([keeperTick(deployer), keeperTick(keeper2)]);
  const after = await rd(A.lens, ops.lens, "game");
  return { activeBefore: before.activeListings, activeDuring: during.activeListings, unbookedDuring: during.lastIssued - during.nextToBook + 1n, queueDuring: queue,
    activeAfter: after.activeListings, booked: after.nextToBook > after.lastIssued, keeper1: k1, keeper2: k2 };
});
if (FORK) {
  // fork only: chain time is skipped to reach epoch close and genesis end (never claimed as live evidence)
  await step("fork-time-skip-epoch-0", async () => {
    const closes = BigInt(state.steps["genesis-ledger"].epoch0ClosesAt);
    const now = (await pub.getBlock()).timestamp;
    await rpc("evm_increaseTime", [toHex(Number(closes - now) + 60)]);
    await rpc("evm_mine", []);
    const k = await keeperTick(deployer);
    return { skippedSec: Number(closes - now) + 60, isFinal0: await rd(A.farm, ops.farm, "isFinal", [0n]), keeper: k.actions.map((a) => a.action) };
  });
}
await step("claims", async () => {
  const closes = BigInt(state.steps["genesis-ledger"].epoch0ClosesAt);
  const now = (await pub.getBlock()).timestamp;
  if (now < closes) throw new Error(`epoch 0 closes at ${closes} (in ${closes - now} s); rerun after that to claim`);
  const claimable = await rd(A.farm, ops.farm, "claimable", [player.address]);
  const r = await tx("farm.claim([0])", player, { address: A.farm, abi: ops.farm, functionName: "claim", args: [[0n]] });
  return { claimable, hash: r.transactionHash };
}).catch((e) => say("claims pending:", e.message));

if (FORK) {
  await step("fork-time-skip-genesis-end", async () => {
    const sched = await rd(A.farm, ops.farm, "schedule");
    const now = (await pub.getBlock()).timestamp;
    await rpc("evm_increaseTime", [toHex(Number(sched[1] - now) + 3600)]);
    await rpc("evm_mine", []);
    // a keeper pass after genesis: settles, releases realised surplus to the buyback, buys and burns,
    // and retires the allocation of epochs nobody earned
    const supply0 = await rd(A.token, ops.token, "totalSupply");
    const k1 = await keeperTick(deployer);
    // a few pulls on a scaled board leave no realised surplus (NAV below capital), so the buyback is
    // funded directly here to exercise buyAndBurn through the keeper
    if ((await pub.getBalance({ address: A.buyback })) < parseEther("0.005")) await rpc("anvil_setBalance", [A.buyback, toHex(parseEther("0.03"))]);
    const burnSupply = await rd(A.token, ops.token, "totalSupply");
    await rpc("evm_increaseTime", [toHex(3601)]); await rpc("evm_mine", []);
    const k2 = await keeperTick(keeper2);
    const supply1 = await rd(A.token, ops.token, "totalSupply");
    return { keeperActions: [...k1.actions, ...k2.actions].map((a) => a.action),
      surplusReleasedWei: await rd(A.controller, ops.controller, "totalSurplusReleased"),
      buybackEthSpentWei: await rd(A.buyback, ops.buyback, "totalEthSpent"), engineBurnedByBuyback: await rd(A.buyback, ops.buyback, "totalBurned"),
      retiredUnearned: await rd(A.farm, ops.farm, "retiredAmount"), supplyBefore: supply0, supplyAfterRetire: burnSupply, supplyAfter: supply1 };
  });
}
writeFileSync(`${ROOT}web/src/deployment.${FORK ? "fork" : "sepolia"}.json`, JSON.stringify({ chainId, ...Object.fromEntries(
  ["shapes", "drawPacks", "timelock", "engine", "controller", "grailVault", "token", "hook", "liquidity", "farm", "treasury", "buyback", "lens"].map((k) => [k, A[k]])) }, null, 2));
say("done; evidence in", statePath);
