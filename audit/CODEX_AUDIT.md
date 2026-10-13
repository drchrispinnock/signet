# Signet code audit

**Date:** 2026-10-13

**Revision:** Final reviewed application snapshot is `a931451ac255e0e67d511a15d1fa4a67adfda4ba` (`main`, 0.9.2). Review began at `0c9dc14` with uncommitted application changes; those changes were committed by another actor during the audit. Six concurrently edited files were compared and the affected native fixtures refreshed before final targeted validation. Layer 2 is now disabled by default. The remaining pre-existing audit rename and roadmap edit were preserved.

**Source manifest:** 206 existing repository files, excluding this new report, SHA-256 `9be2c9fbecd74b2278f8e4569f36f947c15240dafeb9df754c75a29f51fffb0e`. The manifest covers the final working-tree snapshot, including the unrelated roadmap edit. It is recorded locally in `/private/tmp/signet-audit-current/final-source-digests.json`.

**Previous report:** [CODEX_AUDIT_20261012.md](CODEX_AUDIT_20261012.md), accompanying repair commit `8c2041f`. This report supersedes its assessment without changing the archived file. Existing finding IDs are retained; new findings start at S30.

**Scope:** Reassessment of the previous security boundaries plus changes since `8c2041f`: session-only keys, funded multisig origination, Etherlink balances/deposits/transfers/receive aliases, selected-chain context, recovery, node monitoring, persistence, bridge/native networking, tests, generated bundle and release gating. This is a source and targeted-behavior audit, not a formal verification of every dependency or deployed binary. Only this report was written in the repository by this audit; harnesses and logs are under `/private/tmp`. No real wallet files, production logs, live signing, transaction injection, release publication, commit or push was performed by the audit.

## Assessment

**Six findings are open: one High and five Medium.** Four earlier closures need qualification or reopening: **S07, S09, S11 and S19**. Two findings concern the new Layer 2 paths: **S30 and S31**. The remaining 25 tracked controls retain their closure within the scope stated below.

The most immediate destructive bug is session-key deletion after asynchronous password verification (S07). The import transaction boundary also remains incomplete (S09). Etherlink deposits are classified as cancellable reads by the native bridge (S30), and changing sides in an open Send sheet can separate its displayed network from its actual chain service (S31). System logging and native HTTP paths do not inherit all the redaction/resource protections credited to the JavaScript bridge (S11/S19).

No intentional secret-key exfiltration or key-stealing backdoor was identified. Software keys still enter the network-capable JavaScriptCore/dependency runtime for signing; session-key memory protection does not remove those runtime copies. Disabling experimental Layer 2 by default reduces exposure to S30/S31, but does not repair either path after opt-in.

## Finding checklist

Checked means the earlier repair remains supported by the reviewed implementation and stated regression evidence. It does not claim that every variant was independently reproduced again. Unchecked means work remains. Original severities are retained for older findings.

- [x] **S01 (High, retained)** — RPC forging substitution refused through local byte verification
- [x] **S02 (High, retained)** — dApp message signatures restricted to complete packed Micheline envelopes
- [x] **S03 (High, retained)** — dApp approval shows complete effects/costs and freezes operation contents
- [x] **S04 (Medium, retained)** — Request identity derives from authenticated transport state
- [x] **S05 (High, retained)** — Backup pruning requires generation ownership and complete manifests
- [x] **S06 (High, retained)** — Software signer derives and checks the expected address
- [ ] **S07 (High, reopened)** — Session-only Forget deletes by alias after an asynchronous check
- [x] **S08 (Medium, retained)** — Current grants fail closed and directory replacement invalidates authority
- [ ] **S09 (Medium, incomplete closure)** — Import reads the source outside its lock/recovery boundary
- [x] **S10 (Medium, retained)** — Private files use owner-only atomic creation/replacement
- [ ] **S11 (Medium, incomplete closure)** — System console/exception logging bypasses redaction
- [x] **S12 (Medium, retained)** — Existing signing paths verify pinned chain identities and endpoint policy
- [x] **S13 (Medium, retained)** — Artwork work is bounded and untrusted TLS connections pin validated DNS answers
- [x] **S14 (Medium, retained)** — Supported execution paths enforce approved operation/reveal limits
- [x] **S15 (Medium, retained)** — Exact signed intents persist before injection and uncertainty blocks replacement
- [x] **S16 (Medium, retained)** — Multisig asynchronous results use full network/directory generations
- [x] **S17 (Medium, retained)** — Undelivered dApp replies retry without repeating signing
- [x] **S18 (Medium, retained)** — Relay starts wait for complete prior disconnection
- [ ] **S19 (Medium, incomplete closure)** — Native HTTP readers bypass response/parsing budgets
- [x] **S20 (Medium, retained)** — Audited RPC numeric conversions use checked accessors
- [x] **S21 (Medium, retained)** — Faucet work has challenge, deadline and cancellation bounds
- [x] **S22 (Medium, retained for protected calls)** — Whole-device Ledger leases serialize sessions; see S30
- [x] **S23 (Medium, retained)** — Purchase navigation/media trust includes the effective HTTPS port
- [x] **S24 (Medium, retained)** — Default bridge storage/logging is isolated from production state
- [x] **S25 (Medium, retained)** — Release mutation requires draft status and publication requires an appcast
- [x] **S26 (Low, retained)** — Portfolio completeness and failure state remain explicit
- [x] **S27 (High, retained)** — Multisig signing reconstructs approved typed payloads
- [x] **S28 (Medium, retained)** — Contract/proposal-only directories qualify for backup
- [x] **S29 (High, retained)** — Revealed multisig public keys bind to requested signer addresses
- [ ] **S30 (Medium, new)** — Etherlink deposit signing receives read timeouts and context cancellation
- [ ] **S31 (Medium, new)** — Send side-switching rebuilds a live service behind captured network labels

