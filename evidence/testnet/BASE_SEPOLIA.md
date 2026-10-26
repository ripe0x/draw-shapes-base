# Base Sepolia deployment and live scenarios

Chain 84532, RPC https://sepolia.base.org. Every hash below is a real Base Sepolia transaction. VRF words were delivered by the Chainlink VRF v2.5 coordinator; the timelock delay elapsed in real chain time.

## Contracts

| Contract | Address |
| --- | --- |
| shapes | [`0xDf08b4535247D7F175b185a6ADC4E9271Ca125F8`](https://sepolia.basescan.org/address/0xDf08b4535247D7F175b185a6ADC4E9271Ca125F8) |
| drawPacks | [`0xBFd3D8e3B41D48022dFfFCe39D78D9Bb5eBdE2ba`](https://sepolia.basescan.org/address/0xBFd3D8e3B41D48022dFfFCe39D78D9Bb5eBdE2ba) |
| timelock | [`0xA4a90693E1218Cea8e58Cf96f2314E3F83643627`](https://sepolia.basescan.org/address/0xA4a90693E1218Cea8e58Cf96f2314E3F83643627) |
| engine | [`0xA12D21f106962d79ef25af3fC9Ba0b17f5F68418`](https://sepolia.basescan.org/address/0xA12D21f106962d79ef25af3fC9Ba0b17f5F68418) |
| controller | [`0xdF146f88a566Cbb79fb43300E00193A64545880C`](https://sepolia.basescan.org/address/0xdF146f88a566Cbb79fb43300E00193A64545880C) |
| grailVault | [`0x009A051d543032F25ACd0364cb98320bc73F2110`](https://sepolia.basescan.org/address/0x009A051d543032F25ACd0364cb98320bc73F2110) |
| token | [`0xf269ba7B246165c9F70e49Cd90359aA5964F891F`](https://sepolia.basescan.org/address/0xf269ba7B246165c9F70e49Cd90359aA5964F891F) |
| hook | [`0x5B1667cB1e2cCbC3204a4712B0Fb07d046d860cc`](https://sepolia.basescan.org/address/0x5B1667cB1e2cCbC3204a4712B0Fb07d046d860cc) |
| liquidity | [`0x01D285a9791146be33Ea15D37741C3C1B2a4D4e7`](https://sepolia.basescan.org/address/0x01D285a9791146be33Ea15D37741C3C1B2a4D4e7) |
| farm | [`0x8DE90EE3aF9c778773dc23Bc3DD6549db126402B`](https://sepolia.basescan.org/address/0x8DE90EE3aF9c778773dc23Bc3DD6549db126402B) |
| treasury | [`0x5Fae92ef4E76a40D37AEA6d9bFF09bdb7C65D63a`](https://sepolia.basescan.org/address/0x5Fae92ef4E76a40D37AEA6d9bFF09bdb7C65D63a) |
| buyback | [`0x23aB84Ce46b4f553f3947f32c6CA2b8DE31C226C`](https://sepolia.basescan.org/address/0x23aB84Ce46b4f553f3947f32c6CA2b8DE31C226C) |
| lens | [`0x5f2b85D1f6B145feB0D8948535373B337F79feb4`](https://sepolia.basescan.org/address/0x5f2b85D1f6B145feB0D8948535373B337F79feb4) |

Deployment: 39 transactions, 57,662,857 gas, 0.000346 ETH. Opening allocation (testnet scale): pool 0.50 ETH, market 0.05 ETH, board 12 items. VRF subscription 65734759714671740308951963479999569810727601828421277709603279960624053991108.

## Activation through the timelock

Scheduled at 1792987527, executed at 1792988133: waited 606 s against a 600 s delay. Engine activated: true; market launched: true; governance: timelock.

Post-activation batch (surplus sink for genesis end; testnet-only faster GRAIL decay): waited 606 s.

## Pulls and VRF

| Scenario | Quote: fee / settlement / VRF (ETH) | Request tx | Fulfilment tx | Fulfilment gas | Oracle charge (ETH) | VRF fee − charge (ETH) | Latency | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Single pull (referred) (1) | 0.017098 / 0.000171 / 0.0000154 | [0x467426df…](https://sepolia.basescan.org/tx/0x467426dffe935f549e3c49f3030b0c8fd39f8beb5be2446d24605505cdeec321) | [0x9e89701e…](https://sepolia.basescan.org/tx/0x9e89701e8714f1ded96b48fcc7a3aab48329ec6466c9ca34e8bdefbbaf876597) | 667684 | 0.0000074 | 0.0000081 | 1 s | 1 Fulfilled |
| Batch of ten (10) | 0.017640 / 0.000176 / 0.0000764 | [0x4efd4ed8…](https://sepolia.basescan.org/tx/0x4efd4ed8792db0600baf2c20ff777ae63ac11e196de02fd03ddd5ea3d3fc3e32) | [0x6040bf69…](https://sepolia.basescan.org/tx/0x6040bf69435a8b85c5102374e4a12fa0db0eca89ad60bd9651dffac2620742c1) | 1591011 | 0.0000181 | 0.0000583 | 2 s | 3 Fulfilled, 7 Refunded (2 VRF requests) |
| Three pulls paid with prizes (PrizeRouter) (3) | — | [0xfb139c42…](https://sepolia.basescan.org/tx/0xfb139c42989e22182d423c1786193e67932210cb06f8158a9024479a08f5b11d) | [0xc10af3c1…](https://sepolia.basescan.org/tx/0xc10af3c15613155a5110ad93e18f005d2d492e4eb7eb1ea7db54109d99644de7) | 1026256 | 0.0000122 | — | 1 s | 3 Fulfilled |
| Batch of eight, zero negative slippage (8) | 0.016828 / 0.000168 / 0.0000713 | [0xe45c5d30…](https://sepolia.basescan.org/tx/0xe45c5d30ed2f94d387acf5349e40b5476cc700b78c882046ec0f1aff9659b1e8) | [0xf96b4b06…](https://sepolia.basescan.org/tx/0xf96b4b06c6be4fa0f2ea4e0ed4d21cdd24224cb08ab51da690834c2047afec32) | 2063669 | 0.0000241 | 0.0000472 | 2 s | 6 Fulfilled, 1 Refunded, 1 Ready (2 VRF requests) |
| On behalf of another wallet (1) | 0.016469 / 0.000165 / 0.0000154 | [0x7627e24c…](https://sepolia.basescan.org/tx/0x7627e24c197ac2b95c7513b18405e004a3b720e9def972bb7b46a9b91ec7a440) | [0xc82b2b48…](https://sepolia.basescan.org/tx/0xc82b2b48ae3234518183476afc33154596c6085fd4cf4551c95280fc92e3be5a) | 638188 | 0.0000071 | 0.0000083 | 2 s | 1 Fulfilled |
| Batch with the VRF float (rerun) (10) | 0.016914 / 0.000169 / 0.0000764 | [0x009553cd…](https://sepolia.basescan.org/tx/0x009553cd59d1688a47a64b9831b3baf9db7f012435f28a40ec6d00bfac41578b) | [0xf2aec862…](https://sepolia.basescan.org/tx/0xf2aec8622c7105120dcaea494a1d3e4b2b25738f49dd29c57a4e08d73327f6b6) | 1645719 | 0.0000185 | 0.0000579 | 2 s | 3 Fulfilled, 7 Refunded (2 VRF requests) |

Batch of ten: 10 of 10 resolved in the VRF callbacks (2 requests of up to 5 pulls). 7 were refunded by the slippage guard: on a 12-item testnet board the first wins of the batch moved the per-pull price outside the batch's slippage tolerance, so the rest of the batch was refunded as credit that pays for the next pull (on the 100-item launch board the same wins move it about 1–2 %).

### Deliveries (batch of ten)

| Acquisition | Prize | Notional (ETH) | Delivered to purchaser |
| --- | --- | --- | --- |
| 2 | Shape #2 | 0.01170 | true |
| 3 | Shape #5 | 0.01170 | true |
| 4 | Shape #3 | 0.01170 | true |

## Keeper booking and restocking

Booked sequences 1 → 12; selectable listings 12 → 16; pool cash 0.1390 → 0.1300 ETH; maintenance 0.01183 ETH.

| Action | Tx | Gas |
| --- | --- | --- |
| settle | [0x875fd0d7…](https://sepolia.basescan.org/tx/0x875fd0d7d19352cf72ec863e5d7e9120b831e9601145cb28d919c80c5e52f14c) | 3387744 |
| grail-step | [0x918a4767…](https://sepolia.basescan.org/tx/0x918a476757b8994634d0276daa4f4a2206f24e306e30b5ec7c0e4efb96ff42c5) | 336537 |

Keeper net cost after the maintenance refund: -0.0000068 ETH.

## GRAIL listing, odds and repricing

| | Backing | Notional | Status | Odds per pull |
| --- | --- | --- | --- | --- |
| before | 0.050 | 0.0250 | Active (selectable) | 1 in 13 |
| after pulls + keeper step | 0.050 | 0.0250 | Active (selectable) | 1 in 24 |
| before the in-time rerun | 0.050 | 0.0400 | Active (selectable) | 1 in 38 |
| after the in-time rerun + keeper step | 0.050 | 0.0250 | Active (selectable) | 1 in 23 |

Decay is accelerated on testnet only (0.002 ETH per pull, set through the timelock); selection of a GRAIL by the live VRF is a matter of chance at these odds. Once the GRAIL reaches its floor notional (50 % of backing) its notional holds, and its odds move only with the rest of the board (captures and restocking). Decay above the floor is covered by GrailReprice.t.sol and the fork rehearsal.

## Refunds

Batch with zero negative slippage tolerance: 6 Fulfilled, 1 Refunded, 1 Ready; refund credit 0.016996 ETH, withdrawn in [0x04ed6325…](https://sepolia.basescan.org/tx/0x04ed6325121ae155f5acdc833ca6a7d991ae7a788e587d08cc34f11312c285cc). Expiry (no VRF word within 1,800 blocks) cannot be forced on a live coordinator; it is covered by Engine.t.sol.

## Referral and purchase on behalf

Referrer credit 0.0016012 ETH, withdrawn in [0xdc71922a…](https://sepolia.basescan.org/tx/0xdc71922a55cf6d864afbf495ef59be8ccfddf87289e390e5dfc446f96d6d9a15); prize delivered to the beneficiary: true. Token Works / development credit (testnet: deployer) 0.0018240 ETH.

## ENGINE trading and fee routing

Buy 0.01 ETH and sell half through the canonical PoolManager (test router [`0x3186bdceb0820f15946c6ed88fb2c6262cbe3f1a`](https://sepolia.basescan.org/address/0x3186bdceb0820f15946c6ed88fb2c6262cbe3f1a)): volume 0.015337 ETH, hook fees 0.0003067 ETH = 199 bps of volume; operator 0.0000383, treasury 0.0002684 ETH; after distribute the treasury received 0.0002684 ETH (GRAIL fund now 0.04576 ETH, POL pending 0.0000000 ETH).

## Genesis ledger

Epoch 0: 31 accepted, 31 resolved, 19 units, 27 bonus weight; test player 18 units. Claims open after epoch 0 closes and resolves (24 h of real time); rerun the runner then.

## Keeper outage and recovery (two keepers)

With keepers stopped, three batches settled in their callbacks: selectable listings 7 → 4, 18 sequences unbooked. Two keepers then ran at the same moment: keeper 1 [settle, settle, grail-step], keeper 2 [settle]; listings back to 16, books level: true.

## Playing winnings (PrizeRouter)

Every PrizeRouter transaction of the run: Shapes.setApprovalForAll(router) [0x16310c1a…](https://sepolia.basescan.org/tx/0x16310c1a086aa0eaba10742cb965841c4f52383d8832596dba1f6ed8d30ab48b); Draw Packs.setApprovalForAll(router) [0xb2246658…](https://sepolia.basescan.org/tx/0xb2246658b6b8978b5f2617eaf98561e6e42e414fa66671146629391cc3840de4); pullWithPrizes(3) paid with 4 prizes [0x919bb7ba…](https://sepolia.basescan.org/tx/0x919bb7ba2eb6b8b35fc976dfa6d02b4174641e708a6ca20759a86911a7ac0416); Shapes.setApprovalForAll(router) [0xb930fa05…](https://sepolia.basescan.org/tx/0xb930fa0521bb1991a44e3ea5252222c6e87c0368899d15008804f51d63279402); Draw Packs.setApprovalForAll(router) [0x4d1fdc5f…](https://sepolia.basescan.org/tx/0x4d1fdc5f47cc47cd2b5e8986a9552744ec4c112cf4e023f26b814b9e0b279e3c); pullWithPrizes(3) paid with 0 prizes [0xfb139c42…](https://sepolia.basescan.org/tx/0xfb139c42989e22182d423c1786193e67932210cb06f8158a9024479a08f5b11d).

Last scenario run: Two one-time approvals ([0xb930fa05…](https://sepolia.basescan.org/tx/0xb930fa0521bb1991a44e3ea5252222c6e87c0368899d15008804f51d63279402), [0x4d1fdc5f…](https://sepolia.basescan.org/tx/0x4d1fdc5f47cc47cd2b5e8986a9552744ec4c112cf4e023f26b814b9e0b279e3c)), then one transaction ([0xfb139c42…](https://sepolia.basescan.org/tx/0xfb139c42989e22182d423c1786193e67932210cb06f8158a9024479a08f5b11d), gas 827534) paid a 3-pull price of 0.05795 ETH with 0 prizes at face (0.00000 ETH) and 0.06374 ETH sent; wallet change excluding gas -0.05795 ETH. Outcome: 3 Fulfilled.

## Prize redemption

Before the in-time rerun, 3 more prizes returned 0.16000 ETH. In all, the player redeemed 25 prizes for their backing during the run (listed under All transactions), recycling winnings into later scenarios.

## All transactions

| Label | Tx | Status | Gas | Cost (ETH) |
| --- | --- | --- | --- | --- |
| vrf.addConsumer(engine) | [0xad0ed7c4…](https://sepolia.basescan.org/tx/0xad0ed7c43f2af673a73ea003dc8e48ca69da449dc6da58d6300c41c382b0be1f) | success | 78166 | 0.00000047 |
| timelock.scheduleBatch(activation) | [0x80ee4669…](https://sepolia.basescan.org/tx/0x80ee4669346e5251dd37c5fb69f76318aa69eaa6b22d262412ba9ce81d99e8b7) | success | 93716 | 0.00000056 |
| timelock.executeBatch(activation) | [0x53031c87…](https://sepolia.basescan.org/tx/0x53031c879c0d40ea7714b4d7e98ddc69cf2d3c2b7ec36af86f1acfb00085c723) | success | 479709 | 0.00000288 |
| timelock.scheduleBatch(setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only) + vault.setLadder(0.05, 0.1 ETH, testnet only)) | [0x2133dc12…](https://sepolia.basescan.org/tx/0x2133dc12c954844dc16c0be1d0188c09665ec4de321ab55b85513f5e722b4d00) | success | 75124 | 0.00000045 |
| timelock.executeBatch(setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only) + vault.setLadder(0.05, 0.1 ETH, testnet only)) | [0xed2aa78a…](https://sepolia.basescan.org/tx/0xed2aa78affd910c1debebd02ec59618bbf22becf2ab2bc1e3100a0fd96eee67a) | success | 115820 | 0.00000069 |
| vault.fundGrail(testnet GRAIL backing + mint fee) | [0xbd22492a…](https://sepolia.basescan.org/tx/0xbd22492a9d68be509f1f8ca17923e877513b80be9cc1ad83456a7435bd10ec75) | success | 67321 | 0.00000040 |
| vault.step(mint + list GRAIL) | [0xf4839d1f…](https://sepolia.basescan.org/tx/0xf4839d1fee23567cb3ddd4e0801a5d50f8a2444c72917a6fbbc8974ab546b3d7) | success | 840973 | 0.00000505 |
| timelock.scheduleBatch(engine.setVrfConfig(word deadline 7,200 blocks, testnet only)) | [0x99eda604…](https://sepolia.basescan.org/tx/0x99eda6045589b277a079ac7f6461f81a4ad80f7ffbfd038e2456667709cd0433) | success | 62414 | 0.00000037 |
| timelock.executeBatch(engine.setVrfConfig(word deadline 7,200 blocks, testnet only)) | [0x3b293293…](https://sepolia.basescan.org/tx/0x3b2932938dd52eec7b6127446fcea29cea44c11eafed454c6f93a77bf400ba9f) | success | 74942 | 0.00000045 |
| fund player | [0xea7f1230…](https://sepolia.basescan.org/tx/0xea7f123066319eef1a2660079f9f855b19aefe743494029985cc672b7cc4f0ff) | success | 21000 |  |
| fund referrer | [0x144c01a0…](https://sepolia.basescan.org/tx/0x144c01a0b6cca7b8a78bae20425e1db799ab82a09049c3b4d5f4cddd268be53e) | success | 21000 |  |
| fund keeper-2 | [0x86335755…](https://sepolia.basescan.org/tx/0x86335755856b9356e425e3af9f485f4575fa8096083e9ab666ebc11c13ff88fb) | success | 21000 |  |
| acquireBatch(1) with referrer | [0x467426df…](https://sepolia.basescan.org/tx/0x467426dffe935f549e3c49f3030b0c8fd39f8beb5be2446d24605505cdeec321) | success | 529951 | 0.00000318 |
| vrf fulfilment 71054585493358879505969181910425938233992450721316667008371252571450217644815 | [0x9e89701e…](https://sepolia.basescan.org/tx/0x9e89701e8714f1ded96b48fcc7a3aab48329ec6466c9ca34e8bdefbbaf876597) |  | 667684 |  |
| acquireBatch(10) | [0x4efd4ed8…](https://sepolia.basescan.org/tx/0x4efd4ed8792db0600baf2c20ff777ae63ac11e196de02fd03ddd5ea3d3fc3e32) | success | 2062285 | 0.00001237 |
| vrf fulfilment (request 2 of 2) | [0x2063cf2a…](https://sepolia.basescan.org/tx/0x2063cf2a19d2b92779f154c4e24964a0c5c34a6e5d8b95d7be596115a6d09153) |  | 439407 |  |
| vrf fulfilment 27973963310067159041517136288889336954625115313198055920568961642341784320549 | [0x6040bf69…](https://sepolia.basescan.org/tx/0x6040bf69435a8b85c5102374e4a12fa0db0eca89ad60bd9651dffac2620742c1) |  | 1591011 |  |
| settle | [0x875fd0d7…](https://sepolia.basescan.org/tx/0x875fd0d7d19352cf72ec863e5d7e9120b831e9601145cb28d919c80c5e52f14c) | success | 3387744 | 0.00002033 |
| grail-step | [0x918a4767…](https://sepolia.basescan.org/tx/0x918a476757b8994634d0276daa4f4a2206f24e306e30b5ec7c0e4efb96ff42c5) | success | 336537 | 0.00000202 |
| Shapes.setApprovalForAll(router) | [0x16310c1a…](https://sepolia.basescan.org/tx/0x16310c1a086aa0eaba10742cb965841c4f52383d8832596dba1f6ed8d30ab48b) | success | 47358 | 0.00000028 |
| Draw Packs.setApprovalForAll(router) | [0xb2246658…](https://sepolia.basescan.org/tx/0xb2246658b6b8978b5f2617eaf98561e6e42e414fa66671146629391cc3840de4) | success | 46774 | 0.00000028 |
| pullWithPrizes(3) paid with 4 prizes | [0x919bb7ba…](https://sepolia.basescan.org/tx/0x919bb7ba2eb6b8b35fc976dfa6d02b4174641e708a6ca20759a86911a7ac0416) | success | 942794 | 0.00000566 |
| Shapes.setApprovalForAll(router) | [0xb930fa05…](https://sepolia.basescan.org/tx/0xb930fa0521bb1991a44e3ea5252222c6e87c0368899d15008804f51d63279402) | success | 27458 | 0.00000016 |
| Draw Packs.setApprovalForAll(router) | [0x4d1fdc5f…](https://sepolia.basescan.org/tx/0x4d1fdc5f47cc47cd2b5e8986a9552744ec4c112cf4e023f26b814b9e0b279e3c) | success | 26874 | 0.00000016 |
| pullWithPrizes(3) paid with 0 prizes | [0xfb139c42…](https://sepolia.basescan.org/tx/0xfb139c42989e22182d423c1786193e67932210cb06f8158a9024479a08f5b11d) | success | 827534 | 0.00000497 |
| vrf fulfilment 99439427335726643498687727953144335815032041226359739805434192132922331736171 | [0xc10af3c1…](https://sepolia.basescan.org/tx/0xc10af3c15613155a5110ad93e18f005d2d492e4eb7eb1ea7db54109d99644de7) |  | 1026256 |  |
| withdrawAcquisitionRefund | [0xb7c83166…](https://sepolia.basescan.org/tx/0xb7c831663f78d02d80ce1de7c0f8e41c48477e1c1c7866b40a783cf71559053f) | success | 36782 | 0.00000022 |
| acquireBatch(5) for GRAIL decay | [0xfee6b457…](https://sepolia.basescan.org/tx/0xfee6b457c4b0d497c875322a4f7125e9130c7c0ae48e08c9cb716f9cd2af8d4d) | success | 1145612 | 0.00000687 |
| vrf fulfilment 22744332308705973563823536092557755569703074796915213834147954800767093094941 | [0x31974816…](https://sepolia.basescan.org/tx/0x319748160adda10bf53f0317384c4c34caa783e4e8b3ab204a6482fb5c84259f) |  | 974344 |  |
| settle | [0xb564051d…](https://sepolia.basescan.org/tx/0xb564051df31c34325c8f9bfda1e2f0296e534c98b94896e1cc56a0445ccb5afe) | success | 4635793 | 0.00002781 |
| settle | [0x4258d3af…](https://sepolia.basescan.org/tx/0x4258d3af12bcf37295df38d26bf4e8dac38bdac7ab8c6558e0f862b7cb9a9267) | success | 1360857 | 0.00000817 |
| redeem Shape #7 (GRAIL scenario) | [0xd5ff7180…](https://sepolia.basescan.org/tx/0xd5ff71809dfd0b2d954349112cbb375550f327a586cfa9ed6fdf288693898a20) | success | 61989 | 0.00000037 |
| redeem Shape #8 (GRAIL scenario) | [0x2d0f76f0…](https://sepolia.basescan.org/tx/0x2d0f76f07078a721cc1b4214169bc4720df2a4c5abf32772a6d61f2f74252e9f) | success | 61989 | 0.00000037 |
| withdrawAcquisitionRefund | [0xa7ca2910…](https://sepolia.basescan.org/tx/0xa7ca291031842d3982d833469c78ead9c089653d9d2a950cbb968eba49d6327d) | success | 36782 | 0.00000022 |
| acquireBatch(8, maxNegativeSlippage 0) | [0xe45c5d30…](https://sepolia.basescan.org/tx/0xe45c5d30ed2f94d387acf5349e40b5476cc700b78c882046ec0f1aff9659b1e8) | success | 1720250 | 0.00001032 |
| vrf fulfilment (request 2 of 2) | [0x4a9b9287…](https://sepolia.basescan.org/tx/0x4a9b92878d99eddb31af397d47465267b426a964fa563f5154db8841eae07719) |  | 263069 |  |
| vrf fulfilment 22472661716191591479586277519482109193904698484612346293749371618594922605060 | [0xf96b4b06…](https://sepolia.basescan.org/tx/0xf96b4b06c6be4fa0f2ea4e0ed4d21cdd24224cb08ab51da690834c2047afec32) |  | 2063669 |  |
| withdrawAcquisitionRefund | [0x04ed6325…](https://sepolia.basescan.org/tx/0x04ed6325121ae155f5acdc833ca6a7d991ae7a788e587d08cc34f11312c285cc) | success | 36782 | 0.00000022 |
| settle | [0xc3a9a3e5…](https://sepolia.basescan.org/tx/0xc3a9a3e55152d08d8fba722a544bb63f3f76ee6c84929e48444ee195ed258b1d) | success | 3688624 | 0.00002213 |
| grail-step | [0x8e0d5b7f…](https://sepolia.basescan.org/tx/0x8e0d5b7f4efc0d24c33f7ad459578b3e3f702f3bd4adb4c8769db7ced548c836) | success | 143580 | 0.00000086 |
| withdrawAcquisitionRefund | [0x6b7b6dba…](https://sepolia.basescan.org/tx/0x6b7b6dbabf698ff930e2a343a8adbfc2e5fb5809fbea6dfaeba39d2651671f27) | success | 36782 | 0.00000022 |
| acquireBatch(1) paid by player for referrer | [0x7627e24c…](https://sepolia.basescan.org/tx/0x7627e24c197ac2b95c7513b18405e004a3b720e9def972bb7b46a9b91ec7a440) | success | 461551 | 0.00000277 |
| vrf fulfilment 50405705933009137975628363522303579701553004576441157904383099677870182634567 | [0xc82b2b48…](https://sepolia.basescan.org/tx/0xc82b2b48ae3234518183476afc33154596c6085fd4cf4551c95280fc92e3be5a) |  | 638188 |  |
| settle | [0x3ce7bf96…](https://sepolia.basescan.org/tx/0x3ce7bf96b61d6646206621503f46f65210ce88a5d4ec41acfdcf6235f7afb80b) | success | 1052375 | 0.00000631 |
| withdrawFeeCredit(referrer) | [0xdc71922a…](https://sepolia.basescan.org/tx/0xdc71922a55cf6d864afbf495ef59be8ccfddf87289e390e5dfc446f96d6d9a15) | success | 38219 | 0.00000023 |
| deploy Swapper (test router) | [0x5b50c19c…](https://sepolia.basescan.org/tx/0x5b50c19c724c976cdc9a2b607d8142a736789a5a1f8f78ace98df3c37eabe349) |  | 726205 |  |
| swap: buy ENGINE with 0.01 ETH | [0x28076fa4…](https://sepolia.basescan.org/tx/0x28076fa403ff7099168cb998faafdb5c00d3b958594a13c52c945966b015b329) | success | 213836 | 0.00000128 |
| approve router | [0xb100a85e…](https://sepolia.basescan.org/tx/0xb100a85e921f7e9ba7f66c1ac0e965b12e1618ac00dcc6057b1d7179638caff5) | success | 45982 | 0.00000028 |
| swap: sell half the ENGINE | [0x5f976469…](https://sepolia.basescan.org/tx/0x5f976469f10ad4916038095804adee5ab473c242744c9295faf7095ee8c5018c) | success | 137233 | 0.00000082 |
| hook.distribute | [0xf69995fd…](https://sepolia.basescan.org/tx/0xf69995fdfd926340404c31891124bff89749239063eb7a61b6f3b0d94777d4be) | success | 171974 | 0.00000103 |
| redeem Shape #29 (slippage scenario) | [0x29363663…](https://sepolia.basescan.org/tx/0x293636631ba9d8308411f9dffba1013e0d6d7f05b7f18f773f65014e592c25d4) | success | 61989 | 0.00000037 |
| redeem Shape #22 (slippage scenario) | [0x0e766126…](https://sepolia.basescan.org/tx/0x0e7661269a00069c4b6930fbf4639e7ae479a2b8a4a9af923f150543486bbdfb) | success | 62007 | 0.00000037 |
| redeem Shape #27 (slippage scenario) | [0x1a835737…](https://sepolia.basescan.org/tx/0x1a835737d5e997b20b78104053ff7ce1d2128ed1f7266200817b913d5556283f) | success | 61989 | 0.00000037 |
| redeem Shape #28 (slippage scenario) | [0xd728859b…](https://sepolia.basescan.org/tx/0xd728859b8f962c43bb5de26cca8d4a47238a6dacb83a74e47788deee29b1aaad) | success | 61989 | 0.00000037 |
| redeem Draw Pack #7 (slippage scenario) | [0xe59dbeb9…](https://sepolia.basescan.org/tx/0xe59dbeb9ecd3af72bcb5992346aa1008e8d596ef70488dfd443f0f29029ecc38) | success | 153912 | 0.00000092 |
| redeem Shape #36 (slippage scenario) | [0xaa373fe6…](https://sepolia.basescan.org/tx/0xaa373fe65575d03edeb5da58253b1c21f01f9db6dc0af071b456c707353b9a08) | success | 61989 | 0.00000037 |
| outage acquireBatch(3) #1 | [0xab0aaa62…](https://sepolia.basescan.org/tx/0xab0aaa621264974dbd677bc76353875e79e7bc1fa34988f9eaa9a1ab8167a240) | success | 803620 | 0.00000482 |
| vrf fulfilment 18687830130380858670897644865203164633003504488873844108899692960528133730605 | [0x81bed9cc…](https://sepolia.basescan.org/tx/0x81bed9cc0cd52389638fa6d12cd5cde92d68f82a69c81bad1bfa4dae260070e9) |  | 1047660 |  |
| outage acquireBatch(3) #2 | [0x3a341ce3…](https://sepolia.basescan.org/tx/0x3a341ce3d4f764d80fef8814137475cbb88c53dbf7509b78efcf2e169f3d6797) | success | 803620 | 0.00000482 |
| redeem Draw Pack #1 (top up for the next pull) | [0xf0cccc6e…](https://sepolia.basescan.org/tx/0xf0cccc6e3c6845e8f9f5cdd9e0cca7dbe4f4ede08a87e3a73691ec3f6f9c73bc) | success | 153912 | 0.00000092 |
| redeem Shape #4 (top up for the next pull) | [0xa542fbd0…](https://sepolia.basescan.org/tx/0xa542fbd0c95ec501d2fc73f7545ab2d3151fa49b141fc92820b71fe44e7e9bc7) | success | 61989 | 0.00000037 |
| redeem Draw Pack #5 (top up for the next pull) | [0x872b1949…](https://sepolia.basescan.org/tx/0x872b19492f064150131c9fb18d9833988d8fdef15541edc9838130b28982cfc5) | success | 183328 | 0.00000110 |
| outage acquireBatch(3) #1 | [0x72556742…](https://sepolia.basescan.org/tx/0x72556742977ea6940dcb0792042f29567538848385ead957a22443a4b9221abc) | success | 803620 | 0.00000482 |
| vrf fulfilment 88858978147300124395337705302012438989942888322062733431627190180964887414629 | [0xb1695160…](https://sepolia.basescan.org/tx/0xb169516037bd628bbaf79d49ea9c8b9233d799733408593c2517bd7c74865803) |  | 896357 |  |
| withdrawAcquisitionRefund | [0xb1e25be9…](https://sepolia.basescan.org/tx/0xb1e25be9952f21357e481b6ae5c488a0a16233b0565ca973aacd453ebc3a0dd9) | success | 36782 | 0.00000022 |
| redeem Shape #1 (top up for the next pull) | [0xa8907fc7…](https://sepolia.basescan.org/tx/0xa8907fc7e96c0ff74f587623879034ea82dac6316cbe855fd4a977310cd12d41) | success | 61989 | 0.00000037 |
| redeem Draw Pack #3 (top up for the next pull) | [0x46d8afb2…](https://sepolia.basescan.org/tx/0x46d8afb24079c654fc02bc57f026f9aaf1a3e9ba70da7114bbc63212fcfc7f86) | success | 153912 | 0.00000092 |
| redeem Shape #26 (top up for the next pull) | [0x2dfdf35e…](https://sepolia.basescan.org/tx/0x2dfdf35e04967f8d8f7470b76d8ca7c03d4f488a3aa1bc88eaf6610cfe918d4c) | success | 61989 | 0.00000037 |
| redeem Draw Pack #4 (top up for the next pull) | [0x7d4d1ea5…](https://sepolia.basescan.org/tx/0x7d4d1ea50b771d9c51cabfd486bb0505bfb2607e8f965ed8b8de7b9532834311) | success | 153912 | 0.00000092 |
| redeem Draw Pack #2 (top up for the next pull) | [0x27d8d55e…](https://sepolia.basescan.org/tx/0x27d8d55e247def3b898f921a42f2dc2acdc3a34a597756736a99210c09396d3a) | success | 153912 | 0.00000092 |
| redeem Shape #37 (top up for the next pull) | [0x8e50ce4d…](https://sepolia.basescan.org/tx/0x8e50ce4d6ec48c266a2f3d014648cb95f087577fad8bfe2b864d379a9c7acbe8) | success | 61989 | 0.00000037 |
| redeem Shape #38 (top up for the next pull) | [0x8eb9fd94…](https://sepolia.basescan.org/tx/0x8eb9fd94da66baadb37667bbbcc4a2a19c4340434f8a9117f42bcf1ef543ab13) | success | 61989 | 0.00000037 |
| redeem Shape #40 (top up for the next pull) | [0x5d624b75…](https://sepolia.basescan.org/tx/0x5d624b75be7a08a7b1f8e1ba93c635402d30e6bef2d1ad4a10f7453631b678fd) | success | 61989 | 0.00000037 |
| redeem Shape #45 (top up for the next pull) | [0xde5674f2…](https://sepolia.basescan.org/tx/0xde5674f218f614e4acb5972253a50d620401fdc7ddd4fd86eca5e9993364c462) | success | 61989 | 0.00000037 |
| redeem Shape #42 (top up for the next pull) | [0xfe7a8c8c…](https://sepolia.basescan.org/tx/0xfe7a8c8c1c26c563b91701adc15515fb493750a4a7c13a9bb8f5c656d17c020c) | success | 61989 | 0.00000037 |
| redeem Shape #31 (top up for the next pull) | [0xb0e33997…](https://sepolia.basescan.org/tx/0xb0e33997b46f4dea1b4d9daf76b405a0017ae1fa31017c9d46d6908b548c5d73) | success | 61989 | 0.00000037 |
| outage acquireBatch(3) #1 | [0x274ee608…](https://sepolia.basescan.org/tx/0x274ee608600e6b341403f1203932b2e021ec2409740b58520f9e7e639d514bca) | success | 803620 | 0.00000482 |
| vrf fulfilment 35385681518566140661081266064915477420736001572937612654990358168186807161221 | [0x3298c835…](https://sepolia.basescan.org/tx/0x3298c835f06413e82bc68db2fffa78cd2f6daaaa54b1ad1253edc6fe6a4a16ab) |  | 756856 |  |
| withdrawAcquisitionRefund | [0xd71aad36…](https://sepolia.basescan.org/tx/0xd71aad3671be3ce2603a07b71917426431c959ea82ad2cc4e838ef95ce05809d) | success | 36782 | 0.00000022 |
| outage acquireBatch(3) #2 | [0xc8619cc4…](https://sepolia.basescan.org/tx/0xc8619cc44a5ac1c95c50c3a0dcdefe817e019b21e7733e2b55a3c1c72a58961e) | success | 803620 | 0.00000482 |
| vrf fulfilment 59374474976240689492237855080386277281925307156705415555744086954710599171595 | [0x10230955…](https://sepolia.basescan.org/tx/0x102309558534d645da06594412d8ab5ecd3355a1e697cb85eda93ba9fd55cf1e) |  | 724433 |  |
| withdrawAcquisitionRefund | [0xe12b2964…](https://sepolia.basescan.org/tx/0xe12b2964d210895e1bba1743e6bfb71cfba01b328c689f5ecc10e8c2dc86c953) | success | 36782 | 0.00000022 |
| outage acquireBatch(3) #3 | [0xb9cfa07e…](https://sepolia.basescan.org/tx/0xb9cfa07eba1b95a954a2d143d7def61f016d575e02e37a139f93a77fbbac7f12) | success | 803620 | 0.00000482 |
| vrf fulfilment 24110381154068841499848299144396008972718577640491009917907684806233904022791 | [0x49897144…](https://sepolia.basescan.org/tx/0x49897144e92e8d21012da0ed4e546a12bfd00bee8254e113257ccec5c471db46) |  | 729383 |  |
| settle | [0x150f47f1…](https://sepolia.basescan.org/tx/0x150f47f1aa6040efb88fbd113d5e7db7d8af7faaab5b98ef7781793d233f3589) | success | 5424575 | 0.00003255 |
| settle | [0xd41a8f9d…](https://sepolia.basescan.org/tx/0xd41a8f9d3c2f683adb0f9c0320a34b9f7cddddb14bd752fc7bc8ed751825cf74) | success | 2865404 | 0.00001719 |
| grail-step | [0xd8540ef9…](https://sepolia.basescan.org/tx/0xd8540ef9dd628b429fec5b971f5ced46bf9456eda799d7a491287bff1237ec48) | success | 806857 | 0.00000484 |
| settle | [0x549434be…](https://sepolia.basescan.org/tx/0x549434be41b6d73fb16c38f3d1641ed1e7e1048b85dd59dadafd9b6bb4dae981) | success | 71703 | 0.00000043 |
| redeem Shape #21 (recycle before in-time batches) | [0x805487ed…](https://sepolia.basescan.org/tx/0x805487ed222ff77282e33a45fd2bd4a2a6133480a450565a3824ca123d079cac) | success | 62024 | 0.00000037 |
| redeem Shape #39 (recycle before in-time batches) | [0x86967085…](https://sepolia.basescan.org/tx/0x869670857ce15c348a749cc93e9a9e45e99944b1e4cbdf99fbd0f95e3560716e) | success | 61989 | 0.00000037 |
| redeem Shape #20 (recycle before in-time batches) | [0x87bcae18…](https://sepolia.basescan.org/tx/0x87bcae18da462922a9afe979d40574f660dd8de0f39b1f824ce6f5485f6fc52b) | success | 62007 | 0.00000037 |
| withdrawAcquisitionRefund | [0xeba64399…](https://sepolia.basescan.org/tx/0xeba64399e5a889ff250c9697682c74ae7446fd9e73ae4dab6d0e0f06051c2bc4) | success | 36782 | 0.00000022 |
| acquireBatch(10) with the VRF float | [0x009553cd…](https://sepolia.basescan.org/tx/0x009553cd59d1688a47a64b9831b3baf9db7f012435f28a40ec6d00bfac41578b) | success | 2062285 | 0.00001237 |
| vrf fulfilment (request 2 of 2) | [0xf9cef1c7…](https://sepolia.basescan.org/tx/0xf9cef1c7bf757ca49fd9acf4cdec2d46429887f292c5a1e1f13a7cd8896dece7) |  | 433884 |  |
| vrf fulfilment 1760431571666695526125163054788778897474112645547120549116267491410067129273 | [0xf2aec862…](https://sepolia.basescan.org/tx/0xf2aec8622c7105120dcaea494a1d3e4b2b25738f49dd29c57a4e08d73327f6b6) |  | 1645719 |  |
| settle | [0xb6c06a2d…](https://sepolia.basescan.org/tx/0xb6c06a2db77a47de06e96852a057c0083a5a5f9670c21db309ce3cd01b2da6d5) | success | 2554473 | 0.00001533 |
| grail-step | [0xb883456d…](https://sepolia.basescan.org/tx/0xb883456d92ddec222282499ee7cac342052e63d601ba5d961b74b5914f52e35b) | success | 319437 | 0.00000192 |
