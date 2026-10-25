// Draw Shapes keeper daemon. Settles and restocks, steps the GRAIL vault when stepDue() (including
// pending decay), distributes trading fees, backstops restocking from the treasury reserve, deploys
// POL (keeper role), runs post-genesis buybacks and surplus release, and retires unearned genesis
// allocations. All calls are simulated first and are idempotent, so run two keepers on independent
// hosts and RPC providers. VRF is funded by purchasers; the keeper only monitors the subscription.
//
// Usage:
//   RPC_URLS=https://a,https://b KEEPER_KEY=0x... DEPLOYMENT=../../deployments/84532.json \
//     node web/scripts/keeper.mjs
// Optional: INTERVAL_MS (15000), HEALTH_PORT (serves GET /health JSON), ALERT_WEBHOOK (POSTs alerts as
// JSON; Slack/Discord-compatible `text`), MAX_GAS_GWEI (skip sends above this gas price),
// PRIORITY_GWEI (0.001), POL_KEEPER=1 (this key is the treasury keeper), CASH_MIN_ETH, VRF_MIN_ETH, ONCE=1 (one tick, exit).
// The key is read from the environment only and never logged.
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { parseEther } from "viem";
import { makeClients, chainFor, snapshot, act, health, refundWindow, DEFAULT_THRESHOLDS } from "./keeper-lib.mjs";

const rpcUrls = (process.env.RPC_URLS ?? process.env.RPC ?? "https://sepolia.base.org").split(",");
const depPath = process.env.DEPLOYMENT ?? new URL("../src/deployment.json", import.meta.url).pathname;
const dep = JSON.parse(readFileSync(depPath));
const chain = chainFor(Number(dep.chainId), rpcUrls[0]);
if (!process.env.KEEPER_KEY) console.warn("KEEPER_KEY not set: monitoring only");
const { pub, wallet, account } = makeClients({ rpcUrls, privateKey: process.env.KEEPER_KEY, chain });

const log = (o) => console.log(JSON.stringify({ t: new Date().toISOString(), keeper: account?.address, ...o },
  (_, v) => (typeof v === "bigint" ? v.toString() : v)));
const ctx = {
  pub, wallet, account, dep, log,
  isPolKeeper: process.env.POL_KEEPER === "1",
  distributeMinWei: parseEther(process.env.DISTRIBUTE_MIN_ETH ?? "0.01"),
  thresholds: {
    ...DEFAULT_THRESHOLDS,
    ...(process.env.CASH_MIN_ETH ? { cashMinWei: parseEther(process.env.CASH_MIN_ETH) } : {}),
    ...(process.env.VRF_MIN_ETH ? { vrfMinWei: parseEther(process.env.VRF_MIN_ETH) } : {}),
  },
  priorityFeeWei: BigInt(Math.round(Number(process.env.PRIORITY_GWEI ?? "0.001") * 1e9)),
  maxGasPriceWei: process.env.MAX_GAS_GWEI ? parseEther(process.env.MAX_GAS_GWEI) / 1_000_000_000n : undefined,
};
let last = { ok: false, at: null, alerts: [], actions: [] };
let alerted = new Map();

async function alert(alerts) {
  const hook = process.env.ALERT_WEBHOOK;
  for (const a of alerts) {
    const prev = alerted.get(a.key) ?? 0;
    if (Date.now() - prev < 30 * 60_000) continue; // at most one alert per condition per 30 min
    alerted.set(a.key, Date.now());
    log({ level: "alert", ...a });
    if (hook) {
      await fetch(hook, { method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ text: `[draw-shapes keeper ${dep.chainId}] ${a.key}: ${a.msg}` }) }).catch(() => {});
    }
  }
  for (const k of [...alerted.keys()]) if (!alerts.find((a) => a.key === k)) alerted.delete(k);
}

async function tick() {
  const s = await snapshot(ctx);
  const actions = wallet ? await act(ctx, s) : [];
  if (!ctx.lastWindow || Date.now() - ctx.lastWindow > 300_000) {
    await refundWindow(ctx);
    ctx.lastWindow = Date.now();
  }
  const alerts = health(ctx, s);
  await alert(alerts);
  last = { ok: true, at: new Date().toISOString(), block: Number(await pub.getBlockNumber()), alerts, actions,
    state: { unsettled: s.game.unsettled, active: s.game.activeListings, queue: s.queue, cash: s.game.cash,
      maintenance: s.game.maintenance, stepDue: s.stepDue, vrfBalance: s.vrf?.subscriptionBalance } };
  log({ level: "info", event: "tick", ...last });
}

if (process.env.HEALTH_PORT) {
  createServer((req, res) => {
    const stale = !last.at || Date.now() - Date.parse(last.at) > 5 * 60_000;
    res.writeHead(stale || last.alerts.length ? 503 : 200, { "content-type": "application/json" });
    res.end(JSON.stringify(last, (_, v) => (typeof v === "bigint" ? v.toString() : v)));
  }).listen(Number(process.env.HEALTH_PORT));
}

const interval = Number(process.env.INTERVAL_MS ?? 15_000);
for (;;) {
  try {
    await tick();
  } catch (e) {
    last.ok = false;
    log({ level: "error", event: "tick-failed", error: String(e.shortMessage ?? e.message ?? e) });
  }
  if (process.env.ONCE === "1") break;
  await new Promise((r) => setTimeout(r, interval));
}
