// Local Base-fork demo helper (anvil only). Usage:
//   node scripts/fork-demo.mjs activate   — new VRF subscription, timelock activation batch
//   node scripts/fork-demo.mjs fulfill    — deliver every open VRF batch from the coordinator, then settle
import { createPublicClient, createWalletClient, http, parseAbi, parseEther, encodeFunctionData, keccak256, toHex } from "viem";
import { readFileSync } from "node:fs";
const RPC = process.env.RPC ?? "http://127.0.0.1:8547";
const dep = JSON.parse(readFileSync(new URL("../src/deployment.json", import.meta.url)));
const batch = JSON.parse(readFileSync(new URL("../../deployments/fork-base-53000000/8453-activation.json", import.meta.url)));
const cfg = JSON.parse(readFileSync(new URL("../../script/config/base-fork.json", import.meta.url)));
const abis = JSON.parse(readFileSync(new URL("../src/abi.json", import.meta.url)));
const chain = { id: 8453, name: "fork", nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } };
const pub = createPublicClient({ chain, transport: http(RPC) });
const rpc = (method, params) => pub.request({ method, params });
const as = async (account) => {
  await rpc("anvil_impersonateAccount", [account]);
  await rpc("anvil_setBalance", [account, toHex(parseEther("100"))]);
  return createWalletClient({ chain, transport: http(RPC), account });
};
const coord = parseAbi([
  "function createSubscription() returns (uint256)",
  "function addConsumer(uint256,address)",
  "function fundSubscriptionWithNative(uint256) payable",
  "event SubscriptionCreated(uint256 indexed subId, address owner)",
]);
const tl = parseAbi([
  "function scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)",
  "function executeBatch(address[],uint256[],bytes[],bytes32,bytes32) payable",
]);
const send = async (w, address, abi, functionName, args, value) => {
  const hash = await w.writeContract({ address, abi, functionName, args, value, chain, gas: 25_000_000n });
  const r = await pub.waitForTransactionReceipt({ hash });
  if (r.status !== "success") throw new Error(`${functionName} reverted`);
  return r;
};

if (process.argv[2] === "activate") {
  const owner = await as(cfg.creator);
  const r = await send(owner, cfg.vrfCoordinator, coord, "createSubscription", []);
  const sub = BigInt(r.logs.find((l) => l.address.toLowerCase() === cfg.vrfCoordinator.toLowerCase()).topics[1]);
  await send(owner, cfg.vrfCoordinator, coord, "addConsumer", [sub, dep.engine]);
  await send(owner, cfg.vrfCoordinator, coord, "fundSubscriptionWithNative", [sub], parseEther("0.05"));
  const vrfConfig = encodeFunctionData({
    abi: abis.engine, functionName: "setVrfConfig",
    args: [{ coordinator: cfg.vrfCoordinator, subscriptionId: sub, keyHash: cfg.vrfKeyHash, requestConfirmations: 3, callbackGasBase: 100000, callbackGasPerAcquisition: 650000, selectionTimeoutBlocks: 1800n }],
  });
  const t = [...batch.targets], v = batch.values.map(BigInt), d = [...batch.datas];
  t.splice(6, 0, dep.engine); v.splice(6, 0, 0n); d.splice(6, 0, vrfConfig); // fork only: point the engine at the new subscription
  const admin = await as(cfg.adminSafe);
  const salt = keccak256(toHex("fork-activate"));
  await send(admin, dep.timelock, tl, "scheduleBatch", [t, v, d, "0x" + "0".repeat(64), salt, 172800n]);
  await rpc("evm_increaseTime", [172801]);
  await rpc("evm_mine", []);
  await send(admin, dep.timelock, tl, "executeBatch", [t, v, d, "0x" + "0".repeat(64), salt]);
  console.log("activated; subscription", sub.toString());
} else if (process.argv[2] === "fulfill") {
  const head = await pub.getBlockNumber();
  const logs = await pub.getContractEvents({ address: dep.engine, abi: abis.engine, eventName: "RandomnessRequested", fromBlock: head - 500n > 53000001n ? head - 500n : 53000001n });
  await rpc("anvil_mine", ["0x3"]);
  const c = await as(cfg.vrfCoordinator);
  for (const l of logs) {
    const [, , observed] = await pub.readContract({ address: dep.engine, abi: abis.engine, functionName: "vrfBatches", args: [l.args.vrfRequestId] });
    if (observed) continue;
    await send(c, dep.engine, abis.engine, "rawFulfillRandomWords", [l.args.vrfRequestId, [BigInt(keccak256(toHex(String(l.args.vrfRequestId))))]]);
    console.log("fulfilled", l.args.vrfRequestId.toString().slice(0, 12) + "…");
  }
  const k = await as(cfg.keeper);
  for (let i = 0; i < 3; i++) await send(k, dep.controller, abis.controller, "settle", [50n]);
  await send(k, dep.grailVault, abis.vault, "step", []);
  console.log("settled");
}
