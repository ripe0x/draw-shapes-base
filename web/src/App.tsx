import { useCallback, useEffect, useMemo, useState } from "react";
import { formatEther, parseAbiItem, parseEventLogs, type Address, type WalletClient } from "viem";
import { abi, addr, addrUrl, chain, connectWallet, deployed, ensureChain, network, publicClient, read, target, txUrl } from "./chain";

const STATUS = ["None", "Pending", "Fulfilled", "Expired", "Refunded", "Ready", "TimedOut", "DeliveryPending", "DeliveryRefunded"];
// what each acquisition status means to a player
const STATUS_TEXT: Record<string, string> = {
  Pending: "Waiting for Chainlink randomness",
  Ready: "Randomness received — settling",
  Fulfilled: "Delivered to your wallet",
  Expired: "Expired — refunded (fee + settlement fee)",
  Refunded: "Refunded (price moved past your limit, or no prize was listed)",
  TimedOut: "Randomness arrived late — being refunded",
  DeliveryPending: "Prize won, delivery failed — retry below",
  DeliveryRefunded: "Delivery failed for 7 days — refunded",
};
const valueAbi = [parseAbiItem("function valueOf(uint256) view returns (uint256)")];
const ZERO = "0x0000000000000000000000000000000000000000" as Address;

const eth = (v?: bigint, d = 6) => (v === undefined || v === null ? "–" : Number(formatEther(v)).toFixed(d));
const pct = (num: bigint, den: bigint) => (den === 0n ? "–" : (Number((num * 100000n) / den) / 1000).toFixed(2) + " %");
const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");
const odds = (ppm?: bigint) => (ppm && ppm > 0n ? `1 in ${Math.round(1e6 / Number(ppm)).toLocaleString()}` : "–");

type Live = { game?: any; quote?: any; board?: any[]; grail?: any; genesis?: any; market?: any; split?: any; refund?: bigint;
  buyback?: { spent: bigint; burned: bigint; start: bigint; supply: bigint }; claimable?: bigint[]; balance?: bigint; chainNow?: bigint; error?: string };
type TxState = { label: string; phase: "wallet" | "submitted" | "confirmed" | "failed"; hash?: string; detail?: string };

function useReferrer(): Address | undefined {
  return useMemo(() => {
    const r = new URLSearchParams(window.location.search).get("ref");
    return r && /^0x[0-9a-fA-F]{40}$/.test(r) ? (r as Address) : undefined;
  }, []);
}
const pullsKey = (account: string) => `pulls:${addr.engine}:${account}`;
function loadPulls(account?: string): bigint[] {
  if (!account) return [];
  try { return (JSON.parse(localStorage.getItem(pullsKey(account)) ?? "[]") as string[]).map(BigInt); } catch { return []; }
}
function savePulls(account: string, ids: bigint[]) {
  try { localStorage.setItem(pullsKey(account), JSON.stringify(ids.map(String))); } catch { /* storage unavailable */ }
}
const Link = ({ href, children }: { href?: string; children: any }) => (href ? <a href={href} target="_blank" rel="noreferrer">{children}</a> : <>{children}</>);

