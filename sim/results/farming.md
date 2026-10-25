# Genesis farming economics

Loss per pull (all-in): 0.002422 ETH = payment 0.015221 − expected backing 0.012819 + gas 2e-05.
Opening market: 2.0 ETH / 10M ENGINE, spot 2.0e-07 ETH per ENGINE.
Outside buying runs 16 days (14 epochs plus two days of sales); buyers hold. Competitive farmers, zero
required margin unless stated. These are model outputs under stated assumptions, not demand forecasts.

## Allocation × outside buying (2 % fee, farmers sell everything)

| Farm | Buys/day | First-order pulls/day | Model pulls/day | Farmer ETH realised | Nominal reward value | Creator mint fees | Premium | GRAIL feed + trading | Operator 0.25% | End price (1e-7 ETH) | End pool ETH |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 50M | 0.0 | 0 | 48 | 1.63 | 2.06 | 0.83 | 0.260 | 0.37 | 0.004 | 0.06 | 0.33 |
| 50M | 0.3 | 124 | 148 | 5.03 | 5.46 | 2.55 | 0.799 | 1.22 | 0.025 | 1.24 | 1.57 |
| 50M | 0.7 | 289 | 299 | 10.14 | 10.55 | 5.13 | 1.611 | 2.49 | 0.054 | 3.46 | 2.63 |
| 50M | 1.5 | 619 | 613 | 20.79 | 21.20 | 10.52 | 3.304 | 5.11 | 0.113 | 9.28 | 4.31 |
| 35M | 0.0 | 0 | 45 | 1.52 | 1.81 | 0.77 | 0.242 | 0.35 | 0.004 | 0.10 | 0.44 |
| 35M | 0.3 | 124 | 141 | 4.78 | 5.04 | 2.42 | 0.760 | 1.17 | 0.024 | 1.66 | 1.82 |
| 35M | 0.7 | 289 | 288 | 9.76 | 9.97 | 4.94 | 1.552 | 2.40 | 0.053 | 4.54 | 3.01 |
| 35M | 1.5 | 619 | 597 | 20.24 | 20.32 | 10.24 | 3.217 | 4.99 | 0.112 | 11.85 | 4.87 |
| 25M | 0.0 | 0 | 41 | 1.40 | 1.60 | 0.71 | 0.223 | 0.32 | 0.004 | 0.16 | 0.57 |
| 25M | 0.3 | 124 | 133 | 4.50 | 4.66 | 2.28 | 0.716 | 1.10 | 0.023 | 2.22 | 2.11 |
| 25M | 0.7 | 289 | 276 | 9.34 | 9.42 | 4.73 | 1.485 | 2.31 | 0.052 | 5.93 | 3.44 |
| 25M | 1.5 | 619 | 579 | 19.62 | 19.51 | 9.93 | 3.119 | 4.85 | 0.110 | 15.11 | 5.50 |
| 15M | 0.0 | 0 | 35 | 1.18 | 1.29 | 0.60 | 0.187 | 0.27 | 0.003 | 0.32 | 0.80 |
| 15M | 0.3 | 124 | 118 | 3.99 | 4.05 | 2.02 | 0.635 | 0.99 | 0.022 | 3.46 | 2.63 |
| 15M | 0.7 | 289 | 252 | 8.56 | 8.50 | 4.33 | 1.360 | 2.13 | 0.050 | 9.01 | 4.25 |
| 15M | 1.5 | 619 | 545 | 18.47 | 18.19 | 9.35 | 2.935 | 4.59 | 0.107 | 22.29 | 6.68 |
| 10M | 0.0 | 0 | 29 | 0.98 | 1.06 | 0.50 | 0.156 | 0.22 | 0.003 | 0.50 | 1.00 |
| 10M | 0.3 | 124 | 104 | 3.51 | 3.52 | 1.78 | 0.558 | 0.88 | 0.021 | 4.87 | 3.12 |
| 10M | 0.7 | 289 | 230 | 7.79 | 7.68 | 3.94 | 1.238 | 1.95 | 0.048 | 12.64 | 5.03 |
| 10M | 1.5 | 619 | 511 | 17.32 | 16.96 | 8.77 | 2.753 | 4.32 | 0.104 | 30.80 | 7.85 |

## Fee level: 2 % vs 5 % (25M allocation, 0.7 ETH/day)

Same buying assumed for both, which flatters 5 %: a higher fee also pushes trades to rival pools (test/unit/Bypass.t.sol) and away from the token.

| Fee | Buying lost to the higher fee | Buys/day | Hook fees | Operator | Treasury | Farmer ETH | Pulls/day |
|---|---|---|---|---|---|---|---|
| 2 % | 0 % | 0.700 | 0.415 | 0.052 | 0.363 | 9.34 | 276 |
| 5 % | 0 % | 0.700 | 1.023 | 0.051 | 0.972 | 8.80 | 259 |
| 5 % | 25 % | 0.525 | 0.776 | 0.039 | 0.738 | 6.77 | 200 |
| 5 % | 50 % | 0.350 | 0.533 | 0.027 | 0.506 | 4.81 | 142 |

## Farmer behaviour (25M, 0.7 ETH/day, 2 %)

| Sold share | Required margin | Pulls/day | Farmer ETH | Unsold farmer ENGINE | End price (1e-7) | End pool ETH |
|---|---|---|---|---|---|---|
| 100 % | 0 % | 276 | 9.34 | 0.0M | 5.93 | 3.44 |
| 100 % | 25 % | 220 | 9.34 | 0.0M | 5.93 | 3.44 |
| 50 % | 0 % | 243 | 8.23 | 12.5M | 10.49 | 4.58 |
| 25 % | 0 % | 199 | 6.74 | 18.8M | 18.59 | 6.10 |
