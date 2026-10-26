"use client";

import { useQuery } from "@tanstack/react-query";
import { useAccount, usePublicClient, useReadContracts } from "wagmi";
import { zeroAddress, type Address, type PublicClient } from "viem";
import { fwaCloneAbi } from "./abi/external";
import { farmAbi, vaultAbi } from "./abi/game";
import { lensAbi } from "./abi/lens";
import { poolAbi } from "./abi/pool";
import type { Deployment } from "./deployment";
import { eth, utc } from "./format";
import { useDeployment } from "../Providers";

export const POLL_MS = 12_000;
/** Batch sizes the pull card offers (the engine allows up to `maxAcquisitionsPerTx`). */
export const MAX_COUNT = 10;

/**
 * Every game read a page needs, in one multicall polled every 12 seconds, shaped like the original
 * Draw Shapes pool view so its components port unchanged. On Base the board belongs to the protocol:
 * DrawController (`pool`) holds the ordinary pool and restocks the board, DrawEngine (`fwaPool`, a
 * fork of FWA's custom pool) sells the pulls, and GrailVault lists the GRAILs.
 */
export function usePool() {
  const dep = useDeployment();
  const { address } = useAccount();
  const chainId = dep.chainId;
  const lens = { chainId, address: dep.lens, abi: lensAbi } as const;
  const ctl = { chainId, address: dep.pool, abi: poolAbi } as const;
  const eng = { chainId, address: dep.fwaPool, abi: fwaCloneAbi } as const;
  const vault = { chainId, address: dep.grailVault, abi: vaultAbi } as const;
  return useReadContracts({
    allowFailure: false,
    contracts: [
      { ...lens, functionName: "game" },
      { ...lens, functionName: "board" },
      { ...lens, functionName: "grail" },
      { ...lens, functionName: "vrf" },
      { ...lens, functionName: "market" },
      { ...ctl, functionName: "feeSplit" },
      { ...ctl, functionName: "queueLength" },
      { ...ctl, functionName: "boardItems" },
      { ...ctl, functionName: "maintenanceFloor" },
      { ...ctl, functionName: "tipWei" },
      { ...ctl, functionName: "listingPaused" },
      { ...ctl, functionName: "releasableSurplus" },
      { ...ctl, functionName: "surplusReleaseStart" },
      { ...eng, functionName: "maxAcquisitionsPerTx" },
      { ...eng, functionName: "settlementFeeBps" },
      { ...eng, functionName: "selectionTimeoutBlocks" },
      { ...eng, functionName: "purchasesResumeAt" },
      { ...eng, functionName: "acquisitionRefundCredit", args: [address ?? zeroAddress] },
      { ...vault, functionName: "config" },
      { ...vault, functionName: "fund" },
      { ...vault, functionName: "pulls" },
      { ...vault, functionName: "nextTarget" },
      { ...vault, functionName: "stepDue" },
      { ...vault, functionName: "cycleStartedAt" },
      { ...vault, functionName: "paused" },
    ],
    query: {
      enabled: dep.present,
      refetchInterval: POLL_MS,
      select: (r) => {
        const [game, board, grail, vrf, market, feeSplit, queueLength, boardItems, maintenanceFloor, tipWei, listingPaused,
          releasableSurplus, surplusReleaseStart, maxBatch, settlementFeeBps, selectionTimeoutBlocks, purchasesResumeAt, refundCredit,
          gcfg, fund, pulls, nextTarget, stepDue, cycleStartedAt, vaultPaused] = r;
        const [listBps, floorBps, probCapBps, stepUpSeconds, stepDownSeconds, decayWeiPerPull] = gcfg;
        const [premiumBps, maintenanceBps, feedBps] = feeSplit;
        return {
          game,
          /** Board rows in the original's shape: list price = the row's notional, plus odds and queue. */
          board: board.map((b) => ({
            rungs: b.rungs,
            backingWei: b.backing,
            listingPrice: b.notional,
            listed: b.listed,
            queued: b.queued,
            count: b.listed + b.queued,
            target: b.target,
            oddsPpm: b.oddsPpm,
          })),
          grail: {
            /** GRAIL fund held by the vault, accumulating toward the next GRAIL. */
            fund,
            funded: grail.funded,
            mintFee: grail.mintFee,
            targetWei: grail.targetWei,
            nextTargetWei: nextTarget,
            cycleId: grail.cycleId,
            listBps,
            floorBps,
            probCapBps,
            decayWeiPerPull,
            pulls,
            cycleStartedAt,
            stepUpSeconds,
            stepDownSeconds,
            stepDue,
            paused: vaultPaused,
            selectable: grail.selectable,
            items: grail.items.map((it, i) => ({
              collection: dep.shapes,
              tokenId: it.tokenId,
              backing: it.backing,
              notional: it.notional,
              /** Zero while the GRAIL waits for its next listing (staged or relisting). */
              listingId: grail.status[i] === 1 ? it.listingId : 0n,
              rawListingId: it.listingId,
              listedAtPull: BigInt(it.listedAtPull),
              status: grail.status[i],
              oddsPpm: grail.oddsPpm[i],
              nextNotional: grail.nextNotional[i],
              done: false,
            })),
          },
          vrf,
          market,
          params: {
            feeSplit: { premiumBps, maintenanceBps, feedBps },
            maxBatch,
            settlementFeeBps,
            selectionTimeoutBlocks,
            purchasesResumeAt,
            boardItems,
            maintenanceFloor,
            tipWei,
            listingPaused,
            surplusReleaseStart,
          },
          queueLength,
          releasableSurplus,
          refundCredit,
          nav: game.nav,
          cash: game.cash,
          backing: game.backing,
          receivable: game.receivable,
          maintenance: game.maintenance,
          listedCount: game.activeListings,
          stagedCount: game.stagedListings,
        };
      },
    },
  });
}

