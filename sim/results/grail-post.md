# GRAIL availability, configuration comparison and keeper outages (sim/grail.py)

Model outputs under the assumptions in the module docstring; not demand forecasts.


## B. After genesis: 14 days of genesis then 28 days at lower organic demand

Genesis at 300 pulls/day; afterwards `post` pulls/day and 1 ETH/day of trading. Buyback = surplus released weekly after genesis (p50 / p10). `no GRAIL after` = hours without a selectable GRAIL in the 28 post-genesis days (672 h).

| config | genesis trading | post pulls/day | buyback total p50 / p10 | no GRAIL during genesis h | no GRAIL after h (p50 / p90) | GRAILs won | RTP total |
|---|---|---|---|---|---|---|---|
| current 4/0.5/2 | 0 | 50 | 2.834 / 2.059 | 213 | 0 / 243 | 2 | 86.49 % |
| current 4/0.5/2 | 0 | 150 | 4.376 / 3.598 | 220 | 40 / 272 | 3 | 86.70 % |
| current 4/0.5/2 | 3 | 50 | 3.012 / 2.450 | 115 | 0 / 162 | 3 | 86.73 % |
| current 4/0.5/2 | 3 | 150 | 4.687 / 3.937 | 118 | 0 / 201 | 5 | 86.95 % |
| alternative 3.5/0.5/3 | 0 | 50 | 2.540 / 2.109 | 147 | 0 / 124 | 2 | 86.36 % |
| alternative 3.5/0.5/3 | 0 | 150 | 4.075 / 3.461 | 141 | 0 / 113 | 5 | 86.47 % |
| alternative 3.5/0.5/3 | 3 | 50 | 2.685 / 2.257 | 89 | 0 / 0 | 3 | 86.47 % |
| alternative 3.5/0.5/3 | 3 | 150 | 4.273 / 3.617 | 86 | 0 / 27 | 4 | 86.47 % |
