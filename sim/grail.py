#!/usr/bin/env python3
"""GRAIL availability, configuration comparison and keeper-outage model (event-driven).

Mirrors the contracts more closely than sim/bankroll.py and sim/followup.py:
- every batch is priced from the board as it stands when `acquireBatch` runs (harmonic mean of
  ACTIVE listings), and its VRF word arrives after a random latency (out-of-order callbacks
  included); acquisitions are processed strictly in sequence order, only once the head's word is
  in, by the callback fast path (measured capacity: k <= 5 -> k, larger batches -> 7) and otherwise
  by the next callback or a keeper's settle; slippage guard +10 % / -10 % at processing; an empty
  board refunds; `maxUnsettledAcquisitions` 250;
- listings made while acquisitions are outstanding are staged and become selectable with the next
  request (up to 6 per acquisition), as in DrawEngine;
- keepers (controller.settle(50) per call, 40 listings per call) book, harvest, split margin,
  mint replacements from cash (treasury backstop to 0.3 ETH from the 0.5 ETH reserve), and step
  the GRAIL vault when `stepDue()`; keeper gas is refunded from maintenance when a call lists;
- GrailVault: minted only when fully funded (backing + 0.001 ETH); listed at 80 % of backing;
  decays 0.00002 ETH per processed pull to 50 %, never past the 5 % probability cap; repricing
  only while nothing is unsettled and every GRAIL is selectable; replacement first; ladder
  0.5 -> 1 -> 5 ETH stepping up when a cycle is funded in < 3 days, down after > 14 days;
- treasury: 1.75 % of ENGINE volume; reserve to 0.5 ETH, then 100 % to the GRAIL fund while no
  GRAIL is held, else 90 % / 10 % POL;
- surplus: after genesis, NAV above the 2.2 ETH capital, from free cash, with the board full, the
  queue empty and maintenance first restored to 0.05 ETH, is released to the buyback (weekly).

`repricing`: "fixed" (this change: stepDue() reports pending decay; decay clamps at the cap) or
"bug" (before: decay ran only when a step was otherwise due, i.e. at a mint or a capture sync, and
a decay crossing the cap was skipped).

Writes sim/results/grail.md. Usage: python3 sim/grail.py [seeds] [section ...]
"""
import hashlib, heapq, math, os, random, sys
from multiprocessing import Pool as MP

sys.path.insert(0, os.path.dirname(__file__))
from bankroll import ROWS, BOARD, TARGET, choose_row  # noqa: E402

BPS = 10_000
FEE = 0.001
ROW_B = [sum(r) for r, _ in ROWS]
ROW_N = [len(r) for r, _ in ROWS]
LADDER = [0.5, 1.0, 5.0]
LIST, FLOOR, DECAY, CAP = 0.8, 0.5, 0.00002, 0.05
CAPITAL, MAINT_FLOOR, RESERVE, BACKSTOP_FLOOR = 2.2, 0.05, 0.5, 0.3
SETTLE_BASE, SETTLE_PER, TIP = 250_000, 690_000, 1e-5
STEP_GAS, MINT_GAS = 120_000, 450_000
MAX_UNSETTLED, ACTIVATIONS = 250, 6

CONFIGS = {
    "current 4/0.5/2": (400, 50, 200),
    "alternative 3.5/0.5/3": (350, 50, 300),
}


def vrf_fee(k, basefee_gwei):
    limit = min(2_500_000, 100_000 + 650_000 * k)
    return (400_000 + limit) * max(basefee_gwei, 0.005) * 1e-9 * 1.85 + 2e-6


def cb_capacity(k):
    return k if k <= 5 else 7


