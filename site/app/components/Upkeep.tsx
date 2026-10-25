"use client";

import { fwaCloneAbi } from "../lib/abi/external";
import { vaultAbi } from "../lib/abi/game";
import { poolAbi } from "../lib/abi/pool";
import { eth } from "../lib/format";
import { usePool } from "../lib/pool";
import { useDeployment } from "../Providers";
import { Kv } from "./Measure";
import { TxButton, TxLine, useTx } from "./Tx";

/** What is waiting, and the permissionless upkeep calls the keepers make: `settle`, the GRAIL vault
 *  `step` and `processAcquisitions`. */
export function Upkeep() {
  const dep = useDeployment();
  const pool = usePool().data;
  const settleTx = useTx();
  const stepTx = useTx();
  const processTx = useTx();
  if (!pool) return null;
  const g = pool.game;
  const unbooked = g.lastIssued >= g.nextToBook ? g.lastIssued - g.nextToBook + 1n : 0n;

  return (
    <div className="protocol-data-grid">
      <div className="card">
        <h3 className="vault-h2">Waiting</h3>
        <Kv label="Pulls awaiting randomness or processing" value={g.unsettled.toLocaleString("en-US")} />
        <Kv label="Settled pulls not yet booked by the controller" value={unbooked.toLocaleString("en-US")} />
        <Kv label="Replacements queued" value={pool.queueLength.toLocaleString("en-US")} />
        <Kv label="GRAIL vault step due" value={pool.grail.stepDue ? "yes" : "no"} />
        <Kv label="Maintenance balance" value={`${eth(pool.maintenance, 4)} ETH (floor ${eth(pool.params.maintenanceFloor, 3)} ETH)`} />
        <Kv label="VRF subscription" value={`${eth(pool.vrf.subscriptionBalance, 4)} ETH`} />
      </div>
      <div className="card">
        <h3 className="vault-h2">Upkeep calls</h3>
        <p className="vault-note">
          Anyone can call these; two keepers run them continuously. Settle refunds the caller&apos;s gas at basefee plus a{" "}
          {eth(pool.params.tipWei, 6)} ETH tip from maintenance.
        </p>
        <div className="row-actions">
          <TxButton
            tx={settleTx}
            label="Settle"
            onClick={() => void settleTx.run(() => settleTx.write({ chainId: dep.chainId, address: dep.pool, abi: poolAbi, functionName: "settle", args: [20n] }))}
          />
          <TxButton
            tx={stepTx}
            label="GRAIL step"
            outline
            disabled={!pool.grail.stepDue}
            onClick={() => void stepTx.run(() => stepTx.write({ chainId: dep.chainId, address: dep.grailVault, abi: vaultAbi, functionName: "step" }))}
          />
          <TxButton
            tx={processTx}
            label="Process pulls"
            outline
            disabled={g.unsettled === 0n}
            onClick={() =>
              void processTx.run(() =>
                processTx.write({ chainId: dep.chainId, address: dep.fwaPool, abi: fwaCloneAbi, functionName: "processAcquisitions", args: [20n] }),
              )
            }
          />
        </div>
        <TxLine tx={settleTx} />
        <TxLine tx={stepTx} />
        <TxLine tx={processTx} />
        <p className="vault-note">
          Settle books up to 20 pulls, collects their proceeds, splits the margin and lists replacements. The GRAIL step mints, lists and
          reprices GRAILs. Process pulls resolves pulls whose randomness arrived but did not settle in the VRF callback, and refunds pulls
          whose randomness came too late.
        </p>
      </div>
    </div>
  );
}
