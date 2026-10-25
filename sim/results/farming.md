# Genesis farming economics

Loss per pull (all-in): 0.002233 ETH = payment 0.0150326 − expected backing 0.01282 + gas 2e-05.
Opening market: 2.0 ETH / 10M ENGINE, spot 2.0e-07 ETH per ENGINE.
Outside buying runs 16 days (14 epochs plus two days of sales); buyers hold. Competitive farmers, zero
required margin unless stated. These are model outputs under stated assumptions, not demand forecasts.

## Allocation × outside buying (2 % fee, farmers sell everything)

| Farm | Buys/day | First-order pulls/day | Model pulls/day | Farmer ETH realised | Nominal reward value | Creator mint fees | Premium | GRAIL feed + trading | Operator 0.25% | End price (1e-7 ETH) | End pool ETH |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 50M | 0.0 | 0 | 52 | 1.63 | 2.06 | 0.90 | 0.375 | 0.21 | 0.004 | 0.06 | 0.33 |
| 50M | 0.3 | 134 | 161 | 5.03 | 5.46 | 2.76 | 1.156 | 0.73 | 0.025 | 1.24 | 1.57 |
| 50M | 0.7 | 314 | 324 | 10.14 | 10.55 | 5.57 | 2.329 | 1.50 | 0.054 | 3.46 | 2.63 |
| 50M | 1.5 | 672 | 665 | 20.79 | 21.20 | 11.41 | 4.776 | 3.10 | 0.113 | 9.28 | 4.31 |
| 35M | 0.0 | 0 | 49 | 1.52 | 1.81 | 0.84 | 0.350 | 0.20 | 0.004 | 0.10 | 0.44 |
| 35M | 0.3 | 134 | 153 | 4.78 | 5.04 | 2.63 | 1.099 | 0.70 | 0.024 | 1.66 | 1.82 |
| 35M | 0.7 | 314 | 312 | 9.76 | 9.97 | 5.36 | 2.243 | 1.45 | 0.053 | 4.54 | 3.01 |
| 35M | 1.5 | 672 | 647 | 20.24 | 20.32 | 11.11 | 4.650 | 3.02 | 0.112 | 11.85 | 4.87 |
| 25M | 0.0 | 0 | 45 | 1.40 | 1.60 | 0.77 | 0.322 | 0.18 | 0.004 | 0.16 | 0.57 |
| 25M | 0.3 | 134 | 144 | 4.50 | 4.66 | 2.47 | 1.035 | 0.66 | 0.023 | 2.22 | 2.11 |
| 25M | 0.7 | 314 | 299 | 9.34 | 9.42 | 5.13 | 2.147 | 1.40 | 0.052 | 5.93 | 3.44 |
| 25M | 1.5 | 672 | 628 | 19.62 | 19.51 | 10.78 | 4.509 | 2.94 | 0.110 | 15.11 | 5.50 |
| 15M | 0.0 | 0 | 38 | 1.18 | 1.29 | 0.65 | 0.270 | 0.15 | 0.003 | 0.32 | 0.80 |
| 15M | 0.3 | 134 | 128 | 3.99 | 4.05 | 2.19 | 0.918 | 0.60 | 0.022 | 3.46 | 2.63 |
| 15M | 0.7 | 314 | 274 | 8.56 | 8.50 | 4.70 | 1.966 | 1.29 | 0.050 | 9.01 | 4.25 |
| 15M | 1.5 | 672 | 591 | 18.47 | 18.19 | 10.14 | 4.243 | 2.79 | 0.107 | 22.29 | 6.68 |
| 10M | 0.0 | 0 | 31 | 0.98 | 1.06 | 0.54 | 0.225 | 0.13 | 0.003 | 0.50 | 1.00 |
| 10M | 0.3 | 134 | 112 | 3.51 | 3.52 | 1.93 | 0.807 | 0.53 | 0.021 | 4.87 | 3.12 |
| 10M | 0.7 | 314 | 249 | 7.79 | 7.68 | 4.28 | 1.790 | 1.19 | 0.048 | 12.64 | 5.03 |
| 10M | 1.5 | 672 | 554 | 17.32 | 16.96 | 9.51 | 3.979 | 2.64 | 0.104 | 30.80 | 7.85 |

## Fee level: 2 % vs 5 % (25M allocation, 0.7 ETH/day)

Same buying assumed for both, which flatters 5 %: a higher fee also pushes trades to rival pools (test/unit/Bypass.t.sol) and away from the token.

| Fee | Buying lost to the higher fee | Buys/day | Hook fees | Operator | Treasury | Farmer ETH | Pulls/day |
|---|---|---|---|---|---|---|---|
| 2 % | 0 % | 0.700 | 0.415 | 0.052 | 0.363 | 9.34 | 299 |
| 5 % | 0 % | 0.700 | 1.023 | 0.051 | 0.972 | 8.80 | 281 |
| 5 % | 25 % | 0.525 | 0.776 | 0.039 | 0.738 | 6.77 | 217 |
| 5 % | 50 % | 0.350 | 0.533 | 0.027 | 0.506 | 4.81 | 154 |

## Farmer behaviour (25M, 0.7 ETH/day, 2 %)

| Sold share | Required margin | Pulls/day | Farmer ETH | Unsold farmer ENGINE | End price (1e-7) | End pool ETH |
|---|---|---|---|---|---|---|
| 100 % | 0 % | 299 | 9.34 | 0.0M | 5.93 | 3.44 |
| 100 % | 25 % | 239 | 9.34 | 0.0M | 5.93 | 3.44 |
| 50 % | 0 % | 263 | 8.23 | 12.5M | 10.49 | 4.58 |
| 25 % | 0 % | 216 | 6.74 | 18.8M | 18.59 | 6.10 |
