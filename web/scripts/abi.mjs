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
