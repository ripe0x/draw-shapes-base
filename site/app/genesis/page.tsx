"use client";

import { useAccount, usePublicClient, useReadContract } from "wagmi";
import { formatEther } from "viem";
import { fwaCloneAbi } from "../lib/abi/external";
import { farmAbi } from "../lib/abi/game";
import { utc } from "../lib/format";
import { claimableEpochs, useGenesis, usePool } from "../lib/pool";
import { useDeployment } from "../Providers";
import { Eth, Kv, Stat } from "../components/Measure";
import { TxButton, TxLine, useTx } from "../components/Tx";

const engine = (wei: bigint, digits = 0) => `${Number(formatEther(wei)).toLocaleString("en-US", { maximumFractionDigits: digits })} ENGINE`;

/** `/genesis`: the 14-day ENGINE genesis (epochs, the wallet's units and claimable ENGINE), the
 *  wallet's referral link and fee credit, and the ENGINE market. */
export default function GenesisPage() {
  return (
    <main className="vault-page">
      <section className="vault-hero">
        <h1 className="vault-headline">Genesis</h1>
        <p className="vault-lede">
          For the first 14 days, every settled pull earns participation units in its day&apos;s epoch. Each epoch shares 1/14 of the 25
          million ENGINE genesis allocation among its units. Rewards become claimable once the epoch has ended and every pull accepted in it
          has settled, and they never expire.
        </p>
      </section>
      <section className="vault-section two-col">
        <div>
          <GenesisCard />
          <ReferralCard />
        </div>
        <div>
          <MarketCard />
        </div>
      </section>
    </main>
  );
}

function GenesisCard() {
  const dep = useDeployment();
  const { address } = useAccount();
  const client = usePublicClient({ chainId: dep.chainId });
  const g = useGenesis().data;
  const tx = useTx();
  if (!g) return <div className="card"><p className="vault-note">Reading genesis.</p></div>;
  const now = Math.floor(Date.now() / 1000);
  const ended = g.started && now >= Number(g.end);
  const epochLabel = !g.started ? "Not started" : ended ? "Ended" : `${(Number(g.currentEpoch) + 1).toString()} of 14`;
  const share = g.epochUnits > 0n ? Number((g.userUnits * 10_000n) / g.epochUnits) / 100 : 0;

  function claim() {
    return tx.run(async () => {
      const epochs = await claimableEpochs(client!, dep, address!, g!.currentEpoch);
      if (!epochs.length) throw new Error("No epoch has a final, unclaimed reward for this wallet yet.");
      return tx.write({ address: dep.farm, abi: farmAbi, functionName: "claim", args: [epochs], chainId: dep.chainId });
    });
  }

  return (
    <div className="card">
      <h3 className="vault-h2">ENGINE genesis</h3>
      <div className="stat-grid">
        <Stat label="Epoch" value={epochLabel} sub={g.started ? `${utc(g.start)} to ${utc(g.end)}` : undefined} />
        <Stat label="Per epoch" value={engine(g.allocationPerEpoch)} />
        <Stat label="Units this epoch" value={g.epochUnits.toLocaleString("en-US")} sub={`${g.epochBonus.toString()} bonus weight`} />
        <Stat label="Claimed by everyone" value={engine(g.totalClaimed)} />
      </div>
      <h3 className="vault-h2" style={{ marginTop: 18 }}>
        Your genesis
      </h3>
      {!address ? (
        <p className="vault-note">Connect a wallet to see its units and rewards.</p>
      ) : (
        <>
          <Kv label="Your units this epoch" value={`${g.userUnits.toLocaleString("en-US")}${share ? ` (${share}% of the epoch)` : ""}`} />
          <Kv label="Your bonus weight this epoch" value={g.userBonus.toString()} />
          <Kv label="Claimable now" value={engine(g.userClaimable, 2)} strong />
          <div className="row-actions">
            <TxButton tx={tx} label="Claim ENGINE" disabled={g.userClaimable === 0n} onClick={() => void claim()} />
          </div>
          <TxLine tx={tx} />
        </>
      )}
      <p className="vault-note">
        85 % of each epoch&apos;s allocation is shared by units (one per settled pull) and 15 % by bonus weight. Allocations of epochs nobody
        played are retired after genesis.
      </p>
    </div>
  );
}

function ReferralCard() {
  const dep = useDeployment();
  const { address } = useAccount();
  const credit = useReadContract({
    chainId: dep.chainId,
    address: dep.fwaPool,
    abi: fwaCloneAbi,
    functionName: "feeCreditOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 12_000 },
  }).data;
  const tx = useTx();
  const link = address && typeof window !== "undefined" ? `${window.location.origin}/?ref=${address}` : undefined;
  return (
    <div className="card">
      <h3 className="vault-h2">Referrals</h3>
      <p className="vault-note">
        A pull made through your link pays you half of its settlement fee (0.5 % of the ticket), credited when the pull settles.
      </p>
      {!address ? (
        <p className="vault-note">Connect a wallet to get your link.</p>
      ) : (
        <>
          <Kv label="Your link" value={<code style={{ wordBreak: "break-all" }}>{link}</code>} />
          <Kv label="Your fee credit" value={<Eth wei={credit ?? 0n} digits={6} />} strong />
          <div className="row-actions">
            <TxButton
              tx={tx}
              label="Withdraw fee credit"
              outline
              disabled={!credit}
              onClick={() =>
                void tx.run(() => tx.write({ address: dep.fwaPool, abi: fwaCloneAbi, functionName: "withdrawFeeCredit", args: [address], chainId: dep.chainId }))
              }
            />
          </div>
          <TxLine tx={tx} />
        </>
      )}
    </div>
  );
}

function MarketCard() {
  const m = usePool().data?.market;
  if (!m) return null;
  return (
    <div className="card">
      <h3 className="vault-h2">ENGINE market</h3>
      <div className="stat-grid">
        <Stat label="Price" value={`${(Number(m.ethPerEngineE18) / 1e18).toPrecision(3)} ETH`} sub="per ENGINE, Uniswap v4 pool" />
        <Stat label="Trading fee" value={`${(Number(m.feeBps) / 100).toString()}%`} sub={`${(Number(m.operatorBps) / 100).toString()}% to the operator`} />
        <Stat label="Volume" value={<Eth wei={m.totalVolume} digits={3} />} />
        <Stat label="Fees" value={<Eth wei={m.totalFees} digits={5} />} />
      </div>
      <Kv label="Treasury reserve" value={<Eth wei={m.treasuryReserve} digits={4} />} />
      <Kv label="Sent to the GRAIL fund" value={<Eth wei={m.treasuryToGrail} digits={5} />} />
      <Kv label="Protocol-owned liquidity pending" value={<Eth wei={m.treasuryPolPending} digits={5} />} />
      <p className="vault-note">
        The treasury fills its reserve first, then sends trading fees to the GRAIL fund (all of them while no GRAIL is live) and to
        protocol-owned liquidity. After genesis, surplus from the game buys ENGINE in small hourly slices and burns it.
      </p>
      <p className="vault-note">ENGINE has a fixed supply of 35 million: 10 million in the launch liquidity and 25 million for genesis.</p>
    </div>
  );
}
