"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useAccount, useBalance, usePublicClient } from "wagmi";
import { zeroAddress, type Address } from "viem";
import { packsAbi, shapesAbi } from "./abi/external";
import { usePool } from "./pool";
import { usePulls } from "./pulls";
import { useDeployment } from "../Providers";

/** A prize the wallet still holds, won in this game. */
export interface Prize {
  key: string;
  collection: Address;
  tokenId: bigint;
  pack: boolean;
  /** ETH it redeems for at face. */
  value: bigint;
  grail: boolean;
  /** Acquisition that won it. */
  requestId: bigint;
  /** Kept prizes are never spent or cashed out by the session controls. */
  kept: boolean;
}

const prizeKey = (collection: Address, tokenId: bigint) => `${collection.toLowerCase()}-${tokenId}`;

// ------------------------------------------------------------------ keep list (per wallet, local)

const keepStorageKey = (chainId: number, owner?: Address) => `draw-keep-${chainId}-${owner?.toLowerCase() ?? ""}`;

function readSet(key: string): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(key) ?? "[]") as string[]);
  } catch {
    return new Set();
  }
}

/** The wallet's kept prizes, remembered in this browser. GRAILs are always kept. */
export function useKeepList() {
  const dep = useDeployment();
  const { address } = useAccount();
  const key = keepStorageKey(dep.chainId, address);
  const [kept, setKept] = useState<Set<string>>(new Set());
  useEffect(() => setKept(readSet(key)), [key]);
  const toggle = useCallback(
    (k: string) => {
      setKept((prev) => {
        const next = new Set(prev);
        if (next.has(k)) next.delete(k);
        else next.add(k);
        try {
          localStorage.setItem(key, JSON.stringify([...next]));
        } catch {
          // storage unavailable: the choice lasts for this page view
        }
        return next;
      });
    },
    [key],
  );
  return { kept, toggle };
}

// ------------------------------------------------------------------ stack

/**
 * The player's stack: wallet ETH, the prizes they hold from this game (at face), and refund
 * credit. Prizes come from the wallet's pulls (`usePulls`) and are rechecked for ownership, so
 * prizes redeemed, cashed out, sold or transferred drop out.
 */
export function useStack() {
  const dep = useDeployment();
  const { address } = useAccount();
  const client = usePublicClient({ chainId: dep.chainId });
  const pulls = usePulls();
  const pool = usePool().data;
  const { kept, toggle } = useKeepList();
  const wallet = useBalance({ address, chainId: dep.chainId, query: { refetchInterval: 12_000 } });

  const won = useMemo(
    () =>
      Object.values(pulls.data?.cards ?? {})
        .filter((c) => c.item && c.item.value > 0n)
        .map((c) => ({ ...c.item!, requestId: c.id })),
    [pulls.data],
  );

  const held = useQuery({
    queryKey: ["held", dep.chainId, address, won.map((w) => `${w.collection}-${w.tokenId}`).join(",")],
    enabled: !!client && !!address && won.length > 0,
    refetchInterval: 15_000,
    queryFn: async () => {
      const owners = await client!.multicall({
        allowFailure: true,
        contracts: won.map((w) => ({ address: w.collection, abi: shapesAbi, functionName: "ownerOf", args: [w.tokenId] }) as const),
      });
      return won.filter((_, i) => owners[i].status === "success" && (owners[i].result as Address).toLowerCase() === address!.toLowerCase());
    },
  });

  const approvals = useQuery({
    queryKey: ["prize-approvals", dep.chainId, address, dep.prizeRouter],
    enabled: !!client && !!address && dep.prizeRouter !== zeroAddress,
    refetchInterval: 30_000,
    queryFn: async () => {
      const [s, p] = await client!.multicall({
        allowFailure: false,
        contracts: [
          { address: dep.shapes, abi: shapesAbi, functionName: "isApprovedForAll", args: [address!, dep.prizeRouter] },
          { address: dep.drawPacks, abi: packsAbi, functionName: "isApprovedForAll", args: [address!, dep.prizeRouter] },
        ],
      });
      return { shapes: s, packs: p };
    },
  });

  const prizes: Prize[] = (held.data ?? [])
    .map((w) => {
      const key = prizeKey(w.collection, w.tokenId);
      return { key, collection: w.collection, tokenId: w.tokenId, pack: w.pack, value: w.value, grail: !!w.grail, requestId: w.requestId, kept: !!w.grail || kept.has(key) };
    })
    .sort((a, b) => (a.value === b.value ? 0 : a.value < b.value ? -1 : 1));
  const playable = prizes.filter((p) => !p.kept);
  const sum = (xs: Prize[]) => xs.reduce((t, p) => t + p.value, 0n);
  const walletWei = wallet.data?.value ?? 0n;
  const creditWei = pool?.refundCredit ?? 0n;
  const playableWei = sum(playable);
  return {
    ready: !!address && (won.length === 0 || held.isSuccess) && wallet.isSuccess,
    walletWei,
    creditWei,
    prizes,
    playable,
    playableWei,
    keptWei: sum(prizes.filter((p) => p.kept)),
    /** Playable stack: wallet ETH + playable prizes at face + refund credit. */
    stackWei: walletWei + playableWei + creditWei,
    approved: !!approvals.data?.shapes && !!approvals.data?.packs,
    approvals: approvals.data,
    routerAvailable: dep.prizeRouter !== zeroAddress,
    toggleKeep: toggle,
  };
}

