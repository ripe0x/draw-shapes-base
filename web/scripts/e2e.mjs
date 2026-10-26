// Browser journey test of the built app (VITE_NETWORK=fork) against the local Base Sepolia fork
// deployment written by testnet.mjs. An injected EIP-1193 wallet forwards to anvil with an unlocked
// test account; the harness delivers the VRF word by impersonating the coordinator (fork only).
//   (cd web && VITE_NETWORK=fork npm run build && npx vite preview --port 4173 &) ; node web/scripts/e2e.mjs
import { createRequire } from "node:module";
import { execSync } from "node:child_process";
// the preinstalled Playwright (global) is used when the project has none
const require = createRequire(import.meta.url);
let pw;
try { pw = require("playwright"); } catch { pw = require(`${execSync("npm root -g").toString().trim()}/playwright`); }
const { chromium } = pw;
import { createPublicClient, encodeFunctionData, http, keccak256, toHex } from "viem";
import { readFileSync, mkdirSync } from "node:fs";

const RPC = "http://127.0.0.1:8547";
const APP = process.env.APP_URL ?? "http://127.0.0.1:4173";
const dep = JSON.parse(readFileSync(new URL("../src/deployment.fork.json", import.meta.url)));
const ops = JSON.parse(readFileSync(new URL("./ops-abi.json", import.meta.url)));
const COORD = "0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE";
const PLAYER = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"; // anvil account #3 (unlocked on the fork)
const out = new URL("../../evidence/web/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });
const pub = createPublicClient({ transport: http(RPC) });
const rpc = (method, params = []) => pub.request({ method, params });
const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(ok ? "PASS" : "FAIL", name, detail); };

const browser = await chromium.launch();
async function page(viewport) {
  const ctx = await browser.newContext({ viewport });
  await ctx.exposeFunction("__rpc", async (method, params) => {
    if (method === "eth_requestAccounts" || method === "eth_accounts") return [PLAYER];
    if (method === "wallet_switchEthereumChain") { await ctx.__setChain?.(Number(params[0].chainId)); return null; }
    return rpc(method, params ?? []);
  });
  await ctx.addInitScript(({ player }) => {
    let chainId = "0x1"; // starts on the wrong network
    const listeners = {};
    window.ethereum = {
      isMetaMask: true,
      request: async ({ method, params }) => {
        if (method === "eth_chainId") return chainId;
        if (method === "wallet_switchEthereumChain") { chainId = params[0].chainId; (listeners.chainChanged ?? []).forEach((f) => f(chainId)); return null; }
        if (method === "wallet_addEthereumChain") return null;
        if (method === "eth_sendTransaction") params[0].from = player;
        return window.__rpc(method, params);
      },
      on: (e, f) => ((listeners[e] ??= []).push(f)),
      removeListener: () => {},
    };
  }, { player: PLAYER });
  const p = await ctx.newPage();
  const errors = [];
  p.on("pageerror", (e) => errors.push(String(e)));
  await p.goto(APP);
  return { p, errors };
}

// ---- desktop journey
const { p, errors } = await page({ width: 1280, height: 900 });
await p.waitForSelector("text=Live", { timeout: 30_000 });
check("live state loads", true);
const total = await p.textContent("button.primary");
check("quote shown on the pull button", /Pull ×10 for 0\.\d+ ETH/.test(total), total);
check("VRF fee shown separately", (await p.textContent("text=VRF fee (one per batch")) !== null);
const grailText = await p.textContent(".grail");
check("GRAIL card distinguishes selectable / funding", /can be won now|No GRAIL can be won right now/.test(grailText) && /accumulating, not drawable/.test(grailText));
check("Base vs Ethereum distinction", (await p.content()).includes("separate collection from Shapes on Ethereum"));
await p.screenshot({ path: `${out}app-desktop-before.png`, fullPage: true });

await p.click("text=Connect wallet");
await p.waitForSelector("text=0x90F7", { timeout: 10_000 });
// the injected wallet answered eth_chainId with chain 1 until the app asked it to switch
const banner = await p.$("text=Your wallet is on another network");
check("network handling: app switched the wallet to the game network", !banner, banner ? "banner still shown" : "switched on connect");
await p.click("button:has-text('×1')");
await p.waitForSelector("button.primary:has-text('Pull ×1')");
await p.click("button.primary");
await p.waitForSelector("text=/Pull ×1: (submitted|confirmed)/", { timeout: 30_000 });
await p.waitForSelector("text=/Pull ×1: confirmed/", { timeout: 60_000 });
check("pull transaction confirmed", true);

// deliver the VRF word if the request is still pending (fork: impersonate the coordinator)
const last = await pub.readContract({ address: dep.engine, abi: ops.engine, functionName: "lastIssuedSequence" });
const a = await pub.readContract({ address: dep.engine, abi: ops.engine, functionName: "acquisitions", args: [last] });
if (Number(a[4]) === 1) {
  const reqId = await pub.readContract({ address: dep.engine, abi: ops.engine, functionName: "vrfRequestOf", args: [last] });
  await rpc("anvil_impersonateAccount", [COORD]);
  await rpc("anvil_setBalance", [COORD, toHex(10n ** 18n)]);
  for (let i = 0; i < 3; i++) await rpc("evm_mine");
  const h = await rpc("eth_sendTransaction", [{ from: COORD, to: dep.engine, gas: toHex(1_200_000n),
    data: encodeFunctionData({ abi: ops.engine, functionName: "rawFulfillRandomWords", args: [reqId, [BigInt(keccak256(toHex("e2e")))]] }) }]);
  await pub.waitForTransactionReceipt({ hash: h });
}
await p.waitForSelector("text=Delivered to your wallet", { timeout: 60_000 });
const row = await p.textContent("text=Delivered to your wallet >> xpath=..");
check("pull settled and prize shown in My pulls", /ETH (Shape|Draw Pack) #\d+/.test(row), row.replace(/\s+/g, " "));
await p.screenshot({ path: `${out}app-desktop-after-pull.png`, fullPage: true });
check("no page errors (desktop)", errors.length === 0, errors.join(" | "));

// ---- mobile layout
const m = await page({ width: 390, height: 844 });
await m.p.waitForSelector("text=Live", { timeout: 30_000 });
const overflow = await m.p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
check("mobile: no horizontal page scroll", !overflow);
await m.p.screenshot({ path: `${out}app-mobile.png`, fullPage: true });
check("no page errors (mobile)", m.errors.length === 0, m.errors.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
