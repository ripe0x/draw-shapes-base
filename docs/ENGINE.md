# DrawEngine and the game contracts (Milestone 1)

Draw Shapes on Base keeps FWA's NFT-based gacha: real ETH-backed Shapes and Draw Packs are minted,
escrowed as listings, priced by notional, selected by inverse-notional weight with a Chainlink VRF
word, and delivered to the player. This document states what was reused, what changed and why.

## Contracts

| Contract | Role | Source |
| --- | --- | --- |
| `src/engine/DrawEngine.sol` | Listings, staging, reservations, segment-tree selection, harmonic-mean price, ordered VRF settlement, delivery escrow, refunds, settlement fee split, participation ledger. | Fork of FWAClone (FWA V2 standard custom pool), verified mainnet source `0xeaa4…1eb31`, MIT. |
| `src/game/DrawController.sol` | Protocol-owned house: mints Shapes / Draw Packs, lists them at notional, books every settled acquisition, queues replacements, splits margin, harvests proceeds, refunds keepers from maintenance, releases realised surplus after the maintenance floor. | Port of Draw Shapes `Pool` + `PoolBooks` + `PoolListing` (ripe0x/draw-shapes `4a13a09`), MIT. |
| `src/game/GrailVault.sol` | GRAIL fund; mints a GRAIL only when its whole backing and mint fee are funded, lists it below backing, decays its notional per pull under a probability cap. A second engine supplier. | Port of the Draw Shapes GRAIL engine (`PoolListing`), simplified. |
| `src/game/PricingLib.sol` | Mix-table math, replacement row draw, listing price, GRAIL notional and decay. | Draw Shapes `src/lib/PricingLib.sol`, entry-fee/share functions removed. |
| Shapes v1, Draw Packs | Prize tokens. Deployed unchanged from `ripe0x/shapes@1b84c102` (the Ethereum mainnet commit) and `ripe0x/shape-packs@3a463f75` (`draw-packs` branch, `MIN_PACK_VALUE = 2 units`). | Submodules, MIT. |

## Pricing (unchanged formulas, no FWA edge)

Notional of an ordinary item with backing `b` made of `k` Shapes:

    p = b * (10_000 + premiumBps + maintenanceBps + feedBps) / 10_000 + k * mintFee

