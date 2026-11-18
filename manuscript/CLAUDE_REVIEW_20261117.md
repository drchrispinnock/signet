# Claude review, 17 November 2026

## Rechecked 17 November, 21:00 (files as saved at 20:55)

## Resolve before publishing (placeholders) <!-- listful: collapsed -->

- [ ] 100-introduction.md:5 — italic "This will be the last chapter to be written" placeholder; the `Introducing Signet` section (lines 10–12) is empty. RECHECK: both still there

## Facts and consistency

- [ ] 150-othertypesofaccount.md:125 — "burger memory" is fixed. RECHECK: a word is missing in "by using the `Scan QR code...` on the burger menu"; add "option" after the label
- [ ] 190-baking.md:108 — "We discussed governance in the [Introduction]". RECHECK: still links to the empty Introduction
- [ ] 190-baking.md:28 — RECHECK: now `Register as a Baker`; the app label is `Register as a baker...` (lower-case "baker", ellipsis)
- [ ] 190-baking.md:110 — "For Ushuaianet, the hash is". CHRIS SAYS: Yes, but I say on the same line: "The test network ran the Tallinn protocol. We will vote for the Ushuaia protocol on the network." CLAUDE: agreed, line 119 explains the setup. The remaining point is small: the hash names the Ushuaia *protocol*, while *Ushuaianet* is a network, so "For Ushuaia, the hash is:" reads more accurately. Close if you prefer it as is
- [ ] 180-multisig.md:96 and 006-DevelopingSignet.md:74 — ellipses. RECHECK: 180:96 and `Sign multisig transaction...` in 006:74 are fixed, but `Submit multisig transaction` in 006:74 still has no ellipsis
- [ ] 110-starting.md:138 — RECHECK: now `Connect a Ledger...`, but the cold-start button has no ellipsis: `Connect a Ledger`
- [ ] 110-starting.md:62 vs 910-apx-ownnode.md:77,84 — RECHECK: 910 now uses `usermod -aG sudo`, but 110:62 still says to edit `/etc/group`; use the same instruction in both
- [ ] 170-dapps.md:19 vs 213 — line 19 now explains that some dApps have older lists. RECHECK: 213 still says "As with the other dApps, our wallet isn't on the list yet", which contradicts TezInvaders (26) and Teia (112); say "3Route's list doesn't include Signet yet"
- [ ] 170-dapps.md:4 — the intro now lists every dApp in the chapter. RECHECK (minor): line 9 still says "We will go through the full process with Objkt.com and 3Route" only
- [ ] 200-etherlink.md:54–57 — the "Link" fee step: the app button is `Link to Etherlink`; confirm the step still applies after Etherlink 8.0. LEAVE FOR NOW
- [ ] 006-DevelopingSignet.md:84 — RECHECK: now "on Bitcoin, Ethereum and on other EVM-based chains", which still groups Bitcoin with the EVM chains; suggest "on Bitcoin, and on Ethereum and other EVM-based chains"
- [ ] 150-othertypesofaccount.md:147, 158 — RECHECK: 147 is fixed; 158 still says `Forget account` without the ellipsis
- [ ] 150-othertypesofaccount.md:9 vs 24 — "five key types" vs "6 types of keys": the first is what Signet creates and the second what Tezos has; make that explicit
- [ ] 150-othertypesofaccount.md:40 — check `tz5` availability on *Bakingnet* and *Weeklynet* (the table lists only Shadownet, Quantumnet, Ushuaianet)
- [ ] 150-othertypesofaccount.md:108 vs 114 — "Ledger Wallet (formerly Ledger Live)", then "Ledger Live" three times on line 114
- [ ] 160-delegatingstaking.md:105 — "It has happened very often on the Tezos network" overstates double baking; "a number of times"?
- [ ] 160-delegatingstaking.md:94 — Finn the finalisation bot: check the claim and add a link
- [ ] 160-delegatingstaking.md:8 vs 190-baking.md:8, 101 — parameter names differ: "Staking over Baking limit" / "Staking over Baking Limit" / "Limit of staking over baking" (the app uses the last)
- [ ] 140-transactions.md:52 — operation hashes begin with `o` but the second letter varies (`oo`, `op`, `on`...); "beginning `o`"
- [ ] 140-transactions.md:16 and 170-dapps.md:15 — "bar code"/"barcode" → QR code
- [ ] 140-transactions.md:4 vs 007-Disclaimer.md:14 — "demonstrative purposes" vs "demonstration purposes"
- [ ] 110-starting.md:168, 201 — Mt Pelerin is described as a centralised exchange; it's an on-ramp/broker, so "provider" fits better
- [ ] 100-introduction.md:31 — "The other wallets run in the web browser, as browser extensions or on mobile devices", but Ledger Wallet is desktop software (line 27)
- [ ] 100-introduction.md:33–40 — the "Tezos only" column mixes Yes/No with descriptions ("Tezos, EVM-style chains.", "Multi-asset"); rename the column (e.g. "Chains") or use Yes/No
- [ ] 190-baking.md:135 vs 145 — participation 39.92% against a 55% quorum, then the vote passes; add "other bakers then voted" so it doesn't read as a contradiction
- [ ] {id: CLAUDE_REVIEW_20261117_2_Style}

