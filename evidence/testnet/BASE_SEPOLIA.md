# Base Sepolia live deployment — status

**Not executed live yet.** This session had no funded Base Sepolia signer, and faucets could not be used
autonomously: QuickNode and Alchemy need an account and a captcha, and the Coinbase CDP faucet needs an API
key. Nothing below is claimed as live testnet evidence.

## What is ready and verified

- **Runner.** `script/testnet/sepolia.sh` runs `web/scripts/testnet.mjs`. It is resumable and runs:
  1. VRF subscription creation and funding;
  2. the production `Deploy.s.sol`;
  3. engine consumer registration;
  4. an opening GRAIL funded with test ETH;
  5. timelock activation, waiting the real 600 s delay;
  6. a post-activation governance batch;
  7. the live scenarios (single pull, batch of ten, real VRF fulfilment with oracle charge and latency,
     deliveries, keeper booking and restocking, GRAIL decay and odds, slippage refunds, purchase on behalf,
     referral, ENGINE trading and fee routing, genesis ledger, outage with two concurrent keepers, prize
     redemption);
  8. claims, once epoch 0 has ended in real time (rerun after 24 h).
- **Report.** `node web/scripts/testnet-report.mjs evidence/testnet/84532-run.json > evidence/testnet/BASE_SEPOLIA.md`
  replaces this file with the live report.
- **Rehearsal.** The identical flow ran end to end on a local fork of Base Sepolia
  (`BASE_SEPOLIA_FORK_REHEARSAL.md`, labelled as fork evidence). It found and fixed:
  - the cold-state VRF callback stipend (engine);
  - a 256-bit VRF subscription id truncated by JSON numbers (runner);
  - a postflight board-count check (deploy script);
  - keeper priority-fee economics;
  - the buyback minimum on a scaled market.
- **Live chain checks.** Read-only, against Base Sepolia on 2026-10-25:
  - coordinator `0x5C210eF4…7BEE`: max callback gas 2.5M, native premium 60 %;
  - key hash `0x9e1344a1…bf71`: registered;
  - PoolManager `0x05E73354…3408`: has code;
  - CREATE2 factory: present;
  - gas price ≈ 0.006 gwei.

## The one action needed

Send **2.0 Base Sepolia ETH** to the testnet deployer `0x79F8829fB147658D537001ECbC535b22df31cFcB`, then run
`script/testnet/sepolia.sh`. 1.5 ETH is enough without the opening GRAIL (`SEED_GRAIL=0`).

Breakdown of the 2.0 ETH:

| Use | ETH |
| --- | --- |
| Pool | 0.7 |
| Treasury reserve | 0.15 |
| Market | 0.2 |
| Shapes seed | 0.01 |
| Maintenance float | 0.01 |
| VRF subscription | 0.03 |
| Opening GRAIL | 0.501 |
| Player | 0.7 |
| Gas | < 0.1 |

That key exists only in this session's container
(`~/.foundry/keystores/sepolia-deployer`, encrypted). If the container has been reclaimed, use your own
testnet key instead:

```
IMPORT_KEY=1 script/testnet/sepolia.sh
```

This prompts (hidden input) for a Base Sepolia key, stores it encrypted, prints only the address and runs
everything. The key never appears on a command line, in logs or in the repository.
