/** Joins shortMessage, metaMessages and details along a viem error's cause chain. The top-level
 *  message of a failed transaction is generic; the revert reason is nested. */
export function formatTxError(err: unknown): string {
  const parts: string[] = [];
  let cur: unknown = err;
  for (let depth = 0; cur && depth < 6; depth++) {
    if (!(cur instanceof Error)) {
      parts.push(String(cur));
      break;
    }
    const e = cur as Error & { shortMessage?: string; metaMessages?: string[]; details?: string; cause?: unknown };
    if (e.shortMessage) parts.push(e.shortMessage);
    if (e.metaMessages?.length) parts.push(...e.metaMessages);
    if (e.details) parts.push(e.details);
    cur = e.cause;
  }
  return parts.length ? [...new Set(parts)].join(" ") : err instanceof Error ? err.message : "Unknown error.";
}

/** Basescan for Base and Base Sepolia. The names stay from the original app, which used evm.now. */
const explorer = (chainId: number) => (chainId === 8453 ? "https://basescan.org" : "https://sepolia.basescan.org");

export function evmNowTxUrl(hash: string, chainId: number): string {
  return `${explorer(chainId)}/tx/${hash}`;
}

export function evmNowAddressUrl(address: string, chainId: number): string {
  return `${explorer(chainId)}/address/${address}`;
}
