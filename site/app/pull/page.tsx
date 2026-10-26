"use client";

import { useState } from "react";
import { OddsGlance } from "../components/OddsGlance";
import { PullCard } from "../components/PullCard";
import { Pulls } from "../components/Pulls";
import { PullTicket } from "../components/PullTicket";
import { SessionPanel } from "../components/SessionPanel";

/** `/pull`: the pull card with batch size and price, the price breakdown, what a pull can draw, and
 *  the wallet's pulls with their reveal. */
export default function PullPage() {
  const [count, setCount] = useState(1);
  return (
    <main className="vault-page">
      <section className="vault-hero">
        <h1 className="vault-headline">Pull</h1>
        <p className="vault-lede">
          One pull buys one listing from the board at the ticket price. Chainlink VRF picks it, each listing weighted by the inverse of its
          list price, and the engine delivers it to your wallet, usually within seconds.
        </p>
      </section>
      <SessionPanel />
      <section className="vault-section two-col">
        <div>
          <div className="card">
            <h3 className="vault-h2">Pull</h3>
            <PullCard variant="panel" count={count} onCount={setCount} />
          </div>
        </div>
        <div>
          <PullTicket count={count} />
          <OddsGlance />
        </div>
      </section>
      <Pulls />
    </main>
  );
}
