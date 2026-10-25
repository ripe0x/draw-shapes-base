# Base Sepolia deployment and live scenarios

Chain 84532, RPC https://sepolia.base.org. Every hash below is a real Base Sepolia transaction. VRF words were delivered by the Chainlink VRF v2.5 coordinator; the timelock delay elapsed in real chain time.

## Contracts

| Contract | Address |
| --- | --- |
| shapes | [`0x062193A0F3Df55d88a7E37366D442CD2238CCeD0`](https://sepolia.basescan.org/address/0x062193A0F3Df55d88a7E37366D442CD2238CCeD0) |
| drawPacks | [`0x835C2447878Ca51329eDffFED95bb2977782E6C4`](https://sepolia.basescan.org/address/0x835C2447878Ca51329eDffFED95bb2977782E6C4) |
| timelock | [`0x0a37004C35BC01Bd5D0E537B85b48Ae650A68bcb`](https://sepolia.basescan.org/address/0x0a37004C35BC01Bd5D0E537B85b48Ae650A68bcb) |
| engine | [`0xF1A489F5b1e629cc0bC9359f59eb5Adcce36e48f`](https://sepolia.basescan.org/address/0xF1A489F5b1e629cc0bC9359f59eb5Adcce36e48f) |
| controller | [`0x2071743214FD3460934c79BC33fae1AbD6BEB0DA`](https://sepolia.basescan.org/address/0x2071743214FD3460934c79BC33fae1AbD6BEB0DA) |
| grailVault | [`0xE58349913Ac8d01DA859369ffa3000BC1B9c3937`](https://sepolia.basescan.org/address/0xE58349913Ac8d01DA859369ffa3000BC1B9c3937) |
| token | [`0x5a38a453d15EE4e918E2D4A24C4EBBf5f0B0Fc48`](https://sepolia.basescan.org/address/0x5a38a453d15EE4e918E2D4A24C4EBBf5f0B0Fc48) |
| hook | [`0xe385F6958bd9aFDFCfcfd085767202c10FC9e0cC`](https://sepolia.basescan.org/address/0xe385F6958bd9aFDFCfcfd085767202c10FC9e0cC) |
| liquidity | [`0x7794be8f04f98430B5Da3719c653Cd9A2d0AD477`](https://sepolia.basescan.org/address/0x7794be8f04f98430B5Da3719c653Cd9A2d0AD477) |
| farm | [`0xd3A6b5bC9294E6b39374378b17908551308d9df0`](https://sepolia.basescan.org/address/0xd3A6b5bC9294E6b39374378b17908551308d9df0) |
| treasury | [`0x44736E45E6b547109337C1D405AdE39eD1c1C38c`](https://sepolia.basescan.org/address/0x44736E45E6b547109337C1D405AdE39eD1c1C38c) |
| buyback | [`0xcd6c48146Fa4DBb7C65B59A22F50c16D16BcE73D`](https://sepolia.basescan.org/address/0xcd6c48146Fa4DBb7C65B59A22F50c16D16BcE73D) |
| lens | [`0x16367F2722e98092670fAdc1b1d43c5C31f4591F`](https://sepolia.basescan.org/address/0x16367F2722e98092670fAdc1b1d43c5C31f4591F) |

Deployment: 46 transactions, 70,410,632 gas, 0.000422 ETH. Opening allocation (testnet scale): pool 0.70 ETH, market 0.20 ETH, board 25 items. VRF subscription 65734759714671740308951963479999569810727601828421277709603279960624053991108.

## Activation through the timelock

Scheduled at 1792945708, executed at 1792946314: waited 606 s against a 600 s delay. Engine activated: true; market launched: true; governance: timelock.

Post-activation batch (surplus sink for genesis end; testnet-only faster GRAIL decay): waited 606 s.

## Pulls and VRF

| Scenario | Quote: fee / settlement / VRF (ETH) | Request tx | Fulfilment tx | Fulfilment gas | Oracle charge (ETH) | VRF fee − charge (ETH) | Latency | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Single pull (referred) (1) | 0.015764 / 0.000158 / 0.0000136 | [0xef5c695a…](https://sepolia.basescan.org/tx/0xef5c695aff2910e5309fee365d80465f660d4146bc948b0ae14da50609160b80) | [0x753e427e…](https://sepolia.basescan.org/tx/0x753e427e9b8e33bd0603f0d145aa89081538a8323b54f09ede41c272e79debcf) | 698196 | 0.0000077 | 0.0000059 | 1374 s | 1 Fulfilled |
| Batch of ten (10) | 0.015969 / 0.000160 / 0.0000288 | [0x2ba8b1c3…](https://sepolia.basescan.org/tx/0x2ba8b1c33bdb33b841ad4e7c2b2672da1ef08b41f5bbf184c0ddb46bcbad0e5f) | [0xc28eed6c…](https://sepolia.basescan.org/tx/0xc28eed6c19854fedaa31d344793158a34133681d77b5b3b4d0840aae752f7463) | 256377 | 0.0000026 | 0.0000263 | 1441 s | 10 TimedOut |
| Batch of eight, zero negative slippage (8) | 0.015632 / 0.000156 / 0.0000288 | [0x9278833a…](https://sepolia.basescan.org/tx/0x9278833a28e09f2ade52d5bd64597df4377243ae8ce6b5c98f19789d66526fba) | [0x30881c9b…](https://sepolia.basescan.org/tx/0x30881c9b756898855d71a256fa61988a46ca3833c5706b5f25bbc76bd4367a54) | 1821521 | 0.0000218 | 0.0000070 | 3 s | 6 Fulfilled, 2 Ready |
| On behalf of another wallet (1) | 0.016240 / 0.000162 / 0.0000136 | [0x9dbe74e9…](https://sepolia.basescan.org/tx/0x9dbe74e909f36f3412529a0354ffb5b3d2dcbfeef72656b5875e644da253388a) | [0xb34057b9…](https://sepolia.basescan.org/tx/0xb34057b990d466c616cf19f9b5ce8aaac32a50a2b94f2489d1b5ab26f784974c) | 634441 | 0.0000071 | 0.0000065 | 2 s | 1 Fulfilled |
| Batch with the VRF float (rerun) (7) | 0.016240 / 0.000162 / 0.0000288 | [0x0cd76ff9…](https://sepolia.basescan.org/tx/0x0cd76ff99b41a71f2c807a0c8c6d498ae13ae93023ee16613a83f041903244c9) | [0xbaa3317c…](https://sepolia.basescan.org/tx/0xbaa3317c9fd0070cf82a3d498a87be2b2f91d8a77b35607d68770e633c8a5383) | 1803449 | 0.0000216 | 0.0000073 | 3 s | 6 Fulfilled, 1 Ready |

Batch of ten: 10 of 10 resolved in the callback (the word was late, so they timed out and were refunded).

### Why words were late before the VRF float

- **First live pull: word arrived after the block deadline (Base Sepolia 0.2 s blocks).** Base Sepolia produces blocks every 0.2 s (Base mainnet 2 s), so the 1,800-block deadline is ~6 min there; the testnet window was raised to 7,200 blocks through the timelock. The word itself was held back by the VRF float (next finding): it arrived just after the deadline, when the cheap timed-out callback fitted the subscription balance. TimedOut (word after the 1,800-block deadline), refunded fee + settlement fee; VRF fee kept (it paid the request)
- **VRF words waited for the subscription balance (Chainlink Max Cost at the lane max gas price).** The node fulfils only once the subscription covers the fulfilment at the key lane max gas price (30 gwei on Base Sepolia) x 1.6, the Max Cost in Chainlink billing docs; actual gas was 0.006 gwei. At 0.03-0.045 ETH every in-time multi-pull callback was above it, so words arrived only after the deadline (1,808 and 7,205 blocks: cheap timed-out callbacks). The single pull went through ~1 min after a top-up to 0.045 ETH (tx 0x65d836940dd92b4b0bc430758657901f1433c1b99eaa6f439709ab2d2c504717). After raising the float to 0.15 ETH (tx 0xf11d8d6030eafe40c6ca7a24aa7f54bc4915784751537b489265de57c138a2c1), words arrived in 12-14 blocks (2-3 s) for 1-, 7- and 8-pull batches. Mainnet 2 gwei lane needs ~0.0086 ETH; the preflight and keeper alert enforce 0.02 ETH.

## Keeper booking and restocking

Booked sequences 1 → 13; selectable listings 27 → 28; pool cash 0.1520 → 0.1544 ETH; maintenance 0.01032 ETH.

| Action | Tx | Gas |
| --- | --- | --- |
| settle | [0x4a72d14b…](https://sepolia.basescan.org/tx/0x4a72d14b3363546fe01f1484dfc5d58f14abfdade532560aedd98a2f6963e5db) | 1495087 |
| grail-step | [0x22a110c2…](https://sepolia.basescan.org/tx/0x22a110c2f22e4c33eca3d604e6047884b8a279baca67df11c56f08fbca081c68) | 336227 |

Keeper net cost after the maintenance refund: -0.0000075 ETH.

## GRAIL listing, odds and repricing

| | Backing | Notional | Status | Odds per pull |
| --- | --- | --- | --- | --- |
| before | 0.050 | 0.0250 | Active (selectable) | 1 in 45 |
| after pulls + keeper step | 0.050 | 0.0250 | Active (selectable) | 1 in 45 |
| before the in-time rerun | 0.050 | 0.0250 | Active (selectable) | 1 in 43 |
| after the in-time rerun + keeper step | 0.050 | 0.0250 | Active (selectable) | 1 in 44 |

Decay is accelerated on testnet only (0.002 ETH per pull, set through the timelock); selection of a GRAIL by the live VRF is a matter of chance at these odds. The first GRAIL pull's word was late (below the VRF float), so its pulls were refunded. By the rerun the GRAIL was already at its floor notional (50 % of backing), so its notional held; its odds move only with the rest of the board (restocking). Decay above the floor is covered by GrailReprice.t.sol and the fork rehearsal.

## Refunds

Batch with zero negative slippage tolerance: 6 Fulfilled, 2 Ready; refund credit 0.000000 ETH, withdrawn in —. Expiry (no VRF word within 1,800 blocks) cannot be forced on a live coordinator; it is covered by Engine.t.sol.

## Referral and purchase on behalf

Referrer credit 0.0007041 ETH, withdrawn in [0x3bc8fb03…](https://sepolia.basescan.org/tx/0x3bc8fb03647d19196d99900eff2cd502fa22a34dc22eb26f3f6e1084fa761ae6); prize delivered to the beneficiary: true. Token Works / development credit (testnet: deployer) 0.0008665 ETH.

## ENGINE trading and fee routing

Buy 0.01 ETH and sell half through the canonical PoolManager (test router [`0x6cb052355170e52e8e988685dac140786f8061cf`](https://sepolia.basescan.org/address/0x6cb052355170e52e8e988685dac140786f8061cf)): volume 0.015017 ETH, hook fees 0.0003003 ETH = 199 bps of volume; operator 0.0000375, treasury 0.0002628 ETH; after distribute the treasury received 0.0002628 ETH (GRAIL fund now 0.00823 ETH, POL pending 0.0000263 ETH).

## Genesis ledger

Epoch 0: 26 accepted, 26 resolved, 10 units, 10 bonus weight; test player 9 units. Claims open after epoch 0 closes and resolves (24 h of real time); rerun the runner then.

## Keeper outage and recovery (two keepers)

With keepers stopped, three batches settled in their callbacks: selectable listings 28 → 19, 9 sequences unbooked. Two keepers then ran at the same moment: keeper 1 [settle, deploy-pol], keeper 2 [settle]; listings back to 28, books level: true.

## Prize redemption

Redeemed 1 prize (notional 0.01170 ETH): 0.01000 ETH of backing returned to the winner. Before the rerun, 9 more prizes returned 0.11000 ETH.

## All transactions

| Label | Tx | Status | Gas | Cost (ETH) |
| --- | --- | --- | --- | --- |
| vrf.createSubscription | [0x7b24dd0c…](https://sepolia.basescan.org/tx/0x7b24dd0c66ceaa7b610a483190e8f5fd8fbaa264076bd377675b806bbfd894bb) | success | 109806 | 0.00000066 |
| vrf.fundSubscriptionWithNative | [0xce772f30…](https://sepolia.basescan.org/tx/0xce772f306c9cf06f8c133d8f850255ddf0a6b0b8382312f271f13709e1559e33) | success | 56125 | 0.00000034 |
| vrf.addConsumer(engine) | [0xd3b9567d…](https://sepolia.basescan.org/tx/0xd3b9567de1243216232a9f41e019513092d33a8bcd7f5297f641a2364cfb899f) | success | 95266 | 0.00000057 |
| timelock.scheduleBatch(activation) | [0xe5c525e9…](https://sepolia.basescan.org/tx/0xe5c525e9d99882320451d991a368d6de6042a0aab4011f6f39b0345f80004df3) | success | 93740 | 0.00000056 |
| timelock.executeBatch(activation) | [0x329773ee…](https://sepolia.basescan.org/tx/0x329773eee31b2bb92861dacf13b4078a9ff9bb66b9351106d49993ae9eaafb10) | success | 480579 | 0.00000288 |
| timelock.scheduleBatch(setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only) + vault.setLadder(0.05, 0.1 ETH, testnet only)) | [0x36cec7be…](https://sepolia.basescan.org/tx/0x36cec7beaa014400af4ff36b23eaad43a5a7d8a6ed07814bc0283e019ea691f6) | success | 75136 | 0.00000045 |
| timelock.executeBatch(setSurplusSink(buyback, genesis end) + vault.setConfig(decay 0.002, testnet only) + vault.setLadder(0.05, 0.1 ETH, testnet only)) | [0x2a384a0f…](https://sepolia.basescan.org/tx/0x2a384a0f19f7d90c66681517a657b4d6171e89ace12f7334e040621a8a3c5189) | success | 115832 | 0.00000069 |
| vault.fundGrail(testnet GRAIL backing + mint fee) | [0x315c0907…](https://sepolia.basescan.org/tx/0x315c0907f297cdb4227a6ef696022e99d0e18b4480f8edbf94d1080d8c78c983) | success | 67321 | 0.00000040 |
| vault.step(mint + list GRAIL) | [0xcf773985…](https://sepolia.basescan.org/tx/0xcf773985e12924e45ee8ba85f604bff582a7aea1dd19d31282e89e2b1b3af83b) | success | 840662 | 0.00000504 |
| fund player | [0x7dcd3d8b…](https://sepolia.basescan.org/tx/0x7dcd3d8b86dc141c657b213fa538859f38b85d016b36ba53c375a65240cd91ec) | success | 21000 |  |
| fund referrer | [0x5634b3cc…](https://sepolia.basescan.org/tx/0x5634b3ccf1786b0501ec70cc7f769c8a6d9fa6dc32fe896693ef7b137f667e69) | success | 21000 |  |
| fund keeper-2 | [0x98b88178…](https://sepolia.basescan.org/tx/0x98b881780677ee79be127ddee5d2c36f980ba4b3372f930ab74fddced2a12724) | success | 21000 |  |
| acquireBatch(1) with referrer | [0xb440a518…](https://sepolia.basescan.org/tx/0xb440a51850ad241c94982a9213d19ebc809d50b192b31053ad8bb79b093d2c5a) | success | 481289 | 0.00000289 |
| processAcquisitions (late word: refund) | [0xc2193182…](https://sepolia.basescan.org/tx/0xc219318207e963d63d461e78da7a12930f3423042403aca7bd9e3ce5d8685c80) | success | 103799 | 0.00000062 |
| timelock.scheduleBatch(engine.setVrfConfig(word deadline 7,200 blocks, testnet only)) | [0xae6dd00a…](https://sepolia.basescan.org/tx/0xae6dd00afa17a93c0586a5fe98a469c40a96feb46f3fde21bed7492f1d23277c) | success | 62414 | 0.00000037 |
| timelock.executeBatch(engine.setVrfConfig(word deadline 7,200 blocks, testnet only)) | [0x314277c7…](https://sepolia.basescan.org/tx/0x314277c7bf35cdaf08c2434792ab861a28d8b5eb741debc2c7753be3281fd7df) | success | 74895 | 0.00000045 |
| acquireBatch(1) with referrer | [0xef5c695a…](https://sepolia.basescan.org/tx/0xef5c695aff2910e5309fee365d80465f660d4146bc948b0ae14da50609160b80) | success | 447089 | 0.00000268 |
| vrf fulfilment 261033580198815560118571741680257357204030624022187115917134765671864906740 | [0x753e427e…](https://sepolia.basescan.org/tx/0x753e427e9b8e33bd0603f0d145aa89081538a8323b54f09ede41c272e79debcf) |  | 698196 |  |
| acquireBatch(10) | [0x2ba8b1c3…](https://sepolia.basescan.org/tx/0x2ba8b1c33bdb33b841ad4e7c2b2672da1ef08b41f5bbf184c0ddb46bcbad0e5f) | success | 1986525 | 0.00001192 |
| vrf fulfilment 63123750908519524823758993897184430472085467584117785558063229366484879055295 | [0xc28eed6c…](https://sepolia.basescan.org/tx/0xc28eed6c19854fedaa31d344793158a34133681d77b5b3b4d0840aae752f7463) |  | 256377 |  |
| settle | [0x4a72d14b…](https://sepolia.basescan.org/tx/0x4a72d14b3363546fe01f1484dfc5d58f14abfdade532560aedd98a2f6963e5db) | success | 1495087 | 0.00000897 |
| grail-step | [0x22a110c2…](https://sepolia.basescan.org/tx/0x22a110c2f22e4c33eca3d604e6047884b8a279baca67df11c56f08fbca081c68) | success | 336227 | 0.00000202 |
| redeem Shape #8 (batch prizes) | [0x6a20ee9b…](https://sepolia.basescan.org/tx/0x6a20ee9bdfa930b51ea03e9fae6c0c8a3b12b5c9cb5b6b699c9a2c97423fb776) | success | 61989 | 0.00000037 |
| acquireBatch(5) for GRAIL decay | [0x950f9a0d…](https://sepolia.basescan.org/tx/0x950f9a0d5787e0bef0727fb54869fa2a580331655842adb50fe2fee31f7fcc4e) | success | 1131282 | 0.00000679 |
| vrf fulfilment 17739670982657830849365232750453616445636606812539810658524866835761161884625 | [0x64cbe9f4…](https://sepolia.basescan.org/tx/0x64cbe9f4db98fdd65e3cbed512cea76e1376c9c10a37c8242a6b2d30496e3701) |  | 194798 |  |
| settle | [0x480b4f09…](https://sepolia.basescan.org/tx/0x480b4f0970049600294c88f586ee2e95b55f02e1651f3dc139038ee208004542) | success | 256097 | 0.00000154 |
| withdrawAcquisitionRefund | [0x351630e6…](https://sepolia.basescan.org/tx/0x351630e6b8d188da166c4563861262d51336da6c375e24fcdd229d9ef136bff7) | success | 36762 | 0.00000022 |
| fundSubscriptionWithNative (VRF float) | [0xf11d8d60…](https://sepolia.basescan.org/tx/0xf11d8d6030eafe40c6ca7a24aa7f54bc4915784751537b489265de57c138a2c1) | success | 39025 | 0.00000023 |
| acquireBatch(8, maxNegativeSlippage 0) | [0x9278833a…](https://sepolia.basescan.org/tx/0x9278833a28e09f2ade52d5bd64597df4377243ae8ce6b5c98f19789d66526fba) | success | 1644401 | 0.00000987 |
| vrf fulfilment 15405078487804265200242313741158126532862249190140575074404946366961276447207 | [0x30881c9b…](https://sepolia.basescan.org/tx/0x30881c9b756898855d71a256fa61988a46ca3833c5706b5f25bbc76bd4367a54) |  | 1821521 |  |
| settle | [0xf739d82b…](https://sepolia.basescan.org/tx/0xf739d82bd69a861bc71492a92c671e21f09a8c925daa05e89c014d7c4861e77f) | success | 6003354 | 0.00003602 |
| acquireBatch(1) paid by player for referrer | [0x9dbe74e9…](https://sepolia.basescan.org/tx/0x9dbe74e909f36f3412529a0354ffb5b3d2dcbfeef72656b5875e644da253388a) | success | 447101 | 0.00000268 |
| vrf fulfilment 59663193646395356548906427505253721931753508864686696196338373383958955670878 | [0xb34057b9…](https://sepolia.basescan.org/tx/0xb34057b990d466c616cf19f9b5ce8aaac32a50a2b94f2489d1b5ab26f784974c) |  | 634441 |  |
| settle | [0xa338b3f9…](https://sepolia.basescan.org/tx/0xa338b3f91f5a10ab607986aa16f12a47f7dec78b8a4ac0e20d8cea726633bfa2) | success | 1007061 | 0.00000604 |
| withdrawFeeCredit(referrer) | [0x3bc8fb03…](https://sepolia.basescan.org/tx/0x3bc8fb03647d19196d99900eff2cd502fa22a34dc22eb26f3f6e1084fa761ae6) | success | 38216 | 0.00000023 |
| deploy Swapper (test router) | [0x6fe66896…](https://sepolia.basescan.org/tx/0x6fe66896d82327968e83193b74bac8ba0215409241ae4dd682d4b9ccf7150021) |  | 726205 |  |
| swap: buy ENGINE with 0.01 ETH | [0x591b620c…](https://sepolia.basescan.org/tx/0x591b620c6a654d00c902b5474864a46c92cf88654db0ed31f738a752f4f067ae) | success | 213776 | 0.00000128 |
| approve router | [0x56dc2626…](https://sepolia.basescan.org/tx/0x56dc262696205cc3c92d58c807d603a5eedb98ff6e409490cd52585df298d504) | success | 45970 | 0.00000028 |
| swap: sell half the ENGINE | [0x3ef53635…](https://sepolia.basescan.org/tx/0x3ef53635f801bf7d25ee28f498e1298ba16f1ceaae31aa2bf9758c4031b8f43c) | success | 137105 | 0.00000082 |
| hook.distribute | [0x667ea842…](https://sepolia.basescan.org/tx/0x667ea842c57cc359f8d5163a57697d40fc984bb2a9f7fd79a831ae8c78f9e0c0) | success | 213945 | 0.00000128 |
| redeem Shape #15 (slippage scenario) | [0xe0a36fff…](https://sepolia.basescan.org/tx/0xe0a36fffa00bd1fee9fd9f34619deae1d71ee2d2ebbe11a59b217c8e8160fee1) | success | 61989 | 0.00000037 |
| redeem Shape #16 (slippage scenario) | [0xacb6cc31…](https://sepolia.basescan.org/tx/0xacb6cc3101462eb3d338de72344694cff3936fbe0b0be18cc17a18d4ea3a4fa4) | success | 61989 | 0.00000037 |
| redeem Shape #10 (slippage scenario) | [0x0a0d4592…](https://sepolia.basescan.org/tx/0x0a0d45920f42d9c643c0dc78a4e13ccb2bf54053e3937f9c773077382ec15ad7) | success | 61989 | 0.00000037 |
| redeem Draw Pack #5 (slippage scenario) | [0x16587b9f…](https://sepolia.basescan.org/tx/0x16587b9ff5f4b33c7b93565be58534fed2c78ff450b758fc7a8b1338cbd24090) | success | 153912 | 0.00000092 |
| redeem Shape #1 (slippage scenario) | [0x3f26607b…](https://sepolia.basescan.org/tx/0x3f26607b247aa89dadf2c116d7a7917824aecb3d163eea1016357727655c89ed) | success | 61989 | 0.00000037 |
| redeem Draw Pack #8 (slippage scenario) | [0xb3d915a4…](https://sepolia.basescan.org/tx/0xb3d915a44230ebfb98459facbcbb8f444a5490c7dcafab9857768fae4b47d530) | success | 183328 | 0.00000110 |
| redeem Shape #6 (slippage scenario) | [0xa590ae1d…](https://sepolia.basescan.org/tx/0xa590ae1d6d49496924ce504e7e90bdf3b9525f57dcfb00cd7b63d6ea5374b460) | success | 61989 | 0.00000037 |
| redeem Shape #12 (slippage scenario) | [0x765488f6…](https://sepolia.basescan.org/tx/0x765488f673722f8386d39988d8e45d87d139f2b25dc2a6de5e4d389df96f794e) | success | 61989 | 0.00000037 |
| outage acquireBatch(3) #1 | [0x9b688562…](https://sepolia.basescan.org/tx/0x9b688562309ac6bd4f05df8ce8dbfc305a07834bd574dc35f7c34856b4a1f3d2) | success | 789181 | 0.00000474 |
| vrf fulfilment 100009701841889224925893199765864705827683608251486410761247391586928620170079 | [0xeb4f7735…](https://sepolia.basescan.org/tx/0xeb4f77357a8c05d2aa66b62ef880ebd51073f8b4a6916050681bf5f23ff57c37) |  | 1075928 |  |
| outage acquireBatch(3) #2 | [0x47ce9c3d…](https://sepolia.basescan.org/tx/0x47ce9c3d135ab5b5008ff2631f8c85bce9b1459214c02e115b7b2b4ef7b3e538) | success | 789181 | 0.00000474 |
| vrf fulfilment 24273584807571514069978513091068955535563965592444750299400144216071489281570 | [0x168b7d83…](https://sepolia.basescan.org/tx/0x168b7d830af795eb5e23e73098d667d54a9f9738574fe486bb5a1fe1eb60d006) |  | 1042452 |  |
| outage acquireBatch(3) #3 | [0x4902ffd4…](https://sepolia.basescan.org/tx/0x4902ffd443fa162428fbeba3d0f21f87d1c95ff40723881462561d70dc464a84) | success | 789181 | 0.00000474 |
| vrf fulfilment 28891581271209689860260874116276600112806947623091524899117845450719335455179 | [0xd92a15e4…](https://sepolia.basescan.org/tx/0xd92a15e44b81263f278f7851d850d6064f6d8201e9777df5ed55181637320391) |  | 1017438 |  |
| settle | [0xecd8d373…](https://sepolia.basescan.org/tx/0xecd8d373a1d436c0fdc391d5595176dc7d8ea17faf57115c165d6f4f3f41d455) | success | 6059804 | 0.00003636 |
| deploy-pol | [0x50a55a38…](https://sepolia.basescan.org/tx/0x50a55a384eda7b62ecc2a3aed49ed2416c1fda3e93df55ede7a04a8ad819ca3c) | success | 171722 | 0.00000103 |
| settle | [0x6e2b7d41…](https://sepolia.basescan.org/tx/0x6e2b7d4185b14f8bc5e4dfae557bfccae5e43ccce9f8f169461ff252b0417199) | success | 80714 | 0.00000048 |
| redeem Shape #3 (recycle before in-time batches) | [0x2a04d037…](https://sepolia.basescan.org/tx/0x2a04d037acf2bb412fc77e840afd847a8190b112d67833585925b1fa508136ee) | success | 61989 | 0.00000037 |
| redeem Shape #43 (recycle before in-time batches) | [0xf20d7099…](https://sepolia.basescan.org/tx/0xf20d7099fe2b53d55ba0ca6171010541c0f92b5a2c1e9ccda1ef2e7339bf48c6) | success | 61989 | 0.00000037 |
| redeem Shape #9 (recycle before in-time batches) | [0xf440d3a9…](https://sepolia.basescan.org/tx/0xf440d3a9bbd6ad8f5e870cc96669b433403bd277ed86bda1c610d1ae7b973286) | success | 61989 | 0.00000037 |
| redeem Shape #11 (recycle before in-time batches) | [0xbf279ef1…](https://sepolia.basescan.org/tx/0xbf279ef1c219abfefd42c4dff5c919682dd98b4645817994cc6ed0d0ee47b9ac) | success | 61989 | 0.00000037 |
| redeem Draw Pack #3 (recycle before in-time batches) | [0x21476b9f…](https://sepolia.basescan.org/tx/0x21476b9f00e464a1c2b719a78fab0f9d70b1ee2151f2234835b10462ebc514dc) | success | 153912 | 0.00000092 |
| redeem Draw Pack #11 (recycle before in-time batches) | [0x5d3bda43…](https://sepolia.basescan.org/tx/0x5d3bda432720bb45fb76d173c8ceae355f77e26e49858d8015fcc36d22d87c3a) | success | 153912 | 0.00000092 |
| redeem Shape #40 (recycle before in-time batches) | [0x2e82f77f…](https://sepolia.basescan.org/tx/0x2e82f77ffb5299bf09fbbf7a0fd6ec989c486b727a55bc9b2c4514ec804d3b1b) | success | 61989 | 0.00000037 |
| redeem Shape #14 (recycle before in-time batches) | [0x4c8da3c8…](https://sepolia.basescan.org/tx/0x4c8da3c823e0017c72e8982793a988279c6ee1cee754bbd7fcf8a67091fddc6b) | success | 61989 | 0.00000037 |
| redeem Shape #2 (recycle before in-time batches) | [0x1a6c34a3…](https://sepolia.basescan.org/tx/0x1a6c34a3f58fe2cf8e3b122ceb6a21ff4fa314df467ef993cdf13ce04cfa86c7) | success | 61989 | 0.00000037 |
| acquireBatch(7) with the VRF float | [0x0cd76ff9…](https://sepolia.basescan.org/tx/0x0cd76ff99b41a71f2c807a0c8c6d498ae13ae93023ee16613a83f041903244c9) | success | 1473377 | 0.00000884 |
| vrf fulfilment 66672454273205216479941305596011963094483456086258634409195679504991112547677 | [0xbaa3317c…](https://sepolia.basescan.org/tx/0xbaa3317c9fd0070cf82a3d498a87be2b2f91d8a77b35607d68770e633c8a5383) |  | 1803449 |  |
| settle | [0x3f96cda3…](https://sepolia.basescan.org/tx/0x3f96cda34014b1e8b5166afb7c4800f1337ff289589be0c0b833bae0af797bd7) | success | 5370780 | 0.00003222 |
