#!/usr/bin/env python3
"""Constant-product model of the canonical ETH/ENGINE pool with the EngineHook fee rules.

The pool is one full-range Uniswap v4 position with LP fee 0, so within the range it is exactly
x*y = k. The hook takes `fee_bps` of the swap's ETH amount: from the ETH input on exact-input buys
(before the swap) and from the ETH output on exact-input sells (after the swap). `reconcile()`
replays the Foundry run test/sim/MarketSim.t.sol and compares against evidence/market/*.csv.
"""
import csv, os, sys

BPS = 10_000
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


class Pool:
    def __init__(self, eth, tokens, fee_bps=200, operator_bps=25):
        self.x = float(eth)       # ETH reserve
        self.y = float(tokens)    # ENGINE reserve
        self.fee_bps = fee_bps
        self.operator_bps = operator_bps
        self.fees = 0.0
        self.operator = 0.0
        self.volume = 0.0

    def price(self):
        """ETH per ENGINE."""
        return self.x / self.y

    def _charge(self, volume, fee):
        op = min(fee, volume * self.operator_bps / BPS)
        self.operator += op
        self.fees += fee
        self.volume += volume

    def buy(self, eth_in):
        fee = eth_in * self.fee_bps / BPS
        dx = eth_in - fee
        out = self.y * dx / (self.x + dx)
        self.x += dx
        self.y -= out
        self._charge(eth_in, fee)
        return out

    def sell(self, tokens_in):
        gross = self.x * tokens_in / (self.y + tokens_in)
        self.y += tokens_in
        self.x -= gross
        fee = gross * self.fee_bps / BPS
        self._charge(gross, fee)
        return gross - fee

    def quote_sell(self, tokens_in):
        gross = self.x * tokens_in / (self.y + tokens_in)
        return gross * (1 - self.fee_bps / BPS)


def run_grid_scenario(farm, buy_per_day, fee_bps, sell_bps, liq_eth=2.0, liq_tokens=10e6, days=16):
    """Same schedule as MarketSim.t.sol: 24 hourly buys and hourly sales of the previous epoch."""
    p = Pool(liq_eth, liq_tokens, fee_bps)
    per_epoch = farm / 14
    farmer_eth = 0.0
    sold = 0.0
    rows = []
    for day in range(days):
        release = per_epoch if 1 <= day <= 14 else 0.0
        to_sell = release * sell_bps / BPS
        day_eth = 0.0
        for _ in range(24):
            if buy_per_day:
                p.buy(buy_per_day / 24)
            if to_sell:
                day_eth += p.sell(to_sell / 24)
                sold += to_sell / 24
        farmer_eth += day_eth
        rows.append((day, p.price(), p.x, day_eth))
    return p, farmer_eth, sold, rows


def reconcile():
    path = os.path.join(ROOT, "evidence", "market", "summary.csv")
    worst = 0.0
    out = []
    for r in csv.DictReader(open(path)):
        farm = int(r["farm_engine"]) * 1.0
        buy = int(r["buy_per_day_wei"]) / 1e18
        p, feth, sold, _ = run_grid_scenario(farm, buy, int(r["fee_bps"]), int(r["sell_bps"]))
        sol = int(r["farmer_eth"]) / 1e18
        rel = abs(feth - sol) / max(sol, 1e-18)
        worst = max(worst, rel)
        out.append((r["scenario"], sol, feth, rel, int(r["hook_fees"]) / 1e18, p.fees))
    return worst, out


if __name__ == "__main__":
    worst, out = reconcile()
    print("| scenario | farmer ETH (v4, Foundry) | farmer ETH (model) | rel. diff | hook fees (v4) | hook fees (model) |")
    print("|---|---|---|---|---|---|")
    for s, a, b, rel, f1, f2 in out:
        print(f"| {s} | {a:.6f} | {b:.6f} | {rel:.2e} | {f1:.6f} | {f2:.6f} |")
    print(f"\nWorst relative difference: {worst:.2e}")
