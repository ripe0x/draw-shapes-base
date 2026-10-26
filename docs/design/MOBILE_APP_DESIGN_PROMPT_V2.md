# Design brief v2: Draw Shapes mobile app, one home screen per direction

## What we need from you

Three **radically different** concepts for the home screen of a mobile app for Draw Shapes. **One screen per direction**, at
phone size (about 390 × 844). This is the screen a player sees when they open the app and where they pull. No other screens
and no state variations yet; we pick a direction first, then go deeper.

For each direction, include:
- the screen itself;
- a one-paragraph concept;
- a small style sheet (type, colour, key components);
- one line on what it gets right and one on what it gives up.

## The single most important requirement: the three-second read

Someone who has never heard of the game looks at the home screen for **three seconds**. They must be able to say:

1. **What's in the machine:** a board of prizes, each one an artwork holding real ETH.
2. **What's rare:** most prizes are small; a few are big.
3. **The headline prize:** the GRAIL, worth far more than anything else, and winnable right now.
4. **What a pull costs, and how to pull.**

If a direction doesn't pass this test, it doesn't work, however good it looks. Prizes and the GRAIL are the interface. Money
mechanics are not.

## The game in one paragraph

Draw Shapes is a gacha on Base. You pay about **0.016 ETH** to pull and get one random prize a few seconds later. Every
prize is a **Shape** (a single artwork) or a **Draw Pack** (2 or 3 Shapes fanned together), and every prize holds real ETH
inside it that you can take out at any time. Cheaper prizes are more likely. Above everything sits the **GRAIL**: a single
prize holding **0.5 ETH**, then 1 ETH, then 5 ETH as the game grows. Its odds improve a little with every pull until someone
wins it.

## Rarity: use it

The board's value tiers are its rarity system. Make them legible and make them feel different. These are the real
launch numbers, 100 prizes on the board:

| Tier | Prize | ETH inside | On the board | Chance per pull |
| --- | --- | --- | --- | --- |
| Common | Shape | 0.01 | 62 | 79 % |
| Uncommon | Draw Pack of 2 | 0.02 | 26 | 17 % |
| Rare | Draw Pack of 3 | 0.03 | 7 | 3 % (1 in 34) |
| Epic | Shape | 0.05 | 4 | 1 % (1 in 91) |
| Legendary | Shape | 0.1 | 1 | 1 in 723 |
| **GRAIL** | Shape | **0.5** | 1 | 1 in 2,678, improving with every pull toward 1 in 1,674 |

The tier names here are illustrative; you may name them, or not, as fits your concept. On average a pull returns about 85 %
of its cost in ETH. That must be findable from the home screen (one tap is fine), never hidden.

## Artwork: use the attached art pack, don't invent art

The prizes are real, on-chain generative artworks. Attached is an art pack of 24 real Shapes and 8 real Draw Packs
(`docs/design/art-pack/`). The art is printed in a **textured monochrome blue**: a riso or screenprint feel, with grain,
uneven ink and paper. Use these images as they are. Design the frame, the board and everything around them, but do not
redraw, recolour or replace the art. The GRAIL is a Shape too; use any of the Shapes as its artwork, and make it special through how you frame and present it.

## Make the three directions genuinely different

Each direction must differ in **core concept, what the home screen is, how you navigate, and its visual world**: colour, type,
material and mood. Not just accents or layout tweaks. Below are three concepts to start from. You may replace any of them
with a better idea, but keep them this far apart.

- **A, "The Machine."** The home screen *is* the board: you are looking into the machine and can see what's inside, with
  every prize and the GRAIL among them, and the pull sits at the bottom like a slot or lever. Think of a capsule-toy machine
  where you can see the capsules.
- **B, "The Banner."** The home screen is the featured prize. The GRAIL dominates, with its value, its odds right now and
  the art, and the rates and the rest of the board come second. Pulling feels like opening a pack. Think of a gacha banner
  page crossed with a TCG pack opening.
- **C, "The Collection."** The home screen is *your* stuff: your growing collection of prizes and what it's worth. Pulling
  adds to it, and the board and the GRAIL are one tap away and always visible as a teaser. Think of a binder or a wallet of
  cards.

These are about patterns, not looks. Do not copy the styling of any existing product.

## Design principles

- **The three-second read wins.**
- **Open, clean, uncluttered**, with one clear focus per screen.
- **Crypto-native, not DeFi.** Onchain ownership feels natural, but nothing should look like a trading terminal. No dense
  tables, charts, long decimals or jargon on the home screen. Show ETH values to at most 3 decimals.
- **Not a slot machine.** No casino styling, flashing lights, coin showers, near-miss teasing or pressure to keep pulling. The
  excitement comes from the art, the rarity and the GRAIL.

## What the home screen should contain

The hierarchy is up to you, but these should be present or one tap away:
- the prizes, the GRAIL and the rarity;
- the pull, with batch size 1 to 10, the price, and one confirmation;
- the player's balance as **one number** (their ETH plus the value of prizes they can play);
- the prizes they've won (their winnings can pay for the next pull at full value, so pulling again with winnings costs nothing
  extra; don't explain this mechanic on the home screen, just make "your prizes" feel like spendable value);
- **ENGINE**, the game's coin: during the first 14 days every pull earns some. A small presence only; it is not the focus.

Not on the home screen: payment breakdowns, refund credits, fee itemisation, session ledgers, settings.

## Constraints

- **Real numbers:** use the values in this brief.
- **The GRAIL:** show it live and winnable. That is its normal state.
- **ENGINE:** no price or yield language.
- **Pulling:** no autoplay or automatic repeat pulls.
- **Test network:** a test-network notice will be added later. Leave room, but don't design it now.
- **Accessibility:** readable contrast, touch targets of at least 44 px, and no information that depends on colour alone.

## Out of scope

All other screens and states, animation, desktop and implementation details.
