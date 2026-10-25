# Bankroll and restock stress (14 days)

Ordinary pool 2.2 ETH (1.79 ETH spent on the opening board, 0.41 ETH liquid) unless stated. Keeper settles every
`keeper` minutes; requests arrive in batches of 10 (Poisson), priced at request time, settled in order against
the live board (captured items leave at once, replacements wait for the keeper). No ENGINE income reaches the
ordinary pool; `trading` is ETH/day into the GRAIL fund only. `reserve backstop`: the treasury's 0.5 ETH
reserve tops cash up to 0.3 ETH when a replacement waits (Treasury.backstop).

Columns: `p_short` share of runs with any settle that could not fund the next replacement; `p_short_1h` share
with such a shortfall lasting ≥ 60 minutes; `p_below95` share in which the listed board ever fell below 95
items (measured just before each keeper restock; it is 1.0 in every row because farmers arrive in batches of
10, so any batch takes the board below 95 until the next restock — read `min_listed_min` instead, the worst
board depth seen before a restock across all seeds); `p_uncovered` share with a shortfall the reserve could not cover (only for backstop rows; otherwise
equals any shortfall); `refund_rate` share of requested pulls refunded by the 10 % slippage guard. ETH values.

| name | seeds | pulls_p50 | refund_rate | p_short | p_short_1h | max_short_minutes | p_below95 | p_uncovered | backstop_p99 | max_queue_max | unfunded_max | min_cash_p01 | min_listed_min | nav_p01 | nav_p50 | nav_p99 | premium_p50 | feed_p50 | grails_p50 | grail_wins_p50 | fee_p50 | rtp_p50 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100/day, trading 0.0, keeper 5m | 2000 | 1400 | 0.0000 | 0.0025 | 0.0025 | 2180 | 1.0000 | 0.0025 | 0.0000 | 10 | 0.1557 | 0.0572 | 70 | 2.2295 | 2.5671 | 2.9094 | 0.5307 | 0.7075 | 1 | 0 | 0.0158 | 0.8595 |
| 100/day, trading 0.3, keeper 5m | 2000 | 1390 | 0.0000 | 0.0005 | 0.0005 | 290 | 1.0000 | 0.0005 | 0.0000 | 1 | 0.0012 | 0.0971 | 70 | 2.3742 | 2.6895 | 3.0224 | 0.6516 | 0.8687 | 3 | 1 | 0.0161 | 0.8649 |
| 300/day, trading 0.0, keeper 5m | 2000 | 4200 | 0.0001 | 0.0010 | 0.0010 | 595 | 1.0000 | 0.0010 | 0.0000 | 7 | 0.1092 | 0.0689 | 60 | 3.1756 | 3.7382 | 4.3617 | 1.7004 | 2.2672 | 3 | 2 | 0.0159 | 0.8646 |
| 300/day, trading 0.3, keeper 5m | 2000 | 4200 | 0.0001 | 0.0015 | 0.0010 | 205 | 1.0000 | 0.0015 | 0.0000 | 2 | 0.0400 | 0.0642 | 60 | 3.2990 | 3.8745 | 4.4651 | 1.8405 | 2.4541 | 3 | 2 | 0.0160 | 0.8662 |
| 750/day, trading 0.0, keeper 5m | 2000 | 10489 | 0.0005 | 0.0030 | 0.0005 | 70 | 1.0000 | 0.0030 | 0.0000 | 3 | 0.0504 | 0.0617 | 44 | 5.1694 | 6.1175 | 7.0625 | 4.0897 | 5.4530 | 3 | 3 | 0.0159 | 0.8653 |
| 750/day, trading 0.3, keeper 5m | 2000 | 10480 | 0.0005 | 0.0010 | 0.0005 | 450 | 1.0000 | 0.0010 | 0.0000 | 12 | 0.1829 | 0.0438 | 50 | 5.3123 | 6.3065 | 7.3441 | 4.2671 | 5.6895 | 4 | 3 | 0.0159 | 0.8647 |
| 1500/day, trading 0.0, keeper 5m | 2000 | 20939 | 0.0024 | 0.0050 | 0.0005 | 80 | 1.0000 | 0.0050 | 0.0000 | 5 | 0.0791 | 0.0307 | 40 | 8.4389 | 9.8224 | 11.3316 | 7.7907 | 10.3876 | 4 | 3 | 0.0159 | 0.8649 |
| 1500/day, trading 0.3, keeper 5m | 2000 | 20926 | 0.0026 | 0.0045 | 0.0025 | 250 | 1.0000 | 0.0045 | 0.0000 | 11 | 0.1668 | 0.0584 | 36 | 8.7336 | 10.2050 | 11.7519 | 8.1745 | 10.8993 | 5 | 3 | 0.0159 | 0.8673 |
| 300/day, keeper 5m, reserve backstop | 2000 | 4200 | 0.0001 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.0000 | 0 | 0.0000 | 0.0485 | 60 | 3.1195 | 3.7279 | 4.3238 | 1.6900 | 2.2534 | 3 | 2 | 0.0159 | 0.8649 |
| 750/day, keeper 5m, reserve backstop | 2000 | 10500 | 0.0005 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.0000 | 0 | 0.0000 | 0.0551 | 50 | 5.1861 | 6.1142 | 7.0686 | 4.0826 | 5.4434 | 3 | 3 | 0.0159 | 0.8656 |
| 1500/day, keeper 5m, reserve backstop | 2000 | 20944 | 0.0024 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.0000 | 0 | 0.0000 | 0.0604 | 40 | 8.5084 | 9.8552 | 11.3118 | 7.8240 | 10.4320 | 4 | 3 | 0.0159 | 0.8649 |
| 300/day, keeper 60m | 2000 | 4112 | 0.0197 | 0.0060 | 0.0060 | 780 | 1.0000 | 0.0060 | 0.0000 | 7 | 0.1296 | 0.0389 | 30 | 2.8802 | 3.4330 | 4.0031 | 1.4052 | 1.8736 | 2 | 1 | 0.0159 | 0.8725 |
| 300/day, keeper 60m, reserve backstop | 2000 | 4114 | 0.0195 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.0000 | 0 | 0.0000 | 0.0377 | 30 | 2.9050 | 3.4257 | 3.9988 | 1.3940 | 1.8587 | 2 | 1 | 0.0158 | 0.8726 |
| 1500/day, keeper 60m | 2000 | 12651 | 0.3977 | 0.0375 | 0.0375 | 3360 | 1.0000 | 0.0375 | 0.0000 | 29 | 0.4335 | 0.0009 | 6 | 4.0748 | 5.0142 | 5.9439 | 2.9905 | 3.9874 | 3 | 3 | 0.0158 | 0.8877 |
| 1500/day, keeper 60m, reserve backstop | 2000 | 12662 | 0.3970 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.2942 | 0 | 0.0000 | 0.0096 | 6 | 4.0763 | 5.0216 | 5.9645 | 2.9909 | 3.9879 | 3 | 3 | 0.0158 | 0.8877 |
| 300/day, keeper 360m | 2000 | 2218 | 0.4729 | 0.0350 | 0.0350 | 8280 | 1.0000 | 0.0350 | 0.0000 | 17 | 0.2269 | 0.0010 | 4 | 2.0336 | 2.5036 | 2.8628 | 0.4754 | 0.6338 | 1 | 0 | 0.0157 | 0.8859 |
| 300/day, keeper 360m, reserve backstop | 2000 | 2218 | 0.4709 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.2968 | 0 | 0.0000 | 0.0115 | 7 | 2.0869 | 2.5103 | 2.8591 | 0.4718 | 0.6290 | 1 | 0 | 0.0157 | 0.8861 |
| 1500/day, keeper 360m | 2000 | 2293 | 0.8908 | 0.0480 | 0.0480 | 7560 | 1.0000 | 0.0480 | 0.0000 | 20 | 0.3012 | 0.0005 | 4 | 1.9956 | 2.5053 | 2.8998 | 0.4778 | 0.6371 | 1 | 0 | 0.0157 | 0.8871 |
| 1500/day, keeper 360m, reserve backstop | 2000 | 2292 | 0.8908 | 0.0000 | 0.0000 | 0 | 1.0000 | 0.0000 | 0.2965 | 0 | 0.0000 | 0.0063 | 6 | 2.0454 | 2.5157 | 2.8796 | 0.4819 | 0.6426 | 1 | 0 | 0.0157 | 0.8870 |
| 1500/day, keeper 5m, pool 1.9 | 2000 | 20947 | 0.0025 | 0.9425 | 0.6675 | 900 | 1.0000 | 0.9425 | 0.0000 | 26 | 0.4137 | 0.0000 | 40 | 8.1472 | 9.5243 | 10.9763 | 7.7899 | 10.3866 | 4 | 3 | 0.0159 | 0.8650 |
| 1500/day, keeper 5m, pool 2.0 | 2000 | 20925 | 0.0024 | 0.3035 | 0.0735 | 740 | 1.0000 | 0.3035 | 0.0000 | 19 | 0.3020 | 0.0001 | 38 | 8.3246 | 9.6222 | 11.1007 | 7.7904 | 10.3872 | 4 | 3 | 0.0159 | 0.8649 |
