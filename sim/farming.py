#!/usr/bin/env python3
"""Genesis farming economics: how many paid pulls a finite ENGINE allocation can buy.

Model (all inputs are assumptions, not forecasts):
- The ETH/ENGINE pool starts with LIQ_ETH and LIQ_TOKENS (one full-range v4 position, LP fee 0, hook
  fee on the ETH side; `market.Pool` reproduces the v4 run to ~1e-15).
- Outside speculators buy `buy_per_day` ETH of ENGINE, spread hourly, for 16 days, and hold.
- Farmers sell `sell_share` of each epoch's allocation hourly over the day after the epoch closes.
- Competitive farmers pull until the ETH they realise from an epoch's rewards equals their all-in
  cost: pulls_d = realised_ETH(epoch d) / (loss_per_pull * (1 + required_margin)).
  The loss per pull is the reference-board payment minus expected backing plus wallet gas.
- Per pull the game books (reference board, docs/ENGINE.md): replacement mint fees 0.001226 ETH to
  the creator, premium 0.000449, maintenance 0.000064, GRAIL feed 0.000385, settlement fee 0.000149
  (launch: premium 3.5 %, maintenance 0.5 %, feed 3 %; the purchaser's VRF fee goes to Chainlink).
Writes sim/results/farming.md.
"""
import os
from market import Pool

LIQ_ETH = 2.0
LIQ_TOKENS = 10e6
PAYMENT = 0.015092 + 0.0000056  # fee + settlement + VRF share of a 10-pull batch at 0.01 gwei (launch 3.5/0.5/3)
EXPECTED_BACKING = 0.012819
GAS_PER_PULL = 0.00002  # batched acquire + share of settle on Base; measured order 1e-6, kept conservative
LOSS = PAYMENT - EXPECTED_BACKING + GAS_PER_PULL
PER_PULL = {"mint_fees": 0.001226, "premium": 0.000449, "maintenance": 0.000064, "feed": 0.000385,
            "settlement": 0.000149}

HERE = os.path.dirname(os.path.abspath(__file__))


def run(farm, buy_per_day, fee_bps=200, sell_share=1.0, margin=0.0, days=16, reinvest=1.0, loss=None):
    loss = LOSS if loss is None else loss
    pool = Pool(LIQ_ETH, LIQ_TOKENS, fee_bps)
    per_epoch = farm / 14
    realised = [0.0] * 15  # realised ETH of epoch e's rewards
    nominal = [0.0] * 15   # value of epoch e's rewards at the spot price when the epoch closes
    for day in range(days):
        epoch = day - 1
        to_sell = per_epoch * sell_share if 0 <= epoch < 14 else 0.0
        if 0 <= epoch < 14:
            nominal[epoch] = per_epoch * pool.price()
        for _ in range(24):
            if buy_per_day:
                pool.buy(buy_per_day / 24)
            if to_sell:
                realised[epoch] += pool.sell(to_sell / 24)
    # farmers put `reinvest` of the ETH their ENGINE realises into pulls (1.0 = competitive equilibrium)
    pulls = [reinvest * realised[e] / (loss * (1 + margin)) for e in range(14)]
    total = sum(pulls)
    out = {
        "pulls_total": total,
        "pulls_per_day": total / 14,
        "farmer_eth": sum(realised[:14]),
        "nominal_eth": sum(nominal[:14]),
        "spend": total * PAYMENT,
        "end_price": pool.price(),
        "end_pool_eth": pool.x,
        "hook_fees": pool.fees,
        "operator_fees": pool.operator,
        "treasury_fees": pool.fees - pool.operator,
        "buyer_tokens": LIQ_TOKENS - pool.y + farm * sell_share,  # circulating outside the pool
        "unsold_farmer_tokens": farm * (1 - sell_share),
        # where farmer ETH comes from: outside buyers' ETH (net of hook fees) or the opening liquidity
        "external_eth": buy_per_day * days,
        "liquidity_drained": LIQ_ETH - pool.x,
        "farmer_kept": (1 - reinvest) * sum(realised[:14]),
    }
    for k, v in PER_PULL.items():
        out[k] = total * v
    out["grail_from_trading"] = out["treasury_fees"] * 0.9
    out["grail_total"] = out["feed"] + out["grail_from_trading"]
    out["first_order"] = buy_per_day / LOSS
    return out


