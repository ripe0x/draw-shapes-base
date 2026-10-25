"use client";

import { eth } from "../lib/format";
import { drawOdds, useQuote, usePool } from "../lib/pool";
import { Eth, Stat, percent } from "./Measure";

/** Headline numbers: the ordinary pool, the one-pull ticket against its average redeemable value,
 *  the board and the game state. */
export function VaultStats() {
  const pool = usePool().data;
  const quote = useQuote(1).data;
  if (!pool) return null;
  const odds = drawOdds(pool.board, pool.grail);
  const g = pool.game;
  const perPull = quote ? quote.fee + quote.settlementFee : 0n;
  const returnBps = quote && perPull > 0n ? (odds.averageBackingWei * 10_000n) / perPull : undefined;
  return (
    <div className="stat-grid">
      <Stat label="Ordinary pool" value={<Eth wei={pool.nav} digits={3} />} sub={`Capital target ${eth(g.capitalTarget, 2)} ETH`} />
      <Stat
        label="Ticket per pull"
        value={quote ? <Eth wei={quote.fee} digits={5} /> : "-"}
        sub={returnBps === undefined ? undefined : `Average redeemable value ${percent(returnBps)} of ticket + settlement fee`}
      />
      <Stat
        label="Listed items"
        value={pool.listedCount.toLocaleString("en-US")}
        sub={`${pool.queueLength.toString()} replacements queued, ${eth(odds.listedBackingWei, 2)} ETH listed backing`}
      />
      <Stat
        label="Game"
        value={!g.activated ? "Not live" : g.paused ? "Paused" : "Live"}
        sub={`${g.unsettled.toString()} pulls settling, ${(g.lastIssued).toLocaleString("en-US")} pulls so far`}
      />
    </div>
  );
}
