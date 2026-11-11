{#id: REVIEW_2_Substantiv}
## Substantive corrections and inconsistencies

{#id: REVIEW_3_4}
### 4. Correct baker eligibility requirements

[190-baking.md:29](190-baking.md#L29)

**Confirmed factual error.** The paragraph conflates minimum baking power with the baker’s own frozen stake. Documentation distinguishes a 6,000 tez baking-power threshold and a 600 tez minimum own stake, with stake/delegation caps and weighting also relevant. Replace the blanket “6,000 or 10%” rule with requirements for the protocol being demonstrated. [Octez proof of stake](https://octez.tezos.com/docs/alpha/proof_of_stake.html). PDF p. 150.

{#id: REVIEW_3_5}
### 5. Complete the governance success conditions

[190-baking.md:123](190-baking.md#L123)

**Confirmed omission.** Exploration and Promotion need both participation quorum and an 80% Yea supermajority among Yea/Nay voting power. Pass contributes to participation but is excluded from that ratio. Explain that proposals have a separate 5% support threshold; the moving participation quorum belongs to the ballot periods. Mention the tie case in Proposal. [Octez voting rules](https://octez.tezos.com/docs/alpha/voting.html). PDF pp. 158–166.

{#id: REVIEW_3_6}
### 6. Fix the interpretation of the voting percentages

[190-baking.md:129](190-baking.md#L129)

**Misleading wording.** Say “Participation is 39.92%; the required quorum is 55%,” if that is what the screenshot shows. The current wording can mean 39.92% × 55%. Keep participation, Yea/Nay result and proposal support clearly separate. PDF p. 162.

{#id: REVIEW_3_7}
### 7. Use a bounded unstaking delay

[160-delegatingstaking.md:8](160-delegatingstaking.md#L8)

**Factual precision.** Current user documentation says three cycles plus the remainder of the current cycle, up to approximately four days. “Takes 4 cycles” and “as soon as the 4 cycles are up” imply a fixed interval and instantaneous bot processing. Say “up to about four days on Mainnet,” with finalization after eligibility. Apply consistently and revisit the `unstake`/`unstakedays` variables. [Tezos staking guide](https://docs.tezos.com/using/staking). PDF pp. 60, 74–75.

{#id: REVIEW_3_8}
### 8. Distinguish refutation time from withdrawal completion

[200-etherlink.md:37](200-etherlink.md#L37)

**Confirmed factual correction for the existing EVM bridge; future Michelson support remains unverified.** The current bridge documentation distinguishes a 14-day refutation period from about 15 days end to end, and fast withdrawals of about a minute rather than literally immediately. Do not promise identical behavior for an unreleased Michelson withdrawal feature. [Etherlink XTZ bridge](https://docs.etherlink.com/evm/bridging/bridging-tezos/). PDF p. 176.

{#id: REVIEW_3_9}
### 9. Correct the stablecoin reserve description

[170-dapps.md:169](170-dapps.md#L169)

**Confirmed overstatement.** The issuer describes a composite reserve including USDC, USDP and GUSD, rather than one cash dollar directly held for each USDtz. Attribute the backing claim to the issuer and distinguish the intended dollar peg from a guaranteed market price. The public reserve material is dated; current solvency has not been independently verified. [Issuer reserve description](https://usdtz.com/reserve). PDF p. 121.

{#id: REVIEW_3_10}
### 10. Correct the white-paper date in both bibliography sources

[920-bibliography.md:9](920-bibliography.md#L9)

**Confirmed factual error.** The linked white paper is dated 2 September 2014. Correct `bibliography.txt` as well as the generated reading list so regeneration preserves the correction. [Linked white paper](https://tezos.com/whitepaper.pdf). PDF p. 195.

{#id: REVIEW_3_11}
### 11. Avoid “distributed” as the expansion of dApp and DEX

[170-dapps.md:4](170-dapps.md#L4)

**Terminology correction.** The standard names are decentralised application and decentralised exchange. The text already expands DEX correctly in Transactions and Addresses. Change the chapter title, definition, “distributed exchange” and cross-references consistently. PDF p. 91.

{#id: REVIEW_3_12}
### 12. Distinguish a login signature from an on-chain transaction

[170-dapps.md:47](170-dapps.md#L47)

**Conceptual correction.** A message-signing login/authentication request is not necessarily an on-chain transaction and need not incur a network fee. Identify the request actually shown, and distinguish connecting, signing a login message and approving a purchase. Apply the same distinction to the Teia login wording. PDF pp. 99, 109.

{#id: REVIEW_3_13}
### 13. Qualify the NFT explanation

[170-dapps.md:86](170-dapps.md#L86)

**Conceptual correction.** Distinguish a token identifier from multiple editions/balances under one identifier; copies need not have individually distinct token IDs. The five-edition Teia example needs this distinction. Avoid suggesting the token is the artwork file or an unconditional grant of all rights to that artwork. [FA2 token types and identifiers](https://docs.tezos.com/architecture/tokens/FA2). PDF pp. 107–110.

{#id: REVIEW_3_14}
### 14. Qualify burn and royalty guarantees

[170-dapps.md:78](170-dapps.md#L78)

**Overgeneralisation.** Describe what these particular contracts/marketplaces allow. Burn is optional in FA2, and a royalty percentage in metadata is not enough to promise payment on every possible resale. The Teia example says “I will receive 10%” without qualifying the sale mechanism. [FA2 optional mint/burn entrypoints](https://docs.tezos.com/architecture/tokens/FA2). PDF pp. 107–110.

{#id: REVIEW_3_15}
### 15. Clarify off-chain artwork storage

[170-dapps.md:84](170-dapps.md#L84)

**Overgeneralisation.** Say the artwork in this example is stored through IPFS; not every NFT uses it. Briefly explain that IPFS availability depends on someone retaining/pinning the content. [IPFS persistence documentation](https://docs.ipfs.tech/concepts/persistence/). PDF p. 107.

{#id: REVIEW_3_16}
### 16. Do not describe every public-key scheme as immediately broken by any quantum computer

[005-Preface.md:58](005-Preface.md#L58)

**Factual precision.** Quantum computers already exist; the relevant threat is a sufficiently capable, fault-tolerant cryptographically relevant quantum computer. Replace the categorical timing statement. Similarly, describe ML-DSA as designed to resist known classical and quantum attacks rather than absolutely secure against all attacks. PDF pp. vii, 49.

{#id: REVIEW_3_17}
### 17. Clarify what account creation does

[110-starting.md:24](110-starting.md#L24)

**Internal conceptual inconsistency.** Key generation happens locally; the chapter later correctly says the address is not yet found on chain. Say the reader has a key pair and address ready to receive funds, and explain first funding separately from public-key revelation. “Name for your address book” should be “alias for this account.” PDF pp. 5, 12.

{#id: REVIEW_3_18}
### 18. Correct the derivation-path explanation

[150-othertypesofaccount.md:91](150-othertypesofaccount.md#L91)

**Technical correction.** `m` denotes the master/root node, not the account’s private key. Purpose 44 identifies the BIP44 structure; “44 means legacy” imports Bitcoin-specific terminology into a general explanation. Explain that the displayed four-component hardened Tezos path is a scheme-specific convention rather than the exact five-level BIP44 template below it. Distinguish mnemonic words, the derived seed and an optional BIP39 passphrase. [BIP44](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki), [BIP39](https://bips.dev/39/). PDF pp. 51–54.

{#id: REVIEW_3_19}
### 19. Do not equate splitting a string with a robust sharing scheme

[150-othertypesofaccount.md:131](150-othertypesofaccount.md#L131)

**Technical guidance needs revision.** Cutting a key or mnemonic into halves is not threshold secret sharing, leaks partial information and creates recovery dependencies. In particular, do not suggest casually applying the same procedure to a hardware wallet recovery phrase. Explain the limits or remove this recommendation in a beginner manual. PDF p. 57.

{#id: REVIEW_3_20}
### 20. Make backup and restore instructions precise

[165-settings.md:17](165-settings.md#L17)

**Procedure needs verification.** Identify whether the backup is a directory, archive or collection of files and the exact restore steps, including quitting Signet and preserving the current directory first. “Moved to ~/.signet” is ambiguous and could produce a nested directory or overwrite newer keys. Match the configured wallet path, not only the default. No real wallet files were inspected. PDF p. 79.

{#id: REVIEW_3_21}
### 21. Do not imply copying another item erases all clipboard copies

[150-othertypesofaccount.md:121](150-othertypesofaccount.md#L121)

**Technical limitation.** Copying another item replaces the current clipboard item; it does not necessarily clear clipboard histories, synchronization or other retained copies. Revise the claim, and clarify what backup material must be preserved for encrypted exported keys. PDF pp. 8–9, 56.

{#id: REVIEW_3_22}
### 22. Repair the macOS node command

[910-apx-ownnode.md:74](910-apx-ownnode.md#L74)

**Confirmed executable-example error.** Add a trailing backslash after `--history-mode=rolling`. As printed, the shell runs the first two lines and then treats `--net-addr=...` as a new command. PDF p. 190.

{#id: REVIEW_3_23}
### 23. Keep the Docker history mode consistent with the snapshot

[910-apx-ownnode.md:36](910-apx-ownnode.md#L36)

**Procedure needs verification.** The Docker config command omits `--history-mode=rolling`, while the downloaded snapshot is rolling. Add an explicit matching history mode rather than relying on the image default or snapshot-import behavior. Pin the tested Octez image/version instead of a moving `latest` tutorial target. PDF pp. 189–190.

{#id: REVIEW_3_24}
### 24. Correct the Docker RAM recommendation

[910-apx-ownnode.md:21](910-apx-ownnode.md#L21)

**Resource guidance error.** The example begins with a 16GB Mac and then assigns all 16GB to Docker, leaving no sensible allowance for macOS and Signet. Give a hardware-dependent allocation and state the tested RAM/disk requirements. The 50% default is correct. [Docker resource settings](https://docs.docker.com/desktop/settings-and-maintenance/settings/). PDF p. 188.

{#id: REVIEW_3_25}
### 25. State missing command-line prerequisites

[910-apx-ownnode.md:82](910-apx-ownnode.md#L82)

**Reproducibility gap.** `wget` is not supplied by default on macOS; either use the already-demonstrated `curl` or include installation. For Debian, use `ip -br addr` or state the `net-tools` prerequisite for `ifconfig`; verify `extrepo` availability for the target installation. Clarify that `$` is a prompt to omit when copying. PDF pp. 191–192.

{#id: REVIEW_3_26}
### 26. Clarify local RPC binding in the Docker example

[910-apx-ownnode.md:34](910-apx-ownnode.md#L34)

**Scope mismatch in the instructions.** The same-Mac example publishes RPC on all host interfaces, alongside unrestricted RPC in the container. For a localhost-only example, publish `127.0.0.1:8732:8732`; explain the deliberate change needed for the separate home-server example. This is a concrete issue in the printed command, not a review of application code. PDF pp. 189–190.

{#id: REVIEW_3_27}
### 27. Distinguish regulatory cooling-off from provider delays

[110-starting.md:103](110-starting.md#L103)

**Factual precision.** The FCA rule concerns a minimum 24-hour pause in the qualifying first-time consumer promotion journey, not a blanket seven-day waiting period for crypto delivery or every purchase. Clearly separate the author’s seven-day provider experience from that rule. [FCA explanation](https://www.fca.org.uk/publications/good-and-poor-practice/assessing-compliance-back-end-cryptoasset-financial-promotions-rules). PDF pp. 20–23.

{#id: REVIEW_3_28}
### 28. Reconcile the send amount

[140-transactions.md:24](140-transactions.md#L24)

**Confirmed internal inconsistency.** The introduction says 5 tez; the subsequent instruction says 15 tez. Choose the amount matching the screenshots and make the whole example agree. PDF pp. 32, 35.

{#id: REVIEW_3_29}
### 29. Show the signing screenshot for Bob

[180-multisig.md:52](180-multisig.md#L52)

**Confirmed source mismatch.** After Bob signs, the manuscript reuses `180/bobmultisig.png`, which earlier illustrates adding a multisig. `180/bobsign.png` exists and appears intended; inspect it before replacing. PDF pp. 136–137.

{#id: REVIEW_3_31}
### 31. Repair literal code fences and missing references

An additional stray U+FFFC occurs after the account-generation section. PDF pp. 152, 190–191.

{#id: REVIEW_3_32}
### 32. Reconcile direct wallet pairing status

[250-whatscoming.md:12](250-whatscoming.md#L12)

**Confirmed internal inconsistency.** The dApp chapter already says Teia lists Signet and shows the direct connection method. Say some dApps still need manual pairing; remove the blanket requirement. In the dApp chapter, “You will always be able” is also too absolute: it depends on the site exposing a compatible pairing code. PDF pp. 93, 109, 185.

{#id: REVIEW_3_33}
### 33. Reconcile TzEL present and future tense

[250-whatscoming.md:40](250-whatscoming.md#L40)

**Confirmed internal inconsistency.** The development story says support shipped on 21 October, and this paragraph ends by saying it works today, but the earlier sentences describe the same support as future work. Separate implemented experimental features from planned improvements. PDF pp. xii, 186.

{#id: REVIEW_3_34}
### 34. Make book-date and chronology choices explicit

[005-Preface.md:17](005-Preface.md#L17)

**Author decision.** This preview is dated 28 October, the preface is signed 5 November, and the development story is dated 28 October. A publication-date preface may be intentional; confirm it. “Been in development for 23 days” and “since 5 October” also frame an unusually short timeline; label the story’s date clearly. `variables.txt` also contains the November date. PDF pp. i–ii, xiii.

{#id: REVIEW_3_35}
### 35. Supply the promised introduction

[100-introduction.md:4](100-introduction.md#L4)

**Known unfinished content.** The introduction contains only a placeholder. The governance chapter explicitly says governance has already been discussed there. Use TERMS.md as a coverage checklist, prioritizing the basic mental model and deferring cryptographic details. Acknowledgements also still says “To follow.” PDF pp. xv, 1, 157.



{#id: REVIEW_2_Consistenc}
## Consistency and presentation pass

- Follow `STANDARDS.md`: italicized, initially capitalized network names; code formatting for menu items and `tz` addresses; TzKT and TzEL capitalization. Lowercase *mainnet*/*shadownet*, plain Shadownet, `tzkt`, and `defi`/`deFi` occur in the current text. Use DeFi consistently.
- Preserve the book’s distinction between a wallet and an account. The first-run instructions say “create a new wallet”; the key-generation section says “name for your address book”; several transfers say “wallet” where the intended object is an account. Historical quotations/specifications may deliberately retain earlier wording.
- Standardize Mt Pelerin, GitHub, Ledger, Mac App Store, WalletConnect, 3Route, Objkt/objkt.com and IPFS (InterPlanetary File System). Keep filenames unchanged unless their references are updated.
- The receive chapter calls a QR code a “bar code” and a “sending address.” Prefer “QR code encoding the recipient address” so beginners do not confuse sender and recipient.
- Consider writing amounts as “5 tez” rather than “5tz” throughout, and define tez / XTZ / the tez symbol once in the introduction. Distinguish Tezos, the network, from tez, its native asset.
- The appendix command blocks switch between including `$` and omitting it; readers need a consistent convention. Wrapped keys and signatures in PDF p. 152 have continuation markers: explain that those markers are not part of values to paste.
- Sampled rendered PDF pages confirmed the stray backticks (p. 152), missing references (pp. 190–191), and the split key-type table (pp. 48–49). The table is narrow and verbose; shorten the Notes column or move explanations into prose. Screenshot placement leaves substantial whitespace on some pages; this is a layout suggestion, not missing text.
- Every active Markdown image reference resolved to an existing resource, and explicit internal anchor targets resolved. This does not verify that each screenshot depicts the described step; Bob’s repeated screenshot is a concrete mismatch.

{#id: REVIEW_2_Claims}
## Claims still requiring author or release-specific verification

These are not asserted to be wrong. Recheck them against a named Signet release and a dated network/protocol snapshot before publication.

- **Network support:** `tz5` availability on Shadownet/Ushuaianet, Mainnet activation expectations, `tz6` scope, Quantumnet/Bakingnet lifetimes and snapshot URLs. Avoid “will soon” without a date or planned protocol. The table’s “All” needs to mean supported networks at the stated date, not every custom network.
- **Protocol constants:** the five-cycle staking-parameter delay, maximum staking ratio, key activation delay and slashing behavior. Prefer protocol-scoped facts and explain when consensus/companion-key changes actually become active. Do not imply replacement keys take effect immediately after confirmation.
- **Governance example:** distinguish a local Tallinn sandbox voting for Ushuaia from the live Mainnet protocol and from Ushuaianet. “Most of the time” in Proposal is an observation about participation, not a protocol rule.
- **Companion key:** expand DAL and distinguish DAL attestations from ordinary consensus attestations; verify the exact signing role of consensus versus companion keys for the demonstrated protocol.
- **Application behavior:** minimum macOS version and supported CPUs, current DMG installation, exact labels such as `Staking` versus `Stake`, temporary-key persistence, backup format, and whether a chain-ID mismatch merely warns or blocks operations. These were not checked against app source or real wallet data.
- **Provider specifics:** distinguish brokers/on-ramp services from order-book exchanges; verify Mt Pelerin country exclusions and payment methods rather than implying every provider supports every credit card or jurisdiction.
- **Historical claims:** release timestamps/version lists, first graphical-wallet transaction on Quantumnet, first graphical TzEL wallet, and Teia being first to list Signet. Preserve the first-person story but cite evidence or qualify priority claims.
- **Development tooling:** confirm the intended name “Fable” and exact `claude init` command in the historical story. The excerpted specification’s “tz1, 6” should be clarified as “tz1 through tz6” if it is not being reproduced verbatim.
- **Market and platform claims:** Objkt’s seven-million figure and largest-marketplace claim, quoted APYs/capacity/fees, “first official rollup,” Octez.js roadmap expectations and cross-VM Michelson deployment status all need dates or precise attribution. Screenshots demonstrate historical quotes, not current offers.
- **NFT rights:** verify the actual license for each artwork; distinguish token ownership from any permission concerning the underlying image. If this is discussed legally, source the specific license and applicable legal guidance.
- **Transaction retry:** replace “try the transaction again” with a check of its operation hash/status first. A timeout does not prove the first operation failed; a fresh send can duplicate the payment.
- **Double signing:** “same level” is too loose as a technical definition in a round-based consensus system. Describe conflicting signed blocks/attestations for the same relevant level/round context, and make the remote-signer protection conditional on shared persistent anti-double-signing state. “Some or all” stake loss should be tied to the actual offense and protocol.
- **Key reuse across chains:** the shared secp256k1 scheme permits compatible key material, not identical addresses or automatically interchangeable wallet formats. State this distinction and avoid recommending routine cross-chain key reuse.
- **Book promises:** the preface promises buying and selling artwork; the worked examples mainly purchase, mint and list. Consider a brief resale walkthrough, or narrow that promise.

