import type { Metadata } from "next";
import { CONTACT, OPERATOR, TERMS_VERSION } from "../lib/legal";
import "./terms.css";

export const metadata: Metadata = { title: "Terms of Use · Draw Shapes on Base" };

const testnet = process.env.NEXT_PUBLIC_CHAIN_ID === "84532";
const contact = CONTACT ? <a href={CONTACT.includes("@") ? `mailto:${CONTACT}` : CONTACT}>{CONTACT}</a> : "the contact listed on this site";

export default function Page() {
  return (
    <main className="vault-page terms-page">
      <h1 className="vault-headline">Terms of Use</h1>
      <p className="vault-note">Version {TERMS_VERSION}</p>

      <section className="vault-section">
        <h2 className="vault-h2">1. Agreement</h2>
        <p>
          These Terms are an agreement between you and {OPERATOR} (&ldquo;we&rdquo;, &ldquo;us&rdquo;), which operates this website (the
          &ldquo;Interface&rdquo;). You accept them by ticking the box and choosing &ldquo;Agree and continue&rdquo; when you connect a wallet, or
          by using the Interface. If you do not agree, do not use it. Section 13 requires individual arbitration and waives class actions.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">2. Who may play</h2>
        <p>You confirm that:</p>
        <ul>
          <li>you are at least 18 years old and old enough to enter a binding contract where you live;</li>
          <li>
            taking part in a game of chance with prizes of monetary value is lawful for you where you are, and you are solely responsible for
            complying with the laws that apply to you;
          </li>
          <li>
            you are not the subject of sanctions administered by the United States, the United Kingdom, the European Union or the United
            Nations, are not located in a comprehensively sanctioned country or region, and are not acting for anyone who is;
          </li>
          <li>you are using your own wallet and funds, for yourself.</li>
        </ul>
        <p>If any of these stops being true, you must stop using the Interface.</p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">3. What Draw Shapes is</h2>
        <p>
          The Interface is a website for interacting with smart contracts on the Base network. A pull pays a ticket, a settlement fee and a
          randomness (VRF) fee. Chainlink VRF supplies the random number that selects a prize. Every prize is a Shape or a Draw Pack: an
          NFT holding ETH that its contract pays to the holder on redemption.
        </p>
        <p>
          <strong>
            Outcomes are random. On average a pull returns less ETH than it costs (about 85 %), so over time you should expect to lose
            money.
          </strong>{" "}
          The odds and the average return shown in the Interface are read from the contracts and change as the board changes. Past results
          say nothing about future pulls. Play only with money you can afford to lose.
        </p>
        {testnet && (
          <p>
            This deployment runs on the Base Sepolia test network. Test ETH and test tokens have no monetary value, and the test deployment
            may be reset or abandoned at any time.
          </p>
        )}
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">4. Your wallet and transactions</h2>
        <p>
          The Interface is non-custodial: we never hold your keys or your funds. You are responsible for your wallet, its security and every
          transaction you sign. Blockchain transactions are final and cannot be reversed by us. You pay network gas for your own transactions.
        </p>
        <p>
          Refunds happen only where the contracts provide for them (for example a pull whose random word arrives late, or whose price moved
          past your slippage limit), as refund credit you can apply to your next pull or withdraw. The VRF fee is not refunded.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">5. ENGINE</h2>
        <p>
          ENGINE is the game&rsquo;s token. It is not offered as an investment, and nothing in the Interface is an offer of securities or
          financial advice. We make no promise that ENGINE will have or keep any value or liquidity. Mechanisms described in the protocol
          documentation, such as buybacks, run in the contracts under parameters that governance may change, and may never occur.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">6. Risks</h2>
        <p>Using the Interface and the contracts involves risks, including:</p>
        <ul>
          <li>bugs or exploits in the smart contracts, which have not been independently audited;</li>
          <li>delays or failures of the Base network, Chainlink VRF, RPC providers, keepers or the Interface;</li>
          <li>prices and odds changing between your purchase and its settlement;</li>
          <li>the market value of NFTs and ENGINE falling, including to zero;</li>
          <li>changes in law or regulation that limit or end the game where you are;</li>
          <li>losing access to your wallet.</li>
        </ul>
        <p>You accept these risks.</p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">7. Prohibited use</h2>
        <p>
          You must not use the Interface or the contracts to launder money, evade sanctions, finance unlawful activity, exploit a bug, or let
          anyone under 18 play. We may block wallets from the Interface for any of these.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">8. Availability and changes</h2>
        <p>
          We may change, suspend or stop the Interface at any time, and may pause new pulls through the protocol&rsquo;s guardian role. The
          contracts may remain callable directly; using them outside the Interface is at your own risk and still subject to these Terms.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">9. Intellectual property</h2>
        <p>
          The tokens you hold are yours. The Interface, its design and its content (other than your tokens) belong to us or our licensors;
          you may use them only to use the Interface.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">10. No warranties</h2>
        <p>
          The Interface and the contracts are provided &ldquo;as is&rdquo; and &ldquo;as available&rdquo;, without warranties of any kind,
          express or implied, including merchantability, fitness for a particular purpose and non-infringement, to the fullest extent the law
          allows.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">11. Limitation of liability</h2>
        <p>
          To the fullest extent the law allows, we are not liable for any indirect, incidental, special, consequential or punitive damages,
          or for lost profits, lost funds or lost data, arising from the Interface or the contracts. Our total liability for any claim is
          limited to the greater of US$100 and the fees we received from your pulls in the 12 months before the claim arose.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">12. Indemnity</h2>
        <p>
          You will indemnify us against claims, losses and costs arising from your breach of these Terms or of any law in your use of the
          Interface or the contracts.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">13. Disputes: individual arbitration, no class actions</h2>
        <p>
          Any dispute between you and us arising from these Terms, the Interface or the contracts will be resolved by binding individual
          arbitration administered by the American Arbitration Association under its Consumer Arbitration Rules, except that either side may
          bring an individual claim in small-claims court. The Federal Arbitration Act governs this section.
        </p>
        <p>
          <strong>
            You and we each waive the right to a jury trial and to bring or join a class, collective or representative action.
          </strong>{" "}
          The arbitrator may award relief only to you individually. If this waiver is found unenforceable for a claim, that claim goes to court
          and the rest of this section still applies.
        </p>
        <p>
          You may opt out of arbitration within 30 days of first accepting these Terms by sending your wallet address and a statement that
          you opt out to {contact}.
        </p>
      </section>

      <section className="vault-section">
        <h2 className="vault-h2">14. General</h2>
        <p>
          These Terms are governed by the laws of the state in which {OPERATOR} is organized, without regard to conflict-of-law rules. We may
          update them; when we do, the Interface asks you to accept the new version before you continue. If a provision is unenforceable, the
          rest remains in effect. These Terms are the whole agreement between you and us about the Interface. Notices to us go to {contact}.
        </p>
      </section>
    </main>
  );
}
