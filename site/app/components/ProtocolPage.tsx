"use client";

import { eth, pct } from "../lib/format";
import { usePool } from "../lib/pool";
import { useDeployment } from "../Providers";
import { GrailBoard } from "./GrailBoard";
import { Eth, Kv } from "./Measure";
import { OddsGlance } from "./OddsGlance";
import { ParamsDisclosure } from "./ParamsDisclosure";
import { Upkeep } from "./Upkeep";
import { VaultStats } from "./VaultStats";

const FAQS = [
  {
    question: "What happens when someone pulls?",
    answer:
      "The pull pays the ticket, a 1 % settlement fee and one VRF fee for the batch to the engine, a protocol-owned fork of FWA's custom pool. Chainlink VRF returns a random word, the engine selects one listing per pull by weight 1e36 divided by list price and sends it to the purchaser, usually inside the VRF callback. A later settle books the capture on the controller, splits the margin and queues a replacement.",
  },
  {
    question: "Where does a ticket go?",
    answer:
      "The ticket is the harmonic mean of the selectable list prices. The controller receives it when the pull settles. The margin over the captured item's backing first repays the replacement mint fee to the Shapes creator, then splits premium : maintenance : feed. The premium stays in the ordinary pool, and after genesis its realised surplus funds ENGINE buybacks. Maintenance refunds keeper gas. The feed goes to the GRAIL fund. The settlement fee pays the referrer half (development without one), Token Works a quarter and development a quarter.",
  },
  {
    question: "What does the VRF fee pay for?",
    answer:
      "Chainlink's charge for the batch's random word, priced at the block basefee with Chainlink's 60 % premium and a buffer, forwarded to the subscription in the purchase. The mainnet build adds a 30 % service margin on the same gas cost, credited to development (FWA V2's model); the Base Sepolia test deployment predates it. It is one fee per batch, so it falls per pull as the batch grows, and it is not refunded.",
  },
  {
    question: "Why can a pull be refunded?",
    answer:
      "If the random word arrives after the deadline, if the ticket fell further than the purchaser's slippage limit before the pull was processed, or if delivery fails, the engine credits the ticket and settlement fee back to the purchaser, who withdraws them on the Pull page. The VRF fee is spent when the request is made.",
  },
  {
    question: "How does the GRAIL work?",
    answer:
      "The feed share of every margin and the treasury's trading fees fill the GRAIL fund. When the fund covers the current target and its mint fee, the vault mints a Shape holding that ETH and lists it at a fraction of its backing; each pull lowers its price down to a floor, so its odds rise, while the decay pauses if GRAILs would pass the probability cap. The target steps up the ladder after a quick cycle and down after a slow one.",
  },
  {
    question: "Who pays for upkeep?",
    answer:
      "Settle refunds its caller's gas at basefee plus a small tip from the maintenance bucket, which the maintenance share of every margin refills. Keepers run settle, the GRAIL step and processing continuously, and anyone else can.",
  },
  {
    question: "Who controls what?",
    answer:
      "Every policy change goes through a 48-hour timelock owned by a multisig. A guardian can pause new pulls, listing, GRAIL steps and buybacks; settlement, delivery, refunds and claims always continue. No role can withdraw escrow, refund credits, fee credits, prizes, the GRAIL fund or the treasury reserve.",
  },
  {
    question: "What is ENGINE?",
    answer:
      "A fixed-supply token of 35 million: 10 million seeded the ETH/ENGINE Uniswap v4 pool at launch and 25 million are earned by pulling during the 14-day genesis. A 2 % fee on ENGINE trades funds the treasury (reserve, GRAIL fund and protocol-owned liquidity) and the operator. After genesis, realised surplus from the game buys ENGINE back and burns it.",
  },
] as const;

