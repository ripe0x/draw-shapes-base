"use client";

import { useState } from "react";
import { useAccount, useBalance, usePublicClient } from "wagmi";
import { decodeEventLog } from "viem";
import { fwaCloneAbi } from "../lib/abi/external";
import { formatTxError } from "../lib/errors";
import { eth } from "../lib/format";
import { estimateGas, MAX_COUNT, neededWei, pullState, readFresh, useQuote, usePool } from "../lib/pool";
import { usePulls } from "../lib/pulls";
import { referrerFor } from "../lib/referral";
import { useDeployment } from "../Providers";
import { Eth } from "./Measure";
import { PullBatchView, SealedPacks } from "./PullReveal";
import { TxButton, TxLine, useTx } from "./Tx";
import { poolAbi } from "../lib/abi/pool";
import { ACQ } from "../lib/pulls";

/**
 * The pull card: pool state, batch size, price and the pull button, then the batch it sent in place
 * of the button. `variant` picks the hero or panel chrome; state, copy and behavior match on both.
 */
export function PullCard({
  variant,
  count: countProp,
  onCount,
}: {
  variant: "hero" | "panel";
  /** Batch size held by the parent, so a sibling price panel reads the same quote. */
  count?: number;
  onCount?: (n: number) => void;
}) {
  const dep = useDeployment();
  const { address, chainId: walletChain } = useAccount();
  const client = usePublicClient({ chainId: dep.chainId });
  const pool = usePool().data;
  const tx = useTx();
  const finishTx = useTx();
  const pulls = usePulls();
  const [ownCount, setOwnCount] = useState(1);
  const count = countProp ?? ownCount;
  const setCount = onCount ?? setOwnCount;
  const quote = useQuote(count);
  const q = quote.data;
  const balance = useBalance({ address, chainId: dep.chainId, query: { refetchInterval: 12_000 } });
  const [shown, setShown] = useState<`0x${string}`>();

  const maxCount = pool ? Math.min(MAX_COUNT, Number(pool.params.maxBatch) || 1) : 1;
  const counts = Array.from({ length: maxCount }, (_, i) => i + 1);
  const state = pool ? pullState(pool) : undefined;

  function pull() {
    return tx.run(async () => {
      const f = await readFresh(client, dep, count);
      const req = {
        address: dep.fwaPool,
        abi: fwaCloneAbi,
        functionName: "acquireBatch",
        args: [address!, referrerFor(address!), BigInt(count), f.maxFee, 0n, f.negativeSlippageBps, f.version, f.deadline],
        value: f.value,
      } as const;
      // The engine prices the VRF fee at the block basefee; the sent value carries 10 % headroom and
      // the engine refunds the excess in the same transaction.
      const gas = await estimateGas(() => client!.estimateContractGas({ ...req, account: address! }));
      const hash = await tx.write({ ...req, chainId: dep.chainId, ...gas });
      setShown(hash);
      return hash;
    });
  }

  function again() {
    tx.reset();
    setShown(undefined);
  }

  const cardClass = variant === "hero" ? "pull-card pull-card-hero" : "pull-card pull-card-panel";
  // The sent batch: its first acquisition id from the receipt's AcquisitionRequested log.
  const firstId = shown ? firstRequestId(tx.receipt.data?.logs) : undefined;
  const batch = firstId !== undefined ? pulls.data?.batches.find((b) => b.ids.includes(firstId)) : undefined;
  // Pulls of this batch whose word arrived but whose delivery the VRF callback left for a later call.
  const waiting = batch ? batch.ids.filter((id) => pulls.data?.cards[id.toString()]?.status === ACQ.Ready).length : 0;

  // A sent pull: sealed cards until its acquisitions are read, then its cards.
  if (shown || (tx.pending && !tx.error)) {
    // wagmi reports a reverted receipt as an error carrying the revert reason.
    const reverted = tx.receipt.isError || tx.receipt.data?.status === "reverted";
    return (
      <div className={cardClass}>
        <h3 className="vault-h2">Your pull{count > 1 ? "s" : ""}</h3>
        {reverted ? (
          <div className="pack pack-broken">
            <p className="pack-title">The pull reverted</p>
            <p className="vault-note">The sent ETH stayed in the wallet. The gas is spent.</p>
          </div>
        ) : batch && pulls.data ? (
          <PullBatchView batch={batch} cards={pulls.data.cards} fresh={new Set(pulls.data.fresh)} />
        ) : (
          <SealedPacks count={count} sent={!!tx.hash} />
        )}
        <TxLine tx={tx} />
        {waiting > 0 && (
          <div className="row-actions">
            <TxButton
              tx={finishTx}
              label={`Finish delivering ${waiting} ${waiting === 1 ? "pull" : "pulls"}`}
              outline
              onClick={() =>
                void finishTx.run(() => finishTx.write({ chainId: dep.chainId, address: dep.pool, abi: poolAbi, functionName: "settle", args: [20n] }))
              }
            />
            <p className="vault-note">
              The randomness has arrived; {waiting === 1 ? "this pull waits" : "these pulls wait"} for a settle call, which keepers usually make
              within seconds. Anyone can make it, and it refunds the caller&apos;s gas.
            </p>
            <TxLine tx={finishTx} />
          </div>
        )}
        {(batch || reverted) && (
          <div className="pack-again">
            <button type="button" className="landing-pull-btn" onClick={again}>
              <span>{reverted ? "Try again" : "Pull again"}</span>
              <span aria-hidden>→</span>
            </button>
          </div>
        )}
      </div>
    );
  }

  const wrongNetwork = !!address && walletChain !== undefined && walletChain !== dep.chainId;
  const need = q ? neededWei(q) : 0n;
  const short = !!address && !wrongNetwork && !!balance.data && !!q && balance.data.value < need;

  let label: string;
  let disabled = true;
  if (!state) label = "Reading the pool";
  else if (!state.open) label = state.headline;
  else if (!q) label = "Pricing this batch";
  else if (!q.purchasable) label = q.reason ? `Unavailable: ${q.reason}` : "This batch size is unavailable";
  else if (!address) label = "Connect a wallet to pull";
  else if (short) label = "Not enough ETH";
  else {
    label = `Pull ${count} for ${eth(q.total, 5)} ETH`;
    disabled = false;
  }

  return (
    <div className={cardClass}>
      {state && (
        <>
          {!state.open && (
            <div className="pull-status-row">
              <span className={`landing-pill is-${state.tone}`}>
                <span className="landing-pill-dot" />
                {state.pill}
              </span>
            </div>
          )}
          <div className="pull-status-headline">{state.headline}</div>
          {state.sub && <div className="pull-status-sub">{state.sub}</div>}
        </>
      )}

      {variant === "panel" && q && state?.open && (
        <div className="pull-price">
          <p className="vault-note">
            <strong>{eth(q.total, 5)} ETH</strong> for {count} {count === 1 ? "pull" : "pulls"}: a <Eth wei={q.fee} digits={5} /> ticket and a{" "}
            <Eth wei={q.settlementFee} digits={6} /> settlement fee per pull, plus one <Eth wei={q.vrf} digits={6} /> VRF fee for the batch. The
            wallet sends 10% more and the engine refunds the excess in the same transaction.
          </p>
        </div>
      )}

      {state?.open && counts.length > 1 && (
        <div className="pull-quantity" role="group" aria-label="Number of pulls">
          <span className="pull-quantity-label">How many pulls?</span>
          <div className="pull-quantity-options">
            {counts.map((n) => (
              <button key={n} type="button" className={count === n ? "is-selected" : undefined} aria-pressed={count === n} onClick={() => setCount(n)}>
                {n}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="pull-cta">
        <button
          type="button"
          className={variant === "hero" ? "landing-pull-btn" : "btn-filled"}
          disabled={disabled || tx.pending}
          onClick={() => void pull()}
        >
          <span>{tx.pending ? "Confirm in your wallet" : label}</span>
          {variant === "hero" && <span aria-hidden>→</span>}
        </button>
      </div>
      {short && q && (
        <p className="pull-status-footer">
          The wallet holds {eth(balance.data!.value)} ETH. This pull needs about {eth(need)} ETH with gas.
        </p>
      )}
      {wrongNetwork && <p className="pull-status-footer">The wallet switches to the game&apos;s network when you pull.</p>}
      {quote.error && <p className="error-line">The quote failed: {formatTxError(quote.error)}</p>}
      <TxLine tx={tx} />
    </div>
  );
}

/** First acquisition id of a pull transaction, from its AcquisitionRequested logs. */
function firstRequestId(logs: readonly { data: `0x${string}`; topics: readonly `0x${string}`[] }[] | undefined): bigint | undefined {
  for (const l of logs ?? []) {
    try {
      const e = decodeEventLog({ abi: fwaCloneAbi, data: l.data, topics: l.topics as [`0x${string}`, ...`0x${string}`[]] });
      if (e.eventName === "AcquisitionRequested") return e.args.requestId;
    } catch {
      // another contract's log
    }
  }
  return undefined;
}
