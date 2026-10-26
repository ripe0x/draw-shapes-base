#!/usr/bin/env python3
"""Ordinary-pool bankroll and restock stress test for the 14-day genesis.

Faithful to the contracts where it matters for solvency (src/game/DrawController.sol,
src/engine/DrawEngine.sol, src/game/PricingLib.sol):
- notional p = b * (1 + premium + maintenance + feed) + mintFee * rungs (launch 1.07); weight = 1e36 // p; fee = harmonic mean of active listings
  (GRAILs included) at request time; settlement fee is outside the pool.
- requests within a settle window are priced at request time and settle in order against the live
  board (captured items leave immediately, replacements wait for the keeper's settle);
- at each settle: proceeds become cash, margin = proceeds - value (netted, negative carries), mint
  line repaid first, rest split premium:maintenance:feed (launch 3.5:0.5:3) (maintenance and feed leave the
  pool), replacement rows from Draw Shapes' deficit / surprise / band draw, minted from cash only;
- GRAIL vault: feed + trading-fee share; a GRAIL (0.5, 1, 5 ETH ladder) is listed only when fully
  funded, at 80 % of backing decaying 0.00002 ETH per pull to 50 %; its capture never touches the
  ordinary pool's cash.
A restock shortfall is a settle at which cash cannot fund the next queued replacement.
Writes sim/results/bankroll.md. Usage: python3 sim/bankroll.py [seeds]
"""
import math, os, random, sys, hashlib
from multiprocessing import Pool as MP

BPS = 10_000
FEE = 0.001
ROWS = [  # rungs (backings), share bps
    ([0.01], 6200), ([0.01, 0.01], 2600), ([0.01, 0.01, 0.01], 700), ([0.05], 400), ([0.1], 100)]
BOARD = 100
# premium / maintenance / GRAIL feed bps (launch 3.5 / 0.5 / 3); BANKROLL_SPLIT="400,50,200" runs another
# split and writes results/bankroll-<split>.md
SPLIT = tuple(int(x) for x in os.environ.get("BANKROLL_SPLIT", "350,50,300").split(","))
MARKUP = 1 + sum(SPLIT) / BPS
SURPRISE_BPS, RESTORE_K, BAND_BPS = 200, 8, 3000
LADDER = [0.5, 1.0, 5.0]
GRAIL_LIST, GRAIL_FLOOR, GRAIL_DECAY, PROB_CAP = 0.8, 0.5, 0.00002, 0.05

