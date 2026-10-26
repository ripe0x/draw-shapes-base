/** Bump when the Terms change materially: every wallet is asked to accept again. */
export const TERMS_VERSION = "2026-10-26";

/** The legal entity that operates the interface, named in the Terms (set at build time). */
export const OPERATOR = process.env.NEXT_PUBLIC_OPERATOR_NAME || "the operator of Draw Shapes";

/** Where notices, including arbitration opt-outs, are sent (set at build time). */
export const CONTACT = process.env.NEXT_PUBLIC_CONTACT || "";
