# Administrative authority and external dependencies

## Roles

| Role | Holder (deployment config) | Speed | Can | Cannot |
| --- | --- | --- | --- | --- |
| Governance | OpenZeppelin `TimelockController`, proposer and executor = admin Safe (`adminSafe`), delay 48 h (`timelockDelay`) | slow | Engine: activate (once), suppliers, fee policy (settlement ≤ 2 %, referrer + Token Works shares), recipients, limits within caps, VRF config only while idle, purchaser VRF fee formula (premium ≤ 200 %, buffer ≤ 50 %, service margin ≤ 100 %, result ≤ 0.002 ETH/batch), guardian, retire. Controller: fee split (≤ 15 % total), mix, board size / cash floor, replacement parameters, tip ≤ 0.001 ETH, capital target, maintenance floor, surplus sink, external prizes, listing hand-off. Vault: GRAIL config and ladder. Hook: fee ≤ 5 %, operator share, recipients, fee exemptions. Treasury: reserve target ≤ 50 ETH, backstop floor ≤ 5 ETH, GRAIL share, keeper. Migration of protocol-owned ETH to a successor (`DrawController.migrateCapital`, `GrailVault.migrate`, `Treasury.migrate`; see RUNBOOK). Buyback: slice, spacing, impact cap ≤ 10 %, bounty ≤ 1 %, minimum buy ≤ slice, bounty cap ≤ 0.001 ETH. ProtocolLiquidity: launch (once), treasury pointer. | Move escrow, refund credits, fee credits, proceeds of another depositor, prizes players hold, LP liquidity or farm tokens to itself or anyone. Migrate controller capital while a pull is unresolved, the books are behind or items are still listed; migrate the GRAIL vault while a pull is unresolved. Mint ENGINE. Change earned rewards. Upgrade anything in place. |
| Guardian | `guardian` (a fast multisig) | immediate | Pause/unpause: engine acquisitions, controller minting and listing, GRAIL vault steps, buybacks. | Anything else. Pausing never blocks VRF callbacks, processing, delivery, refunds, withdrawals, claims or settlement booking. |
| Keeper | `keeper` | immediate | Deploy the treasury's POL share with a price limit. | — |
| Operator | `creator` | — | Receives 0.25 % of canonical-pool volume; is the Shapes fee recipient (0.001 ETH per minted Shape) and Shapes/Draw Packs admin (presentation only — Shapes v1 admin cannot touch backing). | — |
| Anyone | — | — | Process acquisitions, settle/build/book, release surplus (when allowed), recover refunded items, step the GRAIL vault, distribute hook fees, backstop, buy-and-burn, retire unearned farm epochs, claim own rewards and credits. | — |

During deployment the broadcaster is temporary governance of the engine, controller, vault and
hook, configures them, and proposes the timelock; the activation batch makes the timelock accept.
Treasury, buyback and protocol liquidity are owned by the timelock from construction.

Signer addresses are not invented here: `script/config/base.json` ships with zeros and the deploy
script refuses to run until they are supplied.

## Immutable guarantees

- ENGINE: total supply fixed at construction (35M recommended); no mint function, no owner.
- Farm: 14 epochs, allocation per epoch, 85 / 15 split, claim rules and unearned-only retirement are code; no owner.
- Engine: escrowed fees, refund credits, fee credits and per-depositor proceeds are only payable to their owners.
- Protocol liquidity: no removal path.
- No proxies: no contract can be upgraded.

## External dependencies (Base, chain 8453)

| Dependency | Address | Verified | Used for |
| --- | --- | --- | --- |
| Chainlink VRF v2.5 coordinator | `0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634` | on chain 2026-10-24: proving keys 2 gwei `0x00b81b5a…3ccab` and 30 gwei `0xdc2f8767…44d70`, max callback gas 2.5M, native premium 60 % | randomness; subscription owned by the admin Safe |
| Chainlink VRF v2.5 coordinator (Base Sepolia) | `0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE` | on chain: key `0x9e1344a1…44bf71` (30 gwei) | rehearsal |
| Uniswap v4 PoolManager | `0x498581fF718922c3f8e6A244956aF099B2652b2b` | code present, used by the Base fork deployment test | canonical ENGINE market |
| Uniswap v4 PoolManager (Base Sepolia) | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` | code present | rehearsal |
| CREATE2 factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` | standard | hook address mining |
| Shapes v1, Draw Packs | deployed by this project on Base from the pinned commits | — | prizes |
| Token Works settlement-fee recipient | **unverified** | FWA's Ethereum protocol fee recipient `0xaba91665cdf921F0f6B33A099337336B324c9793` has no code on Base; a Base address must come from Token Works | 10 % of settlement fees |