## Open findings and fixes

### S07 — High: Session-only Forget can wipe a different account

**Locations:** `Signet/ViewModels/WalletViewModel.swift:708–715`; `Signet/Services/SessionKeys.swift:73–82`.

**Trigger:** Begin forgetting an encrypted session-only account named `Paper`. While its password is being checked, rename that account to `Saved` and import another account named `Paper`. The old password check succeeds; the pending Forget then calls `sessionKeys.remove(oldWallet)`, which deletes the current secret under alias `Paper` without checking its address, identity or secret generation.

**Confirmed offline:** A temporary test used the production view model/store and an injected importer that performed those two mutations during the decryption await. Forget left the original key under `Saved` and removed the replacement encrypted account, whose password had never been checked. The fixture used synthetic material and tested the state mutation; it did not claim to exercise actual password cryptography or the GUI.

**Impact:** The wrong in-memory secret is wiped. Session keys deliberately have no wallet-directory/backup copy. At minimum this destroys the current session's access to the replacement account; permanent loss depends on whether the user retains an external copy.

**Fix:** Give each session-key entry an immutable identity and mutation generation. Capture its identity and exact secret before decryption, then perform a compare-and-remove on the main actor. Refuse replacement, rename or re-import during the await. Address equality alone is insufficient when the same address is re-imported with another encrypted representation. Avoid silently replacing entries in `SessionKeyStore.add`; reserve/check alias and address again after asynchronous encryption/import work.

**Required regression:** Hold decryption, rename the original, reuse its alias, then release it; the replacement must survive and Forget must fail. Also cover same-address replacement and concurrent imports.

**Previous repair:** The file-backed snapshot/revision path remains intact. The new session-only branch bypasses that contract; the earlier general closure no longer applies to every account type.

### S09 — Medium: Import copies an unrecovered or changing source wallet

**Locations:** `Signet/Services/TezosClientStore.swift:252–281` (`importWallets(from:)`).

**Trigger:** Import from an octez-format source containing an interrupted `wallet_journal`, or while another cooperating writer changes its key files. The implementation locks/recoveries the destination, but calls the source's private `readEntries`/`readRaw` and `PrivateFile.read` directly. It neither takes the source wallet lock nor recovers that source before eligibility, enumeration and reads.

**Confirmed offline:** A temporary source contained an old matching key/public-key pair, a replacement address file, and a journal that would restore the old address. Production import copied the replacement address together with the old key/public key into a clean target. The source journal remained unrecovered. The test used isolated directories and synthetic keys.

**Impact:** The target can persist an inconsistent account snapshot. Expected-address checks still reject signing with a mismatched key, limiting direct fund theft; import correctness and octez compatibility are nevertheless broken. Concurrent source updates can produce the same kind of mixed snapshot.

**Fix:** Obtain a recovered immutable snapshot of all source alias files under the source's process-local and octez-compatible locks, then release that lock before taking the destination lock and merging. Avoid opposite-order nested source/destination locks; reject or explicitly handle importing a directory into itself. Determine accepted aliases from all destination namespaces and parse each source file from that one snapshot.