export type PoolData = NonNullable<ReturnType<typeof usePool>["data"]>;
export type Row = PoolData["board"][number];
export type Grail = PoolData["grail"];
export type GrailItem = Grail["items"][number];

/** The connected wallet's genesis position: epochs, units and claimable ENGINE. */
export function useGenesis() {
  const dep = useDeployment();
  const { address } = useAccount();
  return useReadContracts({
    allowFailure: false,
    contracts: [{ chainId: dep.chainId, address: dep.lens, abi: lensAbi, functionName: "genesis", args: [address ?? zeroAddress] }],
    query: { enabled: dep.present, refetchInterval: POLL_MS, select: ([g]) => g },
  });
}

/** Final, unclaimed epochs with a reward for `owner`: what `GenesisFarm.claim` takes. */
export async function claimableEpochs(client: PublicClient, dep: Deployment, owner: Address, current: bigint): Promise<bigint[]> {
  const epochs = Array.from({ length: Number(current > 14n ? 14n : current) + 1 }, (_, i) => BigInt(i));
  const rows = await client.multicall({
    allowFailure: false,
    contracts: epochs.flatMap((e) => [
      { address: dep.farm, abi: farmAbi, functionName: "isFinal", args: [e] } as const,
      { address: dep.farm, abi: farmAbi, functionName: "claimed", args: [e, owner] } as const,
      { address: dep.farm, abi: farmAbi, functionName: "rewardOf", args: [e, owner] } as const,
    ]),
  });
  return epochs.filter((_, i) => rows[3 * i] === true && rows[3 * i + 1] === false && (rows[3 * i + 2] as bigint) > 0n);
}

// ------------------------------------------------------------------ odds

/** Selection weight of one listing: 1e36 / price (FWA's rule, kept by the engine). */
const weightOf = (priceWei: bigint) => (priceWei > 0n ? 10n ** 36n / priceWei : 0n);

export interface OddsRow {
  key: string;
  /** Redeemable backing of one item. */
  backingWei: bigint;
  priceWei: bigint;
  listed: bigint;
  /** Chance a single pull draws an item of this row, in bps. */
  chanceBps: bigint;
  /** Shape, Draw Pack (rung count) or a GRAIL item. */
  kind: { shape: true } | { pack: number } | { grail: true };
}

/**
 * Selection odds of every listed row and selectable GRAIL, from the board's list prices and the
 * GRAILs' notionals (weight 1e36 / price). `averageBackingWei` is the weight-averaged redeemable
 * backing of one draw.
 */
export function drawOdds(board: readonly Row[], grail: Grail) {
  const parts: Omit<OddsRow, "chanceBps">[] = [];
  board.forEach((r, i) => {
    if (r.listed === 0n || r.listingPrice === 0n) return;
    parts.push({
      key: `row-${i}`,
      backingWei: r.backingWei,
      priceWei: r.listingPrice,
      listed: r.listed,
      kind: r.rungs.length > 1 ? { pack: r.rungs.length } : { shape: true },
    });
  });
  grail.items.forEach((g) => {
    if (g.listingId === 0n || g.notional === 0n) return;
    parts.push({ key: `grail-${g.listingId}`, backingWei: g.backing, priceWei: g.notional, listed: 1n, kind: { grail: true } });
  });
  const weights = parts.map((p) => weightOf(p.priceWei) * p.listed);
  const total = weights.reduce((a, b) => a + b, 0n);
  const rows: OddsRow[] = parts
    .map((p, i) => ({ ...p, chanceBps: total === 0n ? 0n : (weights[i] * 10_000n) / total }))
    .sort((a, b) => (a.backingWei === b.backingWei ? 0 : a.backingWei < b.backingWei ? -1 : 1));
  const averageBackingWei =
    total === 0n ? 0n : parts.reduce((sum, p, i) => sum + weights[i] * p.backingWei, 0n) / total;
  const listedItems = parts.reduce((sum, p) => sum + p.listed, 0n);
  const listedBackingWei = parts.reduce((sum, p) => sum + p.listed * p.backingWei, 0n);
  const largestWei = parts.reduce((max, p) => (p.backingWei > max ? p.backingWei : max), 0n);
  return { rows, averageBackingWei, listedItems, listedBackingWei, largestWei };
}

