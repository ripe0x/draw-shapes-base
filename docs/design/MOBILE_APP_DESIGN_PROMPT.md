# Design brief: Draw Shapes mobile app

## What we need from you

Three distinct directions for a **mobile app** for Draw Shapes, designed around the play session: someone opens the app, pulls,
wins prizes, plays some winnings again, keeps some, cashes out, and leaves.

Each direction should have **its own visual style**, which you develop yourself: typography, colour, layout, iconography,
surfaces and tone of voice. They should also differ in structure and flow, not just appearance. Do not reference or imitate
any existing Draw Shapes website.

For each direction, deliver these static screens at phone size (about 390 × 844):

1. **Opening the app.** First launch and returning player: what they have to play with, and the way into a pull.
2. **Mid-session.** Several pulls in: the player's balance, the prizes collected this session, and the next pull.
3. **Reveal.** A pull resolving, for a single pull and for a batch of 10, shown at rest.
4. **Big hit.** Winning the GRAIL or an unusually large prize.
5. **Prizes.** What the player holds: playing them, keeping them, cashing them out.
6. **Leaving.** The end-of-session summary.

Include a short style sheet for each direction (type, colour, components), and a few lines on what it optimises for and what it
gives up. These are static designs: no animation, motion studies or clickable prototypes yet. Where a moment would be
animated later, show its resting state.

## Design principles

- **Good UX first.** Every screen should make the next action obvious.
- **Open, clean, uncluttered.** Generous space, few elements, one clear focus per screen.
- **Crypto-native, not DeFi.** It should feel at home onchain: wallets, tokens and ownership are natural. But it must not look
  like a trading terminal or dashboard. No dense tables, charts or jargon on the main path.
- **Not a slot machine.** No casino styling, flashing lights, coin showers, near-miss teasing or pressure to keep playing. The
  excitement comes from the prizes themselves, the artwork and the reveal.

## The product

Draw Shapes is an onchain gacha game on Base. A player pays to **pull** and receives one random prize per pull, a few seconds
later.

**Prizes.**
- Every prize is either a **Shape**, a single generative artwork NFT, or a **Draw Pack**, a bundle of 2 or 3 Shapes.
- The artwork is rendered onchain and is fixed: show it as it is, and design the frame around it. You can see examples at
  https://draw-shapes-base-sepolia.netlify.app.
- Every prize holds real ETH inside it, from 0.01 to 0.1 ETH on the ordinary board, and can be turned back into exactly that
  ETH at any time.

**Odds.** Cheaper items are more likely: each item's chance is proportional to the inverse of its price.

**GRAIL.** A rare, high-value prize, 0.5 ETH, 1 ETH or 5 ETH at launch. It sits among the prizes when one is live, and its odds
rise with every pull. Sometimes none is live; then a fund is filling toward the next one.

**Return.** On average a pull returns less ETH than it costs, about 85 %. That gap is part of the game and must be visible,
never hidden.

**ENGINE, the game's coin.**
- During the first 14 days (genesis), every pull earns a share of that day's ENGINE, claimable after the day closes.
- ENGINE trades against ETH. Its trading fees help fund the GRAIL, and later the game's surplus buys ENGINE back and burns it.

## How a session works

These are the mechanics to support. How they are presented is entirely up to you.

- **Balance.** What a player can play with is their ETH + the ETH inside the prizes they hold + any refund credit.
- **Playing prizes.** Prizes can pay for a pull at their full value, so playing winnings costs nothing extra.
- **Paying for a pull.**
  - A pull can be paid with ETH, prizes, or both, in one confirmation.
  - By default the smallest prizes are used first.
  - Kept prizes and GRAILs are never used unless the player chooses them.
- **Keeping.** Any prize can be kept. Kept prizes stay in the player's collection and are never spent.
- **Cashing out.** Any set of prizes turns back into ETH in one confirmation. Nobody has to cash out; prizes hold their ETH
  indefinitely, and players can also hold or trade them like any NFT.
- **First time only.** The player gives the app permission to use their prizes. On a smart wallet this can be part of
  onboarding.
- **Batch size.** 1 to 10 pulls at a time.
- **Timing.** A pull confirms, then reveals within about 3 seconds.
- **Session.** It runs from opening the app to leaving, with an optional budget or time limit set by the player. The ledger
  shows pulls made, ETH put in, value held, ETH cashed out, the net result (shown plainly, including when negative), best hit,
  and ENGINE earned during genesis.
- **Exceptions.** Occasionally a prize takes a little longer to arrive, and anyone can finish it with one tap. Rarely, a pull is
  refunded instead of delivered; its price goes back to the player's balance.

## Content and data available

Use real-looking values.

- **Prizes on offer:** every available prize with its artwork, kind and ETH value (about 100 at launch); the chance per pull for
  each value and for a live GRAIL; the average value per pull.
- **Price:**
  - about 0.0158 ETH per pull, including a 1 % fee;
  - a tiny randomness fee, about 0.000013 ETH per pull;
  - the total for the chosen batch.
- **GRAIL:** whether one is live, with its artwork, value, price and odds; otherwise, how close the fund is to the next one.
- **The player:**
  - wallet ETH;
  - prizes held, with artwork and value;
  - kept prizes;
  - refund credit;
  - ENGINE balance and claimable ENGINE;
  - genesis day and estimated ENGINE earned this session.
- **Each pull's result:**
  - prize artwork, kind and value;
  - whether it was a GRAIL;
  - whether it was refunded;
  - whether it is still arriving.
- **Referrals:** a pull can carry a referrer, and players have a referral link.

## States to account for

You don't need a screen for each, but every direction should show where these live and how they read.

- **Getting started:**
  - no wallet;
  - wallet on the wrong network;
  - first-time permission;
  - not enough to pull;
  - pulls temporarily unavailable.
- **Paying:** with ETH, with prizes, or with both.
- **During a pull:**
  - waiting for the wallet;
  - confirming;
  - waiting for randomness;
  - a prize still arriving.
- **After a pull:**
  - all delivered;
  - some refunded;
  - a GRAIL won;
  - a batch of 1;
  - a batch of 10.
- **Session limits:**
  - budget or time limit reached;
  - the player choosing to stop.
- **Test network:** while on the test network, a clear notice that nothing has real value, and where to get test ETH.

## Constraints

- **Honesty:**
  - every number shown must be real and current;
  - the full cost is visible before the player commits;
  - no implied guarantees;
  - never show a GRAIL as winnable when none is live;
  - ENGINE estimates are labelled as estimates;
  - no price or yield language about ENGINE.
- **Responsible play:** no autoplay or automatic repeat pulls; odds always one tap away; stopping is easy and feels natural.
- **Kept prizes:** a kept prize must never be spent by accident.
- **Batch of 10:** a batch of 10 and a long list of prizes must stay legible on a phone.
- **Accessibility:** readable contrast, comfortable touch targets, and no information that depends on colour alone.

## Out of scope

Desktop and web layouts, the protocol and coin detail pages, animation and motion, and implementation details.
