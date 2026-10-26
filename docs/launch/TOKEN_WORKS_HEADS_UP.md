# Private heads-up to Token Works (draft — not sent)

Hi [name],

We're preparing to launch Draw Shapes on Base and wanted you to hear about it from us first, before anything
public.

**What it is.** A prize draw where every prize is an ETH-backed Shape or Draw Pack. It runs on a fork of
FWA's custom-pool contract (FWAClone, MIT) and keeps your selection, pricing, ordered VRF settlement,
slippage and refund machinery. Changes:
- the house is protocol-owned (the game mints and replaces prizes);
- FWA's 5 % edge is removed;
- one Chainlink request per batch, paid by the purchaser;
- a daily participation ledger used for a token genesis.

**Your share.** A 1 % settlement fee on every delivered pull is split 50 % referrer, **25 % Token Works**,
25 % development. It is paid as a withdrawable credit to a fixed recipient address set at deployment. At about
0.0151 ETH per pull, that is about 0.0000374 ETH per pull to Token Works.

**What we need from you**
1. The Base address that should receive Token Works' share. Your Ethereum recipient has no code on Base, so we
   won't assume it. The deployment refuses to proceed without a confirmed address.
2. Your preference for attribution wording, and any objection to the description above.
3. Optionally, a review of the engine diff against FWAClone (`docs/ENGINE.md` lists every change).

**Status.**
- Not yet deployed to mainnet.
- A Base Sepolia rehearsal is [done / scheduled].
- Audit: [status].
- Target launch: [date].

Happy to walk through it.

[signature]
