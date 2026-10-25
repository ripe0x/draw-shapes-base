// Minimal keeper: settles, steps the GRAIL vault, distributes hook fees and tops up VRF.
// All calls are permissionless. Usage: RPC=... KEEPER_KEY=0x... node scripts/keeper.mjs
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "node:fs";
const RPC = process.env.RPC ?? "https://mainnet.base.org";
const dep = JSON.parse(readFileSync(new URL(process.env.DEPLOYMENT ?? "../src/deployment.json", import.meta.url)));
const abis = JSON.parse(readFileSync(new URL("../src/abi.json", import.meta.url)));
const account = privateKeyToAccount(process.env.KEEPER_KEY);
const chain = { id: dep.chainId, name: "base", nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } };
const pub = createPublicClient({ chain, transport: http(RPC) });
const wallet = createWalletClient({ chain, transport: http(RPC), account });
const call = async (address, abi, functionName, args = []) => {
  try {
    await pub.simulateContract({ address, abi, functionName, args, account });
    const hash = await wallet.writeContract({ address, abi, functionName, args, chain });
    await pub.waitForTransactionReceipt({ hash });
    console.log(new Date().toISOString(), functionName, hash);
  } catch (e) {
    /* nothing to do or not due */
  }
};
let tick = 0;
for (;;) {
  const [lastIssued, nextToBook, queue] = await Promise.all([
    pub.readContract({ address: dep.engine, abi: abis.engine, functionName: "lastIssuedSequence" }),
    pub.readContract({ address: dep.controller, abi: abis.controller, functionName: "nextSequenceToBook" }),
    pub.readContract({ address: dep.controller, abi: abis.controller, functionName: "queueLength" }),
  ]);
  if (nextToBook <= lastIssued || queue > 0n) await call(dep.controller, abis.controller, "settle", [50n]);
  if (await pub.readContract({ address: dep.grailVault, abi: abis.vault, functionName: "stepDue" })) await call(dep.grailVault, abis.vault, "step");
  if (tick % 60 === 0) {
    await call(dep.hook, abis.hook, "distribute");
    await call(dep.controller, abis.controller, "topUpVrf");
  }
  tick++;
  await new Promise((r) => setTimeout(r, 15_000));
}
