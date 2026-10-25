# Launch configuration: decision and exact arithmetic

Status: adopted in code (`script/config/LaunchParams.sol`). Evidence:
- `docs/GRAIL_AVAILABILITY.md`;
- `sim/results/grail-*.md`, `bankroll*.md`, `farming.md`.

Every number in this document is a contract value or a model output under the stated assumptions. None
of them is a demand forecast.

## 1. Settings

| Setting | Launch value | Changed? |
| --- | --- | --- |
| Ordinary premium / maintenance / GRAIL feed | **3.5 % / 0.5 % / 3 %** of backing | yes (was 4 / 0.5 / 2) |
| Shape mint fee | 0.001 ETH per Shape (Shapes v1, to the creator) | no |
| Settlement fee | 1 % of the acquisition fee: 50 % referrer, 25 % Token Works, 25 % development | no |
| VRF | Purchaser-paid, once per Chainlink request (one request per 5 pulls, so every callback can deliver all of its pulls): `gas = (400k + callback limit) × max(basefee, 0.005 gwei)`; `gas × 1.85 + 0.000002 ETH` to the subscription, plus a 30 % service margin `gas × 0.3` credited to development (as FWA V2); ≤ 0.002 ETH in total | callback gas per acquisition 650k → 750k (cold-state fix); service margin added |
| ENGINE | 35,000,000 fixed supply: 10M liquidity, 25M genesis farm (14 × 24 h) | no (immutable) |
| ENGINE trading fee | 2 % of the ETH side; 0.25 % operator, 1.75 % treasury | no |
| Treasury routing | Reserve to 0.5 ETH; then 100 % to the GRAIL fund while none is held, else 90 % GRAIL / 10 % POL | no |
| Opening capital | 5 ETH: 2.2 ordinary pool, 2.0 market liquidity, 0.5 treasury reserve, 0.3 operations | no (not changed without approval) |
| Opening GRAIL | **recommended: +0.501 ETH new capital** (section 4) | decision for the owner |

## 2. Exact reference-board arithmetic (asserted to the wei in `ReferenceBoard.t.sol`)

The board has 100 items:
- 62 × 0.01 ETH Shapes;
- 26 × Draw Packs of two 0.01 ETH Shapes;
- 7 × Draw Packs of three;
- 4 × 0.05 ETH Shapes;
- 1 × 0.1 ETH Shape.

The notional of an item with backing `b` and `k` Shapes is `b × (10,000 + 350 + 50 + 300) / 10,000 + k × 0.001 ETH`:

| Row | b | k | Notional |
| --- | --- | --- | --- |
| Shape | 0.01 | 1 | 0.0107 + 0.001 = **0.0117** |
| Pack of 2 | 0.02 | 2 | 0.0214 + 0.002 = **0.0234** |
| Pack of 3 | 0.03 | 3 | 0.0321 + 0.003 = **0.0351** |
| Shape | 0.05 | 1 | 0.0535 + 0.001 = **0.0545** |
| Shape | 0.10 | 1 | 0.107 + 0.001 = **0.108** |