/** Board rows as a table: made of, share, backing per item, list price, item counts and target depth. */
function BoardTable() {
  const pool = usePool().data;
  if (!pool) return null;
  return (
    <div className="card">
      <h3 className="vault-h2">Board</h3>
      <div className="table-scroll">
        <table className="odds-table">
          <thead>
            <tr>
              <th>Row</th>
              <th>Made of</th>
              <th>Backing per item</th>
              <th>List price</th>
              <th>Listed</th>
              <th>Queued</th>
              <th>Target</th>
              <th>Chance</th>
            </tr>
          </thead>
          <tbody>
            {pool.board.map((r, i) => (
              <tr key={i}>
                <td>{i}</td>
                <td>{r.rungs.length > 1 ? `Draw Pack of ${r.rungs.length} Shapes` : "1 Shape"}</td>
                <td>{eth(r.backingWei)} ETH</td>
                <td>{eth(r.listingPrice, 5)} ETH</td>
                <td>{r.listed.toLocaleString("en-US")}</td>
                <td>{r.queued.toLocaleString("en-US")}</td>
                <td>{r.target.toLocaleString("en-US")}</td>
                <td>{pct(Number(r.oddsPpm) / 100)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="vault-note">
        Listed and queued count a row&apos;s items on the board and its replacements waiting to list. Backing is the redeemable value of
        one item at Shapes, at face.
      </p>
    </div>
  );
}

/** The ordinary pool, then the buckets outside it. */
function Buckets() {
  const pool = usePool().data;
  if (!pool) return null;
  return (
    <div className="card">
      <Kv label="Cash" value={<Eth wei={pool.cash} digits={4} />} />
      <Kv label="Backing on the board" value={<Eth wei={pool.backing} digits={4} />} />
      <Kv label="Receivable (settled pulls not yet harvested)" value={<Eth wei={pool.receivable} digits={4} />} />
      <Kv label="Ordinary pool" value={<Eth wei={pool.nav} digits={4} />} strong />
      <Kv label="Realised surplus releasable to buybacks" value={<Eth wei={pool.releasableSurplus} digits={5} />} />
      <Kv label="Maintenance" value={<Eth wei={pool.maintenance} digits={4} />} />
      <Kv label="GRAIL fund" value={<Eth wei={pool.grail.fund} digits={4} />} />
      <Kv label="Treasury reserve" value={<Eth wei={pool.market.treasuryReserve} digits={4} />} />
      <p className="vault-note">
        Ordinary pool = cash + backing + receivable, with backing counted at face. It belongs to the game: it pays every prize and lists
        every replacement. The GRAIL fund, the GRAILs, maintenance and the treasury sit outside it.
      </p>
    </div>
  );
}

function Section({ n, title, lead, children }: { n: string; title: string; lead: string; children: React.ReactNode }) {
  return (
    <section className="protocol-section">
      <div className="protocol-section-head">
        <span>{n}</span>
        <div>
          <h2>{title}</h2>
          <p>{lead}</p>
        </div>
      </div>
      {children}
    </section>
  );
}

/** `/protocol`: live pool state, the pull path, board, GRAIL, buckets, upkeep, control and FAQ. */
export function ProtocolPage() {
  const dep = useDeployment();
  const grailCapBps = usePool().data?.grail.probCapBps;

  return (
    <main className="protocol-page">
      <header className="protocol-hero">
        <h1>Protocol</h1>
        <p>Live game state, the path of a pull, the board and the GRAIL, the buckets, upkeep and governance.</p>
      </header>

      {!dep.present && (
        <p className="vault-note">This build has no deployment configured, so the live sections stay empty.</p>
      )}

      <Section n="01" title="Live state" lead="Current values read from the engine, the controller and the Lens.">
        <VaultStats />
      </Section>

      <Section
        n="02"
        title="One pull, end to end"
        lead="The ticket, the random draw and the replacement that follows."
      >
        <div className="protocol-flow">
          <article>
            <strong>Quote</strong>
            <p>The Lens quotes the ticket, the settlement fee and one VRF fee for the batch.</p>
          </article>
          <article>
            <strong>Acquire</strong>
            <p>The engine escrows the payment and requests one Chainlink VRF word for the batch.</p>
          </article>
          <article>
            <strong>Deliver</strong>
            <p>
              The VRF callback selects one listing per pull by weight 1e36 / list price and sends it to the purchaser.
            </p>
          </article>
          <article>
            <strong>Settle</strong>
            <p>Settle books the capture, splits the margin and queues a replacement row sampled from the mix.</p>
          </article>
        </div>
        <div className="protocol-data-grid">
          <OddsGlance />
          <BoardTable />
        </div>
      </Section>

      <Section
        n="03"
        title="GRAIL"
        lead="One fund fills to the ladder's target, then the vault mints and lists a GRAIL holding it."
      >
        <div className="protocol-data-grid">
          <GrailBoard detail />
        </div>
        <p className="vault-note">
          Each listed GRAIL&apos;s price drops by the decay amount per pull down to its floor, and the decay pauses while the GRAILs&apos;
          share of the selection weight would pass the probability cap{grailCapBps === undefined ? "" : ` of ${pct(grailCapBps)}`}. A
          captured GRAIL is the winner&apos;s to keep or redeem for its full backing.
        </p>
      </Section>

      <Section
        n="04"
        title="Buckets"
        lead="Every wei the game holds is in one bucket."
      >
        <Buckets />
      </Section>

      <Section
        n="05"
        title="Upkeep"
        lead="Settle books captures and lists replacements. The GRAIL step mints, lists and reprices GRAILs."
      >
        <Upkeep />
      </Section>

      <Section
        n="06"
        title="Capital and control"
        lead="What funds the game, and what governance can and cannot do."
      >
        <div className="protocol-principles">
          <article>
            <strong>Protocol-owned pool</strong>
            <p>The ordinary pool belongs to the game. There are no outside depositors; surplus buys back ENGINE.</p>
          </article>
          <article>
            <strong>Separate buckets</strong>
            <p>The GRAIL fund, GRAIL backing, maintenance and the treasury are accounted apart from the ordinary pool.</p>
          </article>
          <article>
            <strong>Timelock and guardian</strong>
            <p>Bounded parameter changes wait 48 hours in a timelock. A guardian can pause new exposure, never take funds.</p>
          </article>
        </div>
        <div className="card protocol-params">
          <h3 className="vault-h2">Current operating parameters</h3>
          <ParamsDisclosure />
        </div>
      </Section>

      <section className="protocol-section protocol-faq">
        <div className="protocol-section-head">
          <span>07</span>
          <div>
            <h2>Questions</h2>
          </div>
        </div>
        <div className="protocol-faq-list">
          {FAQS.map((item) => (
            <details key={item.question}>
              <summary>
                {item.question}
                <span>+</span>
              </summary>
              <p>{item.answer}</p>
            </details>
          ))}
        </div>
      </section>
    </main>
  );
}
