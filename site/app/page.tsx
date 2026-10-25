"use client";

import Link from "next/link";
import { drawOdds, usePool } from "./lib/pool";
import { eth } from "./lib/format";
import { CardFan } from "./components/CardFan";
import { GrailBoard } from "./components/GrailBoard";
import { OddsGlance } from "./components/OddsGlance";
import { PoolGrid } from "./components/PoolGrid";
import { PullCard } from "./components/PullCard";
import { SessionPanel } from "./components/SessionPanel";
import { useAccount } from "wagmi";

/** `/`: the pull promise and live board summary, the card carousel, the pull card, the listed items
 *  grid beside the GRAIL, what a pull can draw and the ENGINE genesis band. */
export default function Landing() {
  const pool = usePool().data;
  const odds = pool ? drawOdds(pool.board, pool.grail) : undefined;
  const smallestWei = odds?.rows[0]?.backingWei;
  const connected = !!useAccount().address;

  return (
    <main className="landing-page">
      <section className="landing-hero" id="pull">
        <h1 className="landing-hero-promise">
          Draw a card.
          <br />
          Redeem for ETH.
        </h1>
        {odds && (
          <p className="landing-hero-pool-summary">
            <strong>{eth(odds.listedBackingWei)} ETH</strong> of backing listed across{" "}
            <strong>{odds.listedItems.toLocaleString("en-US")} Shapes and Draw Packs</strong>. Largest: <strong>{eth(odds.largestWei)} ETH</strong>.
          </p>
        )}
        <CardFan />
        <PullCard variant="hero" />
      </section>
      {connected && (
        <div className="landing-session">
          <SessionPanel />
        </div>
      )}

      <div className="landing-facts">
        <div className="landing-fact">
          <div className="landing-fact-title">Every pull draws a Shape or a Draw Pack</div>
          <div className="landing-fact-sub">
            Each one redeems at Shapes for its ETH backing at face.
            {smallestWei !== undefined && ` The smallest listed holds ${eth(smallestWei)} ETH.`}
          </div>
        </div>
        <div className="landing-fact">
          <div className="landing-fact-title">A GRAIL waits on the board</div>
          <div className="landing-fact-sub">
            Every pull feeds the GRAIL fund.{pool ? ` When it holds ${eth(pool.grail.targetWei, 3)} ETH, a GRAIL with that backing lists.` : ""} Its
            price drops a little with every pull, so its odds rise.
          </div>
        </div>
        <div className="landing-fact">
          <div className="landing-fact-title">Built on FWA, on Base</div>
          <div className="landing-fact-sub">
            A protocol-owned fork of{" "}
            <a href="https://www.fwa.fun/" target="_blank" rel="noreferrer">
              FWA
            </a>
            &apos;s custom pool selects each item with Chainlink VRF and delivers it to your wallet.
          </div>
        </div>
      </div>

      <div className="landing-pool-layout">
        <PoolGrid />
        <div className="landing-grail-col">
          <GrailBoard />
        </div>
      </div>

      <div className="landing-odds-row">
        <OddsGlance />
      </div>

      <div className="landing-supply-band">
        <div>
          <div className="landing-supply-title">Pull during genesis, earn ENGINE</div>
          <div className="landing-supply-sub">
            For 14 days after launch, every settled pull earns a share of that day&apos;s 1/14 of 25 million ENGINE. ENGINE trades against
            ETH on Uniswap v4; its trading fees fund the treasury and the GRAIL, and surplus from the game buys ENGINE back and burns it.
          </div>
        </div>
        <Link className="landing-supply-link" href="/genesis">
          Genesis
        </Link>
      </div>

      <div className="landing-how-it-works">
        <p>
          The controller mints Shapes and Draw Packs and lists them on the engine. A pull pays the ticket, and the controller lists a
          replacement for every item drawn. {pool && `${pool.listedCount.toLocaleString("en-US")} items are listed now.`}{" "}
          <Link href="/protocol">How it works</Link>
        </p>
      </div>
    </main>
  );
}
