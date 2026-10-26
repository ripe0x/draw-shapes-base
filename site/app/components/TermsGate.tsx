"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useDisconnect } from "wagmi";
import { useTermsAcceptance } from "../lib/terms-acceptance";
import { useDeployment } from "../Providers";

/**
 * Clickwrap: the first time a wallet connects (and again when the Terms change) it must tick the
 * box and accept before it can use the site. Disconnecting is the only other way out.
 */
export function TermsGate() {
  const dep = useDeployment();
  const { address } = useAccount();
  const { disconnect } = useDisconnect();
  const { accepted, accept } = useTermsAcceptance(dep.chainId, address);
  const [checked, setChecked] = useState(false);
  const path = usePathname();

  if (!address || accepted !== false || path?.startsWith("/terms")) return null;
  return (
    <div className="terms-gate" role="dialog" aria-modal="true" aria-labelledby="terms-gate-title">
      <div className="terms-gate-card">
        <h2 id="terms-gate-title" className="vault-h2">
          Before you play
        </h2>
        <ul className="terms-gate-points">
          <li>Every pull is random. On average a pull returns less ETH than it costs (about 85 %), so expect to lose over time.</li>
          <li>Each prize holds ETH that its contract pays out when you redeem it. Transactions on Base are final.</li>
          <li>You must be 18 or older, and it is up to you to make sure playing is legal where you are.</li>
          <li>Not available to sanctioned persons or in sanctioned regions.</li>
          <li>Disputes go to individual arbitration; no class actions.</li>
          {dep.chainId === 84532 && <li>This is the Base Sepolia test network: test ETH has no value.</li>}
        </ul>
        <label className="terms-gate-check">
          <input type="checkbox" checked={checked} onChange={(e) => setChecked(e.target.checked)} />
          <span>
            I am 18 or older and I agree to the{" "}
            <Link href="/terms" target="_blank">
              Terms of Use
            </Link>
            .
          </span>
        </label>
        <div className="row-actions">
          <button type="button" className="btn-filled" disabled={!checked} onClick={accept}>
            Agree and continue
          </button>
          <button type="button" className="btn-outline" onClick={() => disconnect()}>
            Disconnect
          </button>
        </div>
      </div>
    </div>
  );
}