class Sim:
    def __init__(self, p):
        self.p = p
        prem, maint, feed = CONFIGS[p["config"]]
        self.split = (prem, maint, feed)
        markup = 1 + (prem + maint + feed) / BPS
        self.row_p = [b * markup + FEE * n for b, n in zip(ROW_B, ROW_N)]
        self.rnd = random.Random(p["seed"])
        self.t = 0.0
        self.items = []  # dicts: row, b, p, grail, active, listed_at
        self.counts = [0] * len(ROWS)
        self.cash = 2.2
        self.mint_fees = 0.0
        for i, t in enumerate(TARGET):
            for _ in range(t):
                self._add(i, active=True)
                self.cash -= ROW_B[i] + FEE * ROW_N[i]
                self.mint_fees += FEE * ROW_N[i]
        self.queue = []
        self.receivable = self.margin = self.mint_line = 0.0
        self.premium = self.maint_booked = self.feed_total = 0.0
        self.maint = 0.0
        self.keeper_cost = self.keeper_unpaid = 0.0
        self.reserve = RESERVE
        self.backstopped = 0.0
        self.grail_fund = 0.0
        self.grail_from_feed = self.grail_from_trading = self.grail_from_capture = 0.0
        self.pol = 0.0
        self.level = 0
        self.cycle_started = None
        self.cycle_id = 1
        self.grails_minted = 0
        self.grail_backing_minted = 0.0
        self.grail_wins = 0
        self.first_grail_h = None
        self.first_selectable_h = None
        self.pending = []  # FIFO of acquisitions: [batch, fee]
        self.words = set()
        self.batch_seq = 0
        self.batch_activate = {}
        self.processed = 0
        self.requested = self.refunded = self.rejected = self.fulfilled = 0
        self.paid = self.vrf_paid = self.won = self.won_grail = 0.0
        self.trading_accrued = 0.0
        self.shortfall_ticks = 0
        self.released = 0.0
        self.released_genesis = 0.0
        self.samples = []
        self.settle_calls = 0
        self.max_queue = 0
        self.min_active = BOARD
        self.min_cash = self.cash
        self.reserve_used_max = 0.0
        self.recovery = None
        self.outage_end = None
        self.recover_calls = 0
        self.recover_cost = 0.0
        self.house_outage = 0.0

    # --------------------------------------------------------------- board helpers
    def _add(self, row, active, grail_backing=None):
        if grail_backing is None:
            it = {"row": row, "b": ROW_B[row], "p": self.row_p[row], "grail": False, "active": active}
            self.counts[row] += 1
        else:
            it = {"row": -1, "b": grail_backing, "p": grail_backing * LIST, "grail": True, "active": active,
                  "listed_at": self.processed}
        self.items.append(it)
        return it

    def _active(self):
        return [it for it in self.items if it["active"]]

    def _fee(self):
        act = self._active()
        if not act:
            return 0.0
        return len(act) / sum(1 / it["p"] for it in act)

    def _staged(self):
        return [it for it in self.items if not it["active"]]

    def _activate(self, n):
        for it in self.items:
            if n <= 0:
                break
            if not it["active"]:
                it["active"] = True
                n -= 1

    def grails(self):
        return [it for it in self.items if it["grail"]]

    # --------------------------------------------------------------- engine
    def arrive(self, k):
        if len(self.pending) + k > MAX_UNSETTLED:
            self.rejected += k
            return
        if not self.pending:
            self._activate(ACTIVATIONS * k)
        fee = self._fee()
        if fee == 0:
            self.rejected += k  # NoActiveListings: the purchase reverts
            return
        self.batch_seq += 1
        b = self.batch_seq
        self.batch_activate[b] = ACTIVATIONS * k
        vf = vrf_fee(k, self.p["basefee"])
        self.vrf_paid += vf
        for _ in range(k):
            self.pending.append([b, fee])
        self.requested += k
        # VRF latency: mostly ~10-30 s, occasionally minutes (out-of-order callbacks)
        lat = self.rnd.expovariate(1 / 15) + 6 if self.rnd.random() > 0.05 else self.rnd.uniform(60, 600)
        heapq.heappush(self.events, (self.t + lat, 2, "cb", (b, k)))

    def callback(self, b, k):
        self.words.add(b)
        self._process(cb_capacity(k))

    def _process(self, cap):
        n = 0
        while self.pending and n < cap:
            b, fee = self.pending[0]
            if b not in self.words:
                return n
            self.pending.pop(0)
            if b in self.batch_activate:
                self._activate(self.batch_activate.pop(b))
            self._settle_one(fee)
            n += 1
        return n

    def _settle_one(self, fee):
        self.processed += 1
        act = self._active()
        if not act:
            self.refunded += 1
            return
        live = len(act) / sum(1 / it["p"] for it in act)
        if live > fee * 1.10 or live < fee * 0.90:
            self.refunded += 1
            return
        r = self.rnd.random() * sum(1 / it["p"] for it in act)
        acc = 0.0
        for it in act:
            acc += 1 / it["p"]
            if r < acc:
                break
        self.items.remove(it)
        self.fulfilled += 1
        self.paid += fee * 1.01
        self.won += it["b"]
        if self.outage_end is not None and self.t < self.outage_end:
            self.house_outage += fee - it["b"]
        if it["grail"]:
            self.grail_wins += 1
            self.won_grail += it["b"]
            self.grail_fund += fee
            self.grail_from_capture += fee
            self.grail_dirty = True
            return
        self.counts[it["row"]] -= 1
        self.receivable += fee
        self.margin += fee - it["b"]
        self.mint_line += FEE * ROW_N[it["row"]]
        row = choose_row(self.rnd, [self.counts[i] + self.queue.count(i) for i in range(len(ROWS))])
        if row is not None:
            self.queue.append(row)

    # --------------------------------------------------------------- keeper
    def keeper(self, now_h):
        bf = self.p["basefee"] * 1e-9
        calls = 0
        cost = 0.0
        # settle until nothing is left to book or list (one call = 50 processed, 40 listed)
        for _ in range(40):
            processed = self._process(50)
            booked = self.receivable > 0
            self._harvest()
            listed = self._restock(40)
            if processed == 0 and listed == 0 and not booked:
                break
            calls += 1
            c = (SETTLE_BASE + SETTLE_PER * max(processed, listed) + 30_000) * bf + TIP
            cost += c
            if listed:
                if self.maint >= c:
                    self.maint -= c
                    self.keeper_cost += c
                else:
                    self.keeper_unpaid += c
            if listed < 40 and not self.pending:
                break
        self.settle_calls += calls
        if self.outage_end is not None and self.recovery is None and self.t >= self.outage_end:
            self.recover_calls += calls
            self.recover_cost += cost
            if not self.queue and sum(self.counts) >= BOARD:
                self.recovery = (self.t - self.outage_end) / 3600
        self._treasury()
        self._vault_step(now_h)
        if self.p["release"] and now_h >= self.next_release_h - 1e-9:
            self._release()
            self.next_release_h += 24 * 7

    def _harvest(self):
        self.cash += self.receivable
        self.receivable = 0.0
        if self.margin > 0:
            cover = min(self.margin, self.mint_line)
            self.mint_line -= cover
            rest = self.margin - cover
            tot = sum(self.split)
            m = rest * self.split[1] / tot
            f = rest * self.split[2] / tot
            self.cash -= m + f
            self.maint += m
            self.maint_booked += m
            self.feed_total += f
            self.grail_fund += f
            self.grail_from_feed += f
            self.premium += rest - m - f
            self.margin = 0.0

    def _restock(self, limit):
        listed = 0
        while self.queue and listed < limit:
            row = self.queue[0]
            cost = ROW_B[row] + FEE * ROW_N[row]
            if self.cash < cost and self.reserve > 0:
                top = min(self.reserve, max(BACKSTOP_FLOOR - self.cash, cost - self.cash))
                self.reserve -= top
                self.cash += top
                self.backstopped += top
                self.reserve_used_max = max(self.reserve_used_max, RESERVE - self.reserve)
            if self.cash < cost:
                self.shortfall_ticks += 1
                break
            self.cash -= cost
            self.mint_fees += FEE * ROW_N[row]
            self.queue.pop(0)
            self._add(row, active=not self.pending)
            listed += 1
        return listed

    def _treasury(self):
        amt = self.trading_accrued
        self.trading_accrued = 0.0
        if not amt:
            return
        top = min(amt, max(0.0, RESERVE - self.reserve))
        self.reserve += top
        rest = amt - top
        if self.p["policy"] == "new" and not self.grails():
            g = rest
        else:
            g = rest * 0.9
        self.grail_fund += g
        self.grail_from_trading += g
        self.pol += rest - g

    def _target(self):
        live = self.grails()
        if self.p["policy"] == "new" and not live:
            return LADDER[0]
        lvl = self.level if not self.p.get("no_stepup") else 0
        return LADDER[lvl]

    def _vault_step(self, now_h):
        live = self.grails()
        # mint (stepDue: fund >= target + fee); optional replacement buffer kept back while one is live
        target = self._target()
        buffer = LADDER[0] + FEE if (self.p.get("buffer") and live) else 0.0
        minted = False
        if self.grail_fund >= target + FEE + buffer and len(live) < 4:
            replacement = self.p["policy"] == "new" and not live and self.cycle_id != 1
            self.grail_fund -= target + FEE
            self.mint_fees += FEE
            self.grail_backing_minted += target
            self._add(-1, active=not self.pending, grail_backing=target)
            self.grails_minted += 1
            if self.first_grail_h is None:
                self.first_grail_h = now_h
            if self.cycle_started is not None and not replacement:
                el = now_h / 24 - self.cycle_started
                if el < 3 and self.level + 1 < len(LADDER):
                    self.level += 1
                elif el > 14 and self.level:
                    self.level -= 1
            self.cycle_started = now_h / 24
            self.cycle_id += 1
            minted = True
        captured = getattr(self, "grail_dirty", False)
        self.grail_dirty = False
        mode = self.p["repricing"]
        if mode == "off":
            return
        if mode == "bug" and not (minted or captured):
            return
        if self.pending:
            return
        live = self.grails()
        if not live or any(not it["active"] for it in live):
            return
        act = self._active()
        total = sum(1 / it["p"] for it in act)
        gw = sum(1 / it["p"] for it in live)
        for it in live:
            old = it["p"]
            tgt = max(it["b"] * FLOOR, old - DECAY * (self.processed - it["listed_at"]))
            if tgt >= old:
                continue
            ow = 1 / old
            others, rest = gw - ow, total - ow
            if mode == "fixed":
                if CAP * rest <= others:
                    continue
                maxw = (CAP * rest - others) / (1 - CAP)
                if maxw <= ow:
                    continue
                tgt = max(tgt, 1 / maxw)
            else:
                nw = 1 / tgt
                if (others + nw) > CAP * (rest + nw):
                    continue
            if old - tgt < old / 100:
                continue
            it["p"] = tgt
            it["listed_at"] = self.processed
            gw, total = others + 1 / tgt, rest + 1 / tgt

    def nav(self):
        return self.cash + sum(it["b"] for it in self.items if not it["grail"]) + self.receivable

    def _release(self):
        if self.queue or sum(self.counts) < BOARD or self.pending:
            return 0.0
        surplus = max(0.0, self.nav() - CAPITAL)
        surplus = min(surplus, max(0.0, self.cash))
        if surplus <= 0:
            return 0.0
        top = min(surplus, max(0.0, MAINT_FLOOR - self.maint))
        self.maint += top
        self.cash -= surplus
        amt = surplus - top
        self.released += amt
        return amt

    def sample(self, h):
        live = self.grails()
        sel = [it for it in live if it["active"]]
        act = self._active()
        tw = sum(1 / it["p"] for it in act) if act else 0
        odds = sum(1 / it["p"] for it in sel) / tw if tw else 0.0
        self.samples.append((h, len(sel), sum(it["b"] for it in sel), len(live), self.grail_fund, odds,
                             sum(1 for it in act if not it["grail"]), len(self.queue), self.cash))
        if sel and self.first_selectable_h is None:
            self.first_selectable_h = h
        self.max_queue = max(self.max_queue, len(self.queue))
        self.min_active = min(self.min_active, sum(1 for it in act if not it["grail"]))
        self.min_cash = min(self.min_cash, self.cash)

    # --------------------------------------------------------------- driver
    def run(self):
        p = self.p
        days = p["days"]
        self.events = []
        batch = p["batch"]
        tick_s = p["keeper_min"] * 60
        out = p.get("outage")  # (start_h, hours)
        if out:
            self.outage_end = (out[0] + out[1]) * 3600
        t = 0.0
        while t < days * 86400:
            heapq.heappush(self.events, (t, 1, "tick", None))
            t += tick_s
        for h in range(days * 24 * 12):
            heapq.heappush(self.events, (h * 300.0 + 1, 3, "sample", None))
        t = 0.0
        while True:
            day = int(t // 86400)
            rate = (p["pulls"] if day < p["genesis_days"] else p["post_pulls"]) / batch / 86400
            if rate <= 0:
                t += 86400
                if t >= days * 86400:
                    break
                continue
            t += self.rnd.expovariate(rate)
            if t >= days * 86400:
                break
            heapq.heappush(self.events, (t, 0, "arr", batch))
        self.next_release_h = p["genesis_days"] * 24
        trade_rate = lambda tt: (p["trading"] if tt < p["genesis_days"] * 86400 else p["post_trading"]) * 0.0175 / 86400
        last = 0.0
        while self.events:
            t, _, kind, arg = heapq.heappop(self.events)
            self.trading_accrued += trade_rate(t) * (t - last)
            last = t
            self.t = t
            if kind == "arr":
                self.arrive(arg)
            elif kind == "cb":
                self.callback(*arg)
            elif kind == "tick":
                if out and out[0] * 3600 <= t < (out[0] + out[1]) * 3600:
                    continue
                self.keeper(t / 3600)
                if p["release"] and abs(t - p["genesis_days"] * 86400) < tick_s and self.released_genesis == 0:
                    self.released_genesis = self.released
            elif kind == "sample":
                self.sample(t / 3600)
        # final keeper pass at the end of the horizon (settle, step, and the genesis-end release)
        self.t = days * 86400
        self.keeper(days * 24)
        if p["release"] and self.released_genesis == 0 and p["genesis_days"] == days:
            self.released_genesis = self.released
        return self.result()

    def result(self):
        s = self.samples
        g_days = self.p["genesis_days"] * 24
        gen = [x for x in s if x[0] < g_days]
        post = [x for x in s if x[0] >= g_days]
        dt = 5 / 60
        no_sel_g = sum(dt for x in gen if x[1] == 0)
        no_sel_p = sum(dt for x in post if x[1] == 0)
        rtp = self.won / max(self.paid + self.vrf_paid, 1e-18)
        # funds idle: GRAIL fund at or above the next target but no mint yet (keeper timing)
        timeline = []
        for d in range(self.p["days"]):
            day = [x for x in s if d * 24 <= x[0] < (d + 1) * 24]
            if day:
                last = day[-1]
                timeline.append((last[1], last[2], last[3], last[4]))
        return dict(
            first_grail_h=self.first_grail_h if self.first_grail_h is not None else float("inf"),
            first_sel_h=self.first_selectable_h if self.first_selectable_h is not None else float("inf"),
            no_sel_genesis_h=no_sel_g, no_sel_post_h=no_sel_p, grails=self.grails_minted,
            grail_backing=self.grail_backing_minted, grail_wins=self.grail_wins,
            feed=self.grail_from_feed, trading=self.grail_from_trading, capture=self.grail_from_capture,
            fund_end=self.grail_fund, rtp=rtp, rtp_ord=(self.won - self.won_grail) / max(self.paid + self.vrf_paid, 1e-18),
            premium=self.premium, mint_fees=self.mint_fees, buyback_genesis=self.released_genesis,
            buyback_total=self.released, nav=self.nav(), shortfall=self.shortfall_ticks,
            reserve_used=self.reserve_used_max, backstopped=self.backstopped, refund_rate=self.refunded / max(1, self.requested),
            reject_rate=self.rejected / max(1, self.requested + self.rejected), min_active=self.min_active,
            max_queue=self.max_queue, min_cash=self.min_cash, keeper_cost=self.keeper_cost,
            keeper_unpaid=self.keeper_unpaid, maint=self.maint, recovery_h=self.recovery,
            recover_calls=self.recover_calls, recover_cost=self.recover_cost, house_outage=self.house_outage,
            fulfilled=self.fulfilled, mean_sel=sum(x[1] for x in gen) / max(1, len(gen)),
            mean_sel_backing=sum(x[2] for x in gen) / max(1, len(gen)),
            mean_odds=sum(x[5] for x in gen) / max(1, len(gen)), timeline=timeline,
            idle_fund_mean=sum(x[4] for x in gen) / max(1, len(gen)),
        )


DEFAULTS = dict(config="current 4/0.5/2", pulls=300, trading=0.0, basefee=0.01, keeper_min=5, batch=10,
                days=14, genesis_days=14, post_pulls=0, post_trading=0.0, repricing="fixed", policy="new",
                release=True, outage=None)


def one(args):
    p, seed = args
    q = dict(DEFAULTS)
    q.update(p)
    q["seed"] = seed
    return Sim(q).run()


def run(p, seeds):
    key = repr(sorted(p.items()))
    args = [(p, int(hashlib.sha256(f"{key}/{i}".encode()).hexdigest()[:8], 16)) for i in range(seeds)]
    with MP(4) as mp:
        return mp.map(one, args, chunksize=max(1, seeds // 16))


def med(xs):
    s = sorted(xs)
    return s[len(s) // 2]


def pct(xs, q):
    s = sorted(xs)
    return s[min(len(s) - 1, int(q * len(s)))]


def fmt_h(x):
    return "never" if x == float("inf") else f"{x:.0f}"


def section_compare(seeds):
    out = ["## A. Current 4/0.5/2 vs alternative 3.5/0.5/3 (fixed repricing, new GRAIL policy)\n",
           f"{seeds} seeds per row; keeper every 5 min; batches of 10; basefee 0.01 gwei; 14-day genesis. ETH. "
           "`GRAIL ETH` = feed / trading / capture proceeds into the fund (transfers, not earnings). "
           "`no GRAIL (h)` = hours of the 336 with no selectable GRAIL (median / p90). `selectable` = mean "
           "selectable GRAILs (mean selectable backing). Buyback = surplus released at genesis end (p50 / p10).\n",
           "| config | pulls/day | trading | RTP total (ordinary) | creator mint fees | premium | buyback p50 / p10 | "
           "GRAIL ETH feed / trading / capture | first GRAIL h (p50 / p90) | no GRAIL h (p50 / p90) | selectable | "
           "GRAILs minted / won | NAV p1 / p50 | P(shortfall) | reserve used p99 |", "|" + "---|" * 15]
    timelines = {}
    for cfg in CONFIGS:
        for pulls in (100, 300, 750):
            for tr in (0, 1, 3, 10):
                r = run(dict(config=cfg, pulls=pulls, trading=tr), seeds)
                fg = [x["first_grail_h"] for x in r]
                out.append(" | ".join([
                    f"| {cfg}", str(pulls), str(tr),
                    f"{100 * med([x['rtp'] for x in r]):.2f} % ({100 * med([x['rtp_ord'] for x in r]):.2f} %)",
                    f"{med([x['mint_fees'] for x in r]):.3f}", f"{med([x['premium'] for x in r]):.3f}",
                    f"{med([x['buyback_genesis'] for x in r]):.3f} / {pct([x['buyback_genesis'] for x in r], 0.1):.3f}",
                    f"{med([x['feed'] for x in r]):.3f} / {med([x['trading'] for x in r]):.3f} / {med([x['capture'] for x in r]):.3f}",
                    f"{fmt_h(med(fg))} / {fmt_h(pct(fg, 0.9))}",
                    f"{med([x['no_sel_genesis_h'] for x in r]):.0f} / {pct([x['no_sel_genesis_h'] for x in r], 0.9):.0f}",
                    f"{sum(x['mean_sel'] for x in r) / seeds:.2f} ({sum(x['mean_sel_backing'] for x in r) / seeds:.2f})",
                    f"{med([x['grails'] for x in r])} / {med([x['grail_wins'] for x in r])}",
                    f"{pct([x['nav'] for x in r], 0.01):.3f} / {med([x['nav'] for x in r]):.3f}",
                    f"{100 * sum(1 for x in r if x['shortfall']) / seeds:.1f} %",
                    f"{pct([x['reserve_used'] for x in r], 0.99):.3f} |"]))
                if pulls == 300 and tr in (0, 3):
                    timelines[(cfg, tr)] = r
    out += ["", "### GRAIL inventory over time (300 pulls/day): mean at each day's end — selectable GRAILs "
            "(selectable backing ETH) / fully funded held / fund accumulating\n",
            "| config | trading | " + " | ".join(f"d{d + 1}" for d in range(14)) + " |", "|" + "---|" * 16]
    for (cfg, tr), r in timelines.items():
        cells = []
        for d in range(14):
            n = sum(x["timeline"][d][0] for x in r) / seeds
            b = sum(x["timeline"][d][1] for x in r) / seeds
            h = sum(x["timeline"][d][2] for x in r) / seeds
            f = sum(x["timeline"][d][3] for x in r) / seeds
            cells.append(f"{n:.2f} ({b:.2f}) / {h:.2f} / {f:.2f}")
        out.append(f"| {cfg} | {tr} | " + " | ".join(cells) + " |")
    return out


def section_post(seeds):
    out = ["", "## B. After genesis: 14 days of genesis then 28 days at lower organic demand\n",
           "Genesis at 300 pulls/day; afterwards `post` pulls/day and 1 ETH/day of trading. Buyback = surplus "
           "released weekly after genesis (p50 / p10). `no GRAIL after` = hours without a selectable GRAIL in the "
           "28 post-genesis days (672 h).\n",
           "| config | genesis trading | post pulls/day | buyback total p50 / p10 | no GRAIL during genesis h | "
           "no GRAIL after h (p50 / p90) | GRAILs won | RTP total |", "|" + "---|" * 8]
    for cfg in CONFIGS:
        for tr in (0, 3):
            for post in (50, 150):
                r = run(dict(config=cfg, pulls=300, trading=tr, days=42, post_pulls=post, post_trading=1.0), seeds)
                out.append(" | ".join([
                    f"| {cfg}", str(tr), str(post),
                    f"{med([x['buyback_total'] for x in r]):.3f} / {pct([x['buyback_total'] for x in r], 0.1):.3f}",
                    f"{med([x['no_sel_genesis_h'] for x in r]):.0f}",
                    f"{med([x['no_sel_post_h'] for x in r]):.0f} / {pct([x['no_sel_post_h'] for x in r], 0.9):.0f}",
                    str(med([x['grail_wins'] for x in r])), f"{100 * med([x['rtp'] for x in r]):.2f} % |"]))
    return out


def section_levers(seeds):
    out = ["", "## C. GRAIL availability levers (300 pulls/day, 14 days)\n",
           "`no GRAIL` = hours without a selectable GRAIL (median / p90); `idle fund` = mean ETH sitting in the "
           "GRAIL fund (accumulating, not on the board). All levers keep GRAILs fully funded before listing.\n",
           "| config | trading | lever | first GRAIL h (p50) | no GRAIL h (p50 / p90) | mean selectable | GRAILs won | "
           "idle fund mean | RTP total | buyback p50 |", "|" + "---|" * 10]
    levers = [
        ("baseline: fixed repricing, new policy", {}),
        ("before the fix: repricing bug", {"repricing": "bug"}),
        ("no decay at all", {"repricing": "off"}),
        ("old treasury / vault policy", {"policy": "old"}),
        ("no ladder step-up during genesis", {"no_stepup": True}),
        ("replacement buffer (hold 0.501 ETH back while one is live)", {"buffer": True}),
        ("keeper every 60 min", {"keeper_min": 60}),
    ]
    for cfg in CONFIGS:
        for tr in (0, 3):
            for name, extra in levers:
                p = dict(config=cfg, pulls=300, trading=tr)
                p.update(extra)
                r = run(p, seeds)
                out.append(" | ".join([
                    f"| {cfg}", str(tr), name, fmt_h(med([x['first_grail_h'] for x in r])),
                    f"{med([x['no_sel_genesis_h'] for x in r]):.0f} / {pct([x['no_sel_genesis_h'] for x in r], 0.9):.0f}",
                    f"{sum(x['mean_sel'] for x in r) / seeds:.2f}", str(med([x['grail_wins'] for x in r])),
                    f"{sum(x['idle_fund_mean'] for x in r) / seeds:.3f}", f"{100 * med([x['rtp'] for x in r]):.2f} %",
                    f"{med([x['buyback_genesis'] for x in r]):.3f} |"]))
    return out


def section_outage(seeds):
    out = ["", "## D. Keeper outages and recovery (current 4/0.5/2, no trading)\n",
           "One outage starting at hour 72 (day 4); otherwise keepers every 5 min. VRF callbacks keep settling "
           "pulls during the outage (callback fast path); only booking, restocking and GRAIL steps stop. "
           "`rejected` = purchases that revert because the board is empty or 250 are unsettled; `refunded` = "
           "accepted pulls refunded (slippage or empty board), fee + settlement fee returned. `min ordinary active` = "
           "fewest selectable ordinary prizes (p1). `recovery` = hours after the keeper returns until the board is "
           "full and the queue empty (p50 / max); `recovery cost` = keeper gas + tips for it (p50). "
           "`house during outage` = expected margin booked on outage pulls (p1, negative = loss to the pool).\n",
           "| pulls/day | outage | basefee gwei | refunded | rejected | min ordinary active p1 | max queue p99 | "
           "min cash p1 | reserve used p99 | P(shortfall) | recovery h p50 / max | recovery calls / cost p50 | "
           "house during outage p1 / p50 |", "|" + "---|" * 13]
    for pulls in (300, 750, 1500):
        for hours in (0, 0.25, 1, 6, 24):
            for bf in ((0.002, 0.01, 0.1) if hours in (0, 24) and pulls == 1500 else (0.01,)):
                p = dict(pulls=pulls, basefee=bf, outage=(72, hours) if hours else None, days=7, genesis_days=7,
                         release=False)
                r = run(p, seeds)
                rec = [x["recovery_h"] for x in r if x["recovery_h"] is not None]
                out.append(" | ".join([
                    f"| {pulls}", f"{hours} h" if hours else "none", str(bf),
                    f"{100 * med([x['refund_rate'] for x in r]):.2f} %", f"{100 * med([x['reject_rate'] for x in r]):.2f} %",
                    str(pct([x['min_active'] for x in r], 0.01)), str(pct([x['max_queue'] for x in r], 0.99)),
                    f"{pct([x['min_cash'] for x in r], 0.01):.3f}", f"{pct([x['reserve_used'] for x in r], 0.99):.3f}",
                    f"{100 * sum(1 for x in r if x['shortfall']) / seeds:.1f} %",
                    (f"{med(rec):.2f} / {max(rec):.2f}" if rec else "—"),
                    f"{med([x['recover_calls'] for x in r])} / {med([x['recover_cost'] for x in r]):.5f}",
                    f"{pct([x['house_outage'] for x in r], 0.01):.3f} / {med([x['house_outage'] for x in r]):.3f} |"]))
    return out


SECTIONS = {"compare": section_compare, "post": section_post, "levers": section_levers, "outage": section_outage}


def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    names = sys.argv[2:] or list(SECTIONS)
    lines = ["# GRAIL availability, configuration comparison and keeper outages (sim/grail.py)\n",
             "Model outputs under the assumptions in the module docstring; not demand forecasts.\n"]
    for n in names:
        lines += SECTIONS[n](seeds)
        print("\n".join(lines[-3:]), flush=True)
    path = os.path.join(os.path.dirname(__file__), "results", f"grail{'-' + '-'.join(names) if sys.argv[2:] else ''}.md")
    open(path, "w").write("\n".join(lines) + "\n")
    print("wrote", path)


if __name__ == "__main__":
    main()
