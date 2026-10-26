#!/usr/bin/env python3
"""Follow-up economics: before / after comparison and the 14-day treasury and GRAIL policy model.

Part 1 (exact, integer wei like the contracts): reference-board notionals, harmonic-mean fee,
settlement fee and split, purchaser VRF fee, RTP and the expected per-pull margin waterfall for
  - previous   premium 3 %, maintenance 1 %, feed 4 %, Token Works 10 %, VRF paid from maintenance
  - proposed   premium 4 %, maintenance 0.5 %, feed 2 %, Token Works 25 %, purchaser-funded VRF
  - low-cost   premium 3 %, maintenance 0.5 %, feed 1 %, Token Works 25 %, purchaser-funded VRF
  - proposed with maintenance 0.25 % (benchmark only, not adopted)

Part 2 (Monte Carlo, 14 days): the bankroll model of sim/bankroll.py (same board, replacement draw,
ordered settlement against the live board, slippage refunds, keeper windows) extended with
  - the GRAIL vault as implemented: minted only when fully funded; while none is live the target is
    the smallest rung (replacement first) and the ladder does not move on a replacement; listed at
    80 % of backing, decaying 0.00002 ETH per pull to 50 % while GRAIL weight < 5 %;
  - the treasury as implemented: trading receipts refill the 0.5 ETH reserve, then 100 % to the
    GRAIL fund while no GRAIL is live, otherwise 90 % GRAIL / 10 % POL; reserve backstop;
  - VRF: one request per batch; purchaser fee from DrawEngine.vrfFeeFor, oracle bill from the
    Chainlink v2.5 formula with measured callback gas; in `previous` maintenance pays the bill;
  - keepers: one settle per window with work, gas measured in test/unit/GasProbe.t.sol, refunded
    from maintenance at basefee plus the 0.00001 ETH tip;
  - genesis end: realised surplus = NAV - 2.2 ETH capital, only from free cash with the books level,
    queue empty and the board full; maintenance is first topped up to its 0.05 ETH floor; the rest
    is the buyback budget. Treasury and capture transfers are never counted as game earnings.
Writes sim/results/followup.md. Usage: python3 sim/followup.py [seeds]
"""
import hashlib, math, os, random, sys
from multiprocessing import Pool as MP

sys.path.insert(0, os.path.dirname(__file__))
from bankroll import ROWS, BOARD, TARGET, SINGLE, choose_row  # noqa: E402  same board and draw