**Required regression:** Import must recover a source journal before reading, serialize against a concurrent source writer, and avoid deadlock for simultaneous A→B/B→A imports.

**Previous repair:** Normal reads, destination mutations and backup snapshots now serialize/recover. The previous report's broader closure overlooked this source-reading path.

### S11 — Medium: System logging bypasses the scrubber

**Locations:** `Signet/Services/TaquitoBridge.swift:258–273`, `record` and `redactedLine` around lines 550–620.

**Source-supported:** The JavaScript console callback passes raw `text` to `NSLog` before calling `record`. Only `record` scrubs long hex/base58 material and caps line length. The installed uncaught-exception handler likewise passes `exception.toString()` directly to `NSLog` and bypasses `record` entirely. Both handlers exist regardless of the developer diagnostics opt-in.

**Impact:** Disabling verbose relay diagnostics and protecting `bridge.log` does not establish the same policy for the system logging sink. If a dependency or error contains a key, payload, credential or oversized text, that text can reach system logging without the app scrubber. This is a reachable logging-policy gap, not evidence that current ordinary signing prints wallet keys. No real secrets or production logs were inspected.

**Fix:** Redact and cap once before sending a line to any sink, including system logging and uncaught exceptions. Prefer public error categories to whole request/error objects. Keep developer diagnostics explicitly gated, and do not treat base58/hex scrubbing as sufficient protection for arbitrary plaintext credentials.

**Required regression:** Inject synthetic console and exception strings and capture the system sink as well as `consoleLines`/file output. Every sink must remove synthetic key/token material and enforce the cap.

**Previous repair:** Shape-only fetch tracing, private/rotated bridge files and disabled-by-default relay diagnostics remain improvements. The earlier report overstated their coverage of all diagnostics.

### S19 — Medium: Direct native HTTP paths have no streamed response budget

**Locations:** `Signet/Services/TaquitoChainService.swift:68–91`; `Signet/Services/NodeMonitor.swift` (`urlSessionProbe`); `Signet/Services/TzKTService.swift:56–73` and other native indexer reads; native domain/faucet readers.

**Source-supported:** These paths call `URLSession.data` and then parse the full returned `Data`. They do not use the bridge's `ResponseCollector`, `PublicHTTPClient` response cap or `JSONBudget`. The new Etherlink balance and chain-ID readers inherit this behavior. A timeout bounds elapsed request time, not received bytes or parse allocations. Querying an indexer with `limit=200` also trusts the server to honor that value; it is not a client-side response-size limit.

**Impact:** A configured/compromised RPC or service can return a large or deeply structured reply which is accumulated and parsed before rejection. This permits excessive memory/CPU use outside the resource controls credited to S19. No deliberate out-of-memory experiment was run.

**Fix:** Add a shared bounded native HTTP reader that cancels while streaming beyond a per-purpose byte cap and applies structure/string budgets before parsing. Use small caps for chain IDs/balances/headers and appropriately larger caps for portfolio/history pages. Check decoded row counts too. Tests must cover both declared-length and chunked/undeclared oversize replies, plus excessive nesting.

**Previous repair:** Bridge fetches, serialized dApp parsing, file reads, artwork work and read-context teardown have useful budgets. They do not protect these separate URLSession readers. S30 separately describes the newly misclassified signing call rather than duplicating it here.

### S30 — Medium: Etherlink deposits can be abandoned as reads

**Locations:** `Signet/Services/TaquitoBridge.swift:111–112,146–150,199–220`; `Signet/Services/TaquitoChainService.swift` (`sendEtherlinkDeposit`); `TaquitoBridge/src/bridge.js:81–87`.

**Trigger:** `sendEtherlinkDeposit` signs through `signerFor` and `sendApproved`, but its name is absent from the bridge's hard-coded protected signing list. It therefore gets the default 60-second read deadline and the read cancellation handler. On timeout/cancellation, the bridge discards the context, cancels fetches and releases Ledger leases.

**Confirmed offline:** A temporary resource replaced only the two exported API functions with delayed synthetic promises. The unchanged production native bridge timed out `sendEtherlinkDeposit` at a 10 ms test deadline, while the identically delayed `sendTransfer` ignored that deadline and completed. This reproduces native classification/teardown; it is not a real deposit or hardware signing reproduction.