with premium 350, maintenance 50, feed 300 bps (launch; previously 400 / 50 / 200, originally 300 / 100 / 400) and the Shapes mint fee 0.001 ETH. Weight is
`1e36 / p` (FWA's integer numerator and truncation). The acquisition fee is FWA's
`weightedBackingTotal / totalWeight` with **no edge multiplier**, i.e. the harmonic mean of active
notionals, rounded down. The settlement fee is `fee * 100 / 10_000`, rounded down, on the full fee.
The purchaser's VRF fee is quoted and paid separately, once per batch (below).

Reference board (test `ReferenceBoard.t.sol`, real Shapes and Draw Packs):

| Measure | Contract value |
| --- | --- |
| Listings | 62 × 0.01, 26 × 0.02 pack, 7 × 0.03 pack, 4 × 0.05, 1 × 0.1 |
| Backing / mint fees | 1.65 ETH / 0.14 ETH (140 Shapes) |
| Notionals | 0.0117 / 0.0234 / 0.0351 / 0.0545 / 0.108 ETH, exact (launch 3.5 / 0.5 / 3) |
| Acquisition fee | 14,942,455,786,105,613 wei |
| Settlement fee | 148,785,403,573,383 wei |
| Fee + settlement (reference price before VRF) | 15,091,880,343,966,669 wei (≈ 0.015092 ETH) |
| VRF fee (per batch, basefee 0.01 gwei) | 1 pull 0.0000289 ETH; 4–20 pulls 0.0000644 ETH (callback limit capped at 2.5M), each including the 30 % service margin |
| Expected backing | 12,819,466,318,547,036 wei, 84.94 % of fee + settlement (84.91 % incl. a 10-pull batch's VRF share) |

Previous configuration (3 / 1 / 4): fee 15,070,286,533,069,302, payment 15,220,989,398,399,995 wei, 84.22 %.

The test recomputes `Σwᵢpᵢ / Σwᵢ` independently and asserts equality to the wei with the engine's
`acquisitionFee()` and with `quoteAcquisitionPrice(n)` for 1 and 10 pulls.

### Removing the FWA edge

FWAClone charged `EV * (1 + edgeBps)` with `edgeBps = 500` and split the edge half to FWA, half to
the owner (`protocolAmount = (paid - base) / 2`). The engine charges `EV` and pays the whole fee to the
captured listing's depositor. The half that FWA kept is gone from the player's price; the half that
returned to the owner is also gone, so the game's margin is only its configured premium,
maintenance, feed and mint-line allowances. Nothing of the removed 5 % is counted as game profit.

## Changes from FWAClone

| Area | FWAClone | DrawEngine | Why |
| --- | --- | --- | --- |
| Governance | Factory (global flags, VRF config, cooldown, edge) and a locked owner | `governance` (timelock) sets bounded parameters; `guardian` may only pause new acquisitions; approved `suppliers` list inventory | No FWA factory on Base; separate fast and slow powers |
| Price | `EV × (1 + edge)` | `EV` | Brief §4 |
| Fees | Half edge to FWA | 1 % settlement fee on top, escrowed with the fee, split at verified delivery 50 % referrer / 25 % Token Works / 25 % development (follow-up; was 10 / 40) by the policy snapshotted at request; refunded with the fee on every refund path | Brief §6 |
| VRF | One request per acquisition through FWA's VRF service | One Chainlink v2.5 request per `acquireBatch`; acquisition `i` uses `keccak256(word, i)`; callback gas `base + n × perAcquisition` | Brief §11 |
| VRF fee | Player pays the service fee per request | Purchaser pays one VRF fee per batch, quoted separately: `(overheadGas + callbackGasLimit(n)) × max(basefee, floor) × (1 + premium + buffer) + flat`, plus a service margin `(overheadGas + callbackGasLimit(n)) × max(basefee, floor) × marginBps` (30 %, FWA V2's `serviceMarginBps`) credited to development, capped at 0.002 ETH in total with the subscription's share kept first; the Chainlink part is forwarded to the subscription at purchase (`fundSubscriptionWithNative`); never part of backing, escrow or earnings; not refunded (it paid for the request) | FWA V2 model adapted to one request per batch (follow-up) |
| Request ids | Chainlink request id | Local sequence number; `vrfRequestOf` / `vrfBatches` map batches | Batching |
| Inventory | Single owner | Multiple governance-approved suppliers, proceeds per depositor, `transferListings` hand-off without moving NFTs | Extensibility (controller replacement, GRAIL vault, partner prizes) |
| Version guard | Exact version required | Exact version, or `ANY_INVENTORY_VERSION` (fee and value guards still apply) | The protocol-owned controller relists after every capture; exact matching would make farmer batches revert constantly |
| Delivery refund | Purchaser only | Anyone after the 7-day window, credit always to the purchaser | So a ledger day always resolves |
| Rewards | Separate rewards module | In-engine participation ledger per 24 h day of acceptance: accepted, resolved, units and VRF-derived bonus weight per purchaser | Farming (Milestone 2); no external call in settlement |
| Fast path | One `processAcquisitions(1)` self-call | Word cached first, then up to `count` isolated single-item self-calls, each given all gas above a 60k return reserve (≥ 400k to attempt; a cold first acquisition needs ~620k) | Batches settle inside the callback when gas allows (Base fork: 1 → 1, 4 → 4, 10 → 7 settled in the callback) |
| Payer / beneficiary | Purchaser only | `msg.sender` pays and receives only overpayment; `purchaser` receives prize, genesis units and refunds; `referrer` separate; `AcquisitionRequested` carries the payer | Purchase on behalf (follow-up) |
| Concurrency | Per-pool cap 10 (VRF service) | `maxUnsettledAcquisitions` 250, `maxAcquisitionsPerTx` 20 | Farmers batch |
| Edge, protocol fee payout, factory hooks, `IMPLEMENTATION_KIND` | present | removed | Not used |

Retained without behavioural change: staging FIFO and request-time reservation, ordered processing,
cache-first callback, word deadline and timeout, slippage refunds (10 % positive, purchaser-chosen
negative), empty-pool refunds, delivery escrow with permissionless retry, pull refunds, inverse
weights, segment tree, slot free list, withdraw / reprice lock while anything is unsettled, purchase
operator hook, retirement.

## Settlement, books and replacement (controller)

`settle(n)`: process up to `n` engine acquisitions, walk FWA sequences in order, book each:

- Fulfilled ordinary capture: `backing -= value`, `receivable += paid`, `margin += paid - value`,
  `mintLineOwed += mintFee × rungs`, queue a replacement row (deficit draw with `restoreK` 8, surprise
  200 bps, band 3,000 bps; Draw Shapes `PricingLib.chooseRow`), split positive margin.
- Delivery still pending / refunded: written off at its value; a later delivery's proceeds arrive as
  surplus; a later refund is recovered and redeemed (`recoverRefunded`).
- Expired / refunded: nothing.

Margin split (Draw Shapes `_splitMargin`): positive margin repays the mint line, the rest divides
3.5 : 0.5 : 3 into premium (stays in the ordinary pool), maintenance and GRAIL feed. Harvest withdraws
engine proceeds when the walk is level and forwards the feed to `GrailVault`.

Restocking mints from `cash` only (above `cashFloor`). An entry cash cannot fund stays queued.

## GRAILs

The vault mints one Shape of the ladder rung being funded (0.5, 1, 5 ETH) only when
`fund ≥ backing + mintFee`, so a GRAIL is never selectable unfunded. It lists at 80 % of backing,
decays by 0.00002 ETH per processed pull to a 50 % floor while the GRAIL weight stays under 5 % of the
engine weight, and returns capture proceeds to the fund. A cycle funded in under 3 days steps the
next target up, over 14 days down (Draw Shapes step rule). While no GRAIL is live the next target is
the smallest rung (replacement first) and such a replacement does not move the ladder. Funding: the
controller's 3 % feed and the treasury's trading-fee share (100 % while no GRAIL is live, else 90 %),
plus `fundGrail` from anyone.

Deviation: the Draw Shapes 1 ETH piece and merge builder (5 / 10 / 25 / 50 / 100 ETH recipes) is not
ported. Base targets are native Shapes rungs, so a GRAIL is a single mint.

## Roles

| Role | Engine | Controller / vault |
| --- | --- | --- |
| Governance (timelock) | activate, suppliers, bounded fee policy and recipients, limits, VRF config (only idle), VRF fee formula, retire, guardian | fee split, mix, board size, replacement, tip, capital target, maintenance floor, surplus sink, GRAIL config, external prizes, hand-off |
| Guardian | pause / unpause new acquisitions | pause / unpause minting and listing |
| Anyone | process, retry delivery, refund stuck delivery after window, activate staged listings | settle, build, book, release surplus, recover refunded, vault step |

Hard bounds in code: settlement fee ≤ 2 %, VRF fee ≤ 0.002 ETH / batch (premium ≤ 200 %, buffer ≤ 50 %, service margin ≤ 100 %), cooldown ≤ 1 h, batch ≤ 50,
unsettled ≤ 1,000, controller markups sum ≤ 15 %, tip ≤ 0.001 ETH. No role can move escrowed fees,
refund credits, fee credits or listed NFTs to itself.

## Base presentation (card colour)

Shapes and Draw Packs on Base render **white cards with Base-blue shapes** (#fff field, #0052FF
marks; the inverted Black Shape is a Base-blue field with white marks; collection and pack preview
cards are white).
`src/presentation/BaseShapeRenderer.sol`, `BaseShapeCollection.sol` and `BasePackRenderer.sol` are
generated by `script/presentation/make_base_renderers.py` from the pinned v1 sources; the script
asserts that only the listed colour literals change. The Shapes and Draw Packs token contracts
(backing, minting, compose/split, redemption) are deployed unchanged and use these as their
renderer/collection, which Shapes v1 supports through its admin-only presentation pointers (until
the admin locks presentation). `test/unit/Presentation.t.sol` proves the Base card equals the v1 card
with only the colours replaced. Rendered example: `evidence/web/shape-card-base-blue.png`.
