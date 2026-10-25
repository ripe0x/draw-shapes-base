"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAccount, usePublicClient } from "wagmi";
import { type Address, type PublicClient } from "viem";
import { fwaCloneAbi, packsAbi, shapesAbi } from "./abi/external";
import { lensAbi } from "./abi/lens";
import type { Deployment } from "./deployment";
import { useDeployment } from "../Providers";

const POLL_MS = 6_000;
/** Poll while the only open work is a delivered prize waiting for `settle` to book it. */
const BOOKING_POLL_MS = 30_000;

/** DrawEngine `AcquisitionStatus` codes the UI branches on (unchanged from FWA). */
export const ACQ = {
  None: 0,
  Pending: 1,
  Fulfilled: 2,
  Expired: 3,
  Refunded: 4,
  Ready: 5,
  TimedOut: 6,
  DeliveryPending: 7,
  DeliveryRefunded: 8,
} as const;
export const UNRESOLVED = new Set<number>([ACQ.None, ACQ.Pending, ACQ.Ready, ACQ.TimedOut, ACQ.DeliveryPending]);

export interface Item {
  collection: Address;
  tokenId: bigint;
  pack: boolean;
  /** Backing of a Shape, value of a Draw Pack: the ETH it redeems for at face. */
  value: bigint;
  /** True once `settle` booked the capture on the controller (or the GRAIL vault). */
  booked: boolean;
  /** True when the prize was a GRAIL (listed by the GRAIL vault). */
  grail?: boolean;
}
export interface Card {
  id: bigint;
  status: number;
  /** Acquisition fee paid for this pull; the settlement and VRF fees are excluded. */
  ticket: bigint;
  item?: Item;
}
export interface Batch {
  /** VRF request shared by the batch: one request per batch. */
  key: string;
  block: bigint;
  count: bigint;
  fee: bigint;
  ids: readonly bigint[];
}
export interface PullsData {
  /** Highest acquisition id scanned. */
  scanned: bigint;
  batches: Batch[];
  cards: Record<string, Card>;
  /** Request ids seen moving from unresolved to delivered while the page was open. */
  fresh: string[];
}

/** Acquisition ids read per multicall. */
const CHUNK = 300;

/**
 * Finds the wallet's pulls by reading the engine's acquisitions in sequence (ids 1 to
 * `lastIssuedSequence`), not by scanning logs: Base Sepolia's 0.2 s blocks and public RPC log-range
 * caps make log scans from the deployment block impractical. Later reads cover new ids and reread
 * the wallet's unresolved or unbooked pulls through `Lens.receipt`. `prior` carries the earlier result.
 */
