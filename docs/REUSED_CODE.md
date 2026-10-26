# Reused code inventory

Every reused source, the exact revision, its licence and how it is used. Licences were read from
the repository `LICENSE` files and the SPDX headers of the files used.

| Source | Revision | Licence | Used as | Files here |
| --- | --- | --- | --- | --- |
| FWAClone (Token Works FWA V2 standard custom pool), verified Ethereum source of `0xeaa4d032908a9734a2c7939c0d211c35ad51eb31`, as vendored in ripe0x/draw-shapes `external/fwa-v2/mainnet/FWAClone` | draw-shapes `4a13a09e`; file sha256 `09204f13…08be` | MIT (SPDX) | Forked and modified (see docs/ENGINE.md) | `src/engine/DrawEngine.sol` |
| FWACloneVRFService, FWAFactory (same vendoring) | as above | MIT (SPDX) | Read for VRF coverage, limits and config semantics; not deployed | — |
| FWA V2 Rewards (`0xA54b44C7…5f6516`), verified source vendored in ripe0x/punk-or-bust `refs/fwa-v2-rewards` | punk-or-bust `13ad786c` | MIT (SPDX) | Model for request-time epochs, pending-per-epoch gate and pro-rata claims | `src/engine/DrawEngine.sol` (ledger), `src/token/GenesisFarm.sol` (Milestone 2) |
| ripe0x/draw-shapes `Pool`, `PoolBooks`, `PoolListing`, `PoolStorage`, `lib/PricingLib` | `4a13a09e` | MIT (SPDX; repository has no LICENSE file) | Ported with depositor/exit/migration removed | `src/game/DrawController.sol`, `src/game/GrailVault.sol`, `src/game/PricingLib.sol` |
| ripe0x/draw-shapes PR #7 (`2c70c15a`) | | MIT (SPDX) | Economic modelling approach (seeds, percentiles, fork reconciliation) and v4 hook notes; founder-financing architecture not used | `sim/` (Milestone 2) |
| ripe0x/shapes (Shapes v1) | `1b84c102` (commit recorded in its Ethereum mainnet deployment record) | MIT | Token contract unchanged on Base; renderer and collection regenerated with Base-blue colours only | `lib/shapes`, `src/presentation` |
| ripe0x/shape-packs, `draw-packs` branch (Draw Packs) | `3a463f75` | MIT | Unchanged submodule, `MIN_PACK_VALUE = 2 × unit` | `lib/draw-packs` |
| token-works/fwa-relaunch `FWATokenHook`, `FWAToken` | `1085bf6e` | MIT (SPDX; no LICENSE file) | Hook structure (afterSwap fee take, launch latch) adapted; transfer locks not used | `src/token/EngineHook.sol` (Milestone 2) |
| Uniswap v4-core | `59d3ecf5` | BUSL-1.1 (`PoolManager`), MIT / GPL (libraries) | Libraries and interfaces; `PoolManager` deployed only in tests (Base uses the canonical deployment) | `lib/v4-core` |
| Uniswap v4-periphery | `60cd9380` | MIT | `BaseHook`, `LiquidityAmounts` | `lib/v4-periphery` |
| uniswapfoundation/v4-template | `1fbf9554` | MIT | Hook deployment / mining pattern reference | — |
| Chainlink `VRFV2PlusClient`, `IVRFCoordinatorV2Plus`, `IVRFSubscriptionV2Plus` (from the FWA vendored chainlink-evm tree) | as above | MIT | Interfaces only | `src/vendor/chainlink` |
| Solady | `166f85b9` | MIT | `ReentrancyGuard`, `SafeTransferLib`, `SafeCastLib`, `FixedPointMathLib`, `ERC20` | `lib/solady` |
| OpenZeppelin Contracts (the copy vendored inside Shapes) | Shapes `1b84c102` | MIT | `TimelockController`, ERC-721 interfaces | `lib/shapes/lib/openzeppelin-contracts` |
| forge-std | `b3bc8b15` | MIT / Apache-2.0 | Tests | `lib/forge-std` |

The previous September Draw Shapes design (0.05 ETH pulls, heat, four growing targets) is not used.