BPS = 10_000
E = 10**18
GWEI = 10**9
MINT_FEE = E // 1000
ROW_B_WEI = [sum(int(round(x * 1000)) for x in r) * E // 1000 for r, _ in ROWS]
ROW_N = [len(r) for r, _ in ROWS]
TARGET_COUNTS = [62, 26, 7, 4, 1]

CONFIGS = [
    # name, premium, maintenance, feed, Token Works share of the settlement fee, purchaser pays VRF,
    # new GRAIL policy (treasury priority while none is live, replacement first)
    ("previous 3/1/4, TW 10 %", 300, 100, 400, 1000, False, False),
    ("proposed 4/0.5/2, TW 25 %", 400, 50, 200, 2500, True, True),
    ("low-cost 3/0.5/1, TW 25 %", 300, 50, 100, 2500, True, True),
    ("proposed, maintenance 0.25 %", 400, 25, 200, 2500, True, True),
    ("proposed, old GRAIL policy", 400, 50, 200, 2500, True, False),
]
BENCH = ("proposed, maintenance 0.25 %", "proposed, old GRAIL policy")

# DrawEngine VRF fee (LaunchParams.vrfFee) and callback gas schedule (LaunchParams.vrf)
VRF_OVERHEAD, VRF_MIN_PRICE, VRF_PREMIUM, VRF_BUFFER, VRF_FLAT = 400_000, 5 * 10**6, 6_000, 2_500, 2 * 10**12
CB_BASE, CB_PER, CB_MAX = 100_000, 650_000, 2_500_000
# Chainlink v2.5 native billing on Base: (callback gas used + ~300k verification + 42.5k) x price x 1.6 + L1
CL_OVERHEAD, CL_PREMIUM, CL_L1 = 342_500, 16_000, 5 * 10**14 // 1000  # 0.0000005 ETH
# keeper settle gas (GasProbe): ~250k + ~690k per booked pull (replacement mint + list); refund overhead 30k
SETTLE_BASE, SETTLE_PER, TIP = 250_000, 690_000, 10**13
MAINT_FLOOR = 0.05
CAPITAL = 2.2


def cb_limit(n):
    return min(CB_MAX, CB_BASE + n * CB_PER)


def cb_used(n):
    # measured: 1 -> 433k, 5 -> 1.14M, 10 -> 2.05M (fast path runs while the limit allows)
    return min(cb_limit(n), 250_000 + 180_000 * n)


def vrf_fee(n, basefee):
    price = max(basefee, VRF_MIN_PRICE)
    return min((VRF_OVERHEAD + cb_limit(n)) * price * (BPS + VRF_PREMIUM + VRF_BUFFER) // BPS + VRF_FLAT, 2 * 10**15)


def vrf_bill(n, gas_price):
    return (cb_used(n) + CL_OVERHEAD) * gas_price * CL_PREMIUM // BPS + CL_L1


def notional_wei(row, prem, maint, feed):
    return ROW_B_WEI[row] * (BPS + prem + maint + feed) // BPS + MINT_FEE * ROW_N[row]


def exact(cfg):
    name, prem, maint, feed, tw, purchaser_vrf, _ = cfg
    p = [notional_wei(r, prem, maint, feed) for r in range(5)]
    w = [10**36 // x for x in p]
    W = sum(c * x for c, x in zip(TARGET_COUNTS, w))
    WP = sum(c * x * q for c, x, q in zip(TARGET_COUNTS, w, p))
    fee = WP // W
    sfee = fee * 100 // BPS
    eb = sum(c * x * b for c, x, b in zip(TARGET_COUNTS, w, ROW_B_WEI)) // W
    rungs = sum(c * x * n for c, x, n in zip(TARGET_COUNTS, w, ROW_N)) / W
    mint_line = rungs * MINT_FEE
    margin = fee - eb
    rest = margin - mint_line
    tot = prem + maint + feed
    v1, v10 = (vrf_fee(1, 10**7), vrf_fee(10, 10**7)) if purchaser_vrf else (0, 0)
    return dict(name=name, notionals=p, fee=fee, sfee=sfee, price=fee + sfee, eb=eb,
                rtp=eb / (fee + sfee), rtp_vrf1=eb / (fee + sfee + v1), rtp_vrf10=eb / (fee + sfee + v10 / 10),
                vrf1=v1, vrf10=v10, mint_line=mint_line, margin=margin, premium=rest * prem / tot,
                maint=rest * maint / tot, feed=rest * feed / tot, ref=sfee * 5000 // BPS, tw=sfee * tw // BPS,
                dev=sfee - sfee * 5000 // BPS - sfee * tw // BPS, loss=fee + sfee + v10 / 10 - eb)


# ------------------------------------------------------------------------------------------------
# Monte Carlo
# ------------------------------------------------------------------------------------------------

LADDER = [0.5, 1.0, 5.0]
GRAIL_LIST, GRAIL_FLOOR, GRAIL_DECAY, PROB_CAP = 0.8, 0.5, 0.00002, 0.05
STEP_UP_DAYS, STEP_DOWN_DAYS = 3, 14
FEE = 0.001
# Platform rules. Base (DrawEngine): the player pays fee x 1.01 (settlement fee, outside the pool) plus
# the purchaser VRF fee; the pool receives the fee. FWA V2 custom pool (FWAClone): the player pays
# fee x (1 + edge), the pool owner receives fee x (1 + edge / 2), FWA keeps the other half; FWA's VRF
# service charges the player `requestFee` (0 on Ethereum when read 2026-10-26) and pays the oracle.
BASE_PLATFORM = dict(name="base", price=1.01, pool=1.0, own_vrf=True)


def simulate(args):
    cfg, pulls_per_day, trade_vol_per_day, basefee_gwei, settle_minutes, seed, *rest = args
    plat = rest[0] if rest else BASE_PLATFORM
    own_vrf = plat["own_vrf"]
    platform_take = 0.0  # settlement fee (Base) or FWA's half of the edge
    name, prem, maint_bps, feed_bps, tw, purchaser_vrf, new_policy = cfg
    markup = 1 + (prem + maint_bps + feed_bps) / BPS
    split = (prem, maint_bps, feed_bps)
    row_b = [b / E for b in ROW_B_WEI]
    row_p = [b * markup + FEE * n for b, n in zip(row_b, ROW_N)]
    row_w = [1e36 // x for x in row_p]
    rnd = random.Random(seed)
    basefee = int(basefee_gwei * GWEI)
    batch = 10
    items = []  # [row, backing, notional, weight, is_grail, listed_at_pull]
    counts = [0] * len(ROWS)
    cash = 2.2
    mint_fees = 0.0
    for i, t in enumerate(TARGET):
        for _ in range(t):
            items.append([i, row_b[i], row_p[i], row_w[i], False, 0])
            counts[i] += 1
            cash -= row_b[i] + FEE * ROW_N[i]
            mint_fees += FEE * ROW_N[i]
    queue = []
    margin = mint_line = receivable = 0.0
    premium = maint_booked = feed_total = 0.0
    maint_bal = 0.0
    keeper_cost = keeper_unpaid = 0.0
    vrf_collected = vrf_billed = 0.0
    reserve, reserve_target, backstopped = 0.5, 0.5, 0.0
    grail_fund = 0.0
    grail_from_trading = 0.0
    grail_capture_proceeds = 0.0
    pol = 0.0
    level = 0
    cycle_started = None
    cycle_id = 1
    pulls_done = requested = refunded = 0
    paid = paid_grail = backing_won = backing_won_grail = 0.0
    grail_wins = grails_minted = 0
    grail_backing_minted = 0.0
    no_grail_minutes = 0
    first_grail_minute = None
    weight_share_sum = weight_share_n = 0
    inventory = []  # per day: (live grails, live grail backing)
    shortfall = 0
    windows_per_day = int(round(24 * 60 / settle_minutes))
    lam = pulls_per_day / windows_per_day / batch
    treasury_per_window = trade_vol_per_day * 0.0175 / windows_per_day
    gp = basefee * 12 // 10  # oracle gas price: basefee plus priority
    minute = 0
    for day in range(14):
        for w in range(windows_per_day):
            minute += settle_minutes
            now_days = minute / 1440
            live = [it for it in items if it[4]]
            # treasury receipts: reserve first, then GRAIL priority while none is live, else 90 / 10
            amt = treasury_per_window
            if amt:
                top = min(amt, max(0.0, reserve_target - reserve))
                reserve += top
                rest = amt - top
                to_grail = rest if (new_policy and not live) else rest * 0.9
                grail_fund += to_grail
                grail_from_trading += to_grail
                pol += rest - to_grail
            # Poisson batches
            k = 0
            if lam < 30:
                L, pr = math.exp(-lam), 1.0
                while True:
                    pr *= rnd.random()
                    if pr < L:
                        break
                    k += 1
            else:
                k = max(0, int(rnd.gauss(lam, math.sqrt(lam)) + 0.5))
            booked = 0
            for _b in range(k):
                if not items:
                    break
                sw = sum(it[3] for it in items)
                fee = sum(it[3] * it[2] for it in items) / sw
                vf = vrf_fee(batch, basefee) / E
                bill = vrf_bill(batch, gp) / E
                if not own_vrf:
                    vf = bill = 0.0  # FWA's service pays the oracle
                elif purchaser_vrf:
                    vrf_collected += vf
                else:
                    maint_bal -= bill  # previous design: maintenance tops the subscription up
                vrf_billed += bill
                gw = sum(it[3] for it in items if it[4])
                weight_share_sum += gw / sw
                weight_share_n += 1
                for _ in range(batch):
                    if not items:
                        break
                    sw = sum(it[3] for it in items)
                    live_fee = sum(it[3] * it[2] for it in items) / sw
                    requested += 1
                    if live_fee > fee * 1.10 or live_fee < fee * 0.90:
                        refunded += 1
                        continue
                    r = rnd.random() * sw
                    acc = 0.0
                    for idx, it in enumerate(items):
                        acc += it[3]
                        if r < acc:
                            break
                    it = items.pop(idx)
                    pulls_done += 1
                    pay = fee * plat["price"] + (vf / batch if purchaser_vrf else 0.0)
                    paid += pay
                    platform_take += fee * (plat["price"] - plat["pool"])
                    proceeds = fee * plat["pool"]
                    backing_won += it[1]
                    if it[4]:
                        grail_wins += 1
                        backing_won_grail += it[1]
                        grail_fund += proceeds
                        grail_capture_proceeds += proceeds
                        continue
                    counts[it[0]] -= 1
                    booked += 1
                    receivable += proceeds
                    margin += proceeds - it[1]
                    mint_line += FEE * ROW_N[it[0]]
                    row = choose_row(rnd, [counts[i] + queue.count(i) for i in range(len(ROWS))])
                    if row is not None:
                        queue.append(row)
            cash += receivable
            receivable = 0.0
            if margin > 0:
                cover = min(margin, mint_line)
                mint_line -= cover
                rest = margin - cover
                tot = sum(split)
                m = rest * split[1] / tot
                f = rest * split[2] / tot
                cash -= m + f
                maint_booked += m
                maint_bal += m
                feed_total += f
                grail_fund += f
                premium += rest - m - f
                margin = 0.0
            restocked = 0
            while queue:
                row = queue[0]
                cost = row_b[row] + FEE * ROW_N[row]
                if cash < cost and reserve > 0:
                    t = min(reserve, max(0.3 - cash, cost - cash))
                    reserve -= t
                    cash += t
                    backstopped += t
                if cash < cost:
                    shortfall += 1
                    break
                cash -= cost
                mint_fees += FEE * ROW_N[row]
                queue.pop(0)
                items.append([row, row_b[row], row_p[row], row_w[row], False, 0])
                counts[row] += 1
                restocked += 1
            if booked or restocked:
                c = ((SETTLE_BASE + SETTLE_PER * max(booked, restocked) + 30_000) * basefee + TIP) / E
                if maint_bal >= c:
                    maint_bal -= c
                    keeper_cost += c
                else:
                    keeper_unpaid += c  # the controller stops refunding; an operator pays
            # GRAIL vault step
            live = [it for it in items if it[4]]
            target = LADDER[0] if (new_policy and not live) else LADDER[level]
            if grail_fund >= target + FEE and len(live) < 4:
                replacement = new_policy and not live and cycle_id != 1
                grail_fund -= target + FEE
                mint_fees += FEE
                grail_backing_minted += target
                notional = target * GRAIL_LIST
                items.append([-1, target, notional, 1e36 // notional, True, pulls_done])
                grails_minted += 1
                if first_grail_minute is None:
                    first_grail_minute = minute
                if cycle_started is not None and not replacement:
                    elapsed = now_days - cycle_started
                    if elapsed < STEP_UP_DAYS and level + 1 < len(LADDER):
                        level += 1
                    elif elapsed > STEP_DOWN_DAYS and level:
                        level -= 1
                cycle_started = now_days
                cycle_id += 1
                live = [it for it in items if it[4]]
            if not live:
                no_grail_minutes += settle_minutes
            sw = sum(it[3] for it in items)
            gw = sum(it[3] for it in live)
            if sw and gw / sw < PROB_CAP:
                for it in live:
                    nxt = max(it[1] * GRAIL_FLOOR, it[2] - GRAIL_DECAY * (pulls_done - it[5]))
                    if it[2] - nxt >= it[2] / 100:
                        it[2], it[3], it[5] = nxt, 1e36 // nxt, pulls_done
        live = [it for it in items if it[4]]
        inventory.append((len(live), sum(it[1] for it in live)))
    backing = sum(it[1] for it in items if not it[4])
    nav = cash + backing
    board_full = sum(counts) >= BOARD and not queue
    surplus = max(0.0, nav - CAPITAL) if board_full else 0.0
    surplus = min(surplus, max(0.0, cash))
    topup = min(surplus, max(0.0, MAINT_FLOOR - maint_bal))
    buyback = surplus - topup
    return dict(pulls=pulls_done, refund_rate=refunded / max(1, requested), paid=paid, won=backing_won,
                won_grail=backing_won_grail, rtp_total=backing_won / max(paid, 1e-18),
                rtp_ordinary=(backing_won - backing_won_grail) / max(paid, 1e-18), premium=premium,
                maint=maint_booked, maint_bal=maint_bal, keeper=keeper_cost, keeper_unpaid=keeper_unpaid,
                feed=feed_total, grail_trading=grail_from_trading, grail_capture=grail_capture_proceeds,
                grails=grails_minted, grail_backing=grail_backing_minted, grail_wins=grail_wins,
                no_grail_h=no_grail_minutes / 60, first_grail_h=(first_grail_minute or 14 * 1440 + 1) / 60,
                grail_odds=weight_share_sum / max(1, weight_share_n), inventory=inventory, nav=nav,
                surplus=surplus, buyback=buyback, topup=topup, mint_fees=mint_fees, vrf_collected=vrf_collected,
                vrf_billed=vrf_billed, pol=pol, backstopped=backstopped, shortfall=shortfall, reserve=reserve,
                player_loss=paid - backing_won, platform_take=platform_take)


def med(xs):
    s = sorted(xs)
    return s[len(s) // 2]


def pct(xs, p):
    s = sorted(xs)
    return s[min(len(s) - 1, int(p * len(s)))]


def run(cfg, pulls, vol, basefee, seeds, settle=5, platform=None):
    args = [(cfg, pulls, vol, basefee, settle,
             int(hashlib.sha256(f"{cfg[0]}/{pulls}/{vol}/{i}".encode()).hexdigest()[:8], 16)) + ((platform,) if platform else ())
            for i in range(seeds)]
    with MP(4) as mp:
        res = mp.map(simulate, args, chunksize=max(1, seeds // 16))
    out = {k: med([r[k] for r in res]) for k in res[0] if k != "inventory"}
    out["no_grail_h_p90"] = pct([r["no_grail_h"] for r in res], 0.9)
    out["buyback_p10"] = pct([r["buyback"] for r in res], 0.1)
    out["buyback_mean"] = sum(r["buyback"] for r in res) / seeds
    out["p_buyback_zero"] = sum(1 for r in res if r["buyback"] <= 0) / seeds
    out["inventory"] = [(sum(r["inventory"][d][0] for r in res) / seeds, sum(r["inventory"][d][1] for r in res) / seeds)
                        for d in range(14)]
    out["p_shortfall"] = sum(1 for r in res if r["shortfall"]) / seeds
    out["keeper_unpaid_mean"] = sum(r["keeper_unpaid"] for r in res) / seeds
    return out


def f(x, d=4):
    return f"{x:.{d}f}"


def farming_section(ex):
    """Competitive genesis farming (sim/farming.py, 25M farm, 2 % fee, farmers sell everything): farmers
    pull until the ETH their ENGINE realises equals their loss, so total farmer loss equals realised
    rewards in every config; a cheaper pull buys more pulls, and the game's flows scale with pulls."""
    import farming
    out = ["## 5. Genesis farming equilibrium (sim/farming.py market model; 25M farm, 2 % fee)\n",
           "Loss per pull = fee + settlement + VRF share (10-pull batch, 0.01 gwei) - expected backing + 0.00002 "
           "ETH wallet gas. Farmer loss over 14 days equals the ETH their ENGINE realises (identical across configs "
           "for a given outside-buying level); the configs differ in how many pulls that loss buys and where the "
           "ETH goes. 14-day totals in ETH.\n",
           "| outside buying (ETH/day) | config | loss / pull | pulls/day | farmer loss | creator mint fees | premium | "
           "maintenance | GRAIL feed | Token Works | referrer + dev |", "|" + "---|" * 11]
    for buy in (0.0, 0.3, 0.7, 1.5):
        for x in ex:
            if x["name"] in BENCH:
                continue
            loss = (x["fee"] + x["sfee"] + x["vrf10"] / 10 - x["eb"]) / E + farming.GAS_PER_PULL
            farming.LOSS = loss
            r = farming.run(25e6, buy)
            n = r["pulls_total"]
            out.append(f"| {buy} | {x['name']} | {loss:.6f} | {n / 14:.0f} | {r['farmer_eth']:.3f} | "
                       f"{n * x['mint_line'] / E:.3f} | {n * x['premium'] / E:.3f} | {n * x['maint'] / E:.3f} | "
                       f"{n * x['feed'] / E:.3f} | {n * x['tw'] / E:.4f} | {n * (x['ref'] + x['dev']) / E:.3f} |")
    return out


def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    lines = ["# Follow-up economics: before / after (generated by sim/followup.py)\n"]
    lines += ["## 1. Exact per-pull values on the reference board (wei, integer math as in the contracts)\n",
              "VRF fee at basefee 0.01 gwei. `RTP` = expected ETH backing received / (fee + settlement fee); "
              "`RTP incl. VRF (×10)` adds the per-pull share of a 10-pull batch's VRF fee. Margin waterfall: "
              "expected values per pull before the GRAIL/treasury layer.\n",
              "| config | notionals (ETH) | acquisition fee | settlement fee | fee + settlement | VRF 1 pull / 10-pull batch | "
              "E[backing] | RTP | RTP incl. VRF (×1 / ×10) | mint line | premium | maintenance | GRAIL feed | "
              "referrer / Token Works / dev |", "|" + "---|" * 14]
    ex = [exact(c) for c in CONFIGS]
    for x in ex:
        lines.append(" | ".join([
            f"| {x['name']}", " / ".join(f"{p / E:.5f}" for p in x["notionals"]), f"{x['fee']:,}", f"{x['sfee']:,}",
            f"{x['price']:,} ({x['price'] / E:.6f})", f"{x['vrf1'] / E:.7f} / {x['vrf10'] / E:.7f}",
            f"{x['eb']:,}", f"{100 * x['rtp']:.2f} %", f"{100 * x['rtp_vrf1']:.2f} / {100 * x['rtp_vrf10']:.2f} %",
            f"{x['mint_line'] / E:.6f}", f"{x['premium'] / E:.6f}", f"{x['maint'] / E:.6f}", f"{x['feed'] / E:.6f}",
            f"{x['ref'] / E:.7f} / {x['tw'] / E:.7f} / {x['dev'] / E:.7f} |"]))
    lines.append("")
    # VRF and keeper cost per pull vs maintenance, at several basefees
    lines += ["## 2. Per-pull VRF and keeper cost vs the maintenance allocation\n",
              "Oracle gas price = basefee × 1.2. Keeper: one settle per 10 booked pulls, (250k + 690k × 10 + 30k) gas × "
              "basefee + 0.00001 ETH tip, per pull. `previous` pays VRF from maintenance; the others charge it to the "
              "purchaser (collected ≥ billed in every row: Followup.t.sol, BaseVrfFork.t.sol).\n",
              "| basefee (gwei) | VRF bill / pull (10-batch) | VRF fee collected / pull | keeper / pull | "
              + " | ".join(f"maintenance / pull: {x['name']}" for x in ex) + " |", "|" + "---|" * (4 + len(ex))]
    for bf in (0.005, 0.01, 0.05, 0.2):
        b = int(bf * GWEI)
        bill = vrf_bill(10, b * 12 // 10) / 10 / E
        coll = vrf_fee(10, b) / 10 / E
        keeper = ((SETTLE_BASE + SETTLE_PER * 10 + 30_000) * b + TIP) / 10 / E
        cells = []
        for x, c in zip(ex, CONFIGS):
            need = keeper + (0 if c[5] else bill)
            cells.append(f"{x['maint'] / E:.7f} ({x['maint'] / E / need:.1f}× cost)")
        lines.append(f"| {bf} | {bill:.7f} | {coll:.7f} | {keeper:.7f} | " + " | ".join(cells) + " |")
    lines.append("")

    lines += ["## 3. 14-day Monte Carlo: pool, GRAILs, treasury, VRF, keepers, buyback budget\n",
              f"{seeds} seeds per row, keeper every 5 minutes, batches of 10, basefee 0.01 gwei. `trading` = ENGINE "
              "volume in ETH/day (the treasury receives 1.75 %). Medians unless stated. `GRAIL ETH (feed / trading / "
              "capture)` are transfers into the GRAIL fund, not earnings. `buyback` = realised surplus after the "
              "maintenance floor top-up at genesis end (median; p10; share of runs with none).\n"]
    cols = ["config", "pulls/day", "trading", "pulls", "player net cost", "RTP total (ordinary)", "creator mint fees",
            "premium", "maintenance (keeper paid / unpaid)", "VRF collected / billed", "GRAIL ETH feed / trading / capture",
            "GRAILs minted (backing)", "GRAIL wins", "first GRAIL (h)", "hours w/o GRAIL (p50 / p90)", "GRAIL odds",
            "NAV", "buyback p50 / p10 / P(0)"]
    lines += ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    inv_lines = []
    for cfg in CONFIGS:
        for pulls in (100, 300, 750):
            for vol in (0, 1, 3, 10):
                if cfg[0] in BENCH and vol not in (0, 3):
                    continue
                r = run(cfg, pulls, vol, 0.01, seeds)
                lines.append(" | ".join([
                    f"| {cfg[0]}", str(pulls), str(vol), f"{r['pulls']}", f(r["player_loss"], 3),
                    f"{100 * r['rtp_total']:.2f} % ({100 * r['rtp_ordinary']:.2f} %)", f(r["mint_fees"], 3),
                    f(r["premium"], 3), f"{f(r['maint'], 3)} ({f(r['keeper'], 3)} / {f(r['keeper_unpaid_mean'], 3)})",
                    f"{f(r['vrf_collected'], 4)} / {f(r['vrf_billed'], 4)}",
                    f"{f(r['feed'], 3)} / {f(r['grail_trading'], 3)} / {f(r['grail_capture'], 3)}",
                    f"{r['grails']} ({f(r['grail_backing'], 1)})", str(r["grail_wins"]), f(r["first_grail_h"], 0),
                    f"{f(r['no_grail_h'], 0)} / {f(r['no_grail_h_p90'], 0)}", f"{100 * r['grail_odds']:.2f} %",
                       f(r["nav"], 3), f"{f(r['buyback'], 3)} / {f(r['buyback_p10'], 3)} / "
                    f"{100 * r['p_buyback_zero']:.0f} % |"]))
                if pulls == 300 and vol in (0, 3) and cfg[0] != BENCH[0]:
                    inv_lines.append(f"| {cfg[0]} | {vol} | " + " | ".join(
                        f"{n:.2f} ({b:.2f})" for n, b in r["inventory"]) + " |")
    lines.append("")
    lines += ["## 4. GRAIL inventory over time (300 pulls/day; mean live GRAILs (mean live GRAIL backing ETH) at each day's end)\n",
              "| config | trading | " + " | ".join(f"d{d + 1}" for d in range(14)) + " |", "|" + "---|" * 16] + inv_lines
    lines += ["", *farming_section(ex)]
    path = os.path.join(os.path.dirname(__file__), "results", "followup.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
