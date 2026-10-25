# Economics: configuration, money flows and capital

All numbers are contract values from `script/config/LaunchParams.sol` unless marked as a model
output. Model outputs are scenario results under stated assumptions; they are not forecasts.

## 1. Complete launch configuration

| Area | Parameter | Value |
| --- | --- | --- |
| Board | items / mix | 100: 62 × 0.01 Shape, 26 × 0.02 Draw Pack (2 × 0.01), 7 × 0.03 Draw Pack (3 × 0.01), 4 × 0.05 Shape, 1 × 0.1 Shape |
| Notional | markups on backing | premium 300, maintenance 100, GRAIL feed 400 bps; plus 0.001 ETH per Shape (replacement mint fee) |
| Replacement | deficit draw / surprise / band | `restoreK` 8, `surpriseBps` 200, `bandBps` 3,000 (Draw Shapes values) |
| Controller | cash floor / tip / capital target / VRF target | 0 / 0.00001 ETH / 2.2 ETH / 0.02 ETH |
| Engine | per tx / unsettled / activations per request | 20 / 250 / 6 |
| Engine | positive slippage / cooldown / word deadline | 10 % / 0 / 1,800 blocks (1 h on Base) |
| Engine | settlement fee / split | 1 % of the acquisition fee; 50 % referrer, 10 % Token Works, 40 % development (referrer share to development when there is none) |
| VRF | confirmations / callback gas / player VRF fee | 3 / 100,000 + 650,000 per acquisition (cap 2.5M) / 0 |
| GRAIL | ladder / list / floor / decay / cap / steps | 0.5 → 1 → 5 ETH; 80 % of backing; 50 %; 0.00002 ETH per pull; 5 % of weight; up < 3 days, down > 14 days |
| ENGINE | supply | 35,000,000: 10M liquidity, 25M farm |
| Market | pool / fee | ETH/ENGINE v4, LP fee 0, tick spacing 200, full range; hook 200 bps (25 operator, 175 treasury) |
| Farm | epochs / split / bonus weights | 14 × 24 h; 85 % units, 15 % bonus; 25 (1 %), 5 (9 %), 1 (90 %) |
| Treasury | reserve target / backstop floor / GRAIL share | 0.5 ETH / 0.3 ETH / 90 % (10 % POL) |
| Buyback | slice / spacing / impact cap / bounty / start | 0.05 ETH / 1 h / 3 % / 0.5 % / genesis end |
| Timelock | delay | 48 h |

## 2. One pull on the reference board (to the wei)

| Flow | wei | Goes to |
| --- | --- | --- |
| Acquisition fee | 15,070,286,533,069,302 | engine escrow → depositor of the captured listing (the controller, or the GRAIL vault for a GRAIL) |
| Settlement fee | 150,702,865,330,693 | engine escrow → referrer 75,351,432,665,346 / Token Works 15,070,286,533,069 / development 60,281,146,132,278 |
| **Player payment** | **15,220,989,398,399,995** | |
| Expected ETH backing received | 12,819,127,730,909,358 (84.22 %) | the player, inside the prize |

The controller books `proceeds − captured backing` as margin: first it repays the replacement mint
line (≈ 0.001226 ETH per pull = 1.226 Shapes × 0.001, paid to the creator through Shapes), then the
rest divides 3 : 1 : 4 — premium ≈ 0.000385 stays in the ordinary pool, maintenance ≈ 0.000128 funds
keepers and VRF, feed ≈ 0.000513 goes to the GRAIL vault. These are expectations; any single pull
can be a large gain or loss for the pool.

## 3. All money flows

```
player ──payment──► DrawEngine ──fee──► DrawController ──► backing of replacement (Shapes) ─► prize
   │                    │                    │──► 0.001 ETH / Shape mint fee ─► creator (Shapes fee recipient)
   │                    │                    │──► premium (ordinary pool cash) ── after genesis, above 2.2 ETH ─► Buyback ─► burn ENGINE
   │                    │                    │──► maintenance ─► keeper gas refunds, VRF subscription
   │                    │                    └──► GRAIL feed ─► GrailVault
   │                    └─settlement fee─► referrer / Token Works / development (pull credits)
   └──refunds (expiry, slippage, failed delivery): fee + settlement fee back to the player

ENGINE trader ──2 % ETH fee──► EngineHook ──0.25 %──► operator (creator)
                                        └──1.75 %──► Treasury ─► reserve to 0.5 ETH ─► 90 % GrailVault / 10 % locked POL
GrailVault ──when funded──► mint GRAIL Shape ─► engine listing ─► winner; capture proceeds ─► GrailVault
```