/** Odds of one GRAIL per pull, in bps, under the same rule as `drawOdds`. */
export function grailChanceBps(odds: ReturnType<typeof drawOdds>, listingId: bigint): bigint {
  return odds.rows.find((r) => r.key === `grail-${listingId}`)?.chanceBps ?? 0n;
}

// ------------------------------------------------------------------ quote

export interface Quote {
  /** Acquisition fee per pull (the harmonic mean of selectable list prices). */
  fee: bigint;
  /** Settlement fee per pull (1 % of the fee: referrer, Token Works, development). */
  settlementFee: bigint;
  /** One VRF fee for the whole batch, paid to the Chainlink subscription and the service margin. */
  vrf: bigint;
  total: bigint;
  purchasable: boolean;
  /** Lens `quote` reason when not purchasable, empty otherwise. */
  reason: string;
  inventoryVersion: bigint;
}

/** Lens `quote`: the engine prices the VRF fee at the block basefee, so a plain read is exact. */
export async function readQuote(client: PublicClient | undefined, dep: Deployment, count: number): Promise<Quote> {
  if (!client) throw new Error("No RPC client.");
  const q = await client.readContract({ address: dep.lens, abi: lensAbi, functionName: "quote", args: [BigInt(count)] });
  return { fee: q.fee, settlementFee: q.settlementFee, vrf: q.vrfFee, total: q.total, purchasable: q.purchasable, reason: q.reason, inventoryVersion: q.inventoryVersion };
}

export function useQuote(count: number) {
  const dep = useDeployment();
  const client = usePublicClient({ chainId: dep.chainId });
  return useQuery({
    queryKey: ["quote", dep.chainId, dep.fwaPool, count],
    queryFn: () => readQuote(client, dep, count),
    enabled: !!client && dep.present,
    refetchInterval: POLL_MS,
  });
}

/** Gas a pull uses, for the wallet balance check (a 10-pull batch with in-callback settlement). */
export const PULL_GAS = 2_500_000n;

/** Sent value: the quoted total plus 10 percent. The engine refunds the excess in the same
 *  transaction (a basefee rise between quote and inclusion raises the VRF fee slightly). */
export const sendValue = (q: Quote) => (q.total * 110n) / 100n;

/** ETH a wallet needs for a pull: the sent value plus the pull's gas at a generous Base gas price. */
export const neededWei = (q: Quote) => sendValue(q) + PULL_GAS * 50_000_000n;

/** Gas limit from the app's RPC estimate plus 20 percent. A reverting estimate throws with the
 *  decoded revert reason, and the transaction is not sent. */
export async function estimateGas(estimate: () => Promise<bigint>): Promise<{ gas: bigint }> {
  return { gas: ((await estimate()) * 12n) / 10n };
}

/** Quote and inventory version read at send time. The fee cap is 2 percent above the quoted fee;
 *  `maxNegativeSlippageBps` 1,000 tolerates a price fall of up to 10 % before settlement. */
export async function readFresh(client: PublicClient | undefined, dep: Deployment, count: number) {
  if (!client) throw new Error("No RPC client.");
  const q = await readQuote(client, dep, count);
  const block = await client.getBlock().catch(() => undefined);
  const now = Math.max(Number(block?.timestamp ?? 0n), Math.floor(Date.now() / 1000));
  return {
    q,
    negativeSlippageBps: 1_000n,
    version: q.inventoryVersion,
    deadline: BigInt(now + 600),
    maxFee: (q.fee * 102n) / 100n,
    value: sendValue(q),
  };
}

// ------------------------------------------------------------------ pull state

export type PullState = { open: boolean; pill: string; tone: "warn" | "bad"; headline: string; sub?: string };

/** Whether pulls are open, from activation, the pause flag, the inventory cooldown and the board. */
export function pullState(pool: PoolData): PullState {
  const g = pool.game;
  if (!g.activated) return { open: false, pill: "Opening", tone: "warn", headline: "Pulls start when the game activates." };
  if (g.paused) return { open: false, pill: "Paused", tone: "bad", headline: "Pulls are paused by the guardian.", sub: "Settlement, delivery, refunds and claims continue." };
  const resume = Number(pool.params.purchasesResumeAt);
  if (resume > Date.now() / 1000) {
    return { open: false, pill: "Restocking", tone: "warn", headline: "The board is between inventory updates.", sub: `Pulls resume at ${utc(resume)}.` };
  }
  if (g.activeListings === 0n) return { open: false, pill: "Restocking", tone: "warn", headline: "The board is restocking." };
  return {
    open: true,
    pill: "Open",
    tone: "warn",
    headline: "Pull a Shape or a Draw Pack.",
    sub: `${g.activeListings.toLocaleString("en-US")} items listed, ${eth(g.backing, 3)} ETH of backing on the board.`,
  };
}
