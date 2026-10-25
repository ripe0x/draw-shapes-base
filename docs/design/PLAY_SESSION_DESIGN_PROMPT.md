# Design brief: the play session, Draw Shapes on Base

## What we need from you

Three distinct design directions for the **play session**: the experience of someone who sits down and pulls repeatedly,
wins prizes, plays some of those winnings again, keeps some and eventually leaves. This is not a landing-page hero.
Design the place where the game is actually played. Each direction should be a different answer to layout, hierarchy and
flow, not a reskin of the others.

For each direction, deliver these static screens:

1. **Sitting down.** A returning or new player arrives, connects, and sees what they have to play with before their first pull.
2. **Mid-session.** Several pulls in. The player's stack, the prizes they have collected this session, and the next pull.
3. **Reveal.** The moment a pull resolves (a batch of 1 and a batch of 10), shown at rest.
4. **Big hit.** A pull that won a GRAIL or an unusually large prize.
5. **Leaving.** The end-of-session summary and what the player can do with what they hold.

Show each at desktop width (about 1440 px) and mobile width (about 390 px). These are static designs: no animation, motion
studies or clickable prototypes yet. Where a moment would be animated later, show its resting state.

Annotate each direction briefly. Say what it optimises for, what it gives up, and how it handles the states listed below.

## The product

Draw Shapes is an on-chain gacha game on Base. A player pays to "pull" and receives one random prize per pull, within a few
seconds. Every prize is either a **Shape** (a single generative artwork NFT) or a **Draw Pack** (a bundle of 2 or 3 Shapes).
Every prize holds real ETH inside it, between 0.01 and 0.1 ETH on the ordinary board, and can be redeemed at any time for
exactly that ETH.

Cheaper items are more likely: each item's chance is proportional to the inverse of its list price.

A **GRAIL** is a rare, high-value prize, 0.5 ETH, 1 ETH or 5 ETH at launch. It sits on the board when one is live, and its odds
rise with every pull. Sometimes none is live; then a fund is filling toward the next one. GRAILs are collectibles as well as
ETH.

On average a pull returns less ETH backing than it costs, about 85 %. That gap is part of the game and must never be
hidden or softened.

**ENGINE** is the game's coin.
- During the first 14 days (genesis), every settled pull earns a share of that day's ENGINE allocation, claimable after the
  day closes.
- ENGINE trades against ETH. Its trading fees help fund the GRAIL, and after genesis the game's surplus buys ENGINE back and
  burns it.

## How a session works

These are the mechanics the designs must support. How they are presented is up to you.

- **Stack.** A player's playable balance is wallet ETH + the ETH inside the prizes they hold + any refund credit. Prizes can
  be spent in a pull at their full face value, so playing winnings costs nothing extra.
- **Paying for a pull.**
  - A pull can be paid from wallet ETH, from prizes, or a mix, in a single wallet confirmation.
  - By default, the smallest prizes are spent first.
  - Prizes the player marks to keep, and GRAILs, are never spent unless the player chooses them.
- **Keeping.** Any prize can be marked to keep. Kept prizes leave the stack and stay in the player's collection as NFTs.
- **Cashing out.** Any set of prizes can be turned back into ETH in one confirmation. Nothing forces a player to cash out;
  prizes hold their ETH indefinitely.
- **First time only.** The player approves the game to use their prizes (two quick confirmations, once ever).
- **Session.** A session runs from sitting down to leaving. It can have an optional budget and time limit set by the player.
  The session ledger is: ETH put in, prizes held, ETH cashed out, net result, and ENGINE earned during genesis.
- **Batch size.** 1 to 10 pulls per transaction.
- **Timing.** A pull confirms, then reveals within about 3 seconds.
- **Settlement.** Occasionally a prize takes a little longer to arrive; anyone can finish it with one click.
- **Refunds.** Rarely, a pull is refunded instead of delivered: its price is credited back to the stack.

## Goals

