{#id: REVIEW_1_Book}
# Book review - updated 11 November 2026

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


