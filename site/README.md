# Draw Shapes on Base: player site

The original Draw Shapes app (Next.js, RainbowKit, wagmi), ported to the Base contracts. Its components and styles are unchanged where
the game is the same; the data layer reads DrawEngine (the protocol-owned FWA fork that sells pulls), DrawController, GrailVault,
GenesisFarm and the Base Lens.

| Route | Content |
| --- | --- |
| `/` | Live board summary, carousel of listed items, pull card, the board grid beside the GRAIL, what a pull can draw, genesis band. |
| `/pull` | Pull card with batch size 1 to 10, price breakdown, the wallet's pulls with their reveal, refund withdrawal. |
| `/genesis` | ENGINE genesis epochs, the wallet's units and claimable ENGINE, its referral link and fee credit, the ENGINE market. Replaces the original `/deposit`: the Base game has no outside depositors. |
| `/protocol` | Live state, board and odds, GRAIL, buckets, upkeep (`settle`, GRAIL `step`, `processAcquisitions`), parameters, FAQ. |

Art is each token's on-chain `tokenURI` image. Pull history reads the engine's acquisitions by sequence number and `Lens.receipt`,
not event logs: Base Sepolia's 0.2 s blocks and the public RPC's 200-block log cap make log scans impractical. `?ref=0x...` on any
page sets the referrer for the wallet's pulls.

## Build

```
cd site && npm ci
npm run abi            # after `forge build` at the repo root: writes app/lib/abi/*.ts (committed)
npm run build          # static export to out/
```

The deployment record is bundled from `site/deployments/<chainId>.json` (copy from `deployments/` after a deployment).
`NEXT_PUBLIC_CHAIN_ID` selects it (default 84532, Base Sepolia). Optional: `NEXT_PUBLIC_RPC_URL` (primary RPC ahead of the public
ones) and `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`. Netlify builds it from the root `netlify.toml`.
