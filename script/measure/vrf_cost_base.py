#!/usr/bin/env python3
"""Measure what Chainlink VRF v2.5 fulfilments actually cost on Base mainnet.

Reads RandomWordsFulfilled events of the Base VRF v2.5 coordinator over a recent block window and,
for every native-payment fulfilment, the fulfilment transaction's receipt. Reports the payment the
coordinator charged the subscription (the cost a consumer bears), the fulfilment gas and gas price.
Usage: python3 script/measure/vrf_cost_base.py [rpc] [blocks] > evidence/vrf/base-mainnet-fulfilments.md
"""
import json, sys, urllib.request, statistics, time

RPC = sys.argv[1] if len(sys.argv) > 1 else "https://base-rpc.publicnode.com"
WINDOW = int(sys.argv[2]) if len(sys.argv) > 2 else 40000
COORD = "0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634"
FULFILLED = "0xaeb4b4786571e184246d39587f659abf0e26f41f6a3358692250382c0cdb47b7"

def rpc(method, params):
    req = urllib.request.Request(RPC, json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
                                 {"content-type": "application/json", "user-agent": "curl/8"})
    for i in range(5):
        try:
            r = json.loads(urllib.request.urlopen(req, timeout=30).read())
            if "error" in r: raise RuntimeError(r["error"])
            return r["result"]
        except Exception as e:
            if i == 4: raise
            time.sleep(1 + i)

head = int(rpc("eth_blockNumber", []), 16)
logs = []
step = 5000
for start in range(head - WINDOW, head, step):
    logs += rpc("eth_getLogs", [{"address": COORD, "topics": [FULFILLED], "fromBlock": hex(start), "toBlock": hex(min(start + step - 1, head))}])

rows = []
for lg in logs[-120:]:
    d = lg["data"][2:]
    payment = int(d[64:128], 16)
    native = int(d[128:192], 16) == 1
    success = int(d[192:256], 16) == 1
    if not native: continue
    rc = rpc("eth_getTransactionReceipt", [lg["transactionHash"]])
    gas = int(rc["gasUsed"], 16)
    price = int(rc["effectiveGasPrice"], 16)
    l1 = int(rc.get("l1Fee", "0x0"), 16)
    rows.append((int(lg["blockNumber"], 16), payment, gas, price, l1, success))

print(f"# Chainlink VRF v2.5 fulfilment cost on Base mainnet\n")
print(f"Coordinator `{COORD}`, blocks {head-WINDOW} to {head}, measured {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}.")
print(f"Native-payment fulfilments sampled: {len(rows)} (all consumers on the coordinator, not this project).\n")
if rows:
    pay = [r[1] for r in rows]
    gas = [r[2] for r in rows]
    gp = [r[3] for r in rows]
    tx = [r[2]*r[3] + r[4] for r in rows]
    q = lambda xs, p: sorted(xs)[min(len(xs)-1, int(p*len(xs)))]
    print("| Measure | p10 | median | p90 | max |\n|---|---|---|---|---|")
    for name, xs, fmt in [("Subscription charge (ETH)", pay, lambda v: f"{v/1e18:.8f}"),
                          ("Fulfilment tx gas", gas, lambda v: f"{v:,}"),
                          ("Effective gas price (gwei)", gp, lambda v: f"{v/1e9:.6f}"),
                          ("Fulfilment tx cost incl. L1 fee (ETH)", tx, lambda v: f"{v/1e18:.8f}")]:
        print(f"| {name} | {fmt(q(xs,.1))} | {fmt(statistics.median(xs))} | {fmt(q(xs,.9))} | {fmt(max(xs))} |")
    print("\n| block | charge (wei) | gas | gas price (wei) | l1 fee (wei) | callback ok |\n|---|---|---|---|---|---|")
    for r in rows[-40:]:
        print(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} |")