def table(rows, cols):
    head = "| " + " | ".join(c[0] for c in cols) + " |\n|" + "---|" * len(cols) + "\n"
    return head + "\n".join("| " + " | ".join(c[1](r) for c in cols) + " |" for r in rows) + "\n"


def main():
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    lines = ["# Genesis farming economics\n",
             f"Loss per pull (all-in): {LOSS:.6f} ETH = payment {PAYMENT} − expected backing {EXPECTED_BACKING} + gas {GAS_PER_PULL}.",
             f"Opening market: {LIQ_ETH} ETH / {LIQ_TOKENS/1e6:.0f}M ENGINE, spot {LIQ_ETH/LIQ_TOKENS:.1e} ETH per ENGINE.",
             "Outside buying runs 16 days (14 epochs plus two days of sales); buyers hold. Competitive farmers, zero",
             "required margin unless stated. These are model outputs under stated assumptions, not demand forecasts.\n"]
    grid = []
    for farm in (50e6, 35e6, 25e6, 15e6, 10e6):
        for buy in (0.0, 0.3, 0.7, 1.5):
            r = run(farm, buy)
            r.update(farm=farm, buy=buy)
            grid.append(r)
    cols = [("Farm", lambda r: f"{r['farm']/1e6:.0f}M"), ("Buys/day", lambda r: f"{r['buy']:.1f}"),
            ("First-order pulls/day", lambda r: f"{r['first_order']:.0f}"),
            ("Model pulls/day", lambda r: f"{r['pulls_per_day']:.0f}"),
            ("Farmer ETH realised", lambda r: f"{r['farmer_eth']:.2f}"),
            ("Nominal reward value", lambda r: f"{r['nominal_eth']:.2f}"),
            ("Creator mint fees", lambda r: f"{r['mint_fees']:.2f}"),
            ("Premium", lambda r: f"{r['premium']:.3f}"),
            ("GRAIL feed + trading", lambda r: f"{r['grail_total']:.2f}"),
            ("Operator 0.25%", lambda r: f"{r['operator_fees']:.3f}"),
            ("End price (1e-7 ETH)", lambda r: f"{r['end_price']*1e7:.2f}"),
            ("End pool ETH", lambda r: f"{r['end_pool_eth']:.2f}")]
    lines.append("## Allocation × outside buying (2 % fee, farmers sell everything)\n")
    lines.append(table(grid, cols))

    lines.append("## Fee level: 2 % vs 5 % (25M allocation, 0.7 ETH/day)\n")
    lines.append("Same buying assumed for both, which flatters 5 %: a higher fee also pushes trades to rival pools "
                 "(test/unit/Bypass.t.sol) and away from the token.\n")
    fees = []
    for fee, elasticity in ((200, 0.0), (500, 0.0), (500, 0.25), (500, 0.5)):
        if True:
            buy = 0.7 * (1 - elasticity * (fee - 200) / 300)
            r = run(25e6, buy, fee)
            r.update(fee=fee, buyx=buy, el=elasticity)
            fees.append(r)
    lines.append(table(fees, [("Fee", lambda r: f"{r['fee']/100:.0f} %"),
                              ("Buying lost to the higher fee", lambda r: f"{r['el']*100 if r['fee']==500 else 0:.0f} %"),
                              ("Buys/day", lambda r: f"{r['buyx']:.3f}"),
                              ("Hook fees", lambda r: f"{r['hook_fees']:.3f}"),
                              ("Operator", lambda r: f"{r['operator_fees']:.3f}"),
                              ("Treasury", lambda r: f"{r['treasury_fees']:.3f}"),
                              ("Farmer ETH", lambda r: f"{r['farmer_eth']:.2f}"),
                              ("Pulls/day", lambda r: f"{r['pulls_per_day']:.0f}")]))

    lines.append("## Farmer behaviour (25M, 0.7 ETH/day, 2 %)\n")
    beh = []
    for share, margin in ((1.0, 0.0), (1.0, 0.25), (0.5, 0.0), (0.25, 0.0)):
        r = run(25e6, 0.7, 200, share, margin)
        r.update(share=share, margin=margin)
        beh.append(r)
    lines.append(table(beh, [("Sold share", lambda r: f"{r['share']*100:.0f} %"),
                             ("Required margin", lambda r: f"{r['margin']*100:.0f} %"),
                             ("Pulls/day", lambda r: f"{r['pulls_per_day']:.0f}"),
                             ("Farmer ETH", lambda r: f"{r['farmer_eth']:.2f}"),
                             ("Unsold farmer ENGINE", lambda r: f"{r['unsold_farmer_tokens']/1e6:.1f}M"),
                             ("End price (1e-7)", lambda r: f"{r['end_price']*1e7:.2f}"),
                             ("End pool ETH", lambda r: f"{r['end_pool_eth']:.2f}")]))
    lines.append("## Sensitivity: partial reinvestment and the source of farmer ETH (25M, 2 %, farmers sell everything)\n")
    lines.append("The equilibrium above assumes farmers put all realised ENGINE proceeds into pulls. Here only "
                 "`reinvest` of it is; the rest leaves the system as farmer profit. Farmer ETH comes from outside "
                 "buyers (external ETH, net of hook fees) and, where buying is weak, from draining the opening "
                 "2 ETH of liquidity (`liquidity drained`, negative = the pool ended with more ETH). Creator mint fees "
                 "are model outputs scaled from pulls, not expected revenue: they exist only if outside buyers bring "
                 "that ETH and farmers spend it on pulls. Loss per pull for each configuration includes the VRF share.\n")
    sens = []
    configs = (("current 4/0.5/2", 0.015032891 - 0.012819638 + GAS_PER_PULL),
               ("alternative 3.5/0.5/3", 0.015097445 - 0.012819466 + GAS_PER_PULL))
    for buy in (0.0, 0.3, 0.7, 1.5):
        for name, loss in configs:
            for reinvest in (1.0, 0.75, 0.5, 0.25):
                r = run(25e6, buy, reinvest=reinvest, loss=loss)
                r.update(buy=buy, cfg=name, reinvest=reinvest, loss=loss)
                sens.append(r)
    lines.append(table(sens, [("Outside buying ETH/day", lambda r: f"{r['buy']:.1f}"),
                              ("Config", lambda r: r["cfg"]),
                              ("Loss / pull", lambda r: f"{r['loss']:.6f}"),
                              ("Reinvest", lambda r: f"{r['reinvest']*100:.0f} %"),
                              ("Pulls/day", lambda r: f"{r['pulls_per_day']:.0f}"),
                              ("Farmer ETH realised", lambda r: f"{r['farmer_eth']:.2f}"),
                              ("of which kept", lambda r: f"{r['farmer_kept']:.2f}"),
                              ("External ETH in", lambda r: f"{r['external_eth']:.2f}"),
                              ("Liquidity drained", lambda r: f"{r['liquidity_drained']:.2f}"),
                              ("Creator mint fees (model)", lambda r: f"{r['pulls_total'] * 0.0012256:.2f}"),
                              ("Premium", lambda r: f"{r['pulls_total'] * (0.000513 if r['cfg'].startswith('current') else 0.000449):.3f}"),
                              ("GRAIL feed", lambda r: f"{r['pulls_total'] * (0.000256 if r['cfg'].startswith('current') else 0.000385):.3f}")]))
    path = os.path.join(HERE, "results", "farming.md")
    open(path, "w").write("\n".join(lines))
    print(open(path).read())


if __name__ == "__main__":
    main()
