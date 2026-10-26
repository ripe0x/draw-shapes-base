# Draw Shapes on Base

An onchain gacha with real ETH-backed NFT prizes on Base (chain 8453), built on a fork of FWA's
NFT custom-pool engine. Players pay ETH for a verifiably random draw from a board of Shapes and
Draw Packs; every prize holds redeemable ETH. ENGINE is a fixed-supply speculative ERC-20 with a
single 14-day genesis farming distribution, traded on a Uniswap v4 pool whose fees fund GRAIL
prizes. **Nothing here is deployed to Base mainnet**; see docs/RUNBOOK.md for the gates.

```
src/engine/DrawEngine.sol       FWAClone fork: listings, VRF batches, harmonic-mean price, settlement, fees, ledger
src/game/DrawController.sol     protocol-owned house: Shapes/Packs board, books, replacement, margin split
src/game/GrailVault.sol         funded-only GRAILs, below-backing listing and decay
src/token/EngineToken.sol       ENGINE, fixed supply
src/token/EngineHook.sol        v4 hook: 2 % ETH fee (0.25 % operator, 1.75 % treasury)
src/token/ProtocolLiquidity.sol locked full-range protocol liquidity
src/token/GenesisFarm.sol       14 epochs, 85 % pro rata / 15 % VRF bonus, unearned burn
src/treasury/Treasury.sol       reserve → 90 % GRAIL / 10 % POL, restock backstop
src/treasury/Buyback.sol        post-genesis surplus buy-and-burn
src/Lens.sol                    read-only views
script/                         Deployer (shared with tests), Deploy.s.sol, configs, VRF cost measurement
sim/                            market (reconciled with v4), farming, bankroll Monte Carlo
web/                            player app (Vite + React + viem)
docs/                           specifications, results, runbook, security
```

## Build and test

```
git submodule update --init --recursive
forge build
forge test                                            # unit, invariant, rehearsal, market sim
BASE_RPC_URL=https://mainnet.base.org forge test --match-path "test/fork/*" -vv
python3 sim/market.py && python3 sim/farming.py && python3 sim/bankroll.py 2000
cd web && npm install && npm run abi && npm run build
```

Foundry 1.5.1, solc 0.8.28 (0.8.26 for the test-only v4 PoolManager), via_ir, optimizer_runs 20.

## Documents

| | |
| --- | --- |
| docs/FINAL_REPORT.md | what was built, test results, remaining blockers |
| docs/ENGINE.md, docs/M1_RESULTS.md | milestone 1: engine, controller, GRAIL, VRF |
| docs/MARKET.md, docs/M2_RESULTS.md | milestone 2: ENGINE, hook, farm, market and bankroll results, recommendation |
| docs/ECONOMICS.md | full configuration, money flows to the wei, capital, GRAIL and surplus accounting |
| docs/ADMIN.md, docs/SECURITY.md | authority, dependencies, threat model |
| docs/RUNBOOK.md, docs/M3_RESULTS.md | deployment, activation, keepers, emergencies; milestone 3 results |
| docs/REUSED_CODE.md | sources, commits, licences |
