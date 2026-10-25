# GRAIL availability, configuration comparison and keeper outages (sim/grail.py)

Model outputs under the assumptions in the module docstring; not demand forecasts.


## D. Keeper outages and recovery (current 4/0.5/2, no trading)

One outage starting at hour 72 (day 4); otherwise keepers every 5 min. VRF callbacks keep settling pulls during the outage (callback fast path); only booking, restocking and GRAIL steps stop. `rejected` = purchases that revert because the board is empty or 250 are unsettled; `refunded` = accepted pulls refunded (slippage or empty board), fee + settlement fee returned. `min ordinary active` = fewest selectable ordinary prizes (p1). `recovery` = hours after the keeper returns until the board is full and the queue empty (p50 / max); `recovery cost` = keeper gas + tips for it (p50). `house during outage` = expected margin booked on outage pulls (p1, negative = loss to the pool).

| pulls/day | outage | basefee gwei | refunded | rejected | min ordinary active p1 | max queue p99 | min cash p1 | reserve used p99 | P(shortfall) | recovery h p50 / max | recovery calls / cost p50 | house during outage p1 / p50 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 300 | none | 0.01 | 0.00 % | 0.00 % | 80 | 7 | 0.055 | 0.000 | 0.0 % | — | 0 / 0.00000 | 0.000 / 0.000 |
| 300 | 0.25 h | 0.01 | 0.00 % | 0.00 % | 79 | 21 | 0.060 | 0.000 | 0.0 % | 0.00 / 0.00 | 0 / 0.00000 | 1.201 / 1.785 |
| 300 | 1 h | 0.01 | 0.00 % | 0.00 % | 70 | 28 | 0.059 | 0.000 | 0.0 % | 0.00 / 0.00 | 1 / 0.00008 | 1.200 / 1.837 |
| 300 | 6 h | 0.01 | 0.56 % | 0.00 % | 22 | 81 | 0.093 | 0.000 | 0.0 % | 0.00 / 0.00 | 2 / 0.00045 | 1.210 / 1.877 |
| 300 | 24 h | 0.01 | 10.00 % | 0.00 % | 2 | 98 | 0.052 | 0.000 | 0.0 % | 0.00 / 0.00 | 3 / 0.00073 | 1.214 / 1.977 |
| 750 | none | 0.01 | 0.00 % | 0.00 % | 70 | 7 | 0.010 | 0.265 | 0.0 % | — | 0 / 0.00000 | 0.000 / 0.000 |
| 750 | 0.25 h | 0.01 | 0.00 % | 0.00 % | 65 | 28 | 0.037 | 0.000 | 0.0 % | 0.00 / 0.00 | 1 / 0.00008 | 3.380 / 4.556 |
| 750 | 1 h | 0.01 | 0.00 % | 0.00 % | 51 | 55 | 0.034 | 0.291 | 0.0 % | 0.00 / 0.00 | 1 / 0.00022 | 3.301 / 4.541 |
| 750 | 6 h | 0.01 | 2.12 % | 0.00 % | 9 | 91 | 0.039 | 0.000 | 0.0 % | 0.00 / 0.00 | 3 / 0.00067 | 3.705 / 4.538 |
| 750 | 24 h | 0.01 | 12.54 % | 0.00 % | 1 | 100 | 0.094 | 0.000 | 0.0 % | 0.00 / 0.00 | 5 / 0.00164 | 3.733 / 4.746 |
| 1500 | none | 0.002 | 0.10 % | 0.00 % | 50 | 7 | 0.074 | 0.000 | 0.0 % | — | 0 / 0.00000 | 0.000 / 0.000 |
| 1500 | none | 0.01 | 0.10 % | 0.00 % | 53 | 7 | 0.066 | 0.000 | 0.0 % | — | 0 / 0.00000 | 0.000 / 0.000 |
| 1500 | none | 0.1 | 0.10 % | 0.00 % | 51 | 7 | 0.016 | 0.000 | 0.0 % | — | 0 / 0.00000 | 0.000 / 0.000 |
| 1500 | 0.25 h | 0.01 | 0.13 % | 0.00 % | 53 | 35 | 0.023 | 0.000 | 0.0 % | 0.00 / 0.00 | 1 / 0.00015 | 7.192 / 8.763 |
| 1500 | 1 h | 0.01 | 0.24 % | 0.00 % | 29 | 72 | 0.019 | 0.000 | 0.0 % | 0.00 / 0.00 | 2 / 0.00043 | 7.609 / 8.936 |
| 1500 | 6 h | 0.01 | 2.92 % | 0.00 % | 2 | 98 | 0.011 | 0.000 | 0.0 % | 0.00 / 0.00 | 3 / 0.00085 | 7.100 / 8.938 |
| 1500 | 24 h | 0.002 | 7.40 % | 6.87 % | 0 | 100 | 0.014 | 0.286 | 0.0 % | 0.00 / 0.00 | 5 / 0.00039 | 7.374 / 8.826 |
| 1500 | 24 h | 0.01 | 7.40 % | 6.57 % | 0 | 100 | 0.030 | 0.290 | 0.0 % | 0.00 / 0.00 | 5 / 0.00174 | 7.399 / 8.913 |
| 1500 | 24 h | 0.1 | 7.36 % | 6.60 % | 0 | 100 | 0.038 | 0.000 | 0.0 % | 0.00 / 0.00 | 5 / 0.01696 | 7.494 / 9.009 |