async function load(client: PublicClient, dep: Deployment, owner: Address, prior?: PullsData): Promise<PullsData> {
  const last = await client.readContract({ address: dep.fwaPool, abi: fwaCloneAbi, functionName: "lastIssuedSequence" });
  const base = prior && prior.scanned <= last ? prior : undefined;
  const from = base ? base.scanned + 1n : 1n;
  const newIds = Array.from({ length: Number(last >= from ? last - from + 1n : 0n) }, (_, i) => from + BigInt(i));
  const mine: { id: bigint; block: bigint }[] = [];
  for (let i = 0; i < newIds.length; i += CHUNK) {
    const part = newIds.slice(i, i + CHUNK);
    const rows = await client.multicall({
      allowFailure: false,
      contracts: part.map((id) => ({ address: dep.fwaPool, abi: fwaCloneAbi, functionName: "acquisitions", args: [id] }) as const),
    });
    rows.forEach((r, j) => {
      if (r[0].toLowerCase() === owner.toLowerCase()) mine.push({ id: part[j], block: r[1] });
    });
  }

  const cards: Record<string, Card> = {};
  for (const [k, c] of Object.entries(base?.cards ?? {})) cards[k] = { ...c, item: c.item && { ...c.item } };
  // Receipts for new pulls and for the wallet's pulls still unresolved or awaiting booking.
  const reread = [
    ...mine.map((m) => m.id),
    ...Object.values(cards).filter((c) => UNRESOLVED.has(c.status) || (c.item && !c.item.booked)).map((c) => c.id),
  ];
  const receipts = reread.length
    ? await client.multicall({
        allowFailure: false,
        contracts: reread.map((id) => ({ address: dep.lens, abi: lensAbi, functionName: "receipt", args: [id] }) as const),
      })
    : [];

  const batches = (base?.batches ?? []).map((b) => ({ ...b }));
  const byKey = new Map(batches.map((b) => [b.key, b]));
  const blockOf = new Map(mine.map((m) => [m.id, m.block]));
  const delivered: { id: bigint; collection: Address; tokenId: bigint; grail: boolean; booked: boolean }[] = [];
  reread.forEach((id, i) => {
    const r = receipts[i];
    const k = id.toString();
    if (!cards[k]) {
      cards[k] = { id, status: r.status, ticket: r.acquisitionFee };
      const key = r.vrfRequestId.toString();
      const b = byKey.get(key);
      if (b) {
        b.ids = [...b.ids, id];
        b.count += 1n;
      } else {
        const nb: Batch = { key, block: blockOf.get(id) ?? 0n, count: 1n, fee: r.acquisitionFee, ids: [id] };
        byKey.set(key, nb);
        batches.push(nb);
      }
    }
    const c = cards[k];
    c.status = r.status;
    if (r.status === ACQ.Fulfilled) {
      const grail = r.depositor.toLowerCase() === dep.grailVault.toLowerCase();
      if (c.item) {
        c.item.booked = r.bookedByController || grail;
      } else {
        delivered.push({ id, collection: r.collection, tokenId: r.tokenId, grail, booked: r.bookedByController || grail });
      }
    }
  });

  if (delivered.length) {
    const values = await client.multicall({
      allowFailure: true,
      contracts: delivered.map((d) =>
        d.collection.toLowerCase() === dep.drawPacks.toLowerCase()
          ? ({ address: d.collection, abi: packsAbi, functionName: "valueOf", args: [d.tokenId] } as const)
          : ({ address: d.collection, abi: shapesAbi, functionName: "backingOf", args: [d.tokenId] } as const),
      ),
    });
    delivered.forEach((d, i) => {
      // A redeemed prize is burned: its value read fails and the card keeps the token id only.
      const value = values[i].status === "success" ? (values[i].result as bigint) : 0n;
      cards[d.id.toString()].item = {
        collection: d.collection, tokenId: d.tokenId, pack: d.collection.toLowerCase() === dep.drawPacks.toLowerCase(),
        value, booked: d.booked, grail: d.grail,
      };
    });
  }

  const fresh = new Set(base?.fresh);
  for (const [key, c] of Object.entries(cards)) {
    const was = base?.cards[key];
    if (was && UNRESOLVED.has(was.status) && c.status === ACQ.Fulfilled) fresh.add(key);
  }
  batches.sort((a, b) => (a.ids[0] < b.ids[0] ? -1 : 1));
  return { scanned: last, batches, cards, fresh: [...fresh] };
}

/** The connected wallet's pulls. Polls every 6 seconds while a pull is unresolved and every 30
 *  seconds while a delivered prize awaits booking. */
export function usePulls() {
  const dep = useDeployment();
  const { address } = useAccount();
  const client = usePublicClient({ chainId: dep.chainId });
  const queryClient = useQueryClient();
  const key = ["pulls", dep.chainId, dep.fwaPool, address] as const;
  return useQuery({
    queryKey: key,
    queryFn: () => load(client!, dep, address!, queryClient.getQueryData<PullsData>(key)),
    enabled: !!client && !!address && dep.present,
    refetchInterval: (q) => {
      const cards = Object.values(q.state.data?.cards ?? {});
      if (cards.some((c) => UNRESOLVED.has(c.status))) return POLL_MS;
      return cards.some((c) => c.item && !c.item.booked) ? BOOKING_POLL_MS : 60_000;
    },
  });
}
