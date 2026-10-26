"use client";

import { evmNowAddressUrl } from "../lib/errors";
import { duration, eth, pct, short, utc } from "../lib/format";
import { usePool } from "../lib/pool";
import { useDeployment } from "../Providers";
import { Kv } from "./Measure";

/** The game's operating parameters and contracts. Every change goes through the 48 h timelock. */
export function ParamsDisclosure() {
  const dep = useDeployment();
  const pool = usePool().data;
  if (!pool) return null;
  const p = pool.params;
  const g = pool.grail;
  const address = (v: string) => (
    <a href={evmNowAddressUrl(v, dep.chainId)} target="_blank" rel="noreferrer">
      {short(v)}
    </a>
  );
  return (
    <details className="vault-note">
      <summary>Current parameters</summary>
      <Kv label="Engine" value={address(dep.fwaPool)} />
      <Kv label="Controller" value={address(dep.pool)} />
      <Kv label="GRAIL vault" value={address(dep.grailVault)} />
      <Kv label="Shapes" value={address(dep.shapes)} />
      <Kv label="Draw Packs" value={address(dep.drawPacks)} />
      <Kv label="Treasury" value={address(dep.treasury)} />
      <Kv label="Buyback" value={address(dep.buyback)} />
      <Kv label="Timelock (governance)" value={address(dep.timelock)} />
      <Kv label="Premium, of backing" value={pct(p.feeSplit.premiumBps)} />
      <Kv label="Maintenance, of backing" value={pct(p.feeSplit.maintenanceBps)} />
      <Kv label="GRAIL feed, of backing" value={pct(p.feeSplit.feedBps)} />
      <Kv label="Settlement fee, of the ticket" value={pct(p.settlementFeeBps)} />
      <Kv label="Max pulls per transaction" value={p.maxBatch.toString()} />
      <Kv label="VRF word deadline" value={`${p.selectionTimeoutBlocks.toLocaleString("en-US")} blocks`} />
      <Kv label="Board depth target (items)" value={p.boardItems.toLocaleString("en-US")} />
      <Kv label="Maintenance floor" value={`${eth(p.maintenanceFloor, 4)} ETH`} />
      <Kv label="Keeper tip" value={`${eth(p.tipWei, 6)} ETH`} />
      <Kv label="Listing paused" value={p.listingPaused ? "yes" : "no"} />
      <Kv label="Surplus release to buybacks from" value={p.surplusReleaseStart === 0n ? "not set" : utc(p.surplusReleaseStart)} />
      <Kv label="GRAIL list price, of backing" value={pct(g.listBps)} />
      <Kv label="GRAIL price floor, of backing" value={pct(g.floorBps)} />
      <Kv label="GRAIL price drop per pull" value={`${eth(g.decayWeiPerPull, 6)} ETH`} />
      <Kv label="GRAIL probability cap" value={pct(g.probCapBps)} />
      <Kv label="GRAIL ladder steps up after" value={duration(Number(g.stepUpSeconds))} />
      <Kv label="GRAIL ladder steps down after" value={duration(Number(g.stepDownSeconds))} />
    </details>
  );
}
