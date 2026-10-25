# GRAIL availability, configuration comparison and keeper outages (sim/grail.py)

Model outputs under the assumptions in the module docstring; not demand forecasts.


## C2. Opening GRAIL funded at launch (new capital outside the 5 ETH split; needs approval)

`seed_grail` ETH is in the GRAIL fund at activation, so a 0.5 ETH GRAIL lists at launch. Nothing is taken from the ordinary pool, the reserve or the liquidity.

| config | pulls/day | trading | seed | first GRAIL h | no GRAIL h (p50 / p90) | mean selectable | GRAILs won | RTP total | buyback p50 / p10 |
|---|---|---|---|---|---|---|---|---|---|
| current 4/0.5/2 | 100 | 0 | 0.0 | never | 336 / 336 | 0.00 | 0 | 85.96 % | 0.503 / 0.251 |
| current 4/0.5/2 | 100 | 0 | 0.501 | 0 | 0 / 263 | 0.78 | 0 | 86.32 % | 0.594 / 0.353 |
| current 4/0.5/2 | 100 | 3 | 0.0 | 155 | 159 / 222 | 0.55 | 0 | 85.96 % | 0.582 / 0.282 |
| current 4/0.5/2 | 100 | 3 | 0.501 | 0 | 0 / 111 | 1.30 | 1 | 86.81 % | 0.652 / 0.371 |
| current 4/0.5/2 | 300 | 0 | 0.0 | 165 | 209 / 294 | 0.39 | 1 | 86.37 % | 1.934 / 1.471 |
| current 4/0.5/2 | 300 | 0 | 0.501 | 0 | 79 / 214 | 0.92 | 2 | 86.83 % | 2.128 / 1.524 |
| current 4/0.5/2 | 300 | 3 | 0.0 | 98 | 117 / 212 | 0.83 | 2 | 86.60 % | 2.178 / 1.679 |
| current 4/0.5/2 | 300 | 3 | 0.501 | 0 | 12 / 119 | 1.30 | 3 | 86.97 % | 2.265 / 1.828 |
| alternative 3.5/0.5/3 | 100 | 0 | 0.0 | 330 | 330 / 336 | 0.09 | 0 | 85.86 % | 0.420 / 0.214 |
| alternative 3.5/0.5/3 | 100 | 0 | 0.501 | 0 | 0 / 238 | 0.93 | 1 | 86.24 % | 0.512 / 0.265 |
| alternative 3.5/0.5/3 | 100 | 3 | 0.0 | 134 | 143 / 201 | 0.69 | 0 | 85.84 % | 0.490 / 0.249 |
| alternative 3.5/0.5/3 | 100 | 3 | 0.501 | 0 | 0 / 100 | 1.43 | 1 | 86.53 % | 0.567 / 0.327 |
| alternative 3.5/0.5/3 | 300 | 0 | 0.0 | 113 | 138 / 244 | 0.73 | 1 | 86.13 % | 1.788 / 1.299 |
| alternative 3.5/0.5/3 | 300 | 0 | 0.501 | 0 | 12 / 138 | 1.26 | 2 | 86.60 % | 1.976 / 1.498 |
| alternative 3.5/0.5/3 | 300 | 3 | 0.0 | 74 | 87 / 159 | 1.05 | 2 | 86.07 % | 1.948 / 1.548 |
| alternative 3.5/0.5/3 | 300 | 3 | 0.501 | 0 | 0 / 76 | 1.45 | 2 | 86.50 % | 2.044 / 1.652 |