**Impact:** Normal hardware approval can take longer than 60 seconds. A deposit can be cut off during device work or signing/preapply/injection, contrary to the documented protected-call policy. Context teardown can release a device lease before its outstanding HID exchange has completed, undermining session sequencing on this path. If injection already began, the durable journal still protects against replacement operations; that mitigation does not make teardown of an active signature/device session safe.

**Fix:** Protect `sendEtherlinkDeposit` immediately. Then replace the duplicated string allowlist with a typed call policy or explicit noncancellable signing entry point so every new signing/injection API must declare its semantics. Audit all exports for the same omission; the existing transfer, raw, staking, governance, multisig and dApp signing names are currently present.

**Required regression:** Cancel and expire a deposit while a fake Ledger session and delayed injector are active. The operation must retain its session until completion/native HID failure and return a tracked outcome. Keep a corresponding cancellable-read positive control.

### S31 — Medium: Send can execute on a network different from its label

**Locations:** `Signet/Views/SendSheet.swift:17–38,55–56`; related dynamic state in `Signet/Views/BridgeSheet.swift` and `WalletViewModel.bridgeToEtherlink`.

**Trigger:** Open Send on network A with Layer 2 enabled. Change the model's selected network or Layer 2 endpoint/enablement in Settings, then change sides in the still-open Send sheet. `network` used for presentation/explorer links comes from captured `layer1`/`layer2`, but `makeSend` reads the live `model.chainService`/`model.layer2Chain`. The captured `layer2Chain` property is used only to decide whether switching is available. If Layer 2 was disabled after opening, `makeSend` can fall back to the live Layer 1 service while retaining Etherlink presentation/restrictions.

**Source-supported:** Constructor and side-change paths were traced. This GUI sequence was not exercised. Chain-ID checks do not repair it: the live service verifies the chain it represents, while presentation still uses another captured Network.

**Impact:** Approval and explorer links can describe the old network while signing/transfers use the current one. Same-address accounts on different chains can have unrelated funds. The mismatch also routes recovery/watch calls through the wrong service relative to the displayed context.

**Related deposit path:** `BridgeSheet` reads the selected wallet/network dynamically and keys estimate refresh only by direction/amount. A wallet/node/network change can leave an old estimate attached to a new execution context. The model's deposit API captures its service only at submission; it does not bind the earlier estimate/approval to a complete context generation. Approved limits still constrain costs, but cannot establish which account/network those costs were approved for.

**Fix:** Capture each side as one immutable context containing sender, complete Network, chain service and spendable state. Build replacement SendViewModels from those captured contexts, with no cross-layer fallback. Alternatively invalidate/close the sheet on context change and require a fresh approval. Bind deposit estimates and confirmation to the same full context and generation; include account/network/node changes in estimate invalidation.

**Required regression:** Change network, same-name node, Layer 2 node and Layer 2 enablement while the sheet is open, then switch sides. The service/network pair must remain matched or the flow must refuse. Add delayed deposit-estimate tests across the same changes.

## Retained controls and new-code observations

- **S01/S02/S03/S04/S06:** Offline bridge regressions continue to pass local-forging, complete prepared-content, authenticated-request and safe-envelope checks. Native signer construction still requires the expected address. Session-only software keys use that signer boundary too; the deletion flaw does not establish another key can sign for the displayed address.
- **S05/S10/S28:** Targeted native backup/private-store tests pass. Manifest ownership/pruning, owner-only creation and contract/proposal eligibility remain intact. Normal recovered snapshots work; the separate import exception is S09.
- **S08/S17/S18:** Current-grant lookup still throws/fails closed, old directory managers are invalidated, and relay starts wait for full disconnect. Production lifecycle functions pass the offline disconnect-gate fixture. Undelivered replies remain a session-level resend mechanism, not a durable guarantee that every relay reply survives process restart.
- **S12/S14/S15:** The new deposit and Etherlink send use the selected service's pinned chain verification, expected-address signer, checked preparation/local forging and durable injection helper. Funded multisig origination supplies its initial balance through the same approved preparation. Offline approved-limit/injection tests pass, including unknown outcomes and recovery-record checks. Confirmation/rebroadcast and hostile-RPC trust still depend on chain data; archival/history unavailability conservatively leaves pending work blocked. S30/S31 qualify lifecycle/context coverage of the new APIs.
- **S13/S19/S22/S23:** Pinned public connections, artwork concurrency, bridge parsing limits, native whole-device leases and exact purchase origins remain in source and existing fixtures. Native endpoint/purchase tests pass. S19 and S30 explain where their broader application coverage stops.
- **S16/S27/S29:** Multisig generations, typed proposal reconstruction and public-key/address verification remain. Existing native/JavaScript packing/signing tests and source comparisons support those controls; no live multisig round trip was performed in this review.
- **S20/S21/S24/S25/S26:** Checked numeric accessors, bounded faucet work, in-memory/no-log default bridge construction, draft-only release mutation and explicit portfolio state remain. Script syntax passes. The test host composition is still isolated by source review; its current hosted execution could not be verified because LaunchServices failed to launch the runner.
- **Etherlink encoding:** Routing vectors for tz1/tz2/tz3 and malformed-parameter rejection pass the offline bridge harness. Native Keccak tests pass standard digest vectors and the recorded address-alias fixture. This verifies internal encoding regressions; no independent live node/bridge-helper/kernel compatibility test was repeated. Withdrawals and standalone EVM keys remain outside the implemented flow.
- **Session-key storage:** The store avoids intentional wallet/backup secret writes and wipes its owned buffer. `mlock` failure is recorded but not surfaced or treated as fatal, and initialization/bridge use create ordinary Swift/JavaScript copies. Treat “session-only” as an application persistence policy, not a guarantee that every secret copy is locked/wiped or can never reach swap. Strengthen that guarantee separately if it is promised to users.

