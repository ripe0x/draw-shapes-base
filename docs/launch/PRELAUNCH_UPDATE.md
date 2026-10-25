# Prelaunch update (draft): from the FWA custom-pool preview to Draw Shapes on Base

The preview ran Draw Shapes as an FWA custom pool. The Base version keeps FWA's pull mechanics and changes
who supplies prizes and how the economics flow.

**What stays from FWA**
- Inverse-notional selection: cheaper prizes are more likely.
- A harmonic-mean price.
- Ordered settlement from a Chainlink VRF word.
- Slippage protection and refunds.
- Delivery escrow.

The engine is a fork of FWA's custom-pool contract (MIT), credited to Token Works.

**What changes**
- **The house is protocol-owned.** The game mints real Shapes and Draw Packs into the board and replaces
  each prize as it is won. There are no outside depositors.
- **No edge.** FWA's 5 % edge is removed; the price is the board's expected notional. A separate 1 %
  settlement fee goes 50 % to referrers, 25 % to Token Works and 25 % to development.
- **The player pays the randomness.** Each batch pays its own Chainlink fee, shown separately and
  forwarded to the subscription at purchase.
- **GRAILs.** Large prizes are funded from 3 % of every pull's notional and from ENGINE trading fees. They
  are listed only when fully funded.
- **ENGINE and genesis.** A fixed-supply token with a 14-day genesis for players, a 2 % trading fee that
  funds GRAILs and liquidity, and post-genesis buy-and-burn from realised game surplus.

**Safety model**
- A 48-hour timelock for every parameter change, within hard limits.
- A guardian that can only pause.
- No role can move player escrow, refunds or prizes.

**Status:** [Base Sepolia rehearsal results] · [audit status] · [launch date].
