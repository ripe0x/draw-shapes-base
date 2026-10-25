// Keeper library: one `tick()` reads the system, decides what is due, executes it, and reports health.
// Every action is permissionless (except Treasury.deployPol, keeper role) and idempotent: each call is
// simulated first and skipped when it would revert, so several keepers can run side by side.
import { createPublicClient, createWalletClient, fallback, http, formatEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "node:fs";

export const ops = JSON.parse(readFileSync(new URL("./ops-abi.json", import.meta.url)));

/** Default alert thresholds (docs/RUNBOOK.md section 5). Board depth is a share of `boardItems`. */
export const DEFAULT_THRESHOLDS = {
  unsettled: 100, // engine acquisitions waiting
  headStallSec: 600, // the same head acquisition unprocessed this long while unsettled > 0
  queueStallSec: 900, // replacements queued this long
  boardDepthShare: 0.7, // selectable ordinary listings below 70 % of the board
  cashMinWei: 150_000_000_000_000_000n, // 0.15 ETH (scale with the allocation on testnets)
  vrfMinWei: 10_000_000_000_000_000n, // 0.01 ETH in the VRF subscription
  stepDueStallSec: 900, // GrailVault.stepDue() true this long
  settleStallSec: 900, // work pending and no successful settle this long
  refundRate: 0.05, // refunded share of resolved acquisitions over the recent window
};

export function makeClients({ rpcUrls, privateKey, chain }) {
  const transport = fallback(rpcUrls.map((u) => http(u, { retryCount: 3, retryDelay: 500, timeout: 20_000 })));
  const pub = createPublicClient({ chain, transport });
  const account = privateKey ? privateKeyToAccount(privateKey) : undefined;
  const wallet = account ? createWalletClient({ chain, transport, account }) : undefined;
  return { pub, wallet, account };
}

export const chainFor = (chainId, rpcUrl) => ({
  id: chainId,
  name: chainId === 8453 ? "base" : chainId === 84532 ? "base-sepolia" : `chain-${chainId}`,
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Simulates, sends and waits. Returns null when the call would revert (nothing to do). */
export async function send(ctx, { address, abi, functionName, args = [], value = 0n, label, maxGasPriceWei = ctx.maxGasPriceWei }) {
  const { pub, wallet, account } = ctx;
  if (!wallet) return null;
  let request;
  try {
    ({ request } = await pub.simulateContract({ address, abi, functionName, args, account, value }));
  } catch (e) {
    return null; // not due, or another keeper already did it
  }
  if (maxGasPriceWei) {
    const gp = await pub.getGasPrice();
    if (gp > maxGasPriceWei) {
      ctx.log({ level: "warn", event: "gas-price-cap", functionName, gasPrice: gp.toString() });
      return null;
    }
  }
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      // 30 % over the estimate: settle and step size their work by gasleft()
      const gas = await pub.estimateContractGas({ address, abi, functionName, args, account, value });
      // a low priority fee: settle refunds gas at block.basefee plus a fixed tip, so a keeper paying a
      // large priority fee would fund the difference itself (Base: ~0.001 gwei is normal)
      const hash = await wallet.writeContract({ ...request, gas: (gas * 13n) / 10n, maxPriorityFeePerGas: ctx.priorityFeeWei ?? 1_000_000n });
      const receipt = await pub.waitForTransactionReceipt({ hash, timeout: 180_000 });
      const cost = receipt.gasUsed * receipt.effectiveGasPrice;
      ctx.log({ level: receipt.status === "success" ? "info" : "error", event: "tx", label: label ?? functionName,
        hash, status: receipt.status, gasUsed: receipt.gasUsed.toString(), costWei: cost.toString(), block: receipt.blockNumber.toString() });
      return receipt;
    } catch (e) {
      ctx.log({ level: "warn", event: "tx-retry", functionName, attempt, error: String(e.shortMessage ?? e.message ?? e) });
      await sleep(2_000 * attempt);
      try {
        ({ request } = await pub.simulateContract({ address, abi, functionName, args, account, value }));
      } catch {
        return null; // someone else did it meanwhile
      }
    }
  }
  return null;
}

const read = (pub, address, abi, functionName, args = []) => pub.readContract({ address, abi, functionName, args });

/** Snapshot of everything the keeper decides on. */
export async function snapshot(ctx) {
  const { pub, dep } = ctx;
  const [game, vrf, queue, boardItems, stepDue, opAcc, trAcc, now] = await Promise.all([
    read(pub, dep.lens, ops.lens, "game"),
    read(pub, dep.lens, ops.lens, "vrf").catch(() => null),
    read(pub, dep.controller, ops.controller, "queueLength"),
    read(pub, dep.controller, ops.controller, "boardItems"),
    read(pub, dep.grailVault, ops.vault, "stepDue"),
    read(pub, dep.hook, ops.hook, "operatorAccrued"),
    read(pub, dep.hook, ops.hook, "treasuryAccrued"),
    pub.getBlock().then((b) => b.timestamp),
  ]);
  const [reserve, backstopFloor, polPending, bbBal, bbStart, bbLast, bbInterval, bbMin, bbPaused] = await Promise.all([
    read(pub, dep.treasury, ops.treasury, "reserve"),
    read(pub, dep.treasury, ops.treasury, "backstopFloor"),
    read(pub, dep.treasury, ops.treasury, "polPending"),
    pub.getBalance({ address: dep.buyback }),
    read(pub, dep.buyback, ops.buyback, "startTime"),
    read(pub, dep.buyback, ops.buyback, "lastBuyAt"),
    read(pub, dep.buyback, ops.buyback, "minInterval"),
    read(pub, dep.buyback, ops.buyback, "minSpend"),
    read(pub, dep.buyback, ops.buyback, "paused"),
  ]);
  return { game, vrf, queue, boardItems, stepDue, opAcc, trAcc, now, reserve, backstopFloor, polPending,
    bbBal, bbStart, bbLast, bbInterval, bbMin, bbPaused };
}

/** Executes everything due. Returns the actions taken. */
export async function act(ctx, s) {
  const { dep } = ctx;
  const done = [];
  const g = s.game;
  const t = (x) => x && done.push(x);
  // 1. settlement, booking and restocking (also processes acquisitions the callback left behind)
  if (g.nextToBook <= g.lastIssued || s.queue > 0n || g.unsettled > 0n) {
    // settle in chunks of 20 (DrawController.MAX_SETTLE_ITEMS): each call stays far below the EIP-7825
    // per-transaction gas cap; a drained 100-item board recovers in ~17 calls
    for (let i = 0; i < 25; i++) {
      const r = await send(ctx, { address: dep.controller, abi: ops.controller, functionName: "settle", args: [20n], label: "settle" });
      if (!r) break;
      t({ action: "settle", hash: r.transactionHash, gasUsed: r.gasUsed });
      const [q, b, li] = await Promise.all([
        read(ctx.pub, dep.controller, ops.controller, "queueLength"),
        read(ctx.pub, dep.controller, ops.controller, "nextSequenceToBook"),
        read(ctx.pub, dep.engine, ops.engine, "lastIssuedSequence"),
      ]);
      if (q === 0n && b > li) break;
    }
    ctx.lastSettleOk = Number(s.now);
  }
  // 2. treasury backstop when restocking waits on cash
  if (s.queue > 0n && g.cash < s.backstopFloor && s.reserve > 0n) {
    const r = await send(ctx, { address: dep.treasury, abi: ops.treasury, functionName: "backstop", label: "backstop" });
    if (r) t({ action: "backstop", hash: r.transactionHash, gasUsed: r.gasUsed });
  }
  // 3. GRAIL vault: sync, harvest, relist, mint, decay
  if (await read(ctx.pub, dep.grailVault, ops.vault, "stepDue")) {
    const r = await send(ctx, { address: dep.grailVault, abi: ops.vault, functionName: "step", label: "grail-step" });
    if (r) t({ action: "grail-step", hash: r.transactionHash, gasUsed: r.gasUsed });
  }
  // 4. trading fees: operator and treasury shares (hourly or when above a floor)
  const accrued = s.opAcc + s.trAcc;
  if (accrued > 0n && (accrued >= ctx.distributeMinWei || Number(s.now) - (ctx.lastDistribute ?? 0) >= 3600)) {
    const r = await send(ctx, { address: dep.hook, abi: ops.hook, functionName: "distribute", label: "distribute" });
    if (r) {
      ctx.lastDistribute = Number(s.now);
      t({ action: "distribute", hash: r.transactionHash, gasUsed: r.gasUsed });
    }
  }
  // 5. protocol-owned liquidity (keeper role only), price limit 3 % below spot
  if (ctx.isPolKeeper && s.polPending > 0n && Number(s.now) - (ctx.lastPol ?? 0) >= 86_400) {
    const sp = await read(ctx.pub, dep.liquidity, ops.liquidity, "sqrtPriceX96");
    const r = await send(ctx, { address: dep.treasury, abi: ops.treasury, functionName: "deployPol", args: [(sp * 985n) / 1000n], label: "deploy-pol" });
    if (r) {
      ctx.lastPol = Number(s.now);
      t({ action: "deploy-pol", hash: r.transactionHash, gasUsed: r.gasUsed });
    }
  }
  // 6. post-genesis buyback-and-burn, rate-limited by the contract
  if (!s.bbPaused && s.now >= s.bbStart && s.now >= s.bbLast + s.bbInterval && s.bbBal >= s.bbMin) {
    const r = await send(ctx, { address: dep.buyback, abi: ops.buyback, functionName: "buyAndBurn", label: "buyback" });
    if (r) t({ action: "buyback", hash: r.transactionHash, gasUsed: r.gasUsed });
  }
  // 7. release realised surplus to the buyback (after genesis; reverts when not allowed)
  if (s.now >= s.bbStart && Number(s.now) - (ctx.lastRelease ?? 0) >= 6 * 3600) {
    const r = await send(ctx, { address: dep.controller, abi: ops.controller, functionName: "releaseSurplus", label: "release-surplus" });
    ctx.lastRelease = Number(s.now);
    if (r) t({ action: "release-surplus", hash: r.transactionHash, gasUsed: r.gasUsed });
  }
  // 8. genesis maintenance: burn unearned allocations once all 14 epochs are final
  if (s.now >= s.bbStart && !ctx.retired) {
    const r = await send(ctx, { address: dep.farm, abi: ops.farm, functionName: "retireUnearned", label: "retire-unearned" });
    if (r) t({ action: "retire-unearned", hash: r.transactionHash, gasUsed: r.gasUsed });
    if (await read(ctx.pub, dep.farm, ops.farm, "retired").catch(() => false)) ctx.retired = true;
  }
  return done;
}

/** Health checks against thresholds; tracks how long conditions persist across ticks. */
export function health(ctx, s, th = ctx.thresholds) {
  const now = Number(s.now);
  const g = s.game;
  const alerts = [];
  const persist = (key, cond, limitSec, msg) => {
    ctx.since ??= {};
    if (!cond) {
      delete ctx.since[key];
      return;
    }
    ctx.since[key] ??= now;
    if (now - ctx.since[key] >= limitSec) alerts.push({ key, msg, forSec: now - ctx.since[key] });
  };
  if (g.unsettled > BigInt(th.unsettled)) alerts.push({ key: "unsettled", msg: `${g.unsettled} acquisitions unsettled` });
  const headKey = g.unsettled > 0n ? String(g.nextToProcess) : "none";
  persist("head-stall", g.unsettled > 0n && ctx.lastHead === headKey, th.headStallSec, `head acquisition ${g.nextToProcess} not processed`);
  ctx.lastHead = headKey;
  persist("queue-stall", s.queue > 0n, th.queueStallSec, `${s.queue} replacements queued`);
  const depth = Number(g.activeListings);
  if (g.activated && depth < Number(s.boardItems) * th.boardDepthShare) {
    alerts.push({ key: "board-depth", msg: `${depth} selectable listings (board ${s.boardItems})` });
  }
  if (g.cash < th.cashMinWei) alerts.push({ key: "cash", msg: `pool cash ${formatEther(g.cash)} ETH` });
  if (s.vrf && s.vrf.subscriptionBalance < th.vrfMinWei) {
    alerts.push({ key: "vrf", msg: `VRF subscription ${formatEther(s.vrf.subscriptionBalance)} ETH` });
  }
  persist("step-due", s.stepDue, th.stepDueStallSec, "GrailVault.stepDue() stays true");
  const pending = g.nextToBook <= g.lastIssued || s.queue > 0n;
  persist("settle-stall", pending && now - (ctx.lastSettleOk ?? now) > 0, th.settleStallSec, "work pending, no settle");
  if (ctx.refunds && ctx.refunds.resolved >= 20 && ctx.refunds.refunded / ctx.refunds.resolved > th.refundRate) {
    alerts.push({ key: "refund-rate", msg: `refund rate ${(100 * ctx.refunds.refunded / ctx.refunds.resolved).toFixed(1)} %` });
  }
  return alerts;
}

/** Counts refunded vs fulfilled acquisitions in the recent block window (abnormal refund alert). */
export async function refundWindow(ctx, blocks = 1_800n) {
  const { pub, dep } = ctx;
  const to = await pub.getBlockNumber();
  const from = to > blocks ? to - blocks : 0n;
  const ev = ops.engine.find((x) => x.type === "event" && x.name === "AcquisitionProcessed");
  if (!ev) return;
  const logs = await pub.getLogs({ address: dep.engine, event: ev, fromBlock: from, toBlock: to }).catch(() => []);
  let refunded = 0;
  // AcquisitionStatus: 3 Expired, 4 Refunded (slippage / empty board), 8 DeliveryRefunded
  for (const l of logs) if ([3, 4, 8].includes(Number(l.args.status))) refunded++;
  ctx.refunds = { resolved: logs.length, refunded };
}
