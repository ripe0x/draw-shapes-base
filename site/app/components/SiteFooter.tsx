"use client";

import Link from "next/link";
import { useDeployment } from "../Providers";
import { evmNowAddressUrl } from "../lib/errors";

/** Protocol page and the deployment's contracts on evm.now. */
export function SiteFooter() {
  const dep = useDeployment();
  const contracts = [
    ["Engine", dep.fwaPool],
    ["Controller", dep.pool],
    ["GRAIL vault", dep.grailVault],
    ["Shapes", dep.shapes],
    ["Draw Packs", dep.drawPacks],
    ["ENGINE", dep.token],
    ["Timelock", dep.timelock],
  ] as const;
  return (
    <footer className="site-footer">
      <div className="site-footer-inner">
        <div className="site-footer-links">
          <Link href="/protocol">Protocol</Link>
          {dep.present &&
            contracts.map(([label, address]) =>
              address ? (
                <a key={label} href={evmNowAddressUrl(address, dep.chainId)} target="_blank" rel="noreferrer">
                  {label}
                </a>
              ) : null,
            )}
        </div>
        <span>
          by{" "}
          <a href="https://twitter.com/ripe0x" target="_blank" rel="noreferrer">
            ripe
          </a>
        </span>
      </div>
    </footer>
  );
}
