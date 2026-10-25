# Genesis farming economics

Loss per pull (all-in): 0.002299 ETH = payment 0.0150976 − expected backing 0.012819 + gas 2e-05.
Opening market: 2.0 ETH / 10M ENGINE, spot 2.0e-07 ETH per ENGINE.
Outside buying runs 16 days (14 epochs plus two days of sales); buyers hold. Competitive farmers, zero
required margin unless stated. These are model outputs under stated assumptions, not demand forecasts.

## Allocation × outside buying (2 % fee, farmers sell everything)

| Farm | Buys/day | First-order pulls/day | Model pulls/day | Farmer ETH realised | Nominal reward value | Creator mint fees | Premium | GRAIL feed + trading | Operator 0.25% | End price (1e-7 ETH) | End pool ETH |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 50M | 0.0 | 0 | 51 | 1.63 | 2.06 | 0.87 | 0.319 | 0.30 | 0.004 | 0.06 | 0.33 |
| 50M | 0.3 | 131 | 156 | 5.03 | 5.46 | 2.68 | 0.982 | 1.00 | 0.025 | 1.24 | 1.57 |
| 50M | 0.7 | 305 | 315 | 10.14 | 10.55 | 5.41 | 1.980 | 2.04 | 0.054 | 3.46 | 2.63 |
| 50M | 1.5 | 653 | 646 | 20.79 | 21.20 | 11.09 | 4.060 | 4.19 | 0.113 | 9.28 | 4.31 |
| 35M | 0.0 | 0 | 47 | 1.52 | 1.81 | 0.81 | 0.298 | 0.28 | 0.004 | 0.10 | 0.44 |
| 35M | 0.3 | 131 | 149 | 4.78 | 5.04 | 2.55 | 0.934 | 0.95 | 0.024 | 1.66 | 1.82 |
| 35M | 0.7 | 305 | 303 | 9.76 | 9.97 | 5.21 | 1.907 | 1.97 | 0.053 | 4.54 | 3.01 |
| 35M | 1.5 | 653 | 629 | 20.24 | 20.32 | 10.79 | 3.953 | 4.09 | 0.112 | 11.85 | 4.87 |
| 25M | 0.0 | 0 | 44 | 1.40 | 1.60 | 0.75 | 0.273 | 0.26 | 0.004 | 0.16 | 0.57 |
| 25M | 0.3 | 131 | 140 | 4.50 | 4.66 | 2.40 | 0.880 | 0.90 | 0.023 | 2.22 | 2.11 |
| 25M | 0.7 | 305 | 290 | 9.34 | 9.42 | 4.98 | 1.825 | 1.89 | 0.052 | 5.93 | 3.44 |
| 25M | 1.5 | 653 | 610 | 19.62 | 19.51 | 10.47 | 3.833 | 3.98 | 0.110 | 15.11 | 5.50 |
| 15M | 0.0 | 0 | 37 | 1.18 | 1.29 | 0.63 | 0.230 | 0.22 | 0.003 | 0.32 | 0.80 |
| 15M | 0.3 | 131 | 124 | 3.99 | 4.05 | 2.13 | 0.780 | 0.81 | 0.022 | 3.46 | 2.63 |
| 15M | 0.7 | 305 | 266 | 8.56 | 8.50 | 4.56 | 1.671 | 1.75 | 0.050 | 9.01 | 4.25 |
| 15M | 1.5 | 653 | 574 | 18.47 | 18.19 | 9.85 | 3.607 | 3.77 | 0.107 | 22.29 | 6.68 |
| 10M | 0.0 | 0 | 30 | 0.98 | 1.06 | 0.52 | 0.191 | 0.18 | 0.003 | 0.50 | 1.00 |
| 10M | 0.3 | 131 | 109 | 3.51 | 3.52 | 1.87 | 0.686 | 0.72 | 0.021 | 4.87 | 3.12 |
| 10M | 0.7 | 305 | 242 | 7.79 | 7.68 | 4.15 | 1.521 | 1.61 | 0.048 | 12.64 | 5.03 |
| 10M | 1.5 | 653 | 538 | 17.32 | 16.96 | 9.24 | 3.383 | 3.56 | 0.104 | 30.80 | 7.85 |

## Fee level: 2 % vs 5 % (25M allocation, 0.7 ETH/day)

