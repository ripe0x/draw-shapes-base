"use client";

import { isAddress, zeroAddress, type Address } from "viem";

const KEY = "draw-shapes-referrer";

/** Remembers `?ref=0x...` from the page URL, so a referral link survives navigation. */
export function rememberReferrer(): void {
  try {
    const ref = new URLSearchParams(window.location.search).get("ref");
    if (ref && isAddress(ref)) localStorage.setItem(KEY, ref);
  } catch {
    // storage unavailable: the referral applies to this page view only
  }
}

/** The remembered referrer for `purchaser`, or zero (the referral share then goes to development).
 *  The engine also ignores self-referral. */
export function referrerFor(purchaser: Address): Address {
  try {
    const ref = new URLSearchParams(window.location.search).get("ref") ?? localStorage.getItem(KEY);
    if (ref && isAddress(ref) && ref.toLowerCase() !== purchaser.toLowerCase()) return ref;
  } catch {
    // ignore
  }
  return zeroAddress;
}