export default function App() {
  const [account, setAccount] = useState<Address>();
  const [wallet, setWallet] = useState<WalletClient>();
  const [walletChain, setWalletChain] = useState<number>();
  const [count, setCount] = useState(10);
  const [live, setLive] = useState<Live>({});
  const [loaded, setLoaded] = useState(false);
  const [tx, setTx] = useState<TxState>();
  const [pulls, setPulls] = useState<bigint[]>([]);
  const [pullRows, setPullRows] = useState<any[]>([]);
  const referrer = useReferrer();
  const busy = tx && (tx.phase === "wallet" || tx.phase === "submitted");

  const refresh = useCallback(async () => {
    if (!deployed) return;
    try {
      const me = account ?? ZERO;
      const [game, quote, board, grail, genesis, market, split, spent, burned, start, supply] = await Promise.all([
        read<any>("lens", "game"), read<any>("lens", "quote", [BigInt(count)]), read<any[]>("lens", "board"),
        read<any>("lens", "grail"), read<any>("lens", "genesis", [me]), read<any>("lens", "market"),
        read<any>("controller", "feeSplit"), read<bigint>("buyback", "totalEthSpent"), read<bigint>("buyback", "totalBurned"),
        read<bigint>("buyback", "startTime"), read<bigint>("token", "totalSupply"),
      ]);
      const chainNow = (await publicClient.getBlock()).timestamp; // chain time, not the local clock
      let refund = 0n, balance: bigint | undefined, claimable: bigint[] = [];
      if (account) {
        [refund, balance] = await Promise.all([read<bigint>("engine", "acquisitionRefundCredit", [account]), publicClient.getBalance({ address: account })]);
        if (genesis.started) {
          const n = Math.min(Number(genesis.currentEpoch), 14);
          const rows = await Promise.all(Array.from({ length: n }, async (_, e) => {
            const [fin, done, r] = await Promise.all([read<boolean>("farm", "isFinal", [BigInt(e)]), read<boolean>("farm", "claimed", [BigInt(e), account]), read<bigint>("farm", "rewardOf", [BigInt(e), account])]);
            return fin && !done && r > 0n ? BigInt(e) : undefined;
          }));
          claimable = rows.filter((x): x is bigint => x !== undefined);
        }
      }
      setLive({ game, quote, board, grail, genesis, market, split, refund, balance, claimable, buyback: { spent, burned, start, supply }, chainNow });
      setLoaded(true);
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
    const eth = (window as any).ethereum;
    if (!eth?.on) return;
    const onChain = (id: string) => setWalletChain(Number(id));
    const onAccounts = (a: string[]) => setAccount((a[0] as Address) ?? undefined);
    eth.on("chainChanged", onChain);
    eth.on("accountsChanged", onAccounts);
    return () => { eth.removeListener?.("chainChanged", onChain); eth.removeListener?.("accountsChanged", onAccounts); };
  }, []);

  useEffect(() => {
    let stop = false;
    (async () => {
      const rows = [];
      for (const id of pulls.slice(-25).reverse()) {
        const a: any = await read("engine", "acquisitions", [id]);
        const status = STATUS[Number(a[4])];
        let prize = "", listingId = a[3] as bigint;
        if (listingId !== 0n && (status === "Fulfilled" || status === "DeliveryPending")) {
          const l: any = await read("engine", "listings", [listingId]);
          try {
            const v = (await publicClient.readContract({ address: l[0], abi: valueAbi, functionName: "valueOf", args: [l[3]] })) as bigint;
            const grail = l[1].toLowerCase() === addr.grailVault.toLowerCase();
            prize = `${grail ? "GRAIL · " : ""}${eth(v, 3)} ETH ${l[0].toLowerCase() === addr.drawPacks.toLowerCase() ? "Draw Pack" : "Shape"} #${l[3]}`;
          } catch { prize = `token #${l[3]} (redeemed)`; }
        }
        rows.push({ id, status, prize, listingId });
      }
      if (!stop) setPullRows(rows);
    })();
    return () => { stop = true; };
  }, [pulls, live.game?.nextToProcess]);

  async function connect() {
    try {
      const { wallet, account } = await connectWallet();
      setWallet(wallet);
      setAccount(account);
      setWalletChain(await wallet.getChainId());
    } catch (e: any) {
      setTx({ label: "Connect", phase: "failed", detail: e?.shortMessage ?? e?.message ?? String(e) });
    }
  }
  async function switchNetwork() {
    if (!wallet) return connect();
    try { await ensureChain(wallet); setWalletChain(await wallet.getChainId()); }
    catch (e: any) { setTx({ label: "Switch network", phase: "failed", detail: e?.shortMessage ?? e?.message }); }
  }
  const wrongNetwork = !!wallet && walletChain !== undefined && walletChain !== chain.id;

  async function send(label: string, contract: string, functionName: string, args: unknown[], value?: bigint) {
    if (!wallet || !account) return connect();
    if (wrongNetwork) return switchNetwork();
    setTx({ label, phase: "wallet" });
    try {
      const { request } = await publicClient.simulateContract({ address: target(contract), abi: abi[contract], functionName, args, value, account });
      const hash = await wallet.writeContract({ ...request, chain, account } as any);
      setTx({ label, phase: "submitted", hash });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("the transaction reverted");
      setTx({ label, phase: "confirmed", hash, detail: `block ${receipt.blockNumber}` });
      return receipt;
    } catch (e: any) {
      const m = e?.shortMessage ?? e?.message ?? String(e);
      setTx({ label, phase: "failed", detail: /User rejected|denied/i.test(m) ? "cancelled in the wallet" : m });
    } finally {
      refresh();
    }
  }

  async function pull() {
    const q = live.quote;
    if (!q || !account) return connect();
    const block = await publicClient.getBlock(); // deadline from chain time, not the local clock
    const receipt = await send(`Pull ×${count}`, "engine", "acquireBatch",
      // acquisition fee capped at the quote; 10 % negative settlement tolerance (FWA UI default)
      [account, referrer ?? ZERO, BigInt(count), q.fee, 0n, 1000n, 2n ** 256n - 1n, block.timestamp + 600n],
      // the VRF fee follows the basefee: send a 25 % margin on it; the engine returns any excess
      q.total + q.vrfFee / 4n);
    if (receipt) {
      const events = parseEventLogs({ abi: abi.engine, logs: receipt.logs, eventName: "AcquisitionRequested" }) as any[];
      const ids = [...pulls, ...events.map((e) => e.args.requestId as bigint)];
      setPulls(ids);
      savePulls(account, ids);
    }
  }

  const g = live.game;
  const q = live.quote;
  const grail = live.grail;
  const feedPct = live.split ? Number(live.split.feedBps ?? live.split[2]) / 100 : undefined;
  const grailNeed = grail ? grail.targetWei + grail.mintFee : 0n;
  const grailPct = grail && grailNeed > 0n ? Math.min(100, Number((grail.funded * 10000n) / grailNeed) / 100) : 0;
  const perPull = q ? q.total / BigInt(count) : 0n;
  const gen = live.genesis;
  const selectable = Number(grail?.selectable ?? 0n);
  const now = live.chainNow ?? BigInt(Math.floor(Date.now() / 1000));
  const state = !deployed ? `Not deployed on ${chain.name} yet` : !loaded ? "Loading live state…"
    : !g.activated ? "Not open yet — the game and ENGINE open together at activation"
    : g.paused ? "Paused: new pulls are off; settlement and refunds continue" : "Live";
  const pullBlocked = !deployed ? "not deployed on this network" : !loaded ? "loading" : !g?.activated ? "the game has not opened"
    : g?.paused ? "pulls are paused" : !q?.purchasable ? q?.reason || "pulls unavailable"
    : wrongNetwork ? `switch your wallet to ${chain.name}` : live.balance !== undefined && live.balance < q.total + q.vrfFee / 4n ? "not enough ETH in this wallet" : undefined;

  return (
    <div className="page">
      <header>
        <h1>Draw Shapes <small>on Base</small></h1>
        <span className={`state ${g?.activated && !g?.paused ? "live" : "off"}`}>{state}</span>
        {network !== "base" && <span className="state off">{chain.name}: test network, no real value</span>}
        <button onClick={account ? undefined : connect}>{account ? short(account) : "Connect wallet"}</button>
      </header>
      {wrongNetwork && (
        <div className="banner">Your wallet is on another network. <button onClick={switchNetwork}>Switch to {chain.name}</button></div>
      )}

      <section className="hero card">
        <h2>Pull for real ETH-backed prizes</h2>
        <p>
          Every prize is a Shape or Draw Pack on Base holding redeemable ETH. A pull draws one listing at random with Chainlink VRF;
          cheaper listings are more likely (odds ∝ 1 / notional), and the price is the harmonic mean of everything selectable.
        </p>
        <div className="pullrow">
          {[1, 5, 10, 20].map((n) => (
            <button key={n} className={n === count ? "on" : ""} onClick={() => setCount(n)}>×{n}</button>
          ))}
          <button className="primary" disabled={!!busy || !!pullBlocked} onClick={pull}>
            {busy && tx?.label.startsWith("Pull") ? (tx.phase === "wallet" ? "Confirm in wallet…" : "Pulling…") : `Pull ×${count} for ${eth(q?.total)} ETH`}
          </button>
        </div>
        {pullBlocked && loaded && <p className="note">Pulls unavailable: {pullBlocked}.</p>}
        <dl className="facts">
          <div><dt>Per pull, all-in</dt><dd>{eth(perPull)} ETH</dd></div>
          <div><dt>Acquisition fee</dt><dd>{eth(q?.fee)} ETH</dd></div>
          <div><dt>Settlement fee (1 %)</dt><dd>{eth(q?.settlementFee)} ETH</dd></div>
          <div><dt>VRF fee (one per batch, not refundable)</dt><dd>{eth(q?.vrfFee, 7)} ETH</dd></div>
          <div><dt>Expected ETH backing per pull</dt><dd>{eth(g?.expectedBackingPerPull)} ETH ({perPull ? pct(g?.expectedBackingPerPull ?? 0n, perPull) : "–"} of payment)</dd></div>
        </dl>
        {referrer && <p className="note">Referred by {short(referrer)} — they receive half of the 1 % settlement fee of each delivered pull.</p>}
        <p className="note">Wallet gas is extra. On average a pull returns less ETH backing than it costs; the difference pays the replacement mint fee to the Shapes creator, the game premium, maintenance and the GRAIL fund.</p>
      </section>

      {pulls.length === 0 && (
        <section className="card">
          <h2>How it works</h2>
          <ol>
            <li>Connect a wallet on {chain.name}. Choose 1–20 pulls; the price shown is everything you pay except gas.</li>
            <li>Chainlink VRF picks your prizes, usually within seconds. Each prize is sent to your wallet; if a price moves past your limit before it settles, that pull is refunded instead.</li>
            <li>Every prize holds its ETH. Redeem any Shape or Draw Pack on its contract at any time for exactly the ETH inside.</li>
          </ol>
          <p className="note">Shapes on Base are a separate collection from Shapes on Ethereum: same contract and rules, independent tokens and ETH.</p>
        </section>
      )}

      <section className="card grail">
        <h2>GRAIL</h2>
        {selectable > 0 ? (
          <p><b>{selectable} GRAIL{selectable > 1 ? "s" : ""} can be won now.</b> A GRAIL is a large Shape listed below its backing.</p>
        ) : (
          <p><b>No GRAIL can be won right now.</b> The next one becomes drawable only once its whole backing and mint fee are funded.</p>
        )}
        {grail?.items?.length > 0 && (
          <table>
            <thead><tr><th>Fully funded GRAIL</th><th>Backing</th><th>Notional</th><th>Status</th><th>Odds per pull</th></tr></thead>
            <tbody>
              {grail.items.map((it: any, i: number) => {
                const st = Number(grail.status?.[i] ?? 0);
                return (
                  <tr key={i}>
                    <td>Shape #{String(it.tokenId)}</td>
                    <td>{eth(it.backing, 3)} ETH</td>
                    <td>{eth(it.notional, 4)} ETH{grail.nextNotional?.[i] > 0n && <span className="note"> → {eth(grail.nextNotional[i], 4)} at next step</span>}</td>
                    <td>{st === 1 ? "Selectable" : st === 5 ? "Funded — drawable from the next pull" : "Funded — waiting to be relisted (not drawable)"}</td>
                    <td>{st === 1 ? odds(grail.oddsPpm[i]) : "not drawable"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
        <p className="label">Next GRAIL: {eth(grail?.targetWei, 2)} ETH Shape — accumulating, not drawable</p>
        <div className="bar"><div style={{ width: `${grailPct}%` }} /></div>
        <p className="big">{eth(grail?.funded, 4)} / {eth(grailNeed, 3)} ETH funded ({grailPct.toFixed(1)} %)</p>
        <p className="note">
          Funded by {feedPct !== undefined ? `${feedPct} %` : "a share"} of every pull's notional and by ENGINE trading fees. A selectable GRAIL's notional falls a little with
          every pull (raising its odds) until its odds reach 5 % or its notional reaches half its backing. No GRAIL is guaranteed to be available.
        </p>
      </section>

      <section className="card">
        <h2>The board</h2>
        <p className="note">Backing is the ETH inside the prize. Notional is its listing value: backing plus the game's markup plus the replacement mint fee of each Shape in it. Odds are for one pull.</p>
        {!live.board?.length ? <p className="note">Loading the board…</p> : (
          <table>
            <thead><tr><th>Prize</th><th>Backing</th><th>Notional</th><th>Selectable / target</th><th>Odds per pull</th></tr></thead>
            <tbody>
              {live.board.map((r: any, i: number) => (
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
        )}
        {g?.activated && live.board?.length && g.activeListings * 10n < 7n * live.board.reduce((n: bigint, r: any) => n + r.target, 0n) ? (
          <p className="note">The board is restocking; prices and odds follow what is selectable.</p>
        ) : null}
      </section>

      {account && (
        <section className="card">
          <h2>My pulls</h2>
          {live.refund ? (
            <p>Refund credit: <b>{eth(live.refund)} ETH</b>{" "}
              <button disabled={!!busy} onClick={() => send("Withdraw refund", "engine", "withdrawAcquisitionRefund", [])}>Withdraw</button></p>
          ) : null}
          {pullRows.length === 0 ? <p className="note">No pulls from this browser yet.</p> : (
            <table>
              <thead><tr><th>#</th><th>Status</th><th>Prize</th><th></th></tr></thead>
              <tbody>
                {pullRows.map((r) => (
                  <tr key={String(r.id)}>
                    <td>{String(r.id)}</td>
                    <td>{STATUS_TEXT[r.status] ?? r.status}</td>
                    <td>{r.prize}</td>
                    <td>{r.status === "DeliveryPending" && <button disabled={!!busy} onClick={() => send("Retry delivery", "engine", "retryNFTDelivery", [r.listingId])}>Retry</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <p className="note">Redeem a Shape or Draw Pack for its ETH at any time on <Link href={addrUrl(addr.shapes)}>Shapes</Link> or <Link href={addrUrl(addr.drawPacks)}>Base Draw Packs</Link>.</p>
        </section>
      )}

      <section className="card">
        <h2>Genesis farming</h2>
        {!gen?.started ? <p>Genesis has not started. It starts when paid pulls open and lasts 14 days.</p> : (
          <>
            <p>
              Epoch <b>{Math.min(Number(gen.currentEpoch) + 1, 14)} / 14</b>{Number(gen.currentEpoch) >= 14 ? " — genesis has ended; no further ENGINE is issued" : ` — ends ${new Date(Number(gen.start + (gen.currentEpoch + 1n) * 86400n) * 1000).toLocaleString()}`}.
              Each epoch distributes {Number(formatEther(gen.allocationPerEpoch)).toLocaleString()} ENGINE to that epoch's delivered pulls: 85 % by pull count, 15 % by a random bonus weight.
            </p>
            <dl className="facts">
              <div><dt>Delivered pulls this epoch</dt><dd>{String(gen.epochUnits)}</dd></div>
              <div><dt>Mine this epoch</dt><dd>{String(gen.userUnits)} (bonus weight {String(gen.userBonus)})</dd></div>
              <div><dt>Claimable now</dt><dd>{Number(formatEther(gen.userClaimable)).toLocaleString()} ENGINE</dd></div>
            </dl>
            <button disabled={!!busy || !live.claimable?.length} onClick={() => send("Claim ENGINE", "farm", "claim", [live.claimable])}>
              {live.claimable?.length ? `Claim ENGINE (epoch${live.claimable.length > 1 ? "s" : ""} ${live.claimable.map((e) => Number(e) + 1).join(", ")})` : "Nothing to claim yet"}
            </button>
            <p className="note">An epoch's rewards become claimable once it has ended and every pull accepted in it has settled. Unclaimed rewards never expire; allocations of epochs nobody played are burned after genesis.</p>
          </>
        )}
      </section>

      <section className="card warn">
        <h2>ENGINE</h2>
        <dl className="facts">
          <div><dt>Price</dt><dd>{live.market?.ethPerEngineE18 ? `${(Number(live.market.ethPerEngineE18) / 1e18).toExponential(3)} ETH` : "not trading yet"}</dd></div>
          <div><dt>Supply</dt><dd>{live.buyback ? `${Number(formatEther(live.buyback.supply)).toLocaleString(undefined, { maximumFractionDigits: 0 })} (fixed 35,000,000 at launch; only burns reduce it)` : "–"}</dd></div>
          <div><dt>Trading fee</dt><dd>{live.market ? `${Number(live.market.feeBps) / 100} % (0.25 % operator, rest treasury)` : "–"}</dd></div>
          <div><dt>Treasury to GRAILs so far</dt><dd>{eth(live.market?.treasuryToGrail, 4)} ETH</dd></div>
          <div><dt>Buyback-and-burn</dt><dd>{live.buyback ? (live.buyback.start > now ? `starts ${new Date(Number(live.buyback.start) * 1000).toLocaleDateString()} (genesis end)` : `${eth(live.buyback.spent, 4)} ETH spent, ${Number(formatEther(live.buyback.burned)).toLocaleString(undefined, { maximumFractionDigits: 0 })} ENGINE burned`) : "–"}</dd></div>
        </dl>
        <p>
          <b>ENGINE is a speculative token.</b> It is not backed by and gives no claim on the ETH in prizes, the game, the GRAIL fund or the
          treasury. After genesis, realised game surplus buys and burns ENGINE; that budget depends on play and does not support any
          price. ENGINE can trade in other pools that pay no fee to the project.
        </p>
      </section>

      {tx && (
        <div className={`toast ${tx.phase === "failed" ? "err" : ""}`} onClick={() => !busy && setTx(undefined)}>
          {tx.label}: {tx.phase === "wallet" ? "confirm in your wallet…" : tx.phase === "submitted" ? "submitted, waiting for confirmation…" : tx.phase === "confirmed" ? `confirmed (${tx.detail})` : `failed — ${tx.detail}`}
          {tx.hash && <> · <Link href={txUrl(tx.hash)}>view transaction</Link></>}
        </div>
      )}
      {live.error && <div className="toast err second">Could not read the chain: {live.error}</div>}

      <footer>
        <span>{chain.name}</span>
        {["engine", "controller", "grailVault", "token", "farm", "hook", "treasury", "buyback", "shapes", "drawPacks"].map((k) => (
          <span key={k}>{k}: <Link href={addrUrl((addr as any)[k])}>{short((addr as any)[k])}</Link></span>
        ))}
        <span>Selection, pricing and settlement engine adapted from FWA by Token Works (MIT). Shapes and Draw Packs by ripe0x. Not audited.</span>
      </footer>
    </div>
  );
}
