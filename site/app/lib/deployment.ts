import type { Address } from "viem";
import sepolia from "../../deployments/84532.json";

export interface Deployment {
  /** False when no record was found. Pages then render the missing-deployment notice. */
  present: boolean;
  chainId: number;
  /** DrawController: settles, books captures and restocks the board (the original app's "pool"). */
  pool: Address;
  /** DrawEngine: the protocol-owned fork of FWA's custom pool that sells the pulls. */
  fwaPool: Address;
  lens: Address;
  shapes: Address;
  drawPacks: Address;
  grailVault: Address;
  farm: Address;
  token: Address;
  treasury: Address;
  buyback: Address;
  hook: Address;
  timelock: Address;
  /** Block the system was deployed in. */
  blockNumber: number;
}

const ZERO = "0x0000000000000000000000000000000000000000" as const;
/** Deployment records bundled at build time (`site/deployments/<chainId>.json`, copied from
 *  `deployments/` by `npm run deployments`). Base mainnet joins once it is deployed. */
const RECORDS: Record<number, typeof sepolia | undefined> = { 84532: sepolia };

function missing(chainId: number): Deployment {
  return {
    present: false, chainId, pool: ZERO, fwaPool: ZERO, lens: ZERO, shapes: ZERO, drawPacks: ZERO, grailVault: ZERO, farm: ZERO,
    token: ZERO, treasury: ZERO, buyback: ZERO, hook: ZERO, timelock: ZERO, blockNumber: 0,
  };
}

/** The record for `NEXT_PUBLIC_CHAIN_ID` (default Base Sepolia, 84532). */
export function getDeployment(): Deployment {
  const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 84532);
  const r = RECORDS[chainId];
  if (!r?.engine || !r.lens) return missing(chainId);
  return {
    present: true,
    chainId,
    pool: r.controller as Address,
    fwaPool: r.engine as Address,
    lens: r.lens as Address,
    shapes: r.shapes as Address,
    drawPacks: r.drawPacks as Address,
    grailVault: r.grailVault as Address,
    farm: r.farm as Address,
    token: r.token as Address,
    treasury: r.treasury as Address,
    buyback: r.buyback as Address,
    hook: r.hook as Address,
    timelock: r.timelock as Address,
    blockNumber: Number(r.deployBlock ?? 0),
  };
}