### Rehearsal reconciliation (test/rehearsal/GenesisRehearsal.t.sol)

14 simulated days, 200 pulls a day in batches of 10 (half referred), 0.7 ETH/day of outside buying,
farmers claiming and selling every epoch, keepers settling hourly. Every identity below is an
assertion in the test.

| Measure | Value (ETH) |
| --- | --- |
| Pulls accepted / fulfilled | 2,800 / 2,800 |
| Player ETH in | 44.6657 |
| = controller proceeds booked + GRAIL capture proceeds (0.0156) + settlement fees (0.4422) + refunds (0) | ✔ |
| Creator mint fees accrued (opening board 0.14 + replacements + GRAIL mints) | 3.697 |
| Premium kept by the ordinary pool | 1.166 |
| GRAIL funding: feed 1.5550 + trading 0.2987 | = vault funded ✔ |
| GRAILs minted (backing) | 1.5 (0.5 + 1.0) |
| Hook fees = operator 0.0474 + treasury 0.3319 + accrued | ✔ |
| Treasury receipts = 90 % GRAIL + 10 % POL (reserve was full) | ✔ |
| Farm: claimed + dust = 25,000,000 ENGINE | ✔ |
| Ordinary NAV after genesis / releasable surplus | 3.1401 / 0.9401 |
| First buyback slice burned | 150,878.5 ENGINE |

## 4. Opening capital: the creator's 5 ETH

| Use | ETH | Held by | At risk to |
| --- | --- | --- | --- |
| Ordinary pool | 2.20 | controller (1.65 backing + 0.14 mint fees spent, 0.41 liquid) | player wins |
| ENGINE market liquidity | 2.00 | locked v4 position | traders (it is not NAV and not a safety reserve) |
| Treasury reserve | 0.50 | treasury, backstops restocking only | player wins |
| Operations | 0.30 | ops Safe (VRF subscription seed, maintenance float, gas) | — |
| **Total** | **5.00** | | |

Bankroll stress results and the acceptance threshold are in section 5. No change to the proposed split was needed.

## 5. Bankroll stress

Threshold: < 0.5 % probability over 14 days, at 300 pulls/day with a ≤ 5-minute keeper, that the
pool plus the 0.5 ETH reserve cannot fund the next replacement. Result (2,000 seeds per scenario):
pool alone 0.10 % at 300/day and ≤ 0.5 % up to 1,500/day; with the reserve backstop 0 of 2,000 runs
in every scenario, including hourly and 6-hourly keepers and no trading income. A 2.0 ETH pool fails
the threshold (30 % at 1,500/day). The allocation stays 2.2 / 2.0 / 0.3 / 0.5. Full table and reading:
`sim/results/bankroll.md`, `docs/M2_RESULTS.md`.

## 6. Surplus and buybacks

Realised distributable surplus = ordinary NAV (cash + backing + receivable) − `capitalTarget`
(2.2 ETH), paid only from cash above the cash floor, only with the books level with the engine,
the replacement queue empty and the board full, and only after governance sets the sink (scheduled
for genesis end). The buyback spends it in ≤ 0.05 ETH slices, hourly, within a 3 % price-impact cap,
and burns everything it buys. The premium is the only ordinary source of that surplus; the GRAIL
feed and maintenance are not distributable.

## 7. GRAIL accounting identities

- `vault.totalFunded = controller.totalFeedSent + treasury.totalToGrail + direct fundGrail`.
- `vault.totalFunded + vault.totalProceeds = vault.fund + totalBackingMinted + totalMintFeesPaid`.
- A GRAIL exists on the board only after `fund ≥ backing + mintFee` was spent on it.
- At ~300 pulls a day the feed alone funds ~0.154 ETH/day, i.e. a 0.5 ETH GRAIL in a little over
  three days; trading fees shorten that (rehearsal: two GRAILs, 0.5 and 1 ETH, in 14 days at 200 pulls/day).