Weights and price:
- Weight is `w = ⌊1e36 / notional⌋`.
- The acquisition fee is `⌊Σ w·p / Σ w⌋` (FWA's harmonic mean, no edge).

| Quantity | Wei | ETH |
| --- | --- | --- |
| Σ w | 6,692,340,364,358,712,982,513 | |
| Acquisition fee | 14,942,455,786,105,613 | 0.014942456 |
| Settlement fee (fee × 1 %) | 149,424,557,861,056 | 0.000149425 |
| Fee + settlement (price before VRF) | 15,091,880,343,966,669 | **0.015091880** |
| VRF fee, 10-pull batch at 0.01 gwei | 128,700,000,000,000: two requests of 5, each 64,350,000,000,000 (55,650,000,000,000 to the subscription + 8,700,000,000,000 margin) | 0.0000129 per pull |
| Player payment per pull in a 10-pull batch | | **0.0151048** |
| Expected backing `Σ w·b / Σ w` | 12,819,466,318,547,036 | 0.012819466 |
| Ordinary RTP (backing / fee + settlement) | | **84.94 %** (84.87 % including VRF) |

Expected margin waterfall per pull:
- **Mint line:** 1.2256 Shapes × 0.001 = 0.0012256 ETH to the creator through replacement mints.
- **Margin after the mint line:** about 0.000897 ETH. It splits 350 : 50 : 300:
  - premium **0.000449** stays in the ordinary pool and is the only source of surplus for buybacks;
  - maintenance **0.000064** refunds keepers;
  - GRAIL feed **0.000385**.

The settlement fee per pull (0.000149425) splits:
- referrer 0.0000747 (to development when there is no referrer);
- Token Works 0.0000374;
- development 0.0000374.

A listed 0.5 ETH GRAIL at its 0.4 ETH list notional raises the fee by 0.96 % (15,086,244,705,354,466 wei with
the GRAIL listed). That uplift is paid by every pull while the GRAIL is live. On ordinary captures it
returns to the ordinary pool as margin.

## 3. Why 3.5 / 0.5 / 3 over 4 / 0.5 / 2

Monte Carlo, 14 days, 200 seeds:

| | 4 / 0.5 / 2 | 3.5 / 0.5 / 3 |
| --- | --- | --- |
| Price before VRF | 0.015027 | 0.015092 (+0.43 %) |
| Ordinary RTP | 85.31 % | 84.94 % |
| Hours without a GRAIL, 300/day, no trading (p50 / p90) | 218 / 307 | **138 / 230** |
| Same at 750/day | 129 / 210 | **64 / 129** |
| First GRAIL, 300/day, no trading (p50) | 173 h | **113 h** |
| Genesis buyback budget, 300/day (p50 / p10) | 1.94 / 1.43 | 1.81 / 1.38 |
| Buyback over 42 days, 50/day after genesis (p50 / p10) | 2.83 / 2.06 | 2.54 / 2.11 |
| Hours without a GRAIL after genesis (p90) | 243–272 | 113–124 |
| Pool-alone shortfall, 300/day (2,000 seeds) | 0.20 % | **0.05 %** |
| With the reserve, 1,500/day, hourly keeper | 0.45 % | **0.15 %** |
| Farming pulls/day at 0.7 ETH/day outside buying | 299 | 290 (−3 %) |
| Creator mint fees, same scenario, 14 days | 5.13 | 4.98 (−3 %) |

The product needs headline prizes to sustain paid demand. The current split leaves the board without a
GRAIL for about 65 % of genesis at modest volume, and for more than 10 days in the worst post-genesis
cases.

The alternative's cost:
- about 7 % of median genesis buyback;
- almost none of the p10 buyback;
- 0.43 % on the price.

It is also *safer* for the ordinary pool, because its total markup is higher.

**Downsides of 3.5 / 0.5 / 3:**
- slightly worse pull economics;
- about 3 % fewer farming pulls and less creator revenue;
- a smaller median buyback;
- still no GRAIL for most of genesis at 100 pulls/day without trading, unless the opening GRAIL is funded.

**Downsides of 4 / 0.5 / 2:**
- the headline prize is missing most of the time;
- higher pool-alone shortfall risk.

The split is governance-tunable (`DrawController.setFeeSplit`, 48 h timelock, total markup ≤ 15 %).

## 4. Opening GRAIL

| 300 pulls/day, no trading | No seed | 0.501 ETH opening GRAIL |
| --- | --- | --- |
| 3.5 / 0.5 / 3: hours without a GRAIL (p50 / p90) | 138 / 244 | **12 / 138** |
| 3.5 / 0.5 / 3: genesis buyback p50 | 1.79 | 1.98 |
| 4 / 0.5 / 2: hours without a GRAIL (p50 / p90) | 209 / 294 | 79 / 214 |

### Funding source

Reallocating inside the 5 ETH is not recommended:

| Source | Effect | Verdict |
| --- | --- | --- |
| Ordinary pool (2.2) | The board needs 1.79 ETH and 2.0 ETH fails the shortfall threshold at 1,500/day (30 %) | no |
| Treasury reserve (0.5) | The reserve is what covers keeper-outage tails: pool-alone shortfall at 1,500/day with hourly keepers is 8.8 % without it vs 0.15 % with it | no |
| Market liquidity (2.0 → 1.5) | Farming pulls −25 % with no outside buying (44 → 33/day); the end-of-genesis pool ETH falls to 0.43, close to where the 0.005 ETH buyback minimum stops buybacks under the 3 % impact cap | no |
| Operations (0.3) | Too small | no |

**Recommendation:** add **0.501 ETH of new capital** (total 5.501 ETH) and call `GrailVault.fundGrail` before
activation. The vault mints and lists a 0.5 ETH GRAIL so it is selectable from the first pull.

Most of that 0.501 ETH ends up with whoever wins the GRAIL. The rest of its effect comes back through the
fee uplift and the GRAIL fund.

If no new capital is available, launch unfunded. The treasury then routes all trading receipts to the GRAIL
fund until the first GRAIL is minted.

**This needs the owner's approval.**

## 5. Other settings reviewed and kept

| Setting | Value | Reason |
| --- | --- | --- |
| Maintenance | 0.5 % | 0.25 % fails at 0.05 gwei basefee (`docs/FOLLOWUP.md`). |
| Callback gas per acquisition | 750k, raised from 650k | A cold first acquisition needs ~620k inside the callback. Each callback attempt now receives all gas above a 60k return reserve. The single-pull VRF fee rises ~9 %; batches of 3+ are already at the 2.5M cap. |
| Buyback | 0.05 ETH slices, 1 h spacing, 3 % impact cap, 0.5 % bounty capped at 0.00005 ETH, 0.005 ETH minimum, start at genesis end | Unchanged. |

Operational note on the buyback: if the pool's ETH side falls below about 0.34 ETH, the 3 % cap allows less
than the 0.005 ETH minimum, so buybacks pause. Governance can lower `minSpend` (`Buyback.setLimits`).