export type Stack = ReturnType<typeof useStack>;

/**
 * How a pull of `total` is paid: playable prizes smallest first until they cover it (prizes redeem
 * at face, so overshoot returns as ETH change), then wallet ETH for the rest with 10 % headroom on
 * the shortfall (the engine refunds the excess).
 */
export function planPayment(total: bigint, playable: Prize[], usePrizes: boolean) {
  const chosen: Prize[] = [];
  let covered = 0n;
  if (usePrizes) {
    for (const p of playable) {
      if (covered >= total) break;
      chosen.push(p);
      covered += p.value;
    }
  }
  const shortfall = total > covered ? total - covered : 0n;
  const topUp = shortfall === 0n ? 0n : (shortfall * 110n) / 100n;
  return {
    prizes: chosen,
    prizeWei: covered,
    shapeIds: chosen.filter((p) => !p.pack).map((p) => p.tokenId),
    packIds: chosen.filter((p) => p.pack).map((p) => p.tokenId),
    topUp,
    /** ETH the wallet must send (prize-only pulls send none). */
    value: topUp,
  };
}

// ------------------------------------------------------------------ session ledger (local)

export interface Session {
  startedAt: number;
  /** Stack when the session started (wallet + playable prizes + credit, plus kept prizes). */
  startTotalWei: string;
  /** Last acquisition id issued when the session started. */
  startLastIssued: string;
}

const sessionKey = (chainId: number, owner?: Address) => `draw-session-${chainId}-${owner?.toLowerCase() ?? ""}`;

/** The current play session, remembered in this browser. Started on demand; ended by the player. */
export function useSession() {
  const dep = useDeployment();
  const { address } = useAccount();
  const key = sessionKey(dep.chainId, address);
  const [session, setSession] = useState<Session | null>(null);
  useEffect(() => {
    try {
      setSession(JSON.parse(localStorage.getItem(key) ?? "null"));
    } catch {
      setSession(null);
    }
  }, [key]);
  const save = (s: Session | null) => {
    setSession(s);
    try {
      if (s) localStorage.setItem(key, JSON.stringify(s));
      else localStorage.removeItem(key);
    } catch {
      // storage unavailable: the session lasts for this page view
    }
  };
  return {
    session,
    start: (totalWei: bigint, lastIssued: bigint) => save({ startedAt: Date.now(), startTotalWei: totalWei.toString(), startLastIssued: lastIssued.toString() }),
    end: () => save(null),
  };
}
