# Signet code audit

**Date:** 2026-10-13

**Revision:** Verified repair snapshot based on `9f34a62` (Claude’s six-finding repair). This sweep reviewed those changes, completed residual import/HTTP/deposit-context gaps and added regressions. Repairs and this report are included in the same commit. The unrelated `docs/spec/ROADMAP.md` edit was preserved.

**Source manifest:** 208 existing repository files excluding this report, SHA-256 `902eea7aea911f76a2aa88fd1283c9117018ee6dbf3a7b42a268975694c49ada`, recorded in `/private/tmp/signet-sweep-source-digests.json`. The manifest covers the final working tree, including the preserved roadmap edit.

**Previous report:** [CODEX_AUDIT_20261012.md](CODEX_AUDIT_20261012.md), accompanying repair commit `8c2041f`. This report supersedes its assessment without changing the archived file. Existing finding IDs are retained; new findings start at S30.

**Scope:** Verification and completion of S07/S09/S11/S19/S30/S31, plus regression checks for the preceding wallet, signer, approval and recovery boundaries. The prior open-finding assessment is preserved in git commit `2d7dc1c`; the older report remains archived. This sweep changed application/test sources and this report, using synthetic keys and isolated files. No real wallet files, production logs, live transaction injection, physical Ledger signing, release publication or push was performed.

## Assessment

**All 31 tracked findings are resolved within their stated scope.** Claude repaired the principal six open paths in `9f34a62`. This sweep found and finished residual S09 and S31 cases and made S19 cancellation explicit, with stronger S11 sink verification. The other 25 controls retain their closure.

The residuals were source eligibility checked before journal recovery, unfiltered copying into missing target key files despite alias rejection, deposit approvals surviving away-and-back context changes, and missing amount binding. Deposits now retain their submitted account/network/amount for result presentation. Native HTTP responses are collected through a task-local delegate that rejects oversized headers/chunks and explicitly cancels the underlying task, rather than relying on AsyncBytes cleanup.

No intentional secret-key exfiltration or key-stealing backdoor was identified. Software keys still enter the network-capable JavaScriptCore/dependency runtime for signing; session-key memory protection does not remove those runtime copies. Experimental Layer 2 remains disabled by default; its reviewed send/deposit context and signing policies now apply after opt-in too.

## Finding checklist

Checked means the earlier repair remains supported by the reviewed implementation and stated regression evidence. It does not claim that every variant was independently reproduced again. There are no unchecked tracked findings after this sweep. Original severities are retained for older findings.

- [x] **S01 (High, retained)** — RPC forging substitution refused through local byte verification
- [x] **S02 (High, retained)** — dApp message signatures restricted to complete packed Micheline envelopes
- [x] **S03 (High, retained)** — dApp approval shows complete effects/costs and freezes operation contents
- [x] **S04 (Medium, retained)** — Request identity derives from authenticated transport state
- [x] **S05 (High, retained)** — Backup pruning requires generation ownership and complete manifests
- [x] **S06 (High, retained)** — Software signer derives and checks the expected address
- [x] **S07 (High, resolved)** — Session-only Forget compares the exact verified entry before removal
- [x] **S08 (Medium, retained)** — Current grants fail closed and directory replacement invalidates authority
- [x] **S09 (Medium, resolved)** — Import uses a recovered source snapshot and filters accepted aliases
- [x] **S10 (Medium, retained)** — Private files use owner-only atomic creation/replacement
- [x] **S11 (Medium, resolved)** — System, console and file sinks share redacted/capped text
- [x] **S12 (Medium, retained)** — Existing signing paths verify pinned chain identities and endpoint policy
- [x] **S13 (Medium, retained)** — Artwork work is bounded and untrusted TLS connections pin validated DNS answers
- [x] **S14 (Medium, retained)** — Supported execution paths enforce approved operation/reveal limits
- [x] **S15 (Medium, retained)** — Exact signed intents persist before injection and uncertainty blocks replacement
- [x] **S16 (Medium, retained)** — Multisig asynchronous results use full network/directory generations
- [x] **S17 (Medium, retained)** — Undelivered dApp replies retry without repeating signing
- [x] **S18 (Medium, retained)** — Relay starts wait for complete prior disconnection
- [x] **S19 (Medium, resolved)** — Native HTTP readers enforce byte/structure budgets and task cancellation
- [x] **S20 (Medium, retained)** — Audited RPC numeric conversions use checked accessors
- [x] **S21 (Medium, retained)** — Faucet work has challenge, deadline and cancellation bounds
- [x] **S22 (Medium, retained)** — Whole-device Ledger leases serialize sessions; see S30
- [x] **S23 (Medium, retained)** — Purchase navigation/media trust includes the effective HTTPS port
- [x] **S24 (Medium, retained)** — Default bridge storage/logging is isolated from production state
- [x] **S25 (Medium, retained)** — Release mutation requires draft status and publication requires an appcast
- [x] **S26 (Low, retained)** — Portfolio completeness and failure state remain explicit
- [x] **S27 (High, retained)** — Multisig signing reconstructs approved typed payloads
- [x] **S28 (Medium, retained)** — Contract/proposal-only directories qualify for backup
- [x] **S29 (High, retained)** — Revealed multisig public keys bind to requested signer addresses
- [x] **S30 (Medium, resolved)** — Etherlink signing/injection uses protected call policy
- [x] **S31 (Medium, resolved)** — Send sides and deposit approvals bind complete operation contexts

