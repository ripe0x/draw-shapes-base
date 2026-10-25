import { useCallback, useEffect, useMemo, useState } from "react";
import { formatEther, parseAbiItem, parseEventLogs, type Address, type WalletClient } from "viem";
import { abi, addr, chain, connectWallet, publicClient, read } from "./chain";

const STATUS = ["None", "Pending", "Fulfilled", "Expired", "Refunded", "Ready", "TimedOut", "DeliveryPending", "DeliveryRefunded"];
const valueAbi = [parseAbiItem("function valueOf(uint256) view returns (uint256)")];

const eth = (v?: bigint, d = 6) => (v === undefined ? "–" : Number(formatEther(v)).toFixed(d));
const pct = (num: bigint, den: bigint) => (den === 0n ? "–" : (Number((num * 100000n) / den) / 1000).toFixed(2) + "%");
const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

type Live = {
  game?: any;
  quote?: any;
  board?: any[];
  grail?: any;
  genesis?: any;
  market?: any;
  refund?: bigint;
  error?: string;
};

function useReferrer(): Address | undefined {
  return useMemo(() => {
    const r = new URLSearchParams(window.location.search).get("ref");
    return r && /^0x[0-9a-fA-F]{40}$/.test(r) ? (r as Address) : undefined;
  }, []);
}

function loadPulls(account?: string): bigint[] {
  if (!account) return [];
  try {
    return (JSON.parse(localStorage.getItem(`pulls:${addr.engine}:${account}`) ?? "[]") as string[]).map(BigInt);
  } catch {
    return [];
  }
}

function savePulls(account: string, ids: bigint[]) {
  try {
    localStorage.setItem(`pulls:${addr.engine}:${account}`, JSON.stringify(ids.map(String)));
  } catch {
    /* storage unavailable */
  }
}

const grailStatus = (st?: number) =>
  st === 1 ? "Selectable" : st === 5 ? "Listed, selectable from the next pull" : st === 0 || st === undefined ? "Awaiting relist" : "Settling";

