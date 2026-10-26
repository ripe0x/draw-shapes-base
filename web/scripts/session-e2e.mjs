// End-to-end play session against live Base Sepolia, through the built site (site/out served on
// SITE_URL), with an injected wallet signing as the testnet player: connect, enable prizes, pull
// paid with prizes, reveal, keep one, cash out the rest. The player key is derived in-process from
// DEPLOYER_KEY (testnet keystore, see script/testnet/sepolia.sh) and never printed.
//   SITE_URL=http://127.0.0.1:4173 DEPLOYER_KEY=... node web/scripts/session-e2e.mjs <screenshot dir>
import { createRequire } from "node:module";
import { createPublicClient, createWalletClient, http, keccak256, encodePacked, formatEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

const { chromium } = createRequire(import.meta.url)("playwright");
const SITE = process.env.SITE_URL ?? "http://127.0.0.1:4173";
const SHOTS = process.argv[2] ?? ".";
const acct = privateKeyToAccount(keccak256(encodePacked(["bytes32", "string"], [process.env.DEPLOYER_KEY, "draw-shapes/testnet/player"])));
const transport = http("https://sepolia.base.org");
const pub = createPublicClient({ chain: baseSepolia, transport });
const wallet = createWalletClient({ chain: baseSepolia, transport, account: acct });
const sent = [];
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

const b = await chromium.launch();
const page = await b.newPage({ viewport: { width: 1280, height: 1000 } });
page.on("pageerror", (e) => log("PAGEERROR", e.message.slice(0, 200)));
await page.exposeFunction("__ethRequest", async (method, params) => {
  switch (method) {
    case "eth_requestAccounts":
    case "eth_accounts":
      return [acct.address];
    case "eth_chainId":
      return "0x14a34";
    case "net_version":
      return "84532";
    case "wallet_switchEthereumChain":
    case "wallet_addEthereumChain":
      return null;
    case "wallet_requestPermissions":
      return [{ parentCapability: "eth_accounts" }];
    case "eth_sendTransaction": {
      const t = params[0];
      const hash = await wallet.sendTransaction({
        to: t.to, data: t.data, value: t.value ? BigInt(t.value) : 0n, gas: t.gas ? BigInt(t.gas) : undefined, maxPriorityFeePerGas: 1_000_000n,
      });
      sent.push(hash);
      log("tx sent", hash);
      return hash;
    }
    default:
      return await pub.request({ method, params });
  }
});
await page.addInitScript(() => {
  window.ethereum = {
    isMetaMask: true,
    request: ({ method, params }) => window.__ethRequest(method, params ?? []),
    on: () => {},
    removeListener: () => {},
  };
});

const shot = (n) => page.screenshot({ path: `${SHOTS}/session-${n}.png`, fullPage: true });
const body = async () => (await page.innerText("body")).replace(/\n+/g, " | ");
async function waitText(re, ms = 120_000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    if (re.test(await body())) return;
    await page.waitForTimeout(1500);
  }
  throw new Error(`timeout waiting for ${re}`);
}
async function waitReceipt() {
  const h = sent[sent.length - 1];
  const r = await pub.waitForTransactionReceipt({ hash: h });
  log("receipt", h.slice(0, 12), r.status, "gas", r.gasUsed);
  if (r.status !== "success") throw new Error(`tx ${h} reverted`);
  return r;
}

await page.goto(`${SITE}/pull/`, { waitUntil: "networkidle" });
await page.waitForTimeout(5000);
if (/Connect wallet/.test(await body())) {
  await page.getByRole("button", { name: /connect wallet/i }).first().click();
  await page.waitForTimeout(1000);
  await page.getByText(/browser wallet|injected|metamask/i).first().click();
}
await waitText(/prizes at face value/);
log("stack:", (await body()).match(/STACK \|[^]*?KEPT \| [^|]+/i)?.[0]);
await shot("1-sat-down");

for (const name of [/Enable playing Shapes/, /Enable playing Draw Packs/]) {
  const btn = page.getByRole("button", { name });
  if (await btn.count()) {
    await btn.click();
    await page.waitForTimeout(3000);
    await waitReceipt();
  }
}
await waitText(/Paid with \d+ prize/, 60_000);
log("plan:", (await body()).match(/Paid with[^|]+/)?.[0]);
const before = await pub.getBalance({ address: acct.address });
await page.getByRole("button", { name: /^Pull 1 for/ }).first().click();
await page.waitForTimeout(3000);
await waitReceipt();
await waitText(/Pull again/, 120_000);
await page.waitForTimeout(5000);
await shot("2-revealed");
log("wallet ETH change on the prize pull (change minus gas):", formatEther((await pub.getBalance({ address: acct.address })) - before));
log("result:", (await body()).match(/YOUR PULL[^]*?Pull again/i)?.[0]?.slice(0, 300));

await page.getByRole("button", { name: "Pull again" }).first().click();
await page.waitForTimeout(15_000);
const keeps = page.getByRole("button", { name: "Keep", exact: true });
log("keep buttons", await keeps.count());
if (await keeps.count()) await keeps.first().click();
await page.waitForTimeout(1000);
const cash = page.getByRole("button", { name: /^Cash out \d+ prizes/ }).first();
log("cash out:", await cash.innerText());
const pre = await pub.getBalance({ address: acct.address });
await cash.click();
await page.waitForTimeout(3000);
await waitReceipt();
await page.waitForTimeout(16_000);
log("cash out received (minus gas):", formatEther((await pub.getBalance({ address: acct.address })) - pre));
await shot("3-after-cashout");
log("final stack:", (await body()).match(/STACK \|[^]*?KEPT \| [^|]+/i)?.[0]);
log("txs", JSON.stringify(sent));
await b.close();