## Verified repairs — 2026-10-13

### S07 — Resolved (originally High): Session-only Forget checks the exact entry

**Original issue:** An encrypted session account could be renamed during password verification, and a new account could take its alias. Removal by the old alias wiped that unverified replacement.

**Repair verified:** `SessionKeyStore` assigns immutable entry identities and generations. Forget captures a removal snapshot before decryption and compares identity, generation, wallet and secret before wiping. Rename invalidates the generation; removal/re-import changes identity. Add refuses duplicate aliases/addresses. The view model rechecks uniqueness after asynchronous encryption.

**Evidence:** Current native tests preserve both accounts when an alias is reused during the password await, refuse rename/away-and-back removal snapshots, reject duplicate store entries, and admit only one concurrent import for the same alias. Normal password-verified deletion still passes. The file-backed removal contract remains intact.

**Limits:** Session-only storage remains an application persistence policy; ordinary runtime copies and mlock failure are discussed below. No GUI race or real password/key was used.

### S09 — Resolved (originally Medium): Import recovers and filters one source snapshot

**Original issue:** Import bypassed the source lock and journal recovery, allowing mixed key files. Claude added a recovered snapshot and non-nested locks, but retained pre-recovery eligibility and an exact-copy branch that could reintroduce rejected aliases.

**Completed repair:** Source recovery and snapshot acquisition now precede eligibility checks, including a missing address file recoverable from the journal. Source and destination locks are never nested. All target namespaces participate in alias acceptance. Every imported file is filtered by accepted aliases, including when a target key file is absent. Exact file copies remain supported for a genuinely empty target with fully accepted rows. Self-import resolves directory identity and is refused.

**Evidence:** Native regressions cover source rollback, recovery with no hash file present, a concurrent writer holding the source lock, A→B/B→A imports, direct/symlink self-import, and a contracts-only target whose reserved alias must survive while another account is imported. Existing cold-copy, store integrity, private-file and backup tests pass.

**Limits:** External writers must cooperate with the octez advisory lock. This does not authenticate a source wallet against a hostile local writer.

### S11 — Resolved (originally Medium): Every bridge logging sink receives sanitized text

**Original issue:** Console and uncaught-exception text reached NSLog before the file/history scrubber.

**Repair verified:** Both handlers now use `record`, which redacts/caps once before the system sink, console history and file. A configurable system-log sink permits verification of the exact emitted text; production still uses NSLog. Fetch tracing stays shape-only and verbose relay diagnostics remain opt-in.

**Evidence:** Native tests send synthetic key/hex/oversize console data, compare the system sink with console history, and confirm the same sanitized lines in an isolated private log file. Notes share that policy. Source review confirms the exception handler uses the same entry point.

**Limits:** Pattern scrubbing is defense in depth, not permission to log arbitrary plaintext credentials or full requests. No production log was inspected; the test does not query the macOS system-log database.

### S19 — Resolved (originally Medium): Native replies are bounded and explicitly cancelled

