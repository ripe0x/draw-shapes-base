// Extracts the ABIs the app uses from Foundry artifacts (run `forge build` first).
import { readFileSync, writeFileSync } from "node:fs";
const out = new URL("../../out/", import.meta.url);
const pick = (file, name) => JSON.parse(readFileSync(new URL(`${file}/${name}.json`, out))).abi;
const abis = {
  engine: pick("DrawEngine.sol", "DrawEngine"),
  controller: pick("DrawController.sol", "DrawController"),
  vault: pick("GrailVault.sol", "GrailVault"),
  farm: pick("GenesisFarm.sol", "GenesisFarm"),
  hook: pick("EngineHook.sol", "EngineHook"),
  lens: pick("Lens.sol", "Lens"),
  token: pick("EngineToken.sol", "EngineToken"),
};
writeFileSync(new URL("../src/abi.json", import.meta.url), JSON.stringify(abis));
console.log("wrote src/abi.json:", Object.keys(abis).join(", "));

// Operations ABIs and bytecode for the keeper and the testnet runner (not bundled into the app).
const art = (file, name) => JSON.parse(readFileSync(new URL(`${file}/${name}.json`, out)));
const ops = {
  ...abis,
  timelock: pick("TimelockController.sol", "TimelockController"),
  treasury: pick("Treasury.sol", "Treasury"),
  buyback: pick("Buyback.sol", "Buyback"),
  liquidity: pick("ProtocolLiquidity.sol", "ProtocolLiquidity"),
  shapes: pick("Shapes.sol", "Shapes"),
  packs: pick("ShapePacks.sol", "ShapePacks"),
  swapper: pick("Swapper.sol", "Swapper"),
  swapperBytecode: art("Swapper.sol", "Swapper").bytecode.object,
};
writeFileSync(new URL("./ops-abi.json", import.meta.url), JSON.stringify(ops));
console.log("wrote scripts/ops-abi.json:", Object.keys(ops).join(", "));