## Validation and limitations

1. **All JavaScript regressions passed:** `cd TaquitoBridge && npm test`, including prepared dApp batches, identity/grants/budgets, approved limits/uncertain injection, lifecycle/Ledger boundaries and Etherlink routing/parameter fixtures.
2. **Bundle consistency passed:** esbuild from current sources/installed locked dependencies produced byte-identical output to `Signet/Resources/taquito-bridge.js`. No repository bundle or dependency file was rewritten by this audit.
3. **69 tests in 18 suites passed** in a temporary Swift package using current production models/services/view models and copied tests, with Swift 6 strict concurrency. Selection covered wallet stores/directories/backups, session keys, Keccak, purchase/endpoint policy and bridge model/network behavior, including the two deliberately vulnerability-confirming S07/S09 tests. The final relevant concurrent application changes were recopied before this run.
4. **Three targeted boundary tests passed** in a separate run: S07 deletion, S09 import and S30 native timeout classification. For S30 only, temporary exported JavaScript functions were delayed synthetic fixtures; native bridge policy was unchanged. The real bundle was restored in the temporary package before the 69-test run.
5. **Native harness adaptation:** Only the bridge resource lookup was changed to `Bundle.module`; no signing/persistence/context logic was patched. `UpdaterService`, and app/bundle-dependent updater/test-host/QR/purchase-construction tests were excluded from the package. Live-network and real-wallet conditions were not enabled. Synthetic keys and temporary directories were used.
6. **The full hosted suite did not run:** `xcodebuild ... test` compiled the app/test target, then failed with `Could not launch SignetTests` from LaunchServices. The broad temporary-package run also did not complete and was interrupted; only the completed targeted counts above are credited. The prior report's 277-test hosted pass is historical, not a current pass. No running user application was closed to force tests to launch.
7. **Fresh dependency audit:** `npm audit --json` reported zero advisories across 155 dependencies after retrying outside the network-restricted sandbox. Advisory coverage is not cryptographic review of Taquito, the SDK or transitive dependencies.
8. **Static/snapshot checks:** `sh -n scripts/release.sh`, report whitespace checks and final manifest comparison pass. The audit does not stage, commit or push changes.

Evidence: `/private/tmp/signet-audit-current/{npm-test.log,npm-audit.json,xcode-test.log,swift-test.log,boundary-final.log,classification-tests.log,native-targeted.log,final-source-digests.json}`. These temporary artifacts are reproducibility aids, not committed regression tests or durable CI results.

No physical Ledger signing, live Tezos/Etherlink injection or inclusion/reorg recovery, hostile DNS experiment, purchase media-permission GUI exercise, release signing/notarization, deployed updater discovery or independent deployed-binary inspection was performed.

## Repair order

1. Restore the session-key deletion snapshot contract (S07) and source-wallet import transaction boundary (S09).
2. Protect every Etherlink signing call from read cancellation (S30), then bind Send/deposit approval to a single complete context (S31).
3. Route every logging sink through the same policy (S11) and apply streamed HTTP/parse budgets to native readers (S19).
4. Turn the temporary reproductions into repository regressions and obtain a fresh full hosted pass before treating the previous all-resolved assessment as current.