- Make repeated play feel fast and fluid: pull, see the result, pull again, with as little friction as possible.
- Make the player's position obvious at every moment: what they have, what the next pull costs, and how the session is going.
- Make winnings feel like winnings, and make the choice to keep, play or cash out each prize clear and easy.
- Give the GRAIL its weight as the headline prize, and stay honest when none is live.
- Let the artwork lead. The Shapes are the product's identity.
- Make it easy to stop. The end of a session should feel like a natural, clear moment, not friction.

## Visual style (keep it)

Work within the current visual language. Do not introduce a new brand.

- **Palette:** warm off-white page (`#f7f7f3`), near-black ink (`#11110f`), and warm greys for body text, muted text, rules
  and borders (`#2f2f2b`, `#4f4f49`, `#686862`, `#aaa9a1`, `#d8d8d1`, `#e7e7e1`, `#b9b9b1`).
- **Status colours:** used sparingly: good `#2f6b3a`, warn `#9a6a1f`, bad `#a3352f`.
- **Accent:** the only strong colour is the electric blue of the Shape artwork itself.
- **Type:**
  - Archivo (heavy, tight) for headlines and big numbers;
  - IBM Plex Mono for body, labels, data and small caps-style section labels.
- **Surfaces:**
  - flat cards with thin rules;
  - pill-shaped buttons and toggles, with a black filled primary action;
  - playing-card-proportioned artwork (5:7) with a subtle drop shadow.
- **Tone:** quiet, precise, editorial. Exact numbers, plain sentences, no hype or casino styling.

Use the live site as reference for the current style: https://draw-shapes-base-sepolia.netlify.app

## Content and data available

Use real-looking values.

- **Board:** every listed item with its artwork, kind (Shape or Draw Pack of 2 or 3), ETH backing and list price. About 100
  items at launch.
- **Odds:** the chance per pull for each value tier and for each live GRAIL; the average redeemable value per pull; the chance
  a pull returns at least its ticket.
- **Price:**
  - ticket per pull (about 0.0158 ETH);
  - a 1 % settlement fee per pull;
  - a small VRF fee (about 0.000013 ETH per pull);
  - the total for the chosen batch size.
- **GRAIL:**
  - whether one is live, with its artwork, backing, current price and odds per pull;
  - otherwise, how close the fund is to the next one and its size;
  - how much of the fund came from pulls and how much from ENGINE trading.
- **The player:**
  - wallet ETH;
  - every prize held, with artwork and ETH value;
  - kept prizes;
  - refund credit;
  - ENGINE balance and claimable ENGINE;
  - genesis day and estimated ENGINE earned this session.
- **Each pull's result:**
  - prize artwork, kind and ETH value;
  - whether it was a GRAIL;
  - whether it was refunded instead;
  - whether it is still arriving.
- **Session ledger:** pulls made, ETH put in, prizes held, ETH cashed out, net result, best hit.
- **Referrals:** a pull can carry a referrer; players have a referral link.

## States to account for

You don't need a screen for each, but every direction should show where these live and how they read.

- **Before playing:**
  - not connected;
  - wrong network;
  - first-time approval needed;
  - stack too small for the chosen batch;
  - pulls temporarily unavailable (paused or restocking).
- **Paying:** paying only with ETH, only with prizes, or with a mix.
- **During a pull:**
  - waiting for the wallet;
  - confirming;
  - waiting for randomness (seconds);
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

## Constraints

- **Honesty:**
  - every number shown must be real and current;
  - the net result is shown plainly, including when negative;
  - no implied guarantees;
  - never show a GRAIL as winnable when none is live;
  - ENGINE estimates are labelled as estimates;
  - no price or yield language about ENGINE.
- **Responsible play:** no autoplay or automatic repeat pulls, and no misleading near-miss presentation. Odds stay one tap away.
- **Costs:** the full cost of a pull, including fees, must be visible before the player commits.
- **Kept prizes:** a kept prize must never be spent by accident.
- **Mobile:** a batch of 10 and a session tray of many prizes must stay legible on mobile.
- **Testnet:** on Base Sepolia, a testnet notice and faucet links stay visible.
- **Accessibility:** readable contrast within this palette, and information that does not depend on colour alone.

## Out of scope

Branding changes, new colours or typefaces, the protocol and ENGINE pages, animation and motion, and implementation details.