## Style guide

- [ ] Use "tez", not "tz", for amounts: 006:72; 140:18 (×2), 24, 44, 81; 160:30 (965k tz), 32 (126k tz), 51, 67, 73; 170:34, 55, 71 (also "tz price"), 128, 142, 161, 184, 194, 209, 218; 180:15, 32 (×2), 46; 190:32 (6000tz, 600tz ×2), 116 (999999tz); 200:21 (0tz), 33
- [ ] Punctuation inside italics: 140:18 `*Shadownet.*`, 140:38 `*Tezos Domains.*` and `*Mainnet.*`, 140:66 `` `etherlink.tez`*.* ``, 150:43 `*Mainnet.*`, 165:27 `*Custom.*`, 165:44 `*Mainnet.*`, 170:24 `*Mainnet.*`, 200:15, 27 `*Shadownet.*`, 910:15 `*Mainnet,*`
- [ ] 165-settings.md:27 — `*Shadownet, Bakingnet, Ushuaianet, Weeklynet, Quantumnet*` italicises the commas; italicise each name
- [ ] Network names not in italics: 150:39 (Mainnet), 150:40 (Shadownet, Quantumnet, Ushuaianet), 150:41 (Quantumnet), 180:15 (Shadownet), 250:30 (Shadownet ×2, Quantumnet)
- [ ] `tz` addresses not in code font: 150:41 (tz6), 250:26 (tz6), 006:16 ("`tz1` to 6"), 140:86 ("tz address", KT1)
- [ ] Buttons and menu items not in code font: 110:240, 244 (Buy, Get), 140:13 (Receive), 160:53 (Stake), 160:67 ("click use" → `Use`), 170:26 ("show more"), 170:51 (Show More, Show QR Code, Beacon, Copy to clipboard), 170:157 (same), 150:75 (`Legacy fundraiser derivation`), 200:54, 57 (Receive, Link), 250:30 (Shielded Transactions)
- [ ] 180-multisig.md:56 — "clicks sign" → `Sign`
- [ ] 165-settings.md:17 — `~/.signet` in code font
- [ ] 910-apx-ownnode.md:12 — `Custom` in code font here, *Custom* in italics in 165
- [ ] "wallet" used for an account: 170:147 ("my Tezos wallet address"), 180:15, 48 ×2 ("multisig wallet"), 180:24 ("originating wallet"), 006:19 (in the quoted spec, fine to leave)
- [ ] "Ledger" capitalised: 150:114 ("in the ledger"), 190:12 ("connect the ledger")
- [ ] "DEXs" (250:22) vs "DEXes" (005:8, 140:106)
- [ ] "3route" (170:4, 209) vs "3Route" (170:9, 207, 213)
- [ ] "Layer 2"/"layer 2" mixed: 165:48 vs 51, 200:15, 21, 44, 67, 250:18
- [ ] "private key" (110:124) vs "secret key" elsewhere; 150:26 says they are the same, but pick one for beginners
- [ ] {id: CLAUDE_REVIEW_20261117_2_Spelling}

## Spelling and hyphenation