**Original issue:** Native node/indexer/domain/faucet readers buffered and parsed complete URLSession responses outside bridge budgets.

**Completed repair:** These readers use `BoundedHTTP` with per-purpose byte and JSON structure/string limits and bounded decoded page counts. Its task-local delegate rejects excessive declared length or chunks before retaining them, stops the URLSession task on overflow and caller cancellation, and resumes the continuation once. This replaces reliance on leaving an AsyncBytes loop. JSONBudget runs before JSON parsing.

**Evidence:** Native tests cover declared/undeclared oversize replies, excessive depth, fitting/error-status responses, native indexer/monitor use and row truncation. An unfinished-response fixture confirms stopLoading after refusal for both declared and undeclared lengths, before server completion. Existing bridge timeout and artwork-work regressions pass.

**Limits:** These are byte/structure/concurrency bounds, not a general CPU sandbox for every dependency. No deliberate out-of-memory or hostile public-server experiment was performed.

### S30 — Resolved (originally Medium): Deposits and rebroadcasts use protected signing calls

**Original issue:** `sendEtherlinkDeposit` was missing from protected call policy and could discard a context during signing/device work.

**Repair verified:** `signingCalls` includes both `sendEtherlinkDeposit` and `injectSignedBytes`. `kind(of:)` controls deadlines/cancellation for every entry point; `sign` refuses undeclared read names. Production signer/injector/Ledger services use `sign`. Protected calls complete with an outcome rather than undergoing generic read teardown.

**Evidence:** Current native export-policy tests examine the JavaScript public surface for signing/injection markers, require discovered exports to be protected, assert deposit/rebroadcast/Ledger policy, and verify the signing entry point refuses reads. Source review follows the no-deadline/no-read-cancellation paths. Offline JavaScript Ledger-session/injection regressions pass.

**Limits:** The source scan is a regression guard, not a complete transitive call-graph proof. Hardware approval and live injection cancellation were not exercised on a physical device or chain.

### S31 — Resolved (originally Medium): Network, service, amount and generation stay bound

**Original issue:** Send rebuilt its service from live Settings while displaying captured networks. Deposit estimates were not bound to their account/network context. Claude captured Send sides and deposit contexts, but context equality still permitted away-and-back reuse and the estimate did not bind its amount.

**Completed repair:** Each Send side retains one immutable network/service/spendable/recipient-rule context; no side borrows a live service from another layer. Deposit estimates include full account/network/directory context, an operation generation and the approved amount. Any context change, including away and back, invalidates them. Submission rejects a changed amount before signer lookup. The sheet re-estimates on context/amount/step changes, disables stale approval, and retains the submitted context/amount for confirmation presentation and explorer links.

**Evidence:** Native tests exercise account/network/node/Layer-2 enablement changes, away-and-back account/network/enablement changes, altered amounts, changes during estimate awaits, and captured Send side/service matching after Settings changes. Normal deposit/password paths remain covered. The complete SwiftUI sources compile in both the app and isolated test harness.

**Limits:** No interactive GUI or live Etherlink deposit was performed. Captured Send context intentionally remains usable on its original network after Settings changes; current key lookup still verifies the approved account address.

## Retained controls and new-code observations

