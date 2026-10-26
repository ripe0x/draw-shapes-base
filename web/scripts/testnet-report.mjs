// Renders evidence/testnet/<chainId>[-fork]-run.json (written by testnet.mjs) as a Markdown report.
//   node web/scripts/testnet-report.mjs evidence/testnet/84532-run.json > evidence/testnet/BASE_SEPOLIA.md
import { readFileSync } from "node:fs";
import { formatEther } from "viem";

const path = process.argv[2];
const r = JSON.parse(readFileSync(path));
const S = r.steps;
const live = !r.fork;
const scan = (h) => (live ? `[${h.slice(0, 10)}…](https://sepolia.basescan.org/tx/${h})` : `\`${h.slice(0, 10)}…\``);
const addr = (a) => (live ? `[\`${a}\`](https://sepolia.basescan.org/address/${a})` : `\`${a}\``);
const eth = (w, d = 6) => (w === undefined || w === null ? "—" : `${Number(formatEther(BigInt(w))).toFixed(d)}`);
const ST = ["None", "Pending", "Fulfilled", "Expired", "Refunded", "Ready", "TimedOut", "DeliveryPending", "DeliveryRefunded"];
const st = (xs) => (xs ?? []).map((x) => ST[x]).reduce((m, k) => ((m[k] = (m[k] ?? 0) + 1), m), {});
const fmtSt = (xs) => Object.entries(st(xs)).map(([k, v]) => `${v} ${k}`).join(", ");
const out = [];
const p = (...l) => out.push(...l);

p(`# Base Sepolia ${live ? "deployment and live scenarios" : "rehearsal on a local fork (NOT live evidence)"}`, "");
p(live
  ? `Chain ${r.chainId}, RPC ${r.rpc}. Every hash below is a real Base Sepolia transaction. VRF words were delivered by the Chainlink VRF v2.5 coordinator; the timelock delay elapsed in real chain time.`
  : `Chain ${r.chainId} forked locally with anvil. VRF words were delivered by impersonating the coordinator and the timelock delay was skipped with evm_increaseTime; hashes exist only on the local fork. This rehearses the exact live procedure; it is not testnet evidence.`, "");
const d = S.deploy;
p("## Contracts", "", "| Contract | Address |", "| --- | --- |");
for (const k of ["shapes", "drawPacks", "timelock", "engine", "controller", "grailVault", "token", "hook", "liquidity", "farm", "treasury", "buyback", "lens"]) {
  p(`| ${k} | ${addr(d[k])} |`);
}
p("", `Deployment: ${d.deployTxs} transactions, ${Number(d.deployGas).toLocaleString()} gas, ${eth(d.deployCostWei)} ETH. ` +
  `Opening allocation (testnet scale): pool ${eth(d.ordinaryPool, 2)} ETH, market ${eth(d.marketLiquidity, 2)} ETH, board ${d.boardItems} items. ` +
  `VRF subscription ${S["vrf-subscription"].subId}.`, "");
const a = S.activation;
p("## Activation through the timelock", "",
  `Scheduled at ${a.scheduledAt}, executed at ${a.executedAt}: waited ${a.waitedSec} s against a ${a.delay} s delay${a.timeSkippedOnFork ? " (time skipped on the fork)" : ""}. ` +
  `Engine activated: ${a.activated}; market launched: ${a.launched}; governance: timelock.`, "");