- [ ] "quantum resistant" → "quantum-resistant" before a noun: 150:45
- [ ] "day to day" → "day-to-day": 150:43, 165:11
- [ ] "Ethereum compatible" → "Ethereum-compatible": 200:6; "Tezos compatible RPC node" → "Tezos-compatible": 165:51
- [ ] "smart-rollup" (250:30) vs "smart rollup" elsewhere
- [ ] "double-bake" (190:163) vs "double bake" (190:159, 165; 160:107); "double sign" (160:105)
- [ ] 100-introduction.md:23 — "electron" → "Electron"
- [ ] 920-bibliography.md:13 vs 17 — "Bitcoin For Dummies" vs "Ethereum for Dummies"; 920:15 "David A Harding" → "David A. Harding"; 920:43 "Niccolo" → "Niccolò"; 920:19 "In Preparation" → "in preparation"
- [ ] 006-DevelopingSignet.md:8 "Git" vs 915-colophon.md:6 "git"
- [ ] {id: CLAUDE_REVIEW_20261117_2_Wording}

## Wording

- [ ] 150-othertypesofaccount.md:9 — "we created an account on Tezos and we created an account using the `tz1` key type": repeated
- [ ] 150-othertypesofaccount.md:123 — stray comma: "Anyone who has a copy of this sheet, has access"
- [ ] 160-delegatingstaking.md:51 — "the last days" → "the last few days"
- [ ] 160-delegatingstaking.md:30 — "They have... it had a few network misses": they/it mixed
- [ ] 180-multisig.md:46 — "We want to send an account `tz1…` 5tz" → "send 5 tez to `tz1…`"
- [ ] 180-multisig.md:56 — missing colon before the signature string
- [ ] 140-transactions.md:13 — "top left of your Signet menu" → "window"
- [ ] 110-starting.md:22 — "Click the file" → "Double-click"; "application folder"/"applications folder" → "Applications folder"
- [ ] 110-starting.md:38 — "Change the `Delete` button to `Keep anyway`" is unclear: say open the menu next to `Delete` and choose `Keep anyway`
- [ ] 190-baking.md:127 — "Remember that the protocol keeps an exponential moving average": not mentioned earlier
- [ ] 190-baking.md:161 — "same slot" vs "same level" (159, 160:105)
- [ ] 200-etherlink.md:74 — link formatting: `[slow governance process ](...)for` has a space inside the brackets and none after
- [ ] 200-etherlink.md:78–79 — no blank line between them, so they join into one paragraph
- [ ] 100-introduction.md:19–29 — inconsistent bold: `**Kukai -**` vs `**Umami** -`; `octez-client` not bold; `[Octez,]` has the comma inside the link
- [ ] 006-DevelopingSignet.md:44 — "the development team launched *Quantumnet*": name Nomadic Labs
- [ ] 150-othertypesofaccount.md:62 — the BIP39 link goes to cryptotag.io; link the BIP itself (github.com/bitcoin/bips)
- [ ] {id: CLAUDE_REVIEW_20261117_2_Layout}

## Layout and whitespace

- [ ] Ends with extra blank lines: 100-introduction.md, 170-dapps.md, 190-baking.md, 200-etherlink.md
- [ ] Doubled blank lines: 100:7–9, 13, 42–43; 110:35, 216; 140:48; 150:129–130; 160:47, 84, 90, 93, 101; 190:18, 68, 94, 138, 155, 167; 200:101; 910:131
- [ ] Trailing spaces: 005:14 (one space; use two or none), 100:21, 31; 110:128, 221; 140:6, 13, 18, 54, 64, 81, 86, 88; 150:17, 26, 28, 53, 55, 112; 160:26, 28, 45, 51, 78; 165:48, 58; 170:101, 112, 118, 147, 173; 190:12, 22, 32, 45, 108, 121, 135; 200:27, 74, 79; 910:28, 162
- [ ] Double spaces mid-sentence: 170:51, 213; 190:110; 200:36, 79
- [ ] Space before comma: 170:26 (`` `Connect Wallet` , ``)
- [ ] Images without a blank line before or after: 110:125; 140:15, 20, 51, 95, 98; 150:52, 69, 77, 122, 124, 153; 160:25, 52, 59, 68, 77, 98; 165:10, 19, 28, 50, 55; 170:25, 90, 124, 127, 132, 141, 216; 190:44, 100, 118, 123, 126, 131, 134, 136, 140, 144; 200:23, 29, 32, 35, 37, 46, 56, 59; 910:14
- [ ] 140-transactions.md:88–89 — no blank line before the code block
- [ ] 160-delegatingstaking.md:64 — blank line inside the code block after the address
- [ ] 200-etherlink.md:23–24 — the image runs straight into the next `{id: …}` heading