export default function App() {
  const [account, setAccount] = useState<Address>();
  const [wallet, setWallet] = useState<WalletClient>();
  const [count, setCount] = useState(10);
  const [live, setLive] = useState<Live>({});
  const [busy, setBusy] = useState<string>();
  const [msg, setMsg] = useState<string>();
  const [pulls, setPulls] = useState<bigint[]>([]);
  const [pullRows, setPullRows] = useState<any[]>([]);
  const referrer = useReferrer();

  const refresh = useCallback(async () => {
    try {
      const me = account ?? "0x0000000000000000000000000000000000000000";
      const [game, quote, board, grail, genesis, market] = await Promise.all([
        read<any>("lens", "game"),
        read<any>("lens", "quote", [BigInt(count)]),
        read<any[]>("lens", "board"),
        read<any>("lens", "grail"),
        read<any>("lens", "genesis", [me]),
        read<any>("lens", "market"),
      ]);
      const refund = account ? await read<bigint>("engine", "acquisitionRefundCredit", [account]) : 0n;
      setLive({ game, quote, board, grail, genesis, market, refund });
    } catch (e: any) {
      setLive((l) => ({ ...l, error: e?.shortMessage ?? String(e) }));
    }
  }, [account, count]);

  useEffect(() => {
    refresh();
    const t = setInterval(refresh, 6000);
    return () => clearInterval(t);
  }, [refresh]);

  useEffect(() => setPulls(loadPulls(account)), [account]);

  useEffect(() => {
    let stop = false;
    (async () => {
      const rows = [];
      for (const id of pulls.slice(-25).reverse()) {
        const a: any = await read("engine", "acquisitions", [id]);
        const status = STATUS[Number(a[4])];
        let prize = "";
        if (a[3] !== 0n) {
          const l: any = await read("engine", "listings", [a[3]]);
          try {
            const v = (await publicClient.readContract({ address: l[0], abi: valueAbi, functionName: "valueOf", args: [l[3]] })) as bigint;
            prize = `${eth(v, 3)} ETH ${l[0].toLowerCase() === addr.drawPacks.toLowerCase() ? "Draw Pack" : "Shape"} #${l[3]}`;
          } catch {
            prize = `token #${l[3]} (redeemed)`;
          }
        }
        rows.push({ id, status, prize, fee: a[2] });
      }
      if (!stop) setPullRows(rows);
    })();
    return () => {
      stop = true;
    };
  }, [pulls, live.game?.nextToProcess]);

  async function connect() {
    try {
      const { wallet, account } = await connectWallet();
      setWallet(wallet);
      setAccount(account);
    } catch (e: any) {
      setMsg(e?.message ?? String(e));
    }
  }

  async function send(label: string, contract: string, functionName: string, args: unknown[], value?: bigint) {
    if (!wallet || !account) return connect();
    setBusy(label);
    setMsg(undefined);
    try {
      const address = (contract === "vault" ? addr.grailVault : (addr as any)[contract]) as Address;
      const { request } = await publicClient.simulateContract({ address, abi: abi[contract], functionName, args, value, account });
      const hash = await wallet.writeContract({ ...request, chain, account } as any);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      setMsg(`${label}: confirmed in block ${receipt.blockNumber}`);
      return receipt;
    } catch (e: any) {
      setMsg(`${label}: ${e?.shortMessage ?? e?.message ?? String(e)}`);
    } finally {
      setBusy(undefined);
      refresh();
    }
  }

  async function pull() {
    const q = live.quote;
    if (!q || !account) return connect();
    // deadline from chain time, not the local clock
    const block = await publicClient.getBlock();
    const deadline = block.timestamp + 600n;
    const ANY = 2n ** 256n - 1n;
    // maxAcquisitionFee = the quoted fee; 10 % negative settlement tolerance (FWA UI default)
    const receipt = await send(
      `Pull ×${count}`,
      "engine",
      "acquireBatch",
      [account, referrer ?? "0x0000000000000000000000000000000000000000", BigInt(count), q.fee, 0n, 1000n, ANY, deadline],
      // the VRF fee follows the basefee: send a 25 % margin on it; the engine returns any excess
      q.total + q.vrfFee / 4n,
    );
    if (receipt) {
      const events = parseEventLogs({ abi: abi.engine, logs: receipt.logs, eventName: "AcquisitionRequested" }) as any[];
      const ids = [...pulls, ...events.map((e) => e.args.requestId as bigint)];
      setPulls(ids);
      savePulls(account, ids);
    }
  }

  const g = live.game;
  const state = !g ? "Loading live state…" : !g.activated ? "Not open yet — the game and ENGINE open together at activation" : g.paused ? "Paused: new pulls are off; settlement and refunds continue" : "Live";
  const grail = live.grail;
  const grailNeed = grail ? grail.targetWei + grail.mintFee : 0n;
  const grailPct = grail && grailNeed > 0n ? Math.min(100, Number((grail.funded * 10000n) / grailNeed) / 100) : 0;
  const perPull = live.quote ? live.quote.total / BigInt(count) : 0n;
  const gen = live.genesis;

  return (
    <div className="page">
      <header>
        <h1>Draw Shapes</h1>
        <span className={`state ${g?.activated && !g?.paused ? "live" : "off"}`}>{state}</span>
        <button onClick={connect}>{account ? short(account) : "Connect wallet"}</button>
      </header>

      <section className="hero card">
        <h2>Pull for real ETH-backed prizes</h2>
        <p>
          Every prize is a Shape or Draw Pack holding redeemable ETH. A pull picks one listing at random with Chainlink VRF; cheaper
          listings are more likely (weight ∝ 1 / notional), and the price is the harmonic mean of everything listed.
        </p>
        <div className="pullrow">
          {[1, 5, 10, 20].map((n) => (
            <button key={n} className={n === count ? "on" : ""} onClick={() => setCount(n)}>
              ×{n}
            </button>
          ))}
          <button className="primary" disabled={!!busy || !live.quote?.purchasable} onClick={pull}>
            {busy?.startsWith("Pull") ? "Pulling…" : `Pull ×${count} for ${eth(live.quote?.total)} ETH`}
          </button>
        </div>
        <dl className="facts">
          <div><dt>Per pull</dt><dd>{eth(perPull)} ETH</dd></div>
          <div><dt>Acquisition fee</dt><dd>{eth(live.quote?.fee)} ETH</dd></div>
          <div><dt>Settlement fee (1 %)</dt><dd>{eth(live.quote?.settlementFee)} ETH</dd></div>
          <div><dt>VRF fee (whole batch, not refundable)</dt><dd>{eth(live.quote?.vrfFee)} ETH</dd></div>
          <div><dt>Expected ETH backing per pull</dt><dd>{eth(g?.expectedBackingPerPull)} ETH ({perPull ? pct(g?.expectedBackingPerPull ?? 0n, perPull) : "–"} of payment)</dd></div>
        </dl>
        {!live.quote?.purchasable && live.quote?.reason && <p className="note">Pulls unavailable: {live.quote.reason}</p>}
        {referrer && <p className="note">Referred by {short(referrer)} — they receive half of the 1 % settlement fee of each delivered pull.</p>}
        <p className="note">Wallet gas is extra. On average a pull returns less ETH backing than it costs; the gap funds replacement mints, the game premium, maintenance and the GRAIL.</p>
      </section>

      <section className="card grail">
        <h2>GRAIL</h2>
        <p>
          The next GRAIL is a <b>{eth(grail?.targetWei, 2)} ETH</b> Shape. It is only minted and drawable once its full backing and mint
          fee are funded — by 4 % of every pull's notional and by ENGINE trading fees.
        </p>
        <div className="bar"><div style={{ width: `${grailPct}%` }} /></div>
        <p className="big">{eth(grail?.funded, 4)} / {eth(grailNeed, 3)} ETH funded ({grailPct.toFixed(1)} %)</p>
        {grail?.items?.length > 0 && (
          <table>
            <thead><tr><th>Funded GRAIL</th><th>Backing</th><th>Notional</th><th>Status</th><th>Odds per pull</th></tr></thead>
            <tbody>
              {grail.items.map((it: any, i: number) => (
                <tr key={i}>
                  <td>Shape #{String(it.tokenId)}</td>
                  <td>{eth(it.backing, 3)} ETH</td>
                  <td>
                    {eth(it.notional, 4)} ETH
                    {grail.nextNotional?.[i] > 0n && <span className="note"> → {eth(grail.nextNotional[i], 4)} at next step</span>}
                  </td>
                  <td>{grailStatus(grail.status?.[i])}</td>
                  <td>{grail.oddsPpm[i] ? `1 in ${Math.round(1e6 / Number(grail.oddsPpm[i])).toLocaleString()}` : "–"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p className="note">
          {String(grail?.selectable ?? 0n)} selectable now · {grail?.items?.length ?? 0} fully funded · {eth(grail?.funded, 4)} ETH accumulating toward the next.
          A GRAIL's notional falls with every pull until its odds reach the 5 % cap or its notional reaches half its backing.
        </p>
      </section>

      <section className="card">
        <h2>The board</h2>
        <p className="note">Backing is the ETH inside the prize. Notional is its listing value: backing plus the game's markup (premium, maintenance and GRAIL feed) plus the replacement mint fee of each Shape in it.</p>
        <table>
          <thead><tr><th>Prize</th><th>Backing</th><th>Notional</th><th>Listed / target</th><th>Odds per pull</th></tr></thead>
          <tbody>
            {live.board?.map((r: any, i: number) => (
              <tr key={i}>
                <td>{r.rungs.length > 1 ? `Draw Pack of ${r.rungs.length}` : "Shape"}</td>
                <td>{eth(r.backing, 2)} ETH</td>
                <td>{eth(r.notional, 4)} ETH</td>
                <td>{String(r.listed)} / {String(r.target)}{r.queued > 0n ? ` (+${r.queued} restocking)` : ""}</td>
                <td>{(Number(r.oddsPpm) / 1e4).toFixed(2)} %</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      {account && (
        <section className="card">
          <h2>My pulls</h2>
          {live.refund ? (
            <p>
              Refund credit: {eth(live.refund)} ETH{" "}
              <button disabled={!!busy} onClick={() => send("Withdraw refund", "engine", "withdrawAcquisitionRefund", [])}>Withdraw</button>
            </p>
          ) : null}
          {pullRows.length === 0 ? <p className="note">No pulls from this browser yet.</p> : (
            <table>
              <thead><tr><th>#</th><th>Status</th><th>Prize</th></tr></thead>
              <tbody>{pullRows.map((r) => <tr key={String(r.id)}><td>{String(r.id)}</td><td>{r.status}</td><td>{r.prize}</td></tr>)}</tbody>
            </table>
          )}
          <p className="note">Prizes arrive in your wallet when their pull settles. Redeem a Shape or Pack for its ETH at any time on the Shapes contracts.</p>
        </section>
      )}

      <section className="card">
        <h2>Genesis farming</h2>
        {!gen?.started ? <p>Genesis has not started. It starts when paid pulls open.</p> : (
          <>
            <p>
              Epoch <b>{Math.min(Number(gen.currentEpoch) + 1, 14)} / 14</b>{Number(gen.currentEpoch) >= 14 ? " — genesis has ended; no further ENGINE is issued." : ""}. Each epoch
              distributes {Number(formatEther(gen.allocationPerEpoch)).toLocaleString()} ENGINE to that epoch's delivered pulls: 85 % by pull count, 15 % by a random bonus weight.
            </p>
            <dl className="facts">
              <div><dt>Delivered pulls this epoch</dt><dd>{String(gen.epochUnits)}</dd></div>
              <div><dt>Mine</dt><dd>{String(gen.userUnits)} (bonus weight {String(gen.userBonus)})</dd></div>
              <div><dt>Claimable now</dt><dd>{Number(formatEther(gen.userClaimable)).toLocaleString()} ENGINE</dd></div>
            </dl>
            <button disabled={!!busy || gen.userClaimable === 0n} onClick={() => {
              const epochs = Array.from({ length: Math.min(Number(gen.currentEpoch), 14) }, (_, i) => BigInt(i));
              send("Claim", "farm", "claim", [epochs]);
            }}>Claim ENGINE</button>
            <p className="note">Rewards are claimable once an epoch ends and every pull accepted in it has settled. Unclaimed rewards never expire.</p>
          </>
        )}
      </section>

      <section className="card warn">
        <h2>ENGINE</h2>
        <dl className="facts">
          <div><dt>Price</dt><dd>{live.market?.ethPerEngineE18 ? `${(Number(live.market.ethPerEngineE18) / 1e18).toExponential(3)} ETH` : "not trading yet"}</dd></div>
          <div><dt>Trading fee</dt><dd>{live.market ? `${Number(live.market.feeBps) / 100} % (0.25 % operator, rest treasury)` : "–"}</dd></div>
          <div><dt>Treasury to GRAILs so far</dt><dd>{eth(live.market?.treasuryToGrail, 4)} ETH</dd></div>
        </dl>
        <p>
          <b>ENGINE is a speculative token.</b> It is not backed by and gives no claim on the ETH in prizes, the game, the GRAIL fund or the
          treasury. After genesis, realised game surplus buys and burns ENGINE; that budget is a small part of game spending and does not
          guarantee any price. ENGINE can trade in other pools that pay no fee to the project.
        </p>
      </section>

      {msg && <div className="toast" onClick={() => setMsg(undefined)}>{msg}</div>}
      {live.error && <div className="toast err">RPC: {live.error}</div>}

      <footer>
        <span>{chain.name}</span>
        {["engine", "controller", "grailVault", "token", "farm", "hook", "treasury", "shapes", "drawPacks"].map((k) => (
          <span key={k}>{k}: {short((addr as any)[k])}</span>
        ))}
      </footer>
    </div>
  );
}
