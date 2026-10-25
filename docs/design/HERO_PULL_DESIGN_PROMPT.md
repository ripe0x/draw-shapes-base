# Design brief: hero and pull experience, Draw Shapes on Base

## What we need from you

Three distinct design directions for the home page hero and the pulling experience of Draw Shapes on Base. Each direction should
be a different answer to the layout and the information hierarchy, not a reskin of the others.

For each direction, deliver two static screens:

1. **Initial view.** What a visitor sees on arrival: the hero and everything needed to make a pull.
2. **Pulled results view.** The same page after a pull has resolved, showing what the player received.

Show each screen at desktop width (about 1440 px) and at mobile width (about 390 px). These are static designs: no animation,
motion studies or clickable prototypes yet. Where a moment would be animated later, show its resting state.

Annotate each direction briefly. Say what it optimises for, what it gives up, and how it handles the states listed below.

## The product

Draw Shapes is an on-chain gacha game on Base. A player pays a fixed ticket price to "pull" and receives one random prize per pull.
Every prize is either a **Shape** (a single generative artwork NFT) or a **Draw Pack** (a bundle of 2 or 3 Shapes). Every prize holds
real ETH inside it: the holder can redeem it at any time for exactly its backing. Prizes range from 0.01 ETH to 0.1 ETH on the
ordinary board.

Cheaper items are more likely: each item's chance is proportional to the inverse of its list price. Randomness comes from Chainlink
VRF, and the prize arrives in the player's wallet within seconds.

A **GRAIL** is a rare, high-value prize, currently 0.05 ETH on testnet and 0.5 ETH, 1 ETH or 5 ETH at launch. It sits on the same board
when one is live. Its odds rise slowly with every pull. Sometimes none is live; then a fund is filling toward the next one.

On average a pull returns less ETH backing than it costs (about 85–89 %). That gap is part of the game and must never be hidden or
softened.

## Goals

- Make pulling feel exciting and immediate, and make the next pull inviting.
- Make it obvious within seconds what you can win, what it costs, and that every prize is real ETH you can redeem.
- Give the GRAIL its weight as the headline prize, and stay honest that it may be unlikely or not live right now.
- Let the artwork lead. The Shapes are the product's identity.
- Present the results so the player understands what they got, what it is worth and what they can do with it.

## Visual style (keep it)

Work within the current visual language. Do not introduce a new brand.

- **Palette:** warm off-white page (`#f7f7f3`), near-black ink (`#11110f`), and a scale of warm greys for body text, muted text,
  rules and borders (`#2f2f2b`, `#4f4f49`, `#686862`, `#aaa9a1`, `#d8d8d1`, `#e7e7e1`, `#b9b9b1`).
- **Status colours:** used sparingly: good `#2f6b3a`, warn `#9a6a1f`, bad `#a3352f`.
- **Accent:** the only strong colour on the page is the electric blue of the Shape artwork itself.
- **Type:**
  - Archivo (heavy, tight) for headlines and big numbers;
  - IBM Plex Mono for body, labels, data and small caps-style section labels.
- **Surfaces:**
  - flat cards with thin rules;
  - pill-shaped buttons and toggles, with a black filled primary action;
  - playing-card-proportioned artwork (5:7) with a subtle drop shadow.
- **Tone:** quiet, precise, editorial. Exact numbers, plain sentences, no hype or casino styling.

Use the live site as reference: https://draw-shapes-base-sepolia.netlify.app (hero on `/`, pull panel on `/pull`).

## Content and data available

Use real-looking values. Everything below is available live:

- **The board:** every listed item with its artwork, kind (Shape or Draw Pack of 2 or 3), ETH backing and list price. There are
  currently 28 items on testnet and about 100 at launch.
- **Odds:** the chance per pull for each value tier and for each live GRAIL. The average redeemable value per pull, and the chance a
  pull returns at least its ticket.
- **Price:**
  - the ticket per pull (about 0.0158 ETH);
  - a 1 % settlement fee per pull;
  - one small VRF fee per batch (about 0.00001–0.00003 ETH);
  - the total for the chosen batch size.
- **Batch size:** 1 to 10 pulls in one transaction.
- **GRAIL:** whether one is live, its artwork, backing, current list price and odds per pull. Otherwise, the fund's progress toward
  the next GRAIL and its size.
- **Wallet:** connection, ETH balance, network, and the player's past pulls.
- **Each resolved pull:**
  - the prize's artwork, kind and ETH backing;
  - whether it was a GRAIL;
  - whether it was refunded instead (the randomness arrived late, or the price moved past the player's limit).
- **Batch summary:** total paid against total redeemable value received.
- **Genesis (first 14 days):** every pull also earns ENGINE token rewards, claimable later.
- **Referrals:** a pull can carry a referrer.

## States to account for

You don't need a screen for every state, but each direction should show where these would live and how they would read.

**Before pulling:**
- wallet not connected;
- wrong network;
- not enough ETH;
- pulls temporarily unavailable (paused, or the board restocking);
- price loading.

**During a pull:**
- waiting for the wallet signature;
- transaction sent;
- waiting for randomness, usually seconds.

**After a pull:**
- every prize delivered;
- a mix of delivered and refunded;
- a GRAIL won;
- a batch of 1;
- a batch of 10.

## Constraints

- **Honesty:** every number shown must be real and current. No implied guarantees, no hiding the fees or the average return, and
  never show a GRAIL as winnable when none is live.
- **Separate costs:** the ticket, settlement fee and VRF fee are separate costs. They can be summarised, but the full total must be
  visible before the player commits.
- **Results:**
  - redemption at face value is a core promise and should be discoverable from the results;
  - a batch of 10 must stay legible on mobile.
- **Pages:** the hero sits above the existing page sections (board grid, GRAIL detail, odds table, genesis). Those can be referenced
  but are out of scope.
- **Testnet:** on Base Sepolia, a testnet notice and faucet links must stay visible.
- **Accessibility:** readable contrast within this palette, and information that does not depend on colour alone.

## Out of scope

Branding changes, new colours or typefaces, the other pages, animation and motion, and implementation details.
