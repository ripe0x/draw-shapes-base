# GRAIL availability, configuration comparison and keeper outages (sim/grail.py)

Model outputs under the assumptions in the module docstring; not demand forecasts.


## C. GRAIL availability levers (300 pulls/day, 14 days)

`no GRAIL` = hours without a selectable GRAIL (median / p90); `idle fund` = mean ETH sitting in the GRAIL fund (accumulating, not on the board). All levers keep GRAILs fully funded before listing.

| config | trading | lever | first GRAIL h (p50) | no GRAIL h (p50 / p90) | mean selectable | GRAILs won | idle fund mean | RTP total | buyback p50 |
|---|---|---|---|---|---|---|---|---|---|
| current 4/0.5/2 | 0 | baseline: fixed repricing, new policy | 173 | 218 / 307 | 0.38 | 1 | 0.234 | 86.39 % | 1.942 |
| current 4/0.5/2 | 0 | before the fix: repricing bug | 170 | 213 / 305 | 0.38 | 1 | 0.235 | 86.36 % | 1.928 |
| current 4/0.5/2 | 0 | no decay at all | 171 | 212 / 300 | 0.40 | 1 | 0.235 | 86.35 % | 1.908 |
| current 4/0.5/2 | 0 | old treasury / vault policy | 172 | 204 / 292 | 0.41 | 1 | 0.234 | 86.28 % | 1.957 |
| current 4/0.5/2 | 0 | no ladder step-up during genesis | 172 | 208 / 308 | 0.39 | 1 | 0.236 | 86.32 % | 1.880 |
| current 4/0.5/2 | 0 | replacement buffer (hold 0.501 ETH back while one is live) | 170 | 214 / 304 | 0.35 | 1 | 0.254 | 86.38 % | 1.903 |
| current 4/0.5/2 | 0 | keeper every 60 min | 180 | 236 / 313 | 0.33 | 1 | 0.233 | 86.68 % | 1.789 |
| current 4/0.5/2 | 3 | baseline: fixed repricing, new policy | 94 | 112 / 198 | 0.84 | 2 | 0.253 | 86.43 % | 2.162 |
| current 4/0.5/2 | 3 | before the fix: repricing bug | 97 | 116 / 207 | 0.83 | 2 | 0.251 | 86.62 % | 2.147 |
| current 4/0.5/2 | 3 | no decay at all | 93 | 114 / 199 | 0.90 | 1 | 0.250 | 86.44 % | 2.130 |
| current 4/0.5/2 | 3 | old treasury / vault policy | 100 | 120 / 196 | 0.82 | 2 | 0.249 | 86.59 % | 2.149 |
| current 4/0.5/2 | 3 | no ladder step-up during genesis | 96 | 122 / 205 | 0.83 | 2 | 0.240 | 86.74 % | 2.116 |
| current 4/0.5/2 | 3 | replacement buffer (hold 0.501 ETH back while one is live) | 95 | 116 / 200 | 0.66 | 1 | 0.361 | 86.53 % | 2.050 |
| current 4/0.5/2 | 3 | keeper every 60 min | 103 | 123 / 226 | 0.80 | 2 | 0.245 | 86.99 % | 1.974 |
| alternative 3.5/0.5/3 | 0 | baseline: fixed repricing, new policy | 113 | 138 / 230 | 0.73 | 1 | 0.253 | 86.22 % | 1.812 |
| alternative 3.5/0.5/3 | 0 | before the fix: repricing bug | 112 | 148 / 251 | 0.70 | 1 | 0.252 | 86.16 % | 1.803 |
| alternative 3.5/0.5/3 | 0 | no decay at all | 112 | 141 / 260 | 0.71 | 1 | 0.252 | 86.29 % | 1.762 |
| alternative 3.5/0.5/3 | 0 | old treasury / vault policy | 114 | 145 / 251 | 0.70 | 1 | 0.257 | 86.06 % | 1.783 |
| alternative 3.5/0.5/3 | 0 | no ladder step-up during genesis | 110 | 140 / 238 | 0.75 | 1 | 0.243 | 86.21 % | 1.791 |
| alternative 3.5/0.5/3 | 0 | replacement buffer (hold 0.501 ETH back while one is live) | 113 | 134 / 230 | 0.61 | 1 | 0.349 | 85.92 % | 1.780 |
| alternative 3.5/0.5/3 | 0 | keeper every 60 min | 124 | 154 / 241 | 0.67 | 1 | 0.246 | 86.53 % | 1.706 |
| alternative 3.5/0.5/3 | 3 | baseline: fixed repricing, new policy | 78 | 88 / 144 | 1.06 | 2 | 0.311 | 86.25 % | 1.881 |
| alternative 3.5/0.5/3 | 3 | before the fix: repricing bug | 74 | 84 / 144 | 1.06 | 2 | 0.314 | 86.26 % | 1.908 |
| alternative 3.5/0.5/3 | 3 | no decay at all | 74 | 85 / 144 | 1.09 | 2 | 0.326 | 86.16 % | 1.938 |
| alternative 3.5/0.5/3 | 3 | old treasury / vault policy | 76 | 96 / 205 | 0.97 | 2 | 0.333 | 86.43 % | 1.861 |
| alternative 3.5/0.5/3 | 3 | no ladder step-up during genesis | 74 | 84 / 161 | 1.28 | 2 | 0.246 | 86.23 % | 1.982 |
| alternative 3.5/0.5/3 | 3 | replacement buffer (hold 0.501 ETH back while one is live) | 73 | 83 / 154 | 0.90 | 2 | 0.461 | 86.21 % | 1.907 |
| alternative 3.5/0.5/3 | 3 | keeper every 60 min | 79 | 91 / 161 | 1.00 | 2 | 0.302 | 86.66 % | 1.809 |
