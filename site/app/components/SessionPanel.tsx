"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { routerAbi } from "../lib/abi/game";
import { packsAbi, shapesAbi } from "../lib/abi/external";
import { eth } from "../lib/format";
import { usePool } from "../lib/pool";
import { usePulls } from "../lib/pulls";
import { useSession, useStack, type Prize } from "../lib/stack";
import { useDeployment } from "../Providers";
import { Eth, Stat } from "./Measure";
import { TokenArt } from "./TokenArt";
import { TxButton, TxLine, useTx } from "./Tx";

/**
 * The play session: the stack (wallet ETH + playable prizes at face + refund credit), the session
 * ledger, the prize tray with keep toggles, and the one-transaction cash out. Pulls spend playable
 * prizes first (PullCard); kept prizes and GRAILs are never spent.
 */
export function SessionPanel() {
  const dep = useDeployment();
  const { address } = useAccount();
  const stack = useStack();
  const pool = usePool().data;
  const pulls = usePulls().data;
  const { session, start, end } = useSession();
  const approveShapes = useTx();
  const approvePacks = useTx();
  const cashTx = useTx();
  const [summary, setSummary] = useState<{ pulls: number; net: bigint; best: bigint; minutes: number } | null>(null);

  if (!address) {
    return (
      <section className="vault-section session">
        <h2 className="vault-h2">Your session</h2>
        <p className="vault-note">Connect a wallet to see your stack and play your winnings.</p>
      </section>
    );
  }

  const totalWei = stack.walletWei + stack.creditWei + stack.prizes.reduce((t, p) => t + p.value, 0n);
  const lastIssued = pool?.game.lastIssued ?? 0n;
  const sinceId = session ? BigInt(session.startLastIssued) : lastIssued;
  const sessionCards = Object.values(pulls?.cards ?? {}).filter((c) => c.id > sinceId);
  const best = sessionCards.reduce((m, c) => (c.item && c.item.value > m ? c.item.value : m), 0n);
  const net = session ? totalWei - BigInt(session.startTotalWei) : 0n;

  function cashOut(prizes: Prize[]) {
    return cashTx.run(() =>
      cashTx.write({
        chainId: dep.chainId,
        address: dep.prizeRouter,
        abi: routerAbi,
        functionName: "cashOut",
        args: [prizes.filter((p) => !p.pack).map((p) => p.tokenId), prizes.filter((p) => p.pack).map((p) => p.tokenId), address!],
      }),
    );
  }

  function endSession() {
    setSummary({ pulls: sessionCards.length, net, best, minutes: Math.max(1, Math.round((Date.now() - (session?.startedAt ?? Date.now())) / 60_000)) });
    end();
  }

  return (
    <section className="vault-section session">
      <div className="session-head">
        <h2 className="vault-h2">Your session</h2>
        {session ? (
          <button type="button" className="btn-outline" onClick={endSession}>
            End session
          </button>
        ) : (
          stack.ready && (
            <button type="button" className="btn-outline" onClick={() => { setSummary(null); start(totalWei, lastIssued); }}>
              Start a session
            </button>
          )
        )}
      </div>

      {summary && (
        <div className="card session-summary">
          <h3 className="vault-h2">Session ended</h3>
          <div className="stat-grid">
            <Stat label="Pulls" value={summary.pulls.toLocaleString("en-US")} sub={`over ${summary.minutes} min`} />
            <Stat label="Net" value={`${summary.net < 0n ? "−" : "+"}${eth(summary.net < 0n ? -summary.net : summary.net, 5)} ETH`} sub="stack change, gas included" />
            <Stat label="Best hit" value={summary.best > 0n ? <Eth wei={summary.best} digits={3} /> : "-"} />
          </div>
          <p className="vault-note">Your prizes stay in your wallet holding their ETH. Cash them out below, keep them, or play them next time.</p>
        </div>
      )}

      <div className="stat-grid session-stack">
        <Stat label="Stack" value={<Eth wei={stack.stackWei} digits={4} />} sub="what you can play with" />
        <Stat label="Wallet" value={<Eth wei={stack.walletWei} digits={4} />} />
        <Stat
          label="Prizes to play"
          value={<Eth wei={stack.playableWei} digits={4} />}
          sub={`${stack.playable.length} ${stack.playable.length === 1 ? "prize" : "prizes"} at face value`}
        />
        <Stat label="Kept" value={<Eth wei={stack.keptWei} digits={4} />} sub={`${stack.prizes.length - stack.playable.length} kept, never spent`} />
        {stack.creditWei > 0n && <Stat label="Refund credit" value={<Eth wei={stack.creditWei} digits={5} />} />}
      </div>

      {session && (
        <p className="vault-note session-ledger">
          This session: {sessionCards.length} {sessionCards.length === 1 ? "pull" : "pulls"}, net {net < 0n ? "−" : "+"}
          {eth(net < 0n ? -net : net, 5)} ETH (wallet, prizes at face and credit; gas included)
          {best > 0n ? `, best hit ${eth(best, 3)} ETH` : ""}.
        </p>
      )}

      {stack.routerAvailable && stack.playable.length > 0 && (
        <div className="row-actions">
          {!stack.approvals?.shapes && (
            <TxButton
              tx={approveShapes}
              label="Enable playing Shapes (once)"
              outline
              onClick={() => void approveShapes.run(() => approveShapes.write({ chainId: dep.chainId, address: dep.shapes, abi: shapesAbi, functionName: "setApprovalForAll", args: [dep.prizeRouter, true] }))}
            />
          )}
          {!stack.approvals?.packs && (
            <TxButton
              tx={approvePacks}
              label="Enable playing Draw Packs (once)"
              outline
              onClick={() => void approvePacks.run(() => approvePacks.write({ chainId: dep.chainId, address: dep.drawPacks, abi: packsAbi, functionName: "setApprovalForAll", args: [dep.prizeRouter, true] }))}
            />
          )}
          {stack.approved && (
            <TxButton tx={cashTx} label={`Cash out ${stack.playable.length} prizes (${eth(stack.playableWei, 4)} ETH)`} outline onClick={() => void cashOut(stack.playable)} />
          )}
        </div>
      )}
      <TxLine tx={approveShapes} />
      <TxLine tx={approvePacks} />
      <TxLine tx={cashTx} />
      {stack.playable.length > 0 && !stack.approved && (
        <p className="vault-note">
          Two one-time approvals let the game redeem your prizes at face when you play them or cash them out. Each pull or cash-out is then
          a single confirmation.
        </p>
      )}

      {stack.prizes.length > 0 && (
        <div className="session-tray">
          {stack.prizes
            .slice()
            .reverse()
            .map((p) => (
              <div key={p.key} className={p.kept ? "tray-card is-kept" : "tray-card"}>
                <TokenArt token={{ collection: p.collection, tokenId: p.tokenId }} />
                <div className="tray-value">
                  {eth(p.value, 3)} ETH{p.grail ? " · GRAIL" : ""}
                </div>
                {p.grail ? (
                  <div className="tray-keep">Kept</div>
                ) : (
                  <button type="button" className="tray-keep" aria-pressed={p.kept} onClick={() => stack.toggleKeep(p.key)}>
                    {p.kept ? "Kept" : "Keep"}
                  </button>
                )}
              </div>
            ))}
        </div>
      )}
      {stack.prizes.length > 0 && (
        <p className="vault-note">
          Pulls spend your smallest playable prizes first, at face, then wallet ETH. Mark a prize Keep to hold it; GRAILs are always kept.
        </p>
      )}
    </section>
  );
}
