// Writes Safe Transaction Builder files for timelock operations, so the admin Safe schedules and
// later executes them (48 h apart on mainnet). Nothing is signed or sent here.
//
//   node web/scripts/safe-batch.mjs activation <chainId>
//       deployments/<chainId>-activation.json -> deployments/<chainId>-safe-activation-{schedule,execute}.json
//   node web/scripts/safe-batch.mjs surplus-sink <chainId> <ledgerOrigin unix seconds>
//       DrawController.setSurplusSink(buyback, ledgerOrigin + 14 days), scheduled within 2 days of activation
//   node web/scripts/safe-batch.mjs custom <chainId> <name> <file.json with {targets, values, datas}>
import { readFileSync, writeFileSync } from "node:fs";
import { encodeAbiParameters, encodeFunctionData, getAddress, keccak256, parseAbiParameters, toHex } from "viem";

const ROOT = new URL("../../", import.meta.url).pathname;
const ops = JSON.parse(readFileSync(new URL("./ops-abi.json", import.meta.url)));
const [kind, chainId, ...rest] = process.argv.slice(2);
if (!kind || !chainId) throw new Error("usage: safe-batch.mjs <activation|surplus-sink|custom> <chainId> ...");
const dep = JSON.parse(readFileSync(`${ROOT}deployments/${chainId}.json`));
const ZERO32 = toHex(0, { size: 32 });
const delays = { 8453: 172_800n };

function write(name, targets, values, datas, description) {
  const salt = keccak256(toHex(`draw-shapes/${name}/${Date.now()}`));
  const delay = BigInt(rest.find((x) => x.startsWith("--delay="))?.slice(8) ?? delays[chainId] ?? 600n);
  const timelock = getAddress(dep.timelock);
  const schedule = encodeFunctionData({ abi: ops.timelock, functionName: "scheduleBatch", args: [targets, values, datas, ZERO32, salt, delay] });
  const execute = encodeFunctionData({ abi: ops.timelock, functionName: "executeBatch", args: [targets, values, datas, ZERO32, salt] });
  // TimelockController.hashOperationBatch: keccak256(abi.encode(targets, values, payloads, predecessor, salt))
  const id = keccak256(encodeAbiParameters(parseAbiParameters("address[], uint256[], bytes[], bytes32, bytes32"), [targets, values, datas, ZERO32, salt]));
  const file = (phase, data) => ({
    version: "1.0", chainId: String(chainId), createdAt: Date.now(),
    meta: { name: `Draw Shapes: ${name} (${phase})`, description: `${description} Timelock ${timelock}, delay ${delay} s, salt ${salt}, operation id ${id}. ${phase === "schedule" ? "Execute only after the delay has elapsed." : "Requires the matching schedule transaction to be ready."}` },
    transactions: [{ to: timelock, value: "0", data, contractMethod: null, contractInputsValues: null }],
  });
  for (const [phase, data] of [["schedule", schedule], ["execute", execute]]) {
    const out = `${ROOT}deployments/${chainId}-safe-${name}-${phase}.json`;
    writeFileSync(out, JSON.stringify(file(phase, data), null, 2));
    console.log("wrote", out);
  }
  console.log("operation id", id, "— check it with TimelockController.isOperationReady(id) before executing");
}

if (kind === "activation") {
  const b = JSON.parse(readFileSync(`${ROOT}deployments/${chainId}-activation.json`));
  write("activation", b.targets, b.values.map(BigInt), b.datas,
    "Accept governance on engine, vault, controller and hook; wire the liquidity launcher to the treasury; open the ETH/ENGINE market; activate the game (starts genesis). Atomic.");
} else if (kind === "surplus-sink") {
  const origin = BigInt(rest[0] ?? NaN);
  const data = encodeFunctionData({ abi: ops.controller, functionName: "setSurplusSink", args: [dep.buyback, origin + 14n * 86_400n] });
  write("surplus-sink", [dep.controller], [0n], [data], `Release realised surplus to the buyback from genesis end (${origin + 14n * 86_400n}).`);
} else if (kind === "custom") {
  const [name, path] = rest;
  const b = JSON.parse(readFileSync(path));
  write(name, b.targets, b.values.map(BigInt), b.datas, b.description ?? "Custom governance batch.");
} else throw new Error(`unknown kind ${kind}`);
