# Play session through the live site (Base Sepolia, v2 contracts)

Run on 2026-10-26 with `web/scripts/session-e2e.mjs` against https://draw-shapes-base-sepolia.netlify.app, using a
headless browser with an injected wallet signing as the testnet player (`0x14665897E9bA3268Ddc973Ff2014449571E8b60e`).
Contracts: `deployments/84532.json` (engine `0xA12D21f106962d79ef25af3fC9Ba0b17f5F68418`, PrizeRouter
`0xab375876fb70c603d4AF8215118e42E604fD2BF5`).

| Step | Result |
| --- | --- |
| Sat down | Stack 0.2755 ETH: wallet 0.1259, 3 prizes to play at face 0.03, refund credit 0.1196 |
| Pull 1, paid with prizes | Site planned "Paid with 2 prizes (0.02 ETH at face); 0.00239 ETH change". One transaction, [0x9aaddd70…](https://sepolia.basescan.org/tx/0x9aaddd70a19ab389f4eec2915a587ca8c49865e5fb27daac162343f17fce6aa4), gas 552,439; wallet received 0.002382 ETH of change after gas |
| Reveal | Shape #57 (0.01 ETH) delivered about 5 s after the request (VRF callback) |
| Keep | One prize marked Keep (stored in this browser) and excluded from spending and cash out |
| Cash out | "Cash out 1 prizes (0.01 ETH)", one transaction, [0xaf156c89…](https://sepolia.basescan.org/tx/0xaf156c89670a7551a7324dc2947f9f1d20303efa7d49410c12f9239c7270aefc), gas 100,912; 0.009999 ETH received after gas |
| Final | Stack 0.2579 ETH; kept 0.01 ETH; no playable prizes left |

Screenshots: `evidence/web/v2-session-1-sat-down.jpg`, `v2-session-2-revealed.jpg`, `v2-session-3-after-cashout.jpg`.

Refund credit is applied automatically only to direct pulls (`msg.sender == purchaser`); a pull through the PrizeRouter
does not draw on it. The site shows the credit in the stack, and the next wallet-paid pull uses it.
