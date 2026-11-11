{#id: REVIEW_1_Book}
# Book review - updated 11 November 2026

Reviewed the 213-page preview `book-output/preview/tezossignet-preview.pdf`, generated 28 October 2026 at 09:29:45 UTC, against the chapters included in `Book.txt`. Page references below use printed book numbers unless explicitly called PDF pages; printed p. 1 is PDF page 19. The cover and front matter account for the offset.

This is an editorial and factual review, not an application-code audit. The original review did not change chapter prose; completed corrections are recorded in DONE below. Findings distinguish confirmed errors, internal inconsistencies, and points that still require author/version verification. External documentation was checked on 28 October 2026; moving `/alpha/` documentation must be matched to the publication protocol before finalizing version-dependent claims.


**2 November update.** Rechecked the current chapter sources and changes since the 28 October review (through commit `9952728`). Findings 6, 10, 12, 30 and 33 are now complete and have been moved to DONE at the end. Partially corrected findings below describe the remaining work. Finding 36 is new. Original finding numbers and anchors are retained. Legacy source line references and PDF page references describe the original reviewed draft; use the quoted phrases to locate passages after edits; no new PDF was generated or visually reviewed in this update. Octez baking/governance, USDtz reserve and Etherlink bridge documentation were selectively rechecked on 2 November; other external checks retain their original date.

**11 November update.** Targeted source rechecks and author corrections completed findings 11, 16, 17, 21, 22, 24, 26, 27, 28, 29, 31, 32, 34, 36. These are moved to DONE below with dated completion notes and their original findings preserved. Finding 23 retains only version pinning; finding 25 retains only Debian 13 execution verification. This was not a new whole-book review or PDF build. Bob’s signing screenshot and the 15 tez send/confirmation screenshots were visually inspected. FCA, Docker and Octez Ushuaia documentation were selectively rechecked. Other active findings retain their earlier review status.

{#id: REVIEW_2_Substantiv}
## Substantive corrections and inconsistencies

{#id: REVIEW_3_4}
### 4. Correct baker eligibility requirements

[190-baking.md:29](190-baking.md#L29)

**Partially corrected.** The paragraph now distinguishes 600 tez of own stake, but still requires 6,000 tez to be staked (including external stakers), and repeats that minimum for a solo baker. The documented threshold is 6,000 tez of **baking power**, not necessarily frozen stake; delegated funds contribute subject to weighting and limits. Rework the solo-baker example and the blanket “10% of your total balance” rule against the demonstrated protocol. The variable name `minfrozen` also mislabels the 6,000 threshold. [Octez baking power](https://octez.tezos.com/docs/alpha/baking_power.html). Original PDF p. 150.

{#id: REVIEW_3_5}
### 5. Complete the governance success conditions

[190-baking.md:123](190-baking.md#L123)

**Partially corrected.** Exploration and Promotion now mention the 80% Yea/Nay supermajority, and Pass is correctly described as contributing to participation. The Proposal paragraph still associates its threshold with the moving participation quorum: state the separate 5% proposal-support threshold and the tie case. Explicitly say Promotion also requires participation quorum; identify Yea as the numerator of the Yea/(Yea + Nay) ratio and exclude Pass from it. [Octez voting rules](https://octez.tezos.com/docs/alpha/voting.html). Original PDF pp. 158–166.

{#id: REVIEW_3_7}
### 7. Use a bounded unstaking delay

[160-delegatingstaking.md:8](160-delegatingstaking.md#L8)

**Partially corrected.** The opening now says three cycles plus the remainder of the current cycle, up to four days on Mainnet, and `variables.txt` separates `unstake` (3) from `unstakebound` (4). The Unstaking section still says “3 cycles (4 days)” as a fixed delay. Make it use the same bounded explanation. The Finn paragraph now waits for eligibility, but contains “unstaked fund”, “eligilbe”, “as within approximately”, and “within 4 on Mainnet” (missing “days”). Separate eligibility from the bot's subsequent finalization rather than promising a processing deadline. [Tezos staking guide](https://docs.tezos.com/using/staking). Original PDF pp. 60, 74–75.

{#id: REVIEW_3_8}
### 8. Distinguish refutation time from withdrawal completion

[200-etherlink.md:37](200-etherlink.md#L37)

**Partially corrected; author has direct developer information.** Slow withdrawals now say approximately 14–15 days. Existing EVM documentation specifies 15 days end to end, a 14-day refutation period, and fast withdrawals within about a minute for a fee; “immediately” remains in the manuscript. Chris notes that he speaks directly to the developers. Keep that information as author-supplied evidence for the planned Michelson feature, and date/attribute the expected behavior rather than treating the EVM documentation as confirmation of an unreleased interface. [Etherlink XTZ bridge](https://docs.etherlink.com/evm/bridging/bridging-tezos/). Original PDF p. 176.

{#id: REVIEW_3_9}
### 9. Correct the stablecoin reserve description

[170-dapps.md:169](170-dapps.md#L169)

**Partially corrected.** The one-cash-dollar-per-token claim is gone and the paragraph now lists USDC, USDP and GUSD. Attribute that reserve description to the issuer; its public reports on this page stop at August 2023, so they do not establish current backing. Prefer “USDtz is a stablecoin intended to track the US dollar” to the newly introduced “wrapped token” unless the specific wrapping mechanism is explained. Use `USDtz` consistently (the revised paragraph switches to `USDTz`) and distinguish the target peg from a guaranteed price. [Issuer reserve description](https://usdtz.com/reserve). Original PDF p. 121.


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



{#id: REVIEW_3_23}
### 23. Keep the Docker history mode consistent with the snapshot

**Partially corrected — checked 11 November 2026.** The Docker configuration now explicitly selects rolling history and its line continuations are correct. The remaining recommendation is to pin the same tested image tag in the pull, configuration, snapshot-import and run commands; they still use latest explicitly or implicitly. No Docker/node execution was performed.

{#id: REVIEW_3_25}
### 25. Finish the command-line prerequisite and example corrections

**Text corrections complete; execution verification outstanding — checked 11 November 2026.** The Linux example and output use ip -br addr. The prerequisite command installs extrepo and wget, matching the Linux snapshot download; Mac downloads use curl. The prompt convention is explained. The complete sequence has not been tested on Debian 13 in this review; confirm that validation before closing this finding.

{#id: REVIEW_3_35}
### 35. Supply the promised introduction

[100-introduction.md:4](100-introduction.md#L4)

**Known unfinished content.** The introduction contains only a placeholder. The governance chapter explicitly says governance has already been discussed there. Use TERMS.md as a coverage checklist, prioritizing the basic mental model and deferring cryptographic details. Acknowledgements also still says “To follow.” PDF pp. xv, 1, 157.


{#id: REVIEW_2_Consistenc}
## Consistency and presentation pass

- Follow `STANDARDS.md`: italicized, initially capitalized network names; code formatting for menu items and `tz` addresses; TzKT and TzEL capitalization. Lowercase *mainnet*/*shadownet*, plain Shadownet, `tzkt`, and `defi`/`deFi` occur in the current text. Use DeFi consistently.
- Preserve the book’s distinction between a wallet and an account. The first-run discussion uses “create a new wallet” for other wallets; Signet’s actual instruction correctly says “Create a new account”. The import-key section still says “name for your address book”; several transfers say “wallet” where the intended object is an account. Historical quotations/specifications may deliberately retain earlier wording.
- Standardize Mt Pelerin, GitHub, Ledger, Mac App Store, WalletConnect, 3Route, Objkt/objkt.com and IPFS (InterPlanetary File System). Keep filenames unchanged unless their references are updated.
- The receive chapter calls a QR code a “bar code” and a “sending address.” Prefer “QR code encoding the recipient address” so beginners do not confuse sender and recipient.
- Consider writing amounts as “5 tez” rather than “5tz” throughout, and define tez / XTZ / the tez symbol once in the introduction. Distinguish Tezos, the network, from tez, its native asset.
- The appendix command blocks switch between including `$` and omitting it; readers need a consistent convention. Wrapped keys and signatures in PDF p. 152 have continuation markers: explain that those markers are not part of values to paste.
- In the original preview, sampled pages confirmed stray backticks (p. 152), missing references (pp. 190–191), and the split key-type table (pp. 48–49). The backticks and `[??]` have since been fixed in source; the three stray object-replacement characters are now removed (finding 31). The table is narrow and verbose; shorten the Notes column or move explanations into prose. Screenshot placement leaves substantial whitespace on some pages; this is a layout suggestion, not missing text.
- In the original review, every active Markdown image reference resolved to an existing resource, and explicit internal anchor targets resolved. This does not verify that each screenshot depicts the described step; Bob’s screenshot mismatch is now fixed and visually checked (finding 29).

- Remaining local wording from the 11 November rechecks: `110-starting.md:112` says “a key pair and an address are ready”; remove “are”. Two U+FFFC characters remain in the excluded draft `networks-material.md`, lines 6–7; they do not affect finding 31’s published chapters. The tz1–tz5 prose/table labels were formatted with backticks; code blocks were preserved.

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
- **Development tooling:** confirm the intended name “Fable”. The author has confirmed running `claude init`; do not reopen that wording. The excerpted specification’s “tz1, 6” should be clarified as “tz1 through tz6” if it is not being reproduced verbatim.
- **Market and platform claims:** Objkt’s seven-million figure and largest-marketplace claim, quoted APYs/capacity/fees, “first official rollup,” Octez.js roadmap expectations and cross-VM Michelson deployment status all need dates or precise attribution. Screenshots demonstrate historical quotes, not current offers.
- **NFT rights:** verify the actual license for each artwork; distinguish token ownership from any permission concerning the underlying image. If this is discussed legally, source the specific license and applicable legal guidance.
- **Transaction retry:** replace “try the transaction again” with a check of its operation hash/status first. A timeout does not prove the first operation failed; a fresh send can duplicate the payment.
- **Double signing:** “same level” is too loose as a technical definition in a round-based consensus system. Describe conflicting signed blocks/attestations for the same relevant level/round context, and make the remote-signer protection conditional on shared persistent anti-double-signing state. “Some or all” stake loss should be tied to the actual offense and protocol.
- **Key reuse across chains:** the shared secp256k1 scheme permits compatible key material, not identical addresses or automatically interchangeable wallet formats. State this distinction and avoid recommending routine cross-chain key reuse.
- **Book promises:** the preface promises buying and selling artwork; the worked examples mainly purchase, mint and list. Consider a brief resale walkthrough, or narrow that promise.

{#id: REVIEW_2_Introducti}
## Introduction coverage

`TERMS.md` separates terms lacking a working explanation from terms explained later or inadequately. A useful introduction should give readers the wallet/account/key model, explain what is held on chain, introduce tez and fees, distinguish Mainnet from testnets, explain baking/staking/governance at a high level, and map the later chapters. Cryptographic algorithms, Docker and specialist baker terms can remain in local explanations or a glossary.

{#id: REVIEW_2_Review}
## Review limits

For the original 28 October review, the active manuscript chapters were read end to end and compared with extracted PDF text. The 2 November follow-up checked the source changes and existing findings; it did not repeat the PDF review or audit application code. Selected PDF pages were visually inspected, rather than all 213 pages at full resolution. Commands were reviewed as text; no nodes, trades, transactions, installs, app tests or wallet operations were run. External links were checked selectively for the factual issues cited, not exhaustively. The excluded Shield chapter and research drafts were not treated as published chapters.

{#id: REVIEW_2_DONE}
## DONE

Findings 1–3 were recorded as complete in the previous review. Findings 6, 10, 12, 30 and 33 were checked against the current sources on 2 November 2026 and are also complete. Original numbering and review details are retained below for reference. The earlier spelling, grammar and local wording pass remains archived here; new wording issues introduced since that pass are listed with the active findings.

The additional findings completed on 11 November are appended at the end of this DONE section. Their original descriptions are historical, not outstanding requests.

{#id: REVIEW_3_1}
### 1. Correct the signing-scheme explanation

[150-othertypesofaccount.md:32](150-othertypesofaccount.md#L32)

**Confirmed factual error.** Only `tz2` and `tz3` in this table use ECDSA. `tz1` uses Ed25519/EdDSA. Change both the preceding paragraph and the `tz1` row; use the conventional abbreviation ECDSA. [Octez account documentation](https://octez.tezos.com/docs/alpha/accounts.html). PDF pp. 48–49.

{#id: REVIEW_3_2}
### 2. Separate contract multisig from native multisig

[180-multisig.md:5](180-multisig.md#L5)

**Confirmed factual error.** This tutorial originates a `KT1` contract. Tezos also has native BLS/`tz4` multisig accounts, introduced with Seoul; these are different and can stake and bake. Describe the demonstrated feature as the Octez-compatible multisig contract. The development story also says multisig was implemented recently: qualify which scheme is meant. [Tezos account architecture](https://docs.tezos.com/architecture/accounts). PDF p. 129.

{#id: REVIEW_3_3}
### 3. Correct the start date of individual staking

[160-delegatingstaking.md:6](160-delegatingstaking.md#L6)

**Confirmed factual error.** Individual staking launched with Paris in June 2024, not 2023. Keep older baker deposits separate from this feature. [Tezos staking overview](https://tezos.com/stake-tez). PDF p. 60.

{#id: REVIEW_3_6}
### 6. Fix the interpretation of the voting percentages

**Done — checked 2 November 2026.** The wording now separates the 39.92% participation figure from the required 55% quorum and reports the 100% Yay result separately.

Original finding:


[190-baking.md:129](190-baking.md#L129)

**Misleading wording.** Say “Participation is 39.92%; the required quorum is 55%,” if that is what the screenshot shows. The current wording can mean 39.92% × 55%. Keep participation, Yea/Nay result and proposal support clearly separate. PDF p. 162.

{#id: REVIEW_3_10}
### 10. Correct the white-paper date in both bibliography sources

**Done — checked 2 November 2026.** Both `bibliography.txt` and `920-bibliography.md` now give the white paper year as 2014.

Original finding:


[920-bibliography.md:9](920-bibliography.md#L9)

**Confirmed factual error.** The linked white paper is dated 2 September 2014. Correct `bibliography.txt` as well as the generated reading list so regeneration preserves the correction. [Linked white paper](https://tezos.com/whitepaper.pdf). PDF p. 195.

{#id: REVIEW_3_12}
### 12. Distinguish a login signature from an on-chain transaction

**Done — checked 2 November 2026.** Objkt now identifies an authentication request and distinguishes it from an on-chain transaction; Teia now says “sign the login request”. The purchase/mint signing steps remain separate.

Original finding:


[170-dapps.md:47](170-dapps.md#L47)

**Conceptual correction.** A message-signing login/authentication request is not necessarily an on-chain transaction and need not incur a network fee. Identify the request actually shown, and distinguish connecting, signing a login message and approving a purchase. Apply the same distinction to the Teia login wording. PDF pp. 99, 109.

{#id: REVIEW_3_30}
### 30. Finish the baker paragraph

**Done — checked 2 November 2026.** The unfinished fragment has been removed and the baker setup paragraph now ends with complete bibliography references.

Original finding:


[190-baking.md:31](190-baking.md#L31)

**Confirmed incomplete sentence.** This fragment is printed immediately before the Consensus and Companion keys heading. Complete it or remove it. PDF p. 150.

{#id: REVIEW_3_33}
### 33. Reconcile TzEL present and future tense

**Done — checked 2 November 2026.** The future-tense shielding/unshielding description and planned third-balance implementation have been replaced with present-tense experimental support.

Original finding:


[250-whatscoming.md:40](250-whatscoming.md#L40)

**Confirmed internal inconsistency.** The development story says support shipped on 21 October, and this paragraph ends by saying it works today, but the earlier sentences describe the same support as future work. Separate implemented experimental features from planned improvements. PDF pp. xii, 186.

{#id: REVIEW_3_Spelling}
### Spelling, grammar and local wording

**Applied to the manuscript on 28 October 2026.** All 100 entries below have been addressed, including associated agreement and punctuation. The table is retained as a record of the original findings; its source line numbers refer to the reviewed draft. The preview PDF has not been regenerated.

Each entry gives an exact searchable phrase and a suggested correction. Multiple occurrences of a name or spelling should be corrected consistently. These are editorial suggestions, not silent changes.

| Location                                                          | Current text                                                           | Suggested correction                                                                             |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [005-Preface.md:24](005-Preface.md#L24)                           | I've had urge                                                          | I've had an urge                                                                                 |
| [005-Preface.md:79](005-Preface.md#L79)                           | a days work                                                            | a day's work                                                                                     |
| [005-Preface.md:81](005-Preface.md#L81)                           | the test networks faucet                                               | the test network's faucet / the test networks' faucets                                           |
| [005-Preface.md:123](005-Preface.md#L123)                         | There is relay service                                                 | There is a relay service                                                                         |
| [005-Preface.md:97](005-Preface.md#L97)                           | Then you can used                                                      | Then you can use                                                                                 |
| [005-Preface.md:117](005-Preface.md#L117)                         | As far as I now                                                        | As far as I know                                                                                 |
| [005-Preface.md:54](005-Preface.md#L54)                           | a connect from                                                         | a connection from                                                                                |
| [005-Preface.md:97](005-Preface.md#L97)                           | same cryptographic curve to                                            | same cryptographic curve as                                                                      |
| [005-Preface.md:115](005-Preface.md#L115)                         | 1. Shield tez                                                          | Use a consistent three-item list: 1. Shield tez; 2. Unshield tez; 3. Send a shielded transaction |
| [005-Preface.md:71](005-Preface.md#L71)                           | Mt Pellerin                                                            | Mt Pelerin (throughout; preserve actual resource filenames)                                      |
| [005-Preface.md:26](005-Preface.md#L26)                           | GIT repository                                                         | Git repository                                                                                   |
| [005-Preface.md:52](005-Preface.md#L52)                           | Github                                                                 | GitHub (throughout)                                                                              |
| [005-Preface.md:68](005-Preface.md#L68)                           | deFi                                                                   | DeFi (throughout)                                                                                |
| [005-Preface.md:101](005-Preface.md#L101)                         | at 535                                                                 | at 05:35 (choose one consistent clock format for all release times)                              |
| [110-starting.md:7](110-starting.md#L7)                           | Apple Mac's only                                                       | Apple Macs only                                                                                  |
| [110-starting.md:7](110-starting.md#L7)                           | Mac AppStore                                                           | Mac App Store                                                                                    |
| [110-starting.md:13](110-starting.md#L13)                         | outside the AppStore                                                   | outside the App Store                                                                            |
| [110-starting.md:46](110-starting.md#L46)                         | in a two safe and different places                                     | in two different safe places                                                                     |
| [110-starting.md:38](110-starting.md#L38)                         | There's two rules                                                      | There are two rules                                                                              |
| [110-starting.md:46](110-starting.md#L46)                         | is write it down                                                       | is to write it down                                                                              |
| [110-starting.md:50](110-starting.md#L50)                         | seperate                                                               | separate                                                                                         |
| [110-starting.md:90](110-starting.md#L90)                         | explorer. and suggests                                                 | explorer and suggests                                                                            |
| [110-starting.md:106](110-starting.md#L106)                       | wants it citizens                                                      | wants its citizens                                                                               |
| [110-starting.md:115](110-starting.md#L115)                       | pick for 3 others                                                      | pick from three others                                                                           |
| [110-starting.md:127](110-starting.md#L127)                       | At the tez                                                             | As the tez                                                                                       |
| [110-starting.md:131](110-starting.md#L131)                       | for a beginning                                                        | for a beginner                                                                                   |
| [110-starting.md:79](110-starting.md#L79)                         | [Distributed Apps ](#170-dapps_1_Distribute)chapter                    | Add a space before 'chapter', outside the link; use the revised chapter title                    |
| [110-starting.md:55](110-starting.md#L55)                         | top-level, is                                                          | top level is                                                                                     |
| [140-transactions.md:16](140-transactions.md#L16)                 | gives you the possible                                                 | gives you the option                                                                             |
| [140-transactions.md:18](140-transactions.md#L18)                 | kindly send my wallet                                                  | kindly sent my account                                                                           |
| [140-transactions.md:38](140-transactions.md#L38)                 | as an identifier your account                                          | as an identifier for your account                                                                |
| [140-transactions.md:53](140-transactions.md#L53)                 | due to congested or busy node                                          | due to a congested or busy node                                                                  |
| [140-transactions.md:53](140-transactions.md#L53)                 | We will should you have                                                | We will show you how                                                                             |
| [140-transactions.md:103](140-transactions.md#L103)               | swap you tez                                                           | swap your tez                                                                                    |
| [150-othertypesofaccount.md:15](150-othertypesofaccount.md#L15)   | choose the protect                                                     | choose to protect                                                                                |
| [150-othertypesofaccount.md:15](150-othertypesofaccount.md#L15)   | gets hold the encrypted                                                | gets hold of the encrypted                                                                       |
| [150-othertypesofaccount.md:45](150-othertypesofaccount.md#L45)   | move our funds                                                         | move your funds                                                                                  |
| [150-othertypesofaccount.md:50](150-othertypesofaccount.md#L50)   | paste them in into                                                     | paste them into                                                                                  |
| [150-othertypesofaccount.md:70](150-othertypesofaccount.md#L70)   | SIgnet                                                                 | Signet                                                                                           |
| [150-othertypesofaccount.md:108](150-othertypesofaccount.md#L108) | and installed the Tezos Wallet application for the Ledger app store    | and install the Tezos Wallet application from the Ledger app store                               |
| [150-othertypesofaccount.md:114](150-othertypesofaccount.md#L114) | and you a Tezos address                                                | and you have a Tezos address                                                                     |
| [150-othertypesofaccount.md:121](150-othertypesofaccount.md#L121) | displays the key obstructed                                            | displays the key obscured                                                                        |
| [150-othertypesofaccount.md:121](150-othertypesofaccount.md#L121) | gets into you files                                                    | gets into your files                                                                             |
| [150-othertypesofaccount.md:133](150-othertypesofaccount.md#L133) | If you Ledger, or another Hardware Security Module to generate the key | If you use a Ledger or another hardware security module to generate the key                      |
| [160-delegatingstaking.md:4](160-delegatingstaking.md#L4)         | All of reward payment                                                  | All delegation reward payments                                                                   |
| [160-delegatingstaking.md:4](160-delegatingstaking.md#L4)         | by good will                                                           | at the baker's discretion                                                                        |
| [160-delegatingstaking.md:8](160-delegatingstaking.md#L8)         | Delegated funds at not                                                 | Delegated funds are not                                                                          |
| [160-delegatingstaking.md:10](160-delegatingstaking.md#L10)       | seperate                                                               | separate                                                                                         |
| [160-delegatingstaking.md:26](160-delegatingstaking.md#L26)       | This is information regarding delegation is information                | The delegation information shown here is information                                             |
| [160-delegatingstaking.md:28](160-delegatingstaking.md#L28)       | tells you want delegation fee                                          | tells you what delegation fee                                                                    |
| [160-delegatingstaking.md:40](160-delegatingstaking.md#L40)       | see it's                                                               | see its                                                                                          |
| [160-delegatingstaking.md:45](160-delegatingstaking.md#L45)       | well setup infrastructure                                              | well-configured infrastructure                                                                   |
| [160-delegatingstaking.md:43](160-delegatingstaking.md#L43)       | responds to you with questions                                         | responds to your questions                                                                       |
| [160-delegatingstaking.md:53](160-delegatingstaking.md#L53)       | can either click on Not delegated .                                    | can click on `Not delegated`. (Remove 'either' unless a second alternative follows.)             |
| [160-delegatingstaking.md:107](160-delegatingstaking.md#L107)     | if you baker                                                           | if your baker                                                                                    |
| [165-settings.md:9](165-settings.md#L9)                           | (`CMD+,).`                                                             | (`Cmd+,`).                                                                                       |
| [165-settings.md:27](165-settings.md#L27)                         | They are access from                                                   | They are accessed from                                                                           |
| [165-settings.md:27](165-settings.md#L27)                         | Quantunnet                                                             | Quantumnet                                                                                       |
| [165-settings.md:38](165-settings.md#L38)                         | that node provider                                                     | that the node provider                                                                           |
| [165-settings.md:63](165-settings.md#L63)                         | This settings are                                                      | These settings are                                                                               |
| [170-dapps.md:4](170-dapps.md#L4)                                 | come as across                                                         | come across                                                                                      |
| [170-dapps.md:18](170-dapps.md#L18)                               | from burger menu                                                       | from the burger menu                                                                             |
| [170-dapps.md:18](170-dapps.md#L18)                               | `dApps..`                                                              | `dApps...` (match the actual menu label)                                                         |
| [170-dapps.md:78](170-dapps.md#L78)                               | you transfer it another                                                | you can transfer it to another                                                                   |
| [170-dapps.md:84](170-dapps.md#L84)                               | the artwork usually too big                                            | the artwork is usually too big                                                                   |
| [170-dapps.md:179](170-dapps.md#L179)                             | right hand site                                                        | right-hand side                                                                                  |
| [170-dapps.md:173](170-dapps.md#L173)                             | paste the copy                                                         | paste the code                                                                                   |
| [170-dapps.md:194](170-dapps.md#L194)                             | vote with in                                                           | vote in                                                                                          |
| [170-dapps.md:198](170-dapps.md#L198)                             | go to [3route.io](https://3route.io) into your web browser             | open [3route.io](https://3route.io) in your web browser                                          |
| [180-multisig.md:14](180-multisig.md#L14)                         | We will required                                                       | We will require                                                                                  |
| [180-multisig.md:34](180-multisig.md#L34)                         | mulitsig                                                               | multisig                                                                                         |
| [180-multisig.md:80](180-multisig.md#L80)                         | has remember for her                                                   | has remembered for her                                                                           |
| [180-multisig.md:80](180-multisig.md#L80)                         | Alice chose the transaction                                            | Alice chooses the transaction (keep the tutorial tense consistent)                               |
| [190-baking.md:12](190-baking.md#L12)                             | into to wallet                                                         | into the wallet                                                                                  |
| [190-baking.md:12](190-baking.md#L12)                             | that they key                                                          | that the key                                                                                     |
| [190-baking.md:31](190-baking.md#L31)                             | need to setup                                                          | need to set up                                                                                   |
| [190-baking.md:86](190-baking.md#L86)                             | setting you your baker                                                 | setting up your baker                                                                            |
| [190-baking.md:97](190-baking.md#L97)                             | from our accounts                                                      | from other accounts                                                                              |
| [190-baking.md:97](190-baking.md#L97)                             | these parameters too                                                   | these parameters to                                                                              |
| [190-baking.md:116](190-baking.md#L116)                           | network run the Tallinn                                                | network ran the Tallinn                                                                          |
| [190-baking.md:118](190-baking.md#L118)                           | unless you someone                                                     | unless you are someone                                                                           |
| [190-baking.md:133](190-baking.md#L133)                           | if they haven't already implement                                      | if they haven't already, implement                                                               |
| [190-baking.md:139](190-baking.md#L139)                           | next windows                                                           | next window                                                                                      |
| [190-baking.md:147](190-baking.md#L147)                           | not enough votes                                                       | not enough voting participation / not enough votes (recast the full sentence with 'there are')   |
| [200-etherlink.md:4](200-etherlink.md#L4)                         | back to main chain                                                     | back to the main chain                                                                           |
| [200-etherlink.md:28](200-etherlink.md#L28)                       | `Bridge... `from                                                       | `Bridge...` from                                                                                 |
| [200-etherlink.md:43](200-etherlink.md#L43)                       | Send and receiving                                                     | Sending and receiving                                                                            |
| [200-etherlink.md:61](200-etherlink.md#L61)                       | so that Tezos account                                                  | so that a Tezos account                                                                          |
| [250-whatscoming.md:16](250-whatscoming.md#L16)                   | under the scenes                                                       | behind the scenes                                                                                |
| [250-whatscoming.md:20](250-whatscoming.md#L20)                   | treated a first-class                                                  | treated as first-class                                                                           |
| [250-whatscoming.md:20](250-whatscoming.md#L20)                   | Wallet Connect                                                         | WalletConnect                                                                                    |
| [250-whatscoming.md:40](250-whatscoming.md#L40)                   | a third balanced                                                       | a third balance                                                                                  |
| [250-whatscoming.md:40](250-whatscoming.md#L40)                   | You can enabled                                                        | You can enable                                                                                   |
| [910-apx-ownnode.md:21](910-apx-ownnode.md#L21)                   | limit memory usage 8GB                                                 | limit memory usage to 8GB                                                                        |
| [910-apx-ownnode.md:56](910-apx-ownnode.md#L56)                   | $docker                                                                | $ docker (and clarify that '$' is a prompt, not command text)                                    |
| [910-apx-ownnode.md:128](910-apx-ownnode.md#L128)                 | should should protect                                                  | you should protect                                                                               |
| [910-apx-ownnode.md:139](910-apx-ownnode.md#L139)                 | run at boot and now                                                    | start now and run at boot                                                                        |
| [910-apx-ownnode.md:104](910-apx-ownnode.md#L104)                 | A rolling node is suitable for most applications -                     | Complete this sentence or replace the trailing hyphen with a full stop                           |
| [915-colophon.md:6](915-colophon.md#L6)                           | files are writing                                                      | files are written                                                                                |
| [915-colophon.md:8](915-colophon.md#L8)                           | throughly                                                              | thoroughly                                                                                       |

{#id: REVIEW_3_11}
### 11. Finish the decentralised-app terminology correction

**Done — checked 11 November 2026.** The Preface now says decentralised apps, and Getting Started links to Decentralised Apps. Existing anchors are preserved.

Original finding (historical):

[170-dapps.md:4](170-dapps.md#L4)

**Partially corrected.** The chapter title, opening definition and DEX expansion now use “Decentralised”. The Preface still promises “distributed apps” and Getting Started still links to “[Distributed Apps]”. Update those visible names too; the existing `170-dapps_1_Distribute` anchor can remain to preserve links. Original PDF p. 91.

{#id: REVIEW_3_16}
### 16. Do not describe every public-key scheme as immediately broken by any quantum computer

**Done — checked 11 November 2026.** The development story now qualifies the quantum-computer threat and describes ML-DSA as designed to resist attacks; the key-type table likewise says designed to resist known classical and quantum attacks.

Original finding (historical):

[005-Preface.md:58](005-Preface.md#L58)

**Factual precision.** Quantum computers already exist; the relevant threat is a sufficiently capable, fault-tolerant cryptographically relevant quantum computer. Replace the categorical timing statement. Similarly, describe ML-DSA as designed to resist known classical and quantum attacks rather than absolutely secure against all attacks. PDF pp. vii, 49.

{#id: REVIEW_3_17}
### 17. Clarify what account creation does

**Done — checked 11 November 2026.** The account-creation section now explains local key generation, funding separately from revelation, and a local account alias. The substantive issue is resolved; the remaining sentence-level typo is tracked in the consistency pass.

Original finding (historical):

[110-starting.md:24](110-starting.md#L24)

**Internal conceptual inconsistency.** Key generation happens locally; the chapter later correctly says the address is not yet found on chain. Say the reader has a key pair and address ready to receive funds, and explain first funding separately from public-key revelation. “Name for your address book” should be “alias for this account.” PDF pp. 5, 12.

{#id: REVIEW_3_21}
### 21. Do not imply copying another item erases all clipboard copies

**Done — checked 11 November 2026.** The clipboard-clearing claim has been removed. Export guidance now requires the complete encrypted key and its password, with a separate secure password backup.

Original finding (historical):

[150-othertypesofaccount.md:121](150-othertypesofaccount.md#L121)

**Technical limitation.** Copying another item replaces the current clipboard item; it does not necessarily clear clipboard histories, synchronization or other retained copies. Revise the claim, and clarify what backup material must be preserved for encrypted exported keys. PDF pp. 8–9, 56.

{#id: REVIEW_3_22}
### 22. Repair the macOS node command

**Done — checked 11 November 2026.** The native macOS configuration command now has the continuation backslash after --history-mode=rolling.

Original finding (historical):

[910-apx-ownnode.md:74](910-apx-ownnode.md#L74)

**Confirmed executable-example error.** Add a trailing backslash after `--history-mode=rolling`. As printed, the shell runs the first two lines and then treats `--net-addr=...` as a new command. PDF p. 190.

{#id: REVIEW_3_24}
### 24. Correct the Docker RAM recommendation

**Done — checked 11 November 2026.** The advice now describes a default memory limit, reports the author’s tested 16GB setting, and asks readers to choose according to their hardware and other applications. The original claim that this setup necessarily leaves no allowance was too categorical; this finding is resolved as a clarification, not a rejection of the tested setup.

Original finding (historical):

[910-apx-ownnode.md:21](910-apx-ownnode.md#L21)

**Resource guidance error.** The example begins with a 16GB Mac and then assigns all 16GB to Docker, leaving no sensible allowance for macOS and Signet. Give a hardware-dependent allocation and state the tested RAM/disk requirements. The 50% default is correct. [Docker resource settings](https://docs.docker.com/desktop/settings-and-maintenance/settings/). PDF p. 188.

{#id: REVIEW_3_26}
### 26. Clarify local RPC binding in the Docker example

**Done — checked 11 November 2026.** Both Docker port mappings now bind to 127.0.0.1:8732:8732, the unnecessary -P is removed, and the container retains --rpc-addr=0.0.0.0. The separate Linux home-server example deliberately listens on network interfaces.

Original finding (historical):

[910-apx-ownnode.md:34](910-apx-ownnode.md#L34)

**Scope mismatch in the instructions.** The same-Mac example publishes RPC on all host interfaces, alongside unrestricted RPC in the container. For a localhost-only example, publish `127.0.0.1:8732:8732`; explain the deliberate change needed for the separate home-server example. This is a concrete issue in the printed command, not a review of application code. PDF pp. 189–190.

{#id: REVIEW_3_27}
### 27. Distinguish regulatory cooling-off from provider delays

**Done — checked 11 November 2026.** Getting Started now describes the minimum 24-hour pause before a new consumer sees a direct-offer cryptoasset financial promotion. Seven days is explicitly the author’s Mt Pelerin experience; the development story calls it a wait, not a regulatory cooling-off period.

Original finding (historical):

[110-starting.md:103](110-starting.md#L103)

**Factual precision.** The FCA rule concerns a minimum 24-hour pause in the qualifying first-time consumer promotion journey, not a blanket seven-day waiting period for crypto delivery or every purchase. Clearly separate the author’s seven-day provider experience from that rule. [FCA explanation](https://www.fca.org.uk/publications/good-and-poor-practice/assessing-compliance-back-end-cryptoasset-financial-promotions-rules). PDF pp. 20–23.

{#id: REVIEW_3_28}
### 28. Reconcile the send amount

**Done — checked 11 November 2026.** Both prose amounts are 15 tez. The send and confirmation screenshots were visually inspected and also show 15 tez.

Original finding (historical):

[140-transactions.md:24](140-transactions.md#L24)

**Confirmed internal inconsistency.** The introduction says 5 tez; the subsequent instruction says 15 tez. Choose the amount matching the screenshots and make the whole example agree. PDF pp. 32, 35.

{#id: REVIEW_3_29}
### 29. Show the signing screenshot for Bob

**Done — checked 11 November 2026.** The signing section now references 180/bobsign.png. Visual inspection confirms Bob signing the described 5 tez transfer; bobmultisig.png remains in the add-account section.

Original finding (historical):

[180-multisig.md:52](180-multisig.md#L52)

**Confirmed source mismatch.** After Bob signs, the manuscript reuses `180/bobmultisig.png`, which earlier illustrates adding a multisig. `180/bobsign.png` exists and appears intended; inspect it before replacing. PDF pp. 136–137.

{#id: REVIEW_3_31}
### 31. Finish removing missing references and stray characters

**Done — checked 11 November 2026.** The two appendix references are now bibliography items [8] and [6]. All three U+FFFC characters identified in published chapters have been removed. The code fences and earlier [6] reference remain corrected. No regenerated PDF was inspected.

Original finding (historical):

[190-baking.md:54](190-baking.md#L54)

**Partially corrected.** The baker public-key code fences now match and the appendix's `[??]` reference has been replaced by bibliography item [6]. Two U+FFFC object-replacement characters remain in the appendix sentence “For more details see … or …”; replace them with real references. A third U+FFFC remains in Key Management after the account-generation section. Source inspection confirms these three characters are still present; the revised PDF has not been checked. Original PDF pp. 152, 190–191.

{#id: REVIEW_3_32}
### 32. Reconcile direct wallet pairing status

**Done — checked 11 November 2026.** The obsolete future-work limitation is removed. The dApp chapter describes direct connection in updated dApps and conditions manual pairing on a compatible Octez Connect code. The author confirms the Octez Connect team has patched support.

Original finding (historical):

[250-whatscoming.md:12](250-whatscoming.md#L12)

**Confirmed internal inconsistency.** The dApp chapter already says Teia lists Signet and shows the direct connection method. Say some dApps still need manual pairing; remove the blanket requirement. In the dApp chapter, “You will always be able” is also too absolute: it depends on the site exposing a compatible pairing code. PDF pp. 93, 109, 185.

{#id: REVIEW_3_34}
### 34. Make book-date and chronology choices explicit

**Done — checked 11 November 2026.** The Preface is dated 14 November 2026; the development story says just over a month since 5 October, includes November development, and dates completion of the first draft to November. The 23-day statement and old late-October framing are gone.

Original finding (historical):

[005-Preface.md:17](005-Preface.md#L17)

**Partially addressed; author decision remains.** The development story's closing 28 October signature has been removed and the unused `date` variable has been removed from `variables.txt`. The Preface remains signed 5 November, while the story explicitly says it was written at the end of October after 23 days of development. Those dates can be intentional. Confirm the publication-date Preface and retain a clear late-October frame for the historical story so the 23-day statement is not read as a claim about publication day. Original PDF pp. i–ii, xiii.

{#id: REVIEW_3_36}
### 36. Qualify the fund-safety claim for consensus keys

**Done — checked 11 November 2026.** The blanket safety claim is removed. The text states that the consensus key can manage the spendable balance, and gives activation as two cycles after the current cycle. Checked against the Ushuaia documentation during this review.

Original finding (historical):

[190-baking.md:15](190-baking.md#L15)

**Documentation conflict requiring protocol-specific correction.** The chapter recommends separate consensus/companion keys and says “The baking fund is safe”. Octez documents that both manager and consensus keys give control over the delegate's spendable balance. Explain the actual authority and exposure of each key for the demonstrated protocol; a Ledger-held manager key alone does not substantiate the blanket safety claim. Also state when a replacement consensus key activates, rather than implying confirmation immediately rotates it. [Octez consensus-key documentation](https://octez.tezos.com/docs/alpha/proof_of_stake.html#consensus-key).