ROW_B = [sum(r) for r, _ in ROWS]
ROW_N = [len(r) for r, _ in ROWS]
ROW_P = [b * MARKUP + FEE * n for b, n in zip(ROW_B, ROW_N)]
ROW_W = [1e36 // p for p in ROW_P]
TARGET = [math.ceil(BOARD * s / BPS) for _, s in ROWS]
SINGLE = [n == 1 for n in ROW_N]


def choose_row(rnd, counts):
    """PricingLib.chooseRow (deficit draw, surprise, band)."""
    n = len(ROWS)
    weight = []
    any_below = False
    for i in range(n):
        t, c = TARGET[i], counts[i]
        if c < t:
            any_below = True
        boost = RESTORE_K * (t - c) * BPS // t if t > c else 0
        weight.append(ROWS[i][1] * (BPS + boost) // BPS)
    if not any_below:
        return None
    pick = rnd.randrange(sum(weight))
    drawn = 0
    while pick >= weight[drawn]:
        pick -= weight[drawn]
        drawn += 1
    chosen = drawn
    if rnd.randrange(BPS) < SURPRISE_BPS:
        cands = sorted([i for i in range(n) if SINGLE[i] and ROW_B[i] >= 5 * ROW_B[drawn] and counts[i] < TARGET[i]],
                       key=lambda i: (ROW_B[i], i))[:3]
        if cands:
            ws = [60, 30, 10][:len(cands)]
            x = rnd.randrange(100) * sum(ws) // 100
            acc = 0
            for j, w in zip(cands, ws):
                acc += w
                if x < acc:
                    chosen = j
                    break
    t, c = TARGET[chosen], counts[chosen]
    cap = max(t + 1, (t * (BPS + BAND_BPS) + BPS - 1) // BPS)
    if c >= cap:
        best, bd = None, 0
        for i in range(n):
            if TARGET[i] - counts[i] > bd:
                bd, best = TARGET[i] - counts[i], i
        chosen = drawn if best is None else best
    return chosen


def simulate(args):
    pulls_per_day, settle_minutes, trading_grail_per_day, pool_eth, seed, batch, reserve = args
    reserve0 = reserve
    requested = refunded = 0
    run = max_run = 0
    backstopped = 0.0
    uncovered = 0
    below80 = False
    rnd = random.Random(seed)
    # board items: [row, backing, notional, weight]; grails tracked separately in the same list
    items = []
    counts = [0] * len(ROWS)
    cash = pool_eth
    for i, t in enumerate(TARGET):
        for _ in range(t):
            items.append([i, ROW_B[i], ROW_P[i], ROW_W[i], False, 0])
            counts[i] += 1
            cash -= ROW_B[i] + FEE * ROW_N[i]
    queue = []
    margin = 0.0
    mint_line = 0.0
    receivable = 0.0
    premium = maint = feed_total = 0.0
    grail_fund = 0.0
    grail_level = 0
    pulls_done = 0
    shortfall_settles = 0
    max_queue = 0
    max_unfunded = 0.0
    min_cash = cash
    min_listed = BOARD
    grail_wins = 0
    grail_listed_ever = 0
    window = settle_minutes / (24 * 60)
    windows_per_day = int(round(1 / window))
    mean_requests = pulls_per_day / windows_per_day
    fee_sum = 0.0
    backing_paid = 0.0
    for day in range(14):
        for w in range(windows_per_day):
            grail_fund += trading_grail_per_day / windows_per_day
            # requests in this window (batches), priced at request time against the board as it stands
            n = 0
            lam = mean_requests / batch
            # Poisson number of batches
            k = 0
            L = math.exp(-lam) if lam < 700 else 0.0
            p = 1.0
            if lam < 30:
                while True:
                    p *= rnd.random()
                    if p < L:
                        break
                    k += 1
            else:
                k = max(0, int(rnd.gauss(lam, math.sqrt(lam)) + 0.5))
            n = k * batch
            if n == 0 and w != windows_per_day - 1:
                pass
            sw = sum(it[3] for it in items)
            fee = sum(it[3] * it[2] for it in items) / sw if sw else 0.0
            # settle each request in order against the live board
            for _ in range(n):
                if not items:
                    break
                sw = sum(it[3] for it in items)
                live_fee = sum(it[3] * it[2] for it in items) / sw
                requested += 1
                if live_fee > fee * 1.10 or live_fee < fee * 0.90:
                    refunded += 1
                    continue  # slippage refund: no capture, no proceeds
                r = rnd.random() * sw
                acc = 0.0
                for idx, it in enumerate(items):
                    acc += it[3]
                    if r < acc:
                        break
                it = items.pop(idx)
                pulls_done += 1
                fee_sum += fee
                backing_paid += it[1]
                if it[4]:  # GRAIL
                    grail_wins += 1
                    grail_fund += fee
                    continue
                counts[it[0]] -= 1
                receivable += fee
                margin += fee - it[1]
                mint_line += FEE * ROW_N[it[0]]
                row = choose_row(rnd, [counts[i] + queue.count(i) for i in range(len(ROWS))])
                if row is not None:
                    queue.append(row)
            # keeper settle at the end of the window: harvest, split, restock
            cash += receivable
            receivable = 0.0
            if margin > 0:
                cover = min(margin, mint_line)
                mint_line -= cover
                rest = margin - cover
                m = rest * SPLIT[1] / sum(SPLIT)
                f = rest * SPLIT[2] / sum(SPLIT)
                cash -= m + f
                maint += m
                feed_total += f
                grail_fund += f
                premium += rest - m - f
                margin = 0.0
            min_listed = min(min_listed, sum(counts))  # board depth just before the keeper restocks
            if sum(counts) < 80:
                below80 = True
            short_now = False
            while queue:
                row = queue[0]
                cost = ROW_B[row] + FEE * ROW_N[row]
                if cash < cost and reserve > 0:
                    # Treasury.backstop(): top cash up to the 0.3 ETH floor from the reserve
                    top = min(reserve, max(0.3 - cash, cost - cash))
                    reserve -= top
                    cash += top
                    backstopped += top
                if cash < cost:
                    if reserve0 == 0 or reserve <= 0:
                        short_now = True
                    shortfall_settles += 1
                    max_unfunded = max(max_unfunded, sum(ROW_B[q] + FEE * ROW_N[q] for q in queue) - cash)
                    break
                cash -= cost
                queue.pop(0)
                items.append([row, ROW_B[row], ROW_P[row], ROW_W[row], False, 0])
                counts[row] += 1
            run = run + 1 if short_now else 0
            max_run = max(max_run, run)
            if short_now:
                uncovered += 1
            if sum(counts) < 80:
                below80 = True
            max_queue = max(max_queue, len(queue))
            min_cash = min(min_cash, cash)
            min_listed = min(min_listed, sum(counts))
            # GRAIL vault step
            target = LADDER[grail_level]
            grails = [it for it in items if it[4]]
            if grail_fund >= target + FEE and len(grails) < 4:
                grail_fund -= target + FEE
                notional = target * GRAIL_LIST
                items.append([-1, target, notional, 1e36 // notional, True, pulls_done])
                grail_listed_ever += 1
                if grail_listed_ever > 1 and grail_level + 1 < len(LADDER):
                    grail_level += 1
            for it in items:
                if it[4]:
                    nxt = max(it[1] * GRAIL_FLOOR, it[2] - GRAIL_DECAY * (pulls_done - it[5]))
                    if it[2] - nxt >= it[2] / 100:
                        it[2], it[3], it[5] = nxt, 1e36 // nxt, pulls_done
    nav = cash + sum(ROW_B[it[0]] for it in items if not it[4]) + receivable
    return dict(shortfall=shortfall_settles, max_queue=max_queue, max_unfunded=max_unfunded, min_cash=min_cash,
                min_listed=min_listed, nav=nav, premium=premium, maint=maint, feed=feed_total, pulls=pulls_done,
                grail_wins=grail_wins, grails=grail_listed_ever, avg_fee=fee_sum / max(pulls_done, 1),
                requested=requested, refunded=refunded, max_run=max_run * settle_minutes, backstopped=backstopped,
                uncovered=uncovered, below80=below80,
                rtp=backing_paid / max(fee_sum, 1e-18))


def q(xs, p):
    s = sorted(xs)
    return s[min(len(s) - 1, int(p * len(s)))]


def scenario(name, pulls, settle_min, trading, pool_eth, seeds, batch=10, reserve=0.0):
    args = [(pulls, settle_min, trading, pool_eth, int(hashlib.sha256(f"{name}/{i}".encode()).hexdigest()[:8], 16), batch, reserve) for i in range(seeds)]
    with MP(4) as mp:
        res = mp.map(simulate, args, chunksize=max(1, seeds // 16))
    short = [r["shortfall"] for r in res]
    return {
        "name": name, "pulls": pulls, "settle": settle_min, "trading": trading, "pool": pool_eth, "seeds": seeds,
        "p_short": sum(1 for s in short if s) / seeds,
        "short_settles_p99": q(short, 0.99), "max_queue_p99": q([r["max_queue"] for r in res], 0.99),
        "max_queue_max": max(r["max_queue"] for r in res),
        "unfunded_max": max(r["max_unfunded"] for r in res),
        "min_cash_p01": q([r["min_cash"] for r in res], 0.01), "min_cash_min": min(r["min_cash"] for r in res),
        "min_listed_min": min(r["min_listed"] for r in res),
        "nav_p01": q([r["nav"] for r in res], 0.01), "nav_p50": q([r["nav"] for r in res], 0.5),
        "nav_p99": q([r["nav"] for r in res], 0.99),
        "premium_p50": q([r["premium"] for r in res], 0.5), "feed_p50": q([r["feed"] for r in res], 0.5),
        "grail_wins_p50": q([r["grail_wins"] for r in res], 0.5), "grails_p50": q([r["grails"] for r in res], 0.5),
        "rtp_p50": q([r["rtp"] for r in res], 0.5), "fee_p50": q([r["avg_fee"] for r in res], 0.5),
        "pulls_p50": q([r["pulls"] for r in res], 0.5),
        "refund_rate": sum(r["refunded"] for r in res) / max(1, sum(r["requested"] for r in res)),
        "p_short_1h": sum(1 for r in res if r["max_run"] >= 60) / seeds,
        "max_short_minutes": max(r["max_run"] for r in res),
        "p_below80": sum(1 for r in res if r["below80"]) / seeds,
        "p_uncovered": sum(1 for r in res if r["uncovered"]) / seeds,
        "backstop_p99": q([r["backstopped"] for r in res], 0.99),
        "reserve": reserve,
    }


def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    rows = []
    for pulls in (100, 300, 750, 1500):
        for trading in (0.0, 0.3):
            rows.append(scenario(f"{pulls}/day, trading {trading}, keeper 5m", pulls, 5, trading, 2.2, seeds))
    for pulls in (300, 750, 1500):
        rows.append(scenario(f"{pulls}/day, keeper 5m, reserve backstop", pulls, 5, 0.0, 2.2, seeds, reserve=0.5))
    for settle in (60, 360):
        for pulls in (300, 1500):
            rows.append(scenario(f"{pulls}/day, keeper {settle}m", pulls, settle, 0.0, 2.2, seeds))
            rows.append(scenario(f"{pulls}/day, keeper {settle}m, reserve backstop", pulls, settle, 0.0, 2.2, seeds, reserve=0.5))
    for pool in (1.9, 2.0):
        rows.append(scenario(f"1500/day, keeper 5m, pool {pool}", 1500, 5, 0.0, pool, seeds))
    os.makedirs(os.path.join(os.path.dirname(__file__), "results"), exist_ok=True)
    cols = ["name", "seeds", "pulls_p50", "refund_rate", "p_short", "p_short_1h", "max_short_minutes", "p_below80",
            "p_uncovered", "backstop_p99", "max_queue_max", "unfunded_max", "min_cash_p01", "min_listed_min",
            "nav_p01", "nav_p50", "nav_p99", "premium_p50", "feed_p50", "grails_p50", "grail_wins_p50", "fee_p50",
            "rtp_p50"]
    out = [f"# Bankroll and restock stress (14 days), premium / maintenance / feed = {SPLIT} bps\n",
           "Ordinary pool 2.2 ETH (1.79 ETH spent on the opening board, 0.41 ETH liquid) unless stated. Keeper settles every",
           "`keeper` minutes; requests arrive in batches of 10 (Poisson), priced at request time, settled in order against",
           "the live board (captured items leave at once, replacements wait for the keeper). No ENGINE income reaches the",
           "ordinary pool; `trading` is ETH/day into the GRAIL fund only. `reserve backstop`: the treasury's 0.5 ETH",
           "reserve tops cash up to 0.3 ETH when a replacement waits (Treasury.backstop).\n",
           "Columns: `p_short` share of runs with any settle that could not fund the next replacement; `p_short_1h` share",
           "with such a shortfall lasting ≥ 60 minutes; `p_below80` share in which the listed board ever fell below 95",
           "items; `p_uncovered` share with a shortfall the reserve could not cover (only for backstop rows; otherwise",
           "equals any shortfall); `refund_rate` share of requested pulls refunded by the 10 % slippage guard. ETH values.\n",
           "| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        out.append("| " + " | ".join(f"{r[c]:.4f}" if isinstance(r[c], float) else str(r[c]) for c in cols) + " |")
    name = "bankroll.md" if SPLIT == (350, 50, 300) else f"bankroll-{'-'.join(map(str, SPLIT))}.md"
    path = os.path.join(os.path.dirname(__file__), "results", name)
    open(path, "w").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
