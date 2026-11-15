{#id: REVIEW_1_Book}
# Book review - updated 15 November 2026

{#id: REVIEW_2_Substantiv}
## Substantive corrections and inconsistencies

{#id: REVIEW_3_5}
### 5. Complete the governance success conditions

[190-baking.md:121](190-baking.md#L121), [126](190-baking.md#L126), [139](190-baking.md#L139), [142](190-baking.md#L142)

**Partially corrected — rechecked 15 November 2026.** The 80% supermajority is now mentioned in both voting periods and Pass is correctly said to contribute to participation. Still outstanding: the Proposal paragraph conflates proposal support with the moving ballot-participation quorum. State the separate 5% proposal-support threshold and that a tie restarts Proposal. Promotion also needs participation quorum. Clarify that the supermajority is measured using Yea/(Yea + Nay), with Pass excluded. No need to rename UI buttons that display `Yay`. [Octez voting rules](https://octez.tezos.com/docs/active/voting.html). Original PDF pp. 158–166.

{#id: REVIEW_3_14}
### 14. Qualify burn and royalty guarantees

[170-dapps.md:94](170-dapps.md#L94), [104](170-dapps.md#L104), [123](170-dapps.md#L123)

**Narrowed to royalty wording — rechecked 15 November 2026.** The burn passages at lines 94 and 138 concern the particular Objkt/Teia examples, so a blanket accusation that the book promises burn for all FA2 tokens is too strong. A short “where the contract supports it” qualification is optional. The substantive remaining issue is the guaranteed royalty wording: line 104 says the artist gets a cut of every sale, and line 123 says “I will receive 10%” on a later sale. Limit this to sales through a marketplace/contract that honours those royalties. FA2 itself does not require a burn entrypoint or royalty enforcement. [FA2 specification overview](https://docs.tezos.com/architecture/tokens/FA2). Original PDF pp. 107–110.

{#id: REVIEW_3_18}
### 18. Correct the derivation-path explanation

[150-othertypesofaccount.md:91](150-othertypesofaccount.md#L91)

**Still outstanding — rechecked 15 November 2026.** Line 91 should identify `m` as the master/root private node, rather than leaving it as “the private key”, which can be read as the imported account key. Line 95 still says “44 means legacy”; it identifies the BIP44 purpose. Explain that the four-component hardened Tezos path shown at line 83 differs from the five-level BIP44 template. Line 101 still conflates mnemonic entropy with the derived seed; briefly distinguish the mnemonic, derived seed and optional BIP39 passphrase. [BIP44](https://bips.dev/44/), [BIP39](https://bips.dev/39/). Original PDF pp. 51–54.

{#id: REVIEW_3_19}
### 19. Do not equate splitting a string with a robust sharing scheme

[150-othertypesofaccount.md:131](150-othertypesofaccount.md#L131)

**Still outstanding — rechecked 15 November 2026.** Lines 131 and 133 still recommend cutting a secret key or hardware-wallet recovery phrase into halves and storing the pieces separately. This is literal splitting, not a threshold secret-sharing scheme: each piece reveals partial information and both parts are needed for recovery. Explain those limitations or remove the recommendation from the beginner instructions. Original PDF p. 57.

{#id: REVIEW_3_20}
### 20. Make backup and restore instructions precise

[165-settings.md:17](165-settings.md#L17)

**Still outstanding; backup format now source-checked — rechecked 15 November 2026.** The manuscript still calls the backup a “file” and says it can be moved to `~/.signet`. In the local implementation, a backup is a timestamped directory containing selected wallet files and a `.signet-backup` manifest, not an archive or a single wallet file ([WalletBackup.swift](../Signet/Services/WalletBackup.swift#L49)). Specify quitting Signet, preserving the existing configured wallet directory, and restoring the selected generation’s wallet contents to that configured location without nesting the generation directory or mixing generations. The exact user-facing procedure still needs a check with isolated test data. Startup backup may reuse an unchanged generation, so “every time” does not mean a new copy is always created. No real wallet files were inspected. Original PDF p. 79.


{#id: REVIEW_2_Consistenc}
## Consistency and presentation pass

Rechecked against the active chapters in `Book.txt` on 15 November 2026. These are local edits or optional presentation choices, not additional numbered factual findings.

- **Network and key formatting:** punctuation is still inside network-name italics, for example [150-othertypesofaccount.md:43](150-othertypesofaccount.md#L43) and [200-etherlink.md:17](200-etherlink.md#L17). The key-type table has plain network names and an unformatted `tz6` at [150-othertypesofaccount.md:41](150-othertypesofaccount.md#L41). The previous blanket claims about lowercase network names, `tzkt`, and `defi`/`deFi` in published prose were not reproduced in this pass; URLs and the excluded `networks-material.md` are not style errors in the book.
- **Wallet versus account:** the first-run wording is corrected at [110-starting.md:108](110-starting.md#L108), and the transfer chapter no longer supplies the previously alleged examples. Still change “this is for your address book” in the secret-key import at [150-othertypesofaccount.md:53](150-othertypesofaccount.md#L53). Consider “account” for the destination of the Coinbase transfer at [110-starting.md:217](110-starting.md#L217). Keep historical UI quotations as historical quotations.
- **Names:** remaining concrete examples are lowercase “ledger” at [190-baking.md:12](190-baking.md#L12), `3route` in prose at [170-dapps.md:210](170-dapps.md#L210), and the expansion/capitalization of IPFS at [170-dapps.md:100](170-dapps.md#L100). Do not change domain names or resource filenames to enforce prose capitalization.
- **Receive terminology:** [140-transactions.md:16](140-transactions.md#L16) still says “bar code”; prefer “QR code”. It now correctly says “recipient address”, so the “sending address” complaint is resolved.
- **UI label:** the main action is `Stake` in the local app source ([ActionButtonsView.swift](../Signet/Views/ActionButtonsView.swift#L30)); `Staking` is the sheet title. Change “the Staking button” at [190-baking.md:34](190-baking.md#L34). This is a source check, not a screenshot/released-binary check.
- **Amounts:** writing “5 tez” instead of “5tz” remains an optional style choice. Define tez, XTZ and the symbol when completing the introduction; do not treat this as a factual defect.
- **Command presentation:** `$` is explained at [910-apx-ownnode.md:24](910-apx-ownnode.md#L24), but `docker logs` at [910-apx-ownnode.md:67](910-apx-ownnode.md#L67) omits it. Standardizing that is optional. Line-wrapping/continuation marks in the old PDF require checking in the next render; they have not been re-observed today.
- **Layout:** the key-type table remains wide and verbose at [150-othertypesofaccount.md:34](150-othertypesofaccount.md#L34). Its old page split and screenshot whitespace are historical PDF observations, not verified current layout problems. The earlier fixes to stray backticks, missing references and published object-replacement characters remain recorded as completed; no new PDF was generated.
- **Publication placeholders:** resolve the Mac signing comment and Windows distribution/screenshot note at [110-starting.md:30](110-starting.md#L30) and [36](110-starting.md#L36), plus the Etherlink comments at [200-etherlink.md:40](200-etherlink.md#L40) and [54](200-etherlink.md#L54). The introduction placeholder is covered by finding 35.
- **Previously stale wording:** “a key pair and an address ready” is fixed at [110-starting.md:112](110-starting.md#L112). The two U+FFFC characters remain only in excluded `networks-material.md`, lines 6–7; they are not an outstanding published-book finding. Earlier image-path/anchor checks and Bob screenshot verification remain historical checks, not checks rerun in this pass.

{#id: REVIEW_2_Claims}
## Claims still requiring author or release-specific verification

Every previous entry was reconsidered against the current prose. The items below are scoped checks, not assertions that the claims are false. Author-supplied experience and decisions remain accepted. External release history, provider terms, live networks and application binaries were not comprehensively audited in this pass.

- **Network support — still release-specific:** [150-othertypesofaccount.md:40](150-othertypesofaccount.md#L40) scopes `tz5` to named networks and excludes baking; `tz6` is described separately. The “All” cells and forward-looking availability claims still benefit from a named protocol/date. Test-network configuration and snapshot URLs in [910-apx-ownnode.md:164](910-apx-ownnode.md#L164) remain live-service checks, not verified installation results.
- **Protocol constants — narrowed:** the key activation delay is now explicitly two cycles after the current cycle at [190-baking.md:90](190-baking.md#L90); withdraw the criticism that it promises immediate activation. The five-cycle parameter delay and limit of 9 at [190-baking.md:101](190-baking.md#L101) and [103](190-baking.md#L103) still need protocol scoping. Distinguish a protocol cap on effective external stake from what values a parameter-setting interface accepts.
- **Governance example — substantially addressed:** [190-baking.md:119](190-baking.md#L119) explicitly identifies the local Tallinn demonstration voting for Ushuaia. The earlier blanket request to explain that setup is obsolete. Clarify “For Ushuaianet” at line 110 if it could imply the screenshots are that public network. “Most of the time” is an observation, not a protocol guarantee. Voting-rule corrections remain in finding 5.
- **Companion key — narrowed:** DAL is now expanded at [190-baking.md:6](190-baking.md#L6), and the text associates the companion key with DAL attestation. Do not request those additions again. Verify the exact roles against the demonstrated protocol before publication; the consensus-key description mentions block signing without explaining ordinary consensus attestations.
- **Application behavior — partly source-checked:** temporary keys are explicitly held only in memory in local `WalletViewModel.swift` and `ImportAccountSheet.swift`, supporting [150-othertypesofaccount.md:55](150-othertypesofaccount.md#L55). The local `project.yml` targets macOS 15.0. Backup format and `Stake` are checked above. The Mac installation now describes a DMG at [110-starting.md:22](110-starting.md#L22); treat the author’s release information as supplied evidence, while checking CPU support and actual release assets against the chosen release. Whether a chain-ID mismatch permits continuing at [165-settings.md:44](165-settings.md#L44) remains a released-app verification task; the inspected local source did not establish that flow.
- **Provider specifics — narrowed:** [110-starting.md:213](110-starting.md#L213) now explicitly states Mt Pelerin’s USA exclusion and distinguishes its integration from the three browser links. The seven-day wait is clearly personal experience. Do not reopen these as missing wording. Calling all providers centralised exchanges at line 187 is imprecise; “providers” avoids conflating brokers with order-book exchanges. Payment methods and eligibility should remain scoped to the provider and date rather than treated as universal.
- **Historical claims — author verification:** the development story now includes dates and links, including the Quantumnet tweet at [006-DevelopingSignet.md:46](006-DevelopingSignet.md#L46). This documents the author’s account; it does not independently establish a worldwide first. Exact release timestamps, feature parity and priority claims remain author/release-history checks, not demonstrated errors.
- **Development tooling — narrowed:** “Fable” remains at [006-DevelopingSignet.md:24](006-DevelopingSignet.md#L24); confirm the intended product name. The old “tz1, 6” excerpt was not found in the current chapter. The author’s use of `claude init` is settled and requires no action.
- **Market and platform claims — still date-sensitive:** Objkt’s size at [170-dapps.md:46](170-dapps.md#L46), baker APYs/capacity in chapter 160, and roadmap statements in chapter 250 are historical observations or forecasts. Date them where useful. “First official rollup” and the scope/network of Michelson deployment at [200-etherlink.md:6](200-etherlink.md#L6) still warrant precise attribution. Preserve direct developer information; do not use EVM-only documentation to reject it.
- **NFT rights — optional clarification, not a demonstrated licence violation:** the text does not expressly claim transfer of copyright. A short distinction between owning a token and rights to the artwork would help; investigate a particular licence only if making claims about those rights. Edition wording remains in finding 13.
- **Transaction retry — still outstanding:** [140-transactions.md:54](140-transactions.md#L54) still advises trying again after a transaction appears not to go through. First tell the reader to check the operation hash/status; an apparent timeout is not proof the original transaction failed.
- **Double signing — still needs precision:** “same level” remains at [160-delegatingstaking.md:105](160-delegatingstaking.md#L105). Its next paragraph now specifies two baking instances using the same signer, which addresses part of the old concern. Qualify protection by the signer’s enabled, persistent anti-double-signing state. The broader discussion at [190-baking.md:156](190-baking.md#L156) and [158](190-baking.md#L158) should use the relevant level/round context and tie stake loss to the offence/protocol.
- **Key reuse across chains — clarification only:** [150-othertypesofaccount.md:37](150-othertypesofaccount.md#L37) and [006-DevelopingSignet.md:84](006-DevelopingSignet.md#L84) describe compatible secp256k1 key material. They do not actually say addresses are identical, and the latter distinguishes Tezos and 0x addresses. A short format/address distinction may help; the old suggestion that the manuscript recommends routine cross-chain reuse was too strong.
- **Book promises — no demonstrated gap:** minting and listing for sale are worked through at [170-dapps.md:123](170-dapps.md#L123) and [129](170-dapps.md#L129), alongside purchasing and swaps. That reasonably supports the preface’s buy/sell promise. A separate resale walkthrough is optional, not unfinished promised content.

{#id: REVIEW_2_DONE}
## DONE

{#id: REVIEW_3_4}
### 4. Correct baker eligibility requirements

**Resolved — 15 November 2026.** [190-baking.md:32](190-baking.md#L32) now specifies 6,000 tez of baking power, at least 600 tez staked by the baker, and presents the solo-baker amount as a straightforward approach rather than a universal eligibility minimum. The mandatory 10% sentence has been removed. The internal variable name does not need changing. This records the resolution agreed with the author in this session.