# Draw Shapes — player FAQ

**What do I get for a pull?**
One Shape or Draw Pack from the board, chosen by Chainlink VRF. It holds a fixed amount of ETH that you can
redeem at any time.

**What does a pull cost?**
- The board price: the harmonic mean of all selectable prizes, about 0.0151 ETH on the reference board.
- A 1 % settlement fee.
- One Chainlink VRF fee per batch: about 0.000014–0.000025 ETH for a single pull and about
  0.00003–0.000056 ETH for a batch of 4–20, at 0.005–0.01 gwei Base gas. It rises with gas prices.
- Wallet gas.

The app shows the full amount before you confirm.

**What are my odds?**
Each prize's chance is proportional to 1 / its notional, so cheaper prizes are more likely. The app shows each
row's odds per pull, live.

**Do I make money on average?**
No. On average a pull returns about 85 % of what it costs, in ETH backing.

**Where is my prize?**
In your wallet once the pull settles, usually within seconds. Under "My pulls" the app shows a status for
each pull:
- waiting for randomness;
- settling;
- delivered;
- refunded;
- delivery failed (you can retry).

**When do I get refunded?**
In three cases:
- the price moved more than your tolerance (10 % in the app) between your pull and its settlement;
- the board had nothing selectable;
- randomness did not arrive within about an hour.

You get back the price and settlement fee; the VRF fee paid for the randomness. Withdraw refunds from "My pulls".

**How do I redeem a Shape for ETH?**
Call `redeem(tokenId)` on the Shapes contract (or `redeem(packId)` on Base Draw Packs) from the owning wallet.
You receive exactly the backing.

**Are these the same Shapes as on Ethereum?**
No. Shapes on Base are a separate collection with independent tokens and ETH.

**What is a GRAIL and when can I win one?**
A GRAIL is a large Shape listed below its backing. It is drawable only once fully funded and listed; the app
labels whether one can be won now. Funding comes from pulls and ENGINE trading, so there may be periods
without one.

**What is genesis?**
The first 14 days after launch. Each day's 1,785,714 ENGINE is shared among that day's delivered pulls:
85 % by count, 15 % by a random bonus. Claim in the app once the day has ended and its pulls have settled.
Rewards never expire.

**Why is my claim not available yet?**
An epoch becomes claimable when it has ended and every pull accepted during it has settled (delivered or refunded).

**What is ENGINE worth?**
Whatever the market pays. It has no claim on prize or treasury ETH. After genesis, game surplus buys and burns
some ENGINE; that is not a price floor.

**Who can change the game?**
- A multisig, through a public 48-hour timelock, within hard limits.
- A guardian, which can only pause.
- Nobody can take escrowed payments, refunds or prizes.

**Is it audited?**
[Audit status at launch.] Read the risks section before playing.
