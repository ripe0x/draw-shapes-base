# Draw Shapes on Base — player app

Vite + React + viem. Reads live state through the deployed `Lens` and writes directly to the
contracts from the player's wallet. No backend.

```
npm install
npm run abi          # after `forge build` in the repo root
cp ../deployments/<deployment>.json src/deployment.json
VITE_RPC_URL=<rpc> npm run dev     # or: npm run build
```

Features: live open/paused state, quote for 1/5/10/20 pulls with the exact acquisition fee,
settlement fee and expected ETH backing, pulls through `acquireBatch` with the referral from
`?ref=0x…`, my pulls and prizes, refund withdrawal, GRAIL funding progress and live GRAIL odds, the
board with backing vs notional and per-row odds, genesis epoch, units, claimable ENGINE and claims,
ENGINE price and fees with the speculative-token disclosure.

`scripts/keeper.mjs` is a minimal permissionless keeper. `scripts/fork-demo.mjs` activates a local
Base-fork deployment and delivers VRF words from the coordinator address (anvil only); the
screenshots in `evidence/web/` were produced that way.
