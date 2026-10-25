// Read-only preflight for a Base mainnet deployment: validates script/config/base.json and the chain
// state it depends on. It never signs or sends anything. Exit code 0 only when every check passes.
//   RPC_URL=https://mainnet.base.org DEPLOYER=0x... node web/scripts/mainnet-preflight.mjs
import { readFileSync } from "node:fs";
import { createPublicClient, http, getAddress, isAddress, parseAbi, formatEther, parseEther } from "viem";
import { base } from "viem/chains";

const ROOT = new URL("../../", import.meta.url).pathname;
const cfg = JSON.parse(readFileSync(`${ROOT}script/config/base.json`));
const pub = createPublicClient({ chain: base, transport: http(process.env.RPC_URL ?? "https://mainnet.base.org") });
const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`); };
const ZERO = "0x0000000000000000000000000000000000000000";
const coordinatorAbi = parseAbi([
  "function getSubscription(uint256) view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] consumers)",
  "function s_config() view returns (uint16,uint32,bool,uint32,uint32,uint32,uint32,uint8,uint8)",
]);
const safeAbi = parseAbi(["function getThreshold() view returns (uint256)", "function getOwners() view returns (address[])"]);

check("chain is Base mainnet (8453)", (await pub.getChainId()) === 8453);
check("no testnetAllocation in the mainnet config", cfg.testnetAllocation === undefined);
for (const k of ["creator", "tokenWorks", "dev", "adminSafe", "guardian", "keeper"]) {
  const v = cfg[k];
  check(`${k} is set`, isAddress(v ?? "") && v !== ZERO, v === ZERO ? "placeholder (zero address)" : v);
}
check("Token Works recipient confirmed in writing by Token Works", process.env.TOKEN_WORKS_CONFIRMED === "1",
  "set TOKEN_WORKS_CONFIRMED=1 only after Token Works confirms the Base address");
const distinct = new Set(["adminSafe", "guardian", "keeper"].map((k) => String(cfg[k]).toLowerCase()));
check("admin Safe, guardian and keeper are different accounts", distinct.size === 3);

const codeOf = async (a) => (a && a !== ZERO ? (await pub.getCode({ address: a })) ?? "0x" : "0x");
check("PoolManager has code", (await codeOf(cfg.poolManager)).length > 2, cfg.poolManager);
check("VRF coordinator has code", (await codeOf(cfg.vrfCoordinator)).length > 2, cfg.vrfCoordinator);
if (cfg.adminSafe !== ZERO) {
  const isContract = (await codeOf(cfg.adminSafe)).length > 2;
  check("adminSafe is a contract (Safe)", isContract);
  if (isContract) {
    const [th, owners] = await Promise.all([pub.readContract({ address: cfg.adminSafe, abi: safeAbi, functionName: "getThreshold" }).catch(() => 0n),
      pub.readContract({ address: cfg.adminSafe, abi: safeAbi, functionName: "getOwners" }).catch(() => [])]);
    check("adminSafe threshold ≥ 2", th >= 2n, `${th} of ${owners.length}`);
  }
}
if (cfg.guardian !== ZERO) check("guardian is a contract (multisig)", (await codeOf(cfg.guardian)).length > 2);
for (const k of ["shapes", "drawPacks"]) {
  check(`${k}: deploy new (zero) unless reusing an existing Base deployment`, cfg[k] === ZERO || (await codeOf(cfg[k])).length > 2, cfg[k]);
}
const sub = BigInt(cfg.vrfSubscriptionId ?? 0);
check("VRF subscription id is set", sub !== 0n);
if (sub !== 0n) {
  const s = await pub.readContract({ address: cfg.vrfCoordinator, abi: coordinatorAbi, functionName: "getSubscription", args: [sub] }).catch(() => null);
  check("VRF subscription exists", !!s);
  if (s) {
    check("VRF subscription owned by the admin Safe", getAddress(s[3]) === getAddress(cfg.adminSafe === ZERO ? s[3] : cfg.adminSafe) && cfg.adminSafe !== ZERO, s[3]);
    check("VRF subscription native balance ≥ 0.02 ETH (seed; purchasers then fund it)", s[1] >= parseEther("0.02"), `${formatEther(s[1])} ETH`);
  }
}
const kh = await pub.readContract({ address: cfg.vrfCoordinator, abi: parseAbi(["function s_provingKeys(bytes32) view returns (bool,uint64)"]), functionName: "s_provingKeys", args: [cfg.vrfKeyHash] }).catch(() => [false]);
check("VRF key hash registered on the coordinator", kh[0] === true, cfg.vrfKeyHash);
const conf = await pub.readContract({ address: cfg.vrfCoordinator, abi: coordinatorAbi, functionName: "s_config" });
check("coordinator max callback gas ≥ 2.5M", conf[1] >= 2_500_000);
check("timelock delay is 48 h", Number(cfg.timelockDelay) === 172_800, String(cfg.timelockDelay));
if (process.env.DEPLOYER) {
  const bal = await pub.getBalance({ address: process.env.DEPLOYER });
  const need = parseEther("5.01") + BigInt(cfg.maintenanceFloat ?? 0) + parseEther("0.02");
  check("deployer balance covers 2.2 pool + 0.5 reserve + 2.0 liquidity + 0.01 Shapes seed + maintenance float + gas", bal >= need, `${formatEther(bal)} of ${formatEther(need)} ETH`);
} else check("DEPLOYER address given for the balance check", false, "set DEPLOYER=0x...");
check("DRAW_SHAPES_MAINNET_CONFIRM is NOT set during preflight", !process.env.DRAW_SHAPES_MAINNET_CONFIRM);

const failed = results.filter((r) => !r.ok).length;
console.log(`\n${results.length - failed}/${results.length} checks passed${failed ? " — do not deploy" : ""}`);
process.exit(failed ? 1 : 0);