Same buying assumed for both, which flatters 5 %: a higher fee also pushes trades to rival pools (test/unit/Bypass.t.sol) and away from the token.

| Fee | Buying lost to the higher fee | Buys/day | Hook fees | Operator | Treasury | Farmer ETH | Pulls/day |
|---|---|---|---|---|---|---|---|
| 2 % | 0 % | 0.700 | 0.415 | 0.052 | 0.363 | 9.34 | 290 |
| 5 % | 0 % | 0.700 | 1.023 | 0.051 | 0.972 | 8.80 | 273 |
| 5 % | 25 % | 0.525 | 0.776 | 0.039 | 0.738 | 6.77 | 210 |
| 5 % | 50 % | 0.350 | 0.533 | 0.027 | 0.506 | 4.81 | 149 |

## Farmer behaviour (25M, 0.7 ETH/day, 2 %)

| Sold share | Required margin | Pulls/day | Farmer ETH | Unsold farmer ENGINE | End price (1e-7) | End pool ETH |
|---|---|---|---|---|---|---|
| 100 % | 0 % | 290 | 9.34 | 0.0M | 5.93 | 3.44 |
| 100 % | 25 % | 232 | 9.34 | 0.0M | 5.93 | 3.44 |
| 50 % | 0 % | 256 | 8.23 | 12.5M | 10.49 | 4.58 |
| 25 % | 0 % | 209 | 6.74 | 18.8M | 18.59 | 6.10 |

## Sensitivity: partial reinvestment and the source of farmer ETH (25M, 2 %, farmers sell everything)

The equilibrium above assumes farmers put all realised ENGINE proceeds into pulls. Here only `reinvest` of it is; the rest leaves the system as farmer profit. Farmer ETH comes from outside buyers (external ETH, net of hook fees) and, where buying is weak, from draining the opening 2 ETH of liquidity (`liquidity drained`, negative = the pool ended with more ETH). Creator mint fees are model outputs scaled from pulls, not expected revenue: they exist only if outside buyers bring that ETH and farmers spend it on pulls. Loss per pull for each configuration includes the VRF share.

