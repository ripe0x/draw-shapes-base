import type { Metadata } from "next";
import { Archivo, IBM_Plex_Mono } from "next/font/google";
import { Providers } from "./Providers";
import { getDeployment } from "./lib/deployment";
import { Nav } from "./components/Nav";
import { SiteFooter } from "./components/SiteFooter";
import { TermsGate } from "./components/TermsGate";
import "./globals.css";
import "./vault.css";
import "./reveal.css";
import "./landing.css";

const archivo = Archivo({ subsets: ["latin"], weight: ["400", "500", "700", "800"], variable: "--font-archivo" });
const ibmPlexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["400", "500"], variable: "--font-mono" });

export const metadata: Metadata = {
  title: "Draw Shapes on Base",
  description: "Pull a Shape or a Draw Pack on Base. Each redeems for its ETH backing at face.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const deployment = getDeployment();
  return (
    <html lang="en">
      <body className={`${archivo.variable} ${ibmPlexMono.variable}`} suppressHydrationWarning>
        <Providers deployment={deployment}>
          <Nav />
          {deployment.chainId === 84532 && (
            <div className="testnet-banner">
              Base Sepolia test network: pulls use test ETH with no real value. Get some from the{" "}
              <a href="https://portal.cdp.coinbase.com/products/faucet" target="_blank" rel="noreferrer">Coinbase</a>,{" "}
              <a href="https://console.optimism.io/faucet" target="_blank" rel="noreferrer">Superchain</a> or{" "}
              <a href="https://faucets.chain.link/base-sepolia" target="_blank" rel="noreferrer">Chainlink</a> faucet.
            </div>
          )}
          {deployment.present ? (
            children
          ) : (
            <main className="vault-page">
              <h1 className="vault-headline">No deployment record</h1>
              <p className="vault-note">
                Chain {deployment.chainId} has no bundled record. Set <code>NEXT_PUBLIC_CHAIN_ID</code> to a chain with a file in{" "}
                <code>site/deployments/</code>.
              </p>
            </main>
          )}
          <SiteFooter />
          {deployment.present && <TermsGate />}
        </Providers>
      </body>
    </html>
  );
}
