# Draw Shapes — landing page copy

*Draft for review. [Bracketed] items are filled in at launch. No numbers here are promises; prices and odds
are read live from the contracts by the app.*

## Pull for ETH-backed prizes on Base

Draw Shapes is a prize draw where every prize holds real ETH. Each pull picks one prize from a public board of
Shapes and Draw Packs on Base. Every prize can be redeemed at any time for exactly the ETH inside it.

## How a pull works

1. **You pay the board price.** The price of a pull is the harmonic mean of everything on the board; a
   reference board costs about 0.0151 ETH. On top come a 1 % settlement fee and one Chainlink VRF fee per
   batch, about 0.000056 ETH for 4–20 pulls. You can pull 1 to 20 at a time.
2. **Chainlink VRF picks your prize.** Cheaper prizes are more likely: odds are proportional to
   1 / notional, where notional is a prize's listing value. The app shows every row's odds before you pull.
3. **The prize arrives in your wallet**, usually within seconds. If the price moves past your limit before your
   pull settles, or randomness never arrives, you are refunded the price and settlement fee. The VRF fee
   paid for the randomness and is not refunded.
4. **Keep it, trade it or redeem it.** Redeeming a Shape or Draw Pack returns exactly its ETH.

On average a pull returns less ETH than it costs: about 85 % on the reference board. The difference pays:
- the Shapes creator's 0.001 ETH mint fee for each replacement prize;
- the game premium (3.5 %);
- keepers (0.5 %);
- the GRAIL fund (3 %).

## ETH-backed Shapes on Base

A Shape is an onchain object that wraps an exact amount of ETH. Its artwork and metadata are generated
onchain. Draw Packs bundle several Shapes.

**Shapes on Base are a separate collection from Shapes on Ethereum:** the same contract and rules, with
independent tokens and independent ETH. A Base Shape cannot be redeemed on Ethereum.

## GRAILs

A GRAIL is a large Shape (0.5, 1 or 5 ETH) listed below its backing, at 80 %:

- **Funding.** A GRAIL exists only once its whole backing and mint fee are funded. The fund is filled by
  3 % of every pull's notional and by ENGINE trading fees. While no GRAIL is on the board, all of the
  treasury's trading share goes to the next one.
- **Repricing.** Once listed, a GRAIL's notional falls slightly with every pull, so its odds rise. This
  continues until its odds reach 5 % or its notional reaches half its backing.
- **After a win.** The fund rebuilds the smallest GRAIL first.

GRAIL availability depends on play and trading. **There may be periods with no GRAIL to win.** The app
shows, separately, what can be won now, what is funded but not yet drawable, and what is still being funded.

## ENGINE

- **Supply.** ENGINE has a fixed supply of 35,000,000: 10,000,000 in permanently locked protocol
  liquidity, and 25,000,000 for the 14-day genesis. Nobody can mint more.
- **Genesis.** Each daily epoch gives 1,785,714 ENGINE to that day's delivered pulls: 85 % by pull count,
  15 % by a random bonus weight. Allocations of days with no pulls are burned.
- **Trading fees.** The ETH/ENGINE pool on Uniswap v4 charges 2 % of the ETH side: 0.25 % to the operator,
  1.75 % to the treasury. The treasury funds GRAILs and adds protocol-owned liquidity.
- **Buybacks.** After genesis, realised game surplus buys ENGINE in small, rate-limited slices and burns it.

**ENGINE is a speculative token.** It has no claim on any ETH in prizes, the game, the GRAIL fund or the
treasury. Buybacks depend on play and support no price. ENGINE can trade elsewhere without fees to the
project.

## Built with

- **Pull engine.** Selection, pricing and settlement are adapted from FWA by Token Works (MIT). Token Works
  receives a quarter of the settlement fee.
- **Prizes.** Shapes and Draw Packs by ripe0x.
- **Randomness.** Chainlink VRF v2.5.
- **Market.** Uniswap v4.

## Contracts

[Addresses from `deployments/8453.json`, each linked to its verified source on Basescan.]

## Risks and permissions (read before playing)

- **Not audited:** [audit status and report link at launch].
- **Admin powers.** A 48-hour timelock controlled by a multisig can change bounded parameters: fee split
  (≤ 15 % total), board mix, keeper tip, GRAIL settings and the VRF configuration.
- **Guardian.** A guardian can pause new pulls, listing, GRAIL steps and buybacks.
- **What cannot be taken.** No role can take escrowed payments, refunds, prizes, the GRAIL fund or locked
  liquidity.
- **Dependencies.** The game depends on Chainlink VRF, on Base, and on keepers (anyone can run one).
  Outages delay settlement or restocking; a pull either delivers a prize or is refunded, minus the VRF fee.
- **Expected loss.** Pulls have a negative expected ETH return. Play only with money you can afford to lose.