- **S01/S02/S03/S04/S06:** Offline bridge regressions continue to pass local-forging, complete prepared-content, authenticated-request and safe-envelope checks. Native signer construction still requires the expected address. Session-only software keys use that signer boundary too; snapshot-checked deletion complements that signing boundary.
- **S05/S10/S28:** Targeted native backup/private-store tests pass. Manifest ownership/pruning, owner-only creation and contract/proposal eligibility remain intact. Recovered snapshots and the completed import boundary are recorded under S09.
- **S08/S17/S18:** Current-grant lookup still throws/fails closed, old directory managers are invalidated, and relay starts wait for full disconnect. Production lifecycle functions pass the offline disconnect-gate fixture. Undelivered replies remain a session-level resend mechanism, not a durable guarantee that every relay reply survives process restart.
- **S12/S14/S15:** The new deposit and Etherlink send use the selected service's pinned chain verification, expected-address signer, checked preparation/local forging and durable injection helper. Funded multisig origination supplies its initial balance through the same approved preparation. Offline approved-limit/injection tests pass, including unknown outcomes and recovery-record checks. Confirmation/rebroadcast and hostile-RPC trust still depend on chain data; archival/history unavailability conservatively leaves pending work blocked. S30/S31 now complete the reviewed lifecycle/context coverage of the new APIs.
- **S13/S19/S22/S23:** Pinned public connections, artwork concurrency, bridge parsing limits, native whole-device leases and exact purchase origins remain in source and existing fixtures. Native endpoint/purchase tests pass. S19 and S30 extend those controls to the reviewed native HTTP and deposit paths.
- **S16/S27/S29:** Multisig generations, typed proposal reconstruction and public-key/address verification remain. Existing native/JavaScript packing/signing tests and source comparisons support those controls; no live multisig round trip was performed in this review.
- **S20/S21/S24/S25/S26:** Checked numeric accessors, bounded faucet work, in-memory/no-log default bridge construction, draft-only release mutation and explicit portfolio state remain. Script syntax passes. The test host composition is still isolated by source review; its current hosted execution could not be verified because LaunchServices failed to launch the runner.
- **Etherlink encoding:** Routing vectors for tz1/tz2/tz3 and malformed-parameter rejection pass the offline bridge harness. Native Keccak tests pass standard digest vectors and the recorded address-alias fixture. This verifies internal encoding regressions; no independent live node/bridge-helper/kernel compatibility test was repeated. Withdrawals and standalone EVM keys remain outside the implemented flow.
- **Session-key storage:** The store avoids intentional wallet/backup secret writes and wipes its owned buffer. `mlock` failure is recorded but not surfaced or treated as fatal, and initialization/bridge use create ordinary Swift/JavaScript copies. Treat “session-only” as an application persistence policy, not a guarantee that every secret copy is locked/wiped or can never reach swap. Strengthen that guarantee separately if it is promised to users.

## Validation and limitations

- **99 tests in 24 suites passed** in the final isolated Swift package run: all six repair suites plus wallet-directory/store/backup integrity, signer expectations, current grants, recovery persistence, bridge timeout cancellation, artwork work, multisig contexts, Keccak and purchase-origin checks. Copied production models/services/view models/views and tests used Swift 6 strict concurrency. Only resource lookup was adapted to Bundle.module; JavaScript sources were copied to the source-scan fixture’s expected package location. Live-network/real-wallet opt-ins were unset. Keys/files/logs were synthetic or temporary.
- **The final app and test target compile:** `xcodebuild ... build-for-testing` succeeded. The earlier `xcodebuild ... test` attempt compiled but LaunchServices could not launch SignetTests; this sweep does not claim a full hosted execution pass or close a running user app to force one. App/bundle-dependent updater/test-host/QR/purchase-construction tests were excluded from the isolated package.
- **All offline bridge regressions passed with npm test**, including frozen dApp approvals, identity/grants/budgets, approved limits, uncertain outcomes/recovery, lifecycle ordering, Ledger sessions and Etherlink encoding/parameter checks.
- **Bundle consistency passed:** final esbuild output is byte-identical to the shipped resource. Bridge sources/dependencies were unchanged, so no repository bundle regeneration was needed.
- **git diff --check and final source-manifest comparison passed.** The prior fresh npm advisory result remains historical; dependencies were unchanged and npm audit was not rerun in this sweep.

Logs: `/private/tmp/signet-sweep-native-verified.log`, `/private/tmp/signet-sweep-http.log`, `/private/tmp/signet-sweep-node.log`, `/private/tmp/signet-sweep-tests.log`, `/private/tmp/signet-sweep-build-final.log`. The isolated package is `/private/tmp/signet-sweep-native`; permanent regressions are in SignetTests/AuditRepairTests2.swift and BridgeTests.swift. An earlier run exposed a temporary source-fixture path issue and insufficient unfinished-response fixture buffering; both harness problems were corrected before the final passing run.

No physical Ledger signing, live Tezos/Etherlink injection/inclusion/reorg recovery, hostile DNS experiment, interactive purchase/media permission test, release signing/notarization, deployed updater discovery or independent deployed-binary inspection was performed. Retain the adversarial regressions as release gates and obtain a fresh full hosted run when LaunchServices can start the test host.