| Outside buying ETH/day | Config | Loss / pull | Reinvest | Pulls/day | Farmer ETH realised | of which kept | External ETH in | Liquidity drained | Creator mint fees (model) | Premium | GRAIL feed |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.0 | current 4/0.5/2 | 0.002233 | 100 % | 45 | 1.40 | 0.00 | 0.00 | 1.43 | 0.77 | 0.322 | 0.160 |
| 0.0 | current 4/0.5/2 | 0.002233 | 75 % | 34 | 1.40 | 0.35 | 0.00 | 1.43 | 0.58 | 0.241 | 0.120 |
| 0.0 | current 4/0.5/2 | 0.002233 | 50 % | 22 | 1.40 | 0.70 | 0.00 | 1.43 | 0.38 | 0.161 | 0.080 |
| 0.0 | current 4/0.5/2 | 0.002233 | 25 % | 11 | 1.40 | 1.05 | 0.00 | 1.43 | 0.19 | 0.080 | 0.040 |
| 0.0 | alternative 3.5/0.5/3 | 0.002298 | 100 % | 44 | 1.40 | 0.00 | 0.00 | 1.43 | 0.75 | 0.274 | 0.235 |
| 0.0 | alternative 3.5/0.5/3 | 0.002298 | 75 % | 33 | 1.40 | 0.35 | 0.00 | 1.43 | 0.56 | 0.205 | 0.176 |
| 0.0 | alternative 3.5/0.5/3 | 0.002298 | 50 % | 22 | 1.40 | 0.70 | 0.00 | 1.43 | 0.37 | 0.137 | 0.117 |
| 0.0 | alternative 3.5/0.5/3 | 0.002298 | 25 % | 11 | 1.40 | 1.05 | 0.00 | 1.43 | 0.19 | 0.068 | 0.059 |
| 0.3 | current 4/0.5/2 | 0.002233 | 100 % | 144 | 4.50 | 0.00 | 4.80 | -0.11 | 2.47 | 1.035 | 0.516 |
| 0.3 | current 4/0.5/2 | 0.002233 | 75 % | 108 | 4.50 | 1.13 | 4.80 | -0.11 | 1.85 | 0.776 | 0.387 |
| 0.3 | current 4/0.5/2 | 0.002233 | 50 % | 72 | 4.50 | 2.25 | 4.80 | -0.11 | 1.24 | 0.517 | 0.258 |
| 0.3 | current 4/0.5/2 | 0.002233 | 25 % | 36 | 4.50 | 3.38 | 4.80 | -0.11 | 0.62 | 0.259 | 0.129 |
| 0.3 | alternative 3.5/0.5/3 | 0.002298 | 100 % | 140 | 4.50 | 0.00 | 4.80 | -0.11 | 2.40 | 0.880 | 0.755 |
| 0.3 | alternative 3.5/0.5/3 | 0.002298 | 75 % | 105 | 4.50 | 1.13 | 4.80 | -0.11 | 1.80 | 0.660 | 0.566 |
| 0.3 | alternative 3.5/0.5/3 | 0.002298 | 50 % | 70 | 4.50 | 2.25 | 4.80 | -0.11 | 1.20 | 0.440 | 0.377 |
| 0.3 | alternative 3.5/0.5/3 | 0.002298 | 25 % | 35 | 4.50 | 3.38 | 4.80 | -0.11 | 0.60 | 0.220 | 0.189 |
| 0.7 | current 4/0.5/2 | 0.002233 | 100 % | 299 | 9.34 | 0.00 | 11.20 | -1.44 | 5.13 | 2.146 | 1.071 |
| 0.7 | current 4/0.5/2 | 0.002233 | 75 % | 224 | 9.34 | 2.34 | 11.20 | -1.44 | 3.85 | 1.609 | 0.803 |
| 0.7 | current 4/0.5/2 | 0.002233 | 50 % | 149 | 9.34 | 4.67 | 11.20 | -1.44 | 2.56 | 1.073 | 0.535 |
| 0.7 | current 4/0.5/2 | 0.002233 | 25 % | 75 | 9.34 | 7.01 | 11.20 | -1.44 | 1.28 | 0.536 | 0.268 |
| 0.7 | alternative 3.5/0.5/3 | 0.002298 | 100 % | 290 | 9.34 | 0.00 | 11.20 | -1.44 | 4.98 | 1.825 | 1.565 |
| 0.7 | alternative 3.5/0.5/3 | 0.002298 | 75 % | 218 | 9.34 | 2.34 | 11.20 | -1.44 | 3.74 | 1.369 | 1.174 |
| 0.7 | alternative 3.5/0.5/3 | 0.002298 | 50 % | 145 | 9.34 | 4.67 | 11.20 | -1.44 | 2.49 | 0.913 | 0.783 |
| 0.7 | alternative 3.5/0.5/3 | 0.002298 | 25 % | 73 | 9.34 | 7.01 | 11.20 | -1.44 | 1.25 | 0.456 | 0.391 |
| 1.5 | current 4/0.5/2 | 0.002233 | 100 % | 628 | 19.62 | 0.00 | 24.00 | -3.50 | 10.77 | 4.507 | 2.249 |
| 1.5 | current 4/0.5/2 | 0.002233 | 75 % | 471 | 19.62 | 4.91 | 24.00 | -3.50 | 8.08 | 3.381 | 1.687 |
| 1.5 | current 4/0.5/2 | 0.002233 | 50 % | 314 | 19.62 | 9.81 | 24.00 | -3.50 | 5.38 | 2.254 | 1.125 |
| 1.5 | current 4/0.5/2 | 0.002233 | 25 % | 157 | 19.62 | 14.72 | 24.00 | -3.50 | 2.69 | 1.127 | 0.562 |
| 1.5 | alternative 3.5/0.5/3 | 0.002298 | 100 % | 610 | 19.62 | 0.00 | 24.00 | -3.50 | 10.47 | 3.834 | 3.288 |
| 1.5 | alternative 3.5/0.5/3 | 0.002298 | 75 % | 457 | 19.62 | 4.91 | 24.00 | -3.50 | 7.85 | 2.876 | 2.466 |
| 1.5 | alternative 3.5/0.5/3 | 0.002298 | 50 % | 305 | 19.62 | 9.81 | 24.00 | -3.50 | 5.23 | 1.917 | 1.644 |
| 1.5 | alternative 3.5/0.5/3 | 0.002298 | 25 % | 152 | 19.62 | 14.72 | 24.00 | -3.50 | 2.62 | 0.959 | 0.822 |