if (S["post-activation-governance"]) {
  const g = S["post-activation-governance"];
  p(`Post-activation batch (surplus sink for genesis end; testnet-only faster GRAIL decay): waited ${g.waitedSec} s.`, "");
}
if (S["opening-grail"]) {
  const o = S["opening-grail"];
  p("## Opening GRAIL (funded at launch with test ETH)", "", `Backing ${eth(o.backing, 3)} ETH, listed at ${eth(o.notional, 3)} ETH (listing ${o.listingId}, Shape #${o.tokenId}) before activation.`, "");
}
p("## Pulls and VRF", "", "| Scenario | Quote: fee / settlement / VRF (ETH) | Request tx | Fulfilment tx | Fulfilment gas | Oracle charge (ETH) | VRF fee − charge (ETH) | Latency | Outcome |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
for (const [name, k] of [["Single pull (referred)", "single-pull"], ["Batch of ten", "batch-of-ten"], ["Three pulls paid with prizes (PrizeRouter)", "prize-router"], ["Batch of eight, zero negative slippage", "slippage-refund-probe"], ["On behalf of another wallet", "on-behalf-and-referral"], ["Batch with the VRF float (rerun)", "in-time-batches"]]) {
  const x = S[k];
  if (!x) continue;
  const q = x.quote ?? S[k].quote;
  const f = x.fulfil ?? {};
  p(`| ${name}${x.ids ? ` (${x.ids.length})` : ""} | ${q ? `${eth(q.fee)} / ${eth(q.sfee)} / ${eth(q.vrfFee, 7)}` : "—"} | ${x.requestTx ?? x.pullTx ? scan(x.requestTx ?? x.pullTx) : "—"} | ${f.hash ? scan(f.hash) : "—"} | ${f.gasUsed ?? "—"} | ${f.payment ? eth(f.payment, 7) : live ? "—" : "n/a (fork)"} | ${f.payment && q ? eth(BigInt(q.vrfFee) - BigInt(f.payment), 7) : "—"} | ${f.latencySec !== undefined ? `${f.latencySec} s` : "—"} | ${fmtSt(x.statuses)}${f.requests > 1 ? ` (${f.requests} VRF requests)` : ""} |`);
}
p("");
const b = S["batch-of-ten"];
if (b) {
  const refunded = (b.statuses ?? []).filter((x) => x === 4).length;
  const timedOut = (b.statuses ?? []).filter((x) => x === 6).length;
  p(`Batch of ten: ${b.settledInCallback} of 10 resolved in the VRF callbacks (${b.requestIds?.length ?? 1} requests of up to 5 pulls).` +
    (timedOut ? ` ${timedOut} timed out because the word was late, and were refunded.` : "") +
    (refunded ? ` ${refunded} were refunded by the slippage guard: on a ${d.boardItems}-item testnet board the first wins of the batch moved the per-pull price outside the batch's slippage tolerance, so the rest of the batch was refunded as credit that pays for the next pull (on the 100-item launch board the same wins move it about 1–2 %).` : ""), "");
}
if (live && r.findings?.length) {
  p("### Why words were late before the VRF float", "");
  for (const x of r.findings) p(`- **${x.title}.** ${x.cause ?? ""} ${x.outcome ?? ""}`.trim());
  p("");
}
const del = (S["keeper-booking-restock"]?.deliveries ?? []).filter((x) => x.status === 2);
if (del.length) {
  p("### Deliveries (batch of ten)", "", "| Acquisition | Prize | Notional (ETH) | Delivered to purchaser |", "| --- | --- | --- | --- |");
  for (const x of del) p(`| ${x.id} | ${x.collection.toLowerCase() === d.shapes.toLowerCase() ? "Shape" : "Draw Pack"} #${x.tokenId} | ${eth(x.notional, 5)} | ${x.toBeneficiary} |`);
  p("");
}
const k = S["keeper-booking-restock"];
if (k) {
  p("## Keeper booking and restocking", "", `Booked sequences ${k.before.nextToBook} → ${k.after.nextToBook}; selectable listings ${k.before.active} → ${k.after.active}; ` +
    `pool cash ${eth(k.before.cash, 4)} → ${eth(k.after.cash, 4)} ETH; maintenance ${eth(k.after.maintenance, 5)} ETH.`, "",
    "| Action | Tx | Gas |", "| --- | --- | --- |");
  for (const x of k.keeper.actions) p(`| ${x.action} | ${scan(x.hash)} | ${x.gasUsed} |`);
  p("", `Keeper net cost after the maintenance refund: ${eth(k.keeper.netCostWei, 7)} ETH.`, "");
}
const g = S["grail-decay-and-selection"];
if (g) {
  p("## GRAIL listing, odds and repricing", "", "| | Backing | Notional | Status | Odds per pull |", "| --- | --- | --- | --- | --- |");
  const row = (lbl, v) => v.items.forEach((it, i) => p(`| ${lbl} | ${eth(it.backing, 3)} | ${eth(it.notional, 4)} | ${["awaiting relist", "Active (selectable)"][v.status[i]] ?? v.status[i]} | ${v.oddsPpm[i] ? `1 in ${Math.round(1e6 / Number(v.oddsPpm[i]))}` : "—"} |`));
  row("before", g.before);
  row("after pulls + keeper step", g.after);
  const it = S["in-time-batches"]?.grail;
  if (it) { row("before the in-time rerun", it.before); row("after the in-time rerun + keeper step", it.after); }
  p("", "Decay is accelerated on testnet only (0.002 ETH per pull, set through the timelock); selection of a GRAIL by the live VRF is a matter of chance at these odds. Once the GRAIL reaches its floor notional (50 % of backing) its notional holds, and its odds move only with the rest of the board (captures and restocking). Decay above the floor is covered by GrailReprice.t.sol and the fork rehearsal.", "");
}
const sl = S["slippage-refund-probe"];
if (sl) p("## Refunds", "", `Batch with zero negative slippage tolerance: ${fmtSt(sl.statuses)}; refund credit ${eth(sl.refundCreditWei)} ETH, withdrawn in ${sl.withdraw ? scan(sl.withdraw) : "—"}. Expiry (no VRF word within 1,800 blocks) cannot be forced on a live coordinator; it is covered by Engine.t.sol.`, "");
const ob = S["on-behalf-and-referral"];
if (ob) p("## Referral and purchase on behalf", "", `Referrer credit ${eth(ob.referrerCreditWei, 7)} ETH, withdrawn in ${ob.referrerWithdraw ? scan(ob.referrerWithdraw) : "—"}; prize delivered to the beneficiary: ${ob.deliveries?.[0]?.toBeneficiary}. Token Works / development credit (testnet: deployer) ${eth(ob.tokenWorksCreditWei, 7)} ETH.`, "");
const t = S["engine-trading-and-fees"];
if (t) p("## ENGINE trading and fee routing", "", `Buy 0.01 ETH and sell half through the canonical PoolManager (test router ${addr(t.swapper)}): volume ${eth(t.volumeWei)} ETH, hook fees ${eth(t.hookFeesWei, 7)} ETH = ${t.feeBpsOfVolume} bps of volume; operator ${eth(t.operatorAccruedWei, 7)}, treasury ${eth(t.treasuryAccruedWei, 7)} ETH; after distribute the treasury received ${eth(t.treasuryReceivedWei, 7)} ETH (GRAIL fund now ${eth(t.vaultFundAfter, 5)} ETH, POL pending ${eth(t.polPending, 7)} ETH).`, "");
const gl = S["genesis-ledger"];
if (gl) p("## Genesis ledger", "", `Epoch ${gl.epoch}: ${gl.accepted} accepted, ${gl.resolved} resolved, ${gl.units} units, ${gl.bonus} bonus weight; test player ${gl.playerUnits} units. ${S.claims ? `Claimed ${eth(S.claims.claimable, 0)} ENGINE in ${scan(S.claims.hash)}${live ? "" : " (after a fork time skip)"}.` : "Claims open after epoch 0 closes and resolves (24 h of real time); rerun the runner then."}`, "");
const o = S["outage-and-recovery"];
if (o) {
  p("## Keeper outage and recovery (two keepers)", "", `With keepers stopped, three batches settled in their callbacks: selectable listings ${o.activeBefore} → ${o.activeDuring}, ${o.unbookedDuring} sequences unbooked. ` +
    `Two keepers then ran at the same moment: keeper 1 [${o.keeper1.actions.map((x) => x.action).join(", ")}], keeper 2 [${o.keeper2.actions.map((x) => x.action).join(", ") || "nothing left to do"}]; listings back to ${o.activeAfter}, books level: ${o.booked}.`, "");
}
const pr = S["prize-router"];
if (pr) {
  const routerTxs = r.txs.filter((x) => /setApprovalForAll\(router\)|pullWithPrizes|cashOut/.test(x.label ?? ""));
  p("## Playing winnings (PrizeRouter)", "", `Every PrizeRouter transaction of the run: ${routerTxs.map((x) => `${x.label} ${scan(x.hash)}`).join("; ")}.`, "", "Last scenario run: " + `Two one-time approvals (${pr.approvals.map(scan).join(", ")}), then one transaction (${scan(pr.pullTx)}, gas ${pr.pullGas}) paid a 3-pull price of ${eth(pr.priceWei, 5)} ETH with ${pr.prizesSpent} ${pr.prizesSpent === 1 ? "prize" : "prizes"} at face (${eth(pr.prizeWei, 5)} ETH) and ${eth(pr.topUpWei, 5)} ETH sent; ` +
    `wallet change excluding gas ${pr.walletChangeExGasWei < 0 ? "" : "+"}${eth(pr.walletChangeExGasWei, 5)} ETH. Outcome: ${fmtSt(pr.statuses)}.` +
    (pr.cashOut ? ` Cash out of the other ${pr.cashOut.prizes} ${pr.cashOut.prizes === 1 ? "prize" : "prizes"} in one transaction (${scan(pr.cashOut.hash)}): face ${eth(pr.cashOut.valueWei, 5)} ETH, received ${eth(pr.cashOut.receivedWei, 5)} ETH.` : ""), "");
}
const rp = S["redeem-prize-for-backing"];
if (rp) {
  const rc = S["in-time-batches"]?.recycled;
  const redeems = r.txs.filter((x) => /^redeem /.test(x.label ?? ""));
  p("## Prize redemption", "", ((rp.redeemed ? `Redeemed ${rp.redeemed} ${rp.redeemed === 1 ? "prize" : "prizes"} (notional ${eth(rp.notionalWei, 5)} ETH): ${eth(rp.ethReturnedWei, 5)} ETH of backing returned to the winner.` : "") +
    (rc ? ` Before the in-time rerun, ${rc.redeemed} more prizes returned ${eth(rc.ethReturnedWei, 5)} ETH.` : "") +
    ` In all, the player redeemed ${redeems.length} prizes for their backing during the run (listed under All transactions), recycling winnings into later scenarios.`).trim(), "");
}
const ge = S["fork-time-skip-genesis-end"];
if (ge) p("## Genesis end (fork only, time skipped)", "", `Keeper actions: ${ge.keeperActions.join(", ")}. Unearned allocation retired ${eth(ge.retiredUnearned, 0)} ENGINE; buyback spent ${eth(ge.buybackEthSpentWei)} ETH and burned ${eth(ge.engineBurnedByBuyback, 0)} ENGINE; supply ${eth(ge.supplyBefore, 0)} → ${eth(ge.supplyAfter, 0)}.`, "");
p("## All transactions", "", "| Label | Tx | Status | Gas | Cost (ETH) |", "| --- | --- | --- | --- | --- |");
for (const x of r.txs.filter((x) => x.hash && x.label)) p(`| ${x.label} | ${scan(x.hash)} | ${x.status ?? (x.simulated ? "fork" : "")} | ${x.gasUsed ?? ""} | ${x.costWei ? eth(x.costWei, 8) : ""} |`);
console.log(out.join("\n"));
