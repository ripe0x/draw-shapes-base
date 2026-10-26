"use client";

import { drawOdds, grailChanceBps, usePool, type Grail, type GrailItem } from "../lib/pool";
import { eth, pct } from "../lib/format";
import { Eth, Kv, oneIn, Stat } from "./Measure";
import { TokenArt } from "./TokenArt";

/** The GRAIL fund and cycle as one card, then one card per GRAIL: art, backing, list price, odds per
 *  pull and pulls since it listed. The fund and the GRAILs sit outside the ordinary pool. */
export function GrailBoard({ detail = false }: { detail?: boolean }) {
  const pool = usePool().data;
  if (!pool) return null;
  const odds = drawOdds(pool.board, pool.grail);
  return (
    <>
      <CycleCard g={pool.grail} detail={detail} />
      {pool.grail.items.map((it) => (
        <ItemCard key={`${it.collection}-${it.tokenId}`} g={pool.grail} item={it} chanceBps={grailChanceBps(odds, it.listingId)} />
      ))}
    </>
  );
}

function CycleCard({ g, detail }: { g: Grail; detail: boolean }) {
  const need = g.targetWei + g.mintFee;
  const progress = need === 0n ? 0 : Math.min(100, Number((g.funded * 100n) / need));
  return (
    <div className="card grail-card">
      <h3 className="vault-h2">GRAIL, cycle {g.cycleId.toString()}</h3>
      <div className="stat-grid grail-stats">
        <Stat label="Fund" value={<Eth wei={g.funded} digits={4} />} sub={`of ${eth(need, 4)} ETH for the next GRAIL`} />
        <Stat label="Next GRAIL" value={<Eth wei={g.targetWei} digits={3} />} sub={`Then ${eth(g.nextTargetWei, 3)} ETH`} />
        <Stat label="Live GRAILs" value={g.items.length.toLocaleString("en-US")} sub={`${g.selectable.toString()} selectable now`} />
      </div>
      <progress className="grail-progress" max={100} value={progress} aria-label="GRAIL fund toward the next GRAIL">
        {progress}%
      </progress>
      {detail && (
        <>
          <Kv label="List price share of backing" value={pct(g.listBps)} />
          <Kv label="Price drop per pull" value={<Eth wei={g.decayWeiPerPull} digits={5} />} />
          <Kv label="Price floor share of backing" value={pct(g.floorBps)} />
          <Kv label="Probability cap for decay" value={pct(g.probCapBps)} />
          <Kv label="Mint fee" value={<Eth wei={g.mintFee} digits={4} />} />
        </>
      )}
      <p className="vault-note">
        The feed share of every pull&apos;s margin and the ENGINE treasury fill the fund. When it covers the next GRAIL and its mint fee,
        the vault mints a Shape holding that ETH and lists it at {pct(g.listBps)} of its backing. Its price then falls by{" "}
        {eth(g.decayWeiPerPull, 5)} ETH per pull, down to {pct(g.floorBps)} of backing.
      </p>
    </div>
  );
}

function ItemCard({ g, item, chanceBps }: { g: Grail; item: GrailItem; chanceBps: bigint }) {
  const listed = item.listingId !== 0n;
  return (
    <div className="card grail-card">
      <h3 className="vault-h2">GRAIL</h3>
      <div className="grail-art">
        <TokenArt token={{ collection: item.collection, tokenId: item.tokenId }} />
      </div>
      <div className="stat-grid grail-stats">
        <Stat label="Backing" value={<Eth wei={item.backing} digits={3} />} />
        <Stat label="List price" value={listed ? <Eth wei={item.notional} digits={4} /> : "Not listed"} />
        <Stat label="Odds per pull" value={listed ? oneIn(chanceBps) : "Not listed"} />
        <Stat label="Pulls since list" value={(g.pulls - item.listedAtPull).toLocaleString("en-US")} />
      </div>
      <p className="vault-note">
        {listed
          ? `Listed at ${eth(item.notional, 4)} ETH for ${eth(item.backing, 3)} ETH of backing. A pull that draws it wins all of that backing.`
          : "Funded and minted; it lists at the next vault step."}
      </p>
    </div>
  );
}
