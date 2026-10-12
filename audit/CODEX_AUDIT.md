# Signet security and code-quality audit

**Date:** 2026-10-12

**Revision:** Repair snapshot included with this report, based on `9a273ccce240556da15cbb9253b50d0c738b6c84` (`main`). The 192-file source manifest, excluding this report, has SHA-256 `4ce9f9c977697a905c2adda3330efcde328b2e0f12dc5d0229e310daaa9a42fb`. Sources were checked against that manifest after validation.

**Previous verified repair:** `db6475d` (2026-10-10). This report supersedes the previous assessment and Claude's appended repair claims. Finding IDs are preserved.

**Scope:** Repairs for the thirteen findings left open by the 2026-10-11 re-audit, with regression validation of existing S01–S29 controls. Changes cover wallet/backup persistence, dApp authority/lifecycle, network identity, multisig approvals and contexts, durable operation recovery, artwork/bridge budgets, Ledger sessions, purchase origins, test isolation and release gating. The JavaScript app resource and Xcode project were regenerated. No push, release, real-wallet inspection or live transaction injection was performed.

## Assessment

**All 29 tracked findings are resolved within the scope described below.** This repair closes **S08, S09, S12, S13, S14, S15, S16, S18, S19, S22, S23, S24 and S25**. The sixteen previously verified controls remain covered by passing regressions. Closure is based on source review and offline boundary tests; hardware, live-chain, GUI and deployed release behavior were not independently exercised.

Uncertain operations now retain their exact signed bytes across restart and refuse replacement signing for the same account and chain. Recovery deliberately remains blocked if inclusion cannot be established from available chain history. Untrusted HTTPS connections use the system TLS client with validated DNS answers pinned to the actual connection, rather than a separate URL preflight.

No intentional key-stealing backdoor or deliberate upload of wallet secret keys was identified in the reviewed application paths. Software secrets still enter the JavaScriptCore runtime that also hosts networking and third-party signing code; that remains a substantial dependency trust boundary. Ledger private keys remain on the device.

“Confirmed offline” below means a synthetic-key, mocked-service or temporary-file reproduction. Source-supported findings state their trigger and were not presented as live exploits. Passing normal regressions is credited separately from adversarial evidence. No real wallet files, production logs or private release credentials were read.

## Finding checklist

Checked items have verified repairs within the stated scope. Original severity is retained for resolved items.

- [x] **S01 (High, resolved)** — RPC byte substitution in raw-operation signing
- [x] **S02 (High, resolved)** — Transaction signatures through the dApp message API
- [x] **S03 (High, resolved)** — Incomplete dApp fee and contract-effect approval
- [x] **S04 (Medium, resolved)** — Request metadata overriding authenticated dApp identity
- [x] **S05 (High, resolved)** — Backup pruning deleting unrelated directories
- [x] **S06 (High, resolved)** — Software key selection without expected-address verification
- [x] **S07 (High, resolved)** — Account removal crossing wallet-directory changes
- [x] **S08 (Medium, resolved)** — Stale grants and directory/session lifecycle boundaries
- [x] **S09 (Medium, resolved)** — Inconsistent wallet transactions and backup snapshots
- [x] **S10 (Medium, resolved)** — Secret files readable during their creation
- [x] **S11 (Medium, resolved)** — Routine diagnostics retaining credentials and request contents
- [x] **S12 (Medium, resolved)** — Missing chain checks in multisig and incomplete endpoint enforcement
- [x] **S13 (Medium, resolved)** — Artwork concurrency and destination enforcement gaps
- [x] **S14 (Medium, resolved)** — Approved limits not enforced on every signing path
- [x] **S15 (Medium, resolved)** — Uncertain injection outcomes treated as safe failures
- [x] **S16 (Medium, resolved)** — Multisig operations accepting stale network contexts
- [x] **S17 (Medium, resolved)** — Lost dApp replies without safe resend state
- [x] **S18 (Medium, resolved)** — Start/stop overlap reporting a nonexistent dApp connection
- [x] **S19 (Medium, resolved)** — Resource limits stopping after parsing or timeout
- [x] **S20 (Medium, resolved)** — RPC-controlled numbers causing trapping conversions
- [x] **S21 (Medium, resolved)** — Unbounded or invalid faucet proof of work
- [x] **S22 (Medium, resolved)** — Ledger signing sessions can interleave APDUs
- [x] **S23 (Medium, resolved)** — Purchase widget authority omits origin ports
- [x] **S24 (Medium, resolved)** — Test-host initialization still accesses default wallet storage
- [x] **S25 (Medium, resolved)** — Published-release reruns and missing update feeds
- [x] **S26 (Low, resolved)** — Hidden portfolio failures and silent truncation
- [x] **S27 (High, resolved)** — Persisted multisig bytes disconnected from the displayed action
- [x] **S28 (Medium, resolved)** — Contracts-only directories excluded from backups
- [x] **S29 (High, resolved)** — Multisig signer keys not bound to expected addresses

## Findings and verified repairs
### S01 — Resolved (originally High): RPC-supplied bytes were signed without local verification

**Status:** Resolved in `831394d`; verified against the current working-tree sources and shipped bundle.

**Locations:** `TaquitoBridge/src/rawforge.js` (`forgeRawOperation`, `verifyRawForging`); `TaquitoBridge/src/index.js` (`prepareRaw`, `appliedResults`, `sendRawOperation`); `SignetTests/StakingTests.swift` (`RawForgingTests`).

**Original issue:** A malicious RPC could return forged transfer bytes instead of an approved consensus/companion-key update and obtain a spendable signature. Assertions from that same RPC did not establish signing integrity.

**Repair:** A restricted local encoder handles reveal, consensus-key and companion-key updates. The node's forged bytes must equal the complete locally forged operation; only local bytes reach signing. Unsupported operation kinds fail closed. Simulation/preapply require complete result counts and applied statuses.

**Evidence:** The current shipped bundle refused a substituted transfer before preapplication or injection. Empty simulation and empty preapply replies were rejected, while the honest mocked operation reached the stub injector. Native bridge tests compare local forging with Taquito for supported ordinary source/key schemes, large Zarith values and BLS proofs, and reject mismatched node bytes. The rebuilt bundle is byte-identical to the shipped resource.

**Scope of closure:** This closes RPC byte substitution for the supported raw operations. Approved raw-operation estimates are now bound under S14. No live protocol operation, XMSS hardware/on-chain compatibility test or exhaustive protocol-encoding verification was performed; retain canonical encoding fixtures and adversarial byte-comparison tests as release gates.

### S02 — Resolved (originally High): “Sign message” could produce a transaction signature

**Status:** Resolved in `7544c50`; original exploit and repair regressions checked against the current sources and committed bundle.

**Locations:** `Signet/Models/DAppRequest.swift`; `Signet/Models/Micheline.swift`; `Signet/Services/DAppConnectionManager.swift`; `TaquitoBridge/src/octezconnect.js`; `TaquitoBridge/src/micheline.js`; `SignetTests/DAppTests.swift`.

**Original issue:** At `a802c3c`, the message API signed caller bytes unchanged without enforcing the signing type or safe data envelope. The payload `03 + forgedTransfer` produced exactly the signature for `signer.sign(forgedTransfer, [3])`, allowing an ordinary transaction to be authorized through the “Sign message” approval.

**Current behavior:** Only the exact `micheline` type is accepted. Payloads must be even-length hex within the 65,536-character cap, begin with packed-data prefix `05`, and contain exactly one structurally complete Micheline expression. The Swift and JavaScript readers check lengths, child structure, full consumption and depth 128. Swift validates before queueing and before signer lookup; JavaScript validates before `signerFor`. These checks reject the transaction watermark input regardless of its claimed type. Missing signing types are also rejected by the bridge, and the request parser defaults a missing type to the refused `raw` type.

**Evidence:** The current committed bundle rejected the original forged-transfer payload for `micheline`, `operation`, `raw`, unknown and missing types. Valid packed messages still matched direct synthetic-key signatures. The current isolated Swift tests and Node harness pass malformed-envelope and depth-boundary checks. The earlier audit also exercised the 16,000-level crash input and a dedicated JavaScriptCore envelope harness. The bridge rejects invalid payloads even with an invalid signer specification, demonstrating that rejection precedes signer access. A fresh bundle rebuild was byte-identical to the committed resource.

**Scope of closure:** This closes the ordinary operation-signature confusion. The readers validate binary structure rather than Michelson types: primitive identifiers and string/annotation semantics are not fully validated. Further syntax correctness hardening may reject unknown primitive identifiers or invalid UTF-8, but those accepted structures still retain the `05` data prefix and did not restore the demonstrated attack. Arbitrary packed-data signatures can have application-specific authorization meaning; closure does not imply every accepted message is merely proof of account control. Peer grants, request identity, account binding and operation approval remain covered by S04, S06, S08 and S03 (with current-grant enforcement now repaired under S08). Keep the rejection regressions as release gates.

### S03 — Resolved (originally High): Approval hid fees and contract effects

**Status:** Resolved in the 2026-10-10 repair (`db6475d`); verified again in this re-audit.

**Locations:** `TaquitoBridge/src/octezconnect.js` (`buildPrepared`, `freezePrepared`, `octezConnectPrepare`, `octezConnectExecute`, `describeOperation`); `Signet/Services/DAppConnectionManager.swift`; `Signet/Views/DAppRequestSheet.swift`; `SignetTests/DAppTests.swift`; `TaquitoBridge/test/dapp-prepared.cjs`.

**Original issue:** The dApp's supplied fee and contract parameters reached execution while approval displayed only top-level amount/destination/entrypoint. A 100-tez fee and hidden parameter recipient were reproduced offline.

**Repair:** The sheet waits for preparation and displays fees, burn, total debit, standard token effects and full parameters/code/storage. Caller fee/gas/storage values are replaced by prepared limits. Unsupported calls are marked opaque; default KT1 calls without explicit parameters also show the warning and their implicit Unit argument. Preparation freezes the entire RPC operation, including the actual automatic reveal fee/limits, source, branch and counters. Execution locally forges and signs those same contents, without re-estimation or node-controlled forging. Source/reveal-key mismatches and incomplete/failed preapply results are refused.

**Evidence:** Swift approval tests cover standard token effects, unknown calls, supplied excessive fees, default contract calls and actual reveal totals. The offline shipped-bundle regression compares injected bytes with an independently signed full approved operation, including its reveal; empty/failed preapply never reaches injection.

**Scope of closure:** This closes hidden dApp terms and rebuilding beyond their approval. Unknown contract effects require explicit advanced approval of raw parameters; descriptions of token standards are structural interpretations, not verified contract behavior. Network identity, authenticated peer grants, resource budgets and ambiguous injection recovery remain S04, S08, S12, S15 and S19. Expired branches or changed counters fail rather than silently rebuilding the operation; a fresh approval is required.

### S04 — Resolved (originally Medium): Request metadata could impersonate another dApp

**Locations:** `TaquitoBridge/src/octezconnect.js` (`authenticatedContext`, `sanitizeIncomingRequest`); `Signet/Models/DAppRequest.swift`; `TaquitoBridge/test/dapp-identity.cjs`.

**Repair verified:** The bridge derives sender identity from the authenticated transport peer's public key, finds that paired peer and its stored metadata/grants, and rebuilds the request from an allowlist. A claimed `senderId` or `appMetadata.senderId` inconsistent with the authenticated sender is refused. Swift does not take sender identity from app metadata. Permission-request branding can still be self-described; it does not override peer identity.

**Evidence:** Current-bundle offline identity/grant/budget regressions and native request-parsing tests pass. This closes request-field impersonation. SDK transport authentication remains a dependency assumption; permission freshness and lifecycle repairs are recorded under S08/S18.

### S05 — Resolved (originally High): Backup retention deleted directories it did not own

**Status:** Resolved in the 2026-10-10 repair (`db6475d`); verified again in this re-audit.

**Locations:** `Signet/Services/WalletBackup.swift` (`run`, `generations`, `isGeneration`, `prune`); `SignetTests/WalletBackupTests.swift`.

**Original issue:** All non-hidden directories under a selected backup root counted toward retention and could be recursively deleted. The first manifest-based repair still counted another wallet's backups; wallet B deleting wallet A's generation was reproduced offline.

**Repair:** Deduplication and retention select only supported, complete manifest-bearing generations whose source equals the normalized current wallet directory. Manifests must list supported, unique data files; contents must match exactly and be regular files, excluding symlinks. Unknown versions, malformed manifests, extra documents and generations without an ownership manifest are preserved. Pruning rechecks ownership, direct parent and symlink status immediately before deletion. Overlapping source/backup directories are refused.

**Evidence:** Isolated tests preserve unrelated folders, symlink targets, unmarked legacy folders, unknown manifest versions and extra documents. Identical data in two wallets sharing one destination creates separate generations; further B backups prune only B, retaining A.

**Scope of closure:** This protects against accidental pruning of foreign content and cross-wallet generations. Legacy backups are deliberately not automatically adopted or pruned because their source cannot be proven. The manifest is not authentication against a hostile local process able to rewrite the backup tree; multi-file snapshot/serialization repairs are recorded under S09; secret-file creation is now closed under S10.

### S06 — Resolved (originally High): A stale wallet object can sign with another account's key

**Status:** Resolved in `a9d8f3e`, completing the earlier native alias/address check; reverified on 2026-10-11.

**Locations:** `Signet/Services/TezosClientStore.swift`; `Signet/ViewModels/WalletViewModel.swift`; `Signet/ViewModels/SendViewModel.swift`; `TaquitoBridge/src/signers.js`.

**Original issue:** Send captured its original wallet and chain, but its signer provider read the view model's current wallet store. Secret lookup used only the alias. Switching directories, replacing files externally or reusing an alias could therefore return a different account's secret while the sheet still identified the original sender. Software signer specifications contained no expected address check.

**Original evidence:** Native lookup with temporary files retrieved another account's synthetic secret under the same alias. Transfer submission derived the actual source from that signer rather than requiring the displayed sender.

**Repair:** Native lookup verifies the alias/address mapping. Swift software signing specifications require the approved address. The shared JavaScript signer factory requires a nonempty string expected address before loading a secret, then unconditionally derives and compares the key's public key hash before returning the signer. Replacing the secret after native lookup cannot bypass that final check. All software signing callers use this factory.

**Evidence:** The current Node and native tests reject a key for another address and missing/invalid expected addresses; native regressions cover stale wallets after directory changes and alias/address replacement. The 2026-10-09 checks additionally exercised matching and mismatched clear/encrypted keys across tz1–tz5. See the current validation below.

**Scope of closure:** This prevents substitution of another account's software signing key. Network identity, dApp grants and other changes to approval context remain covered by S08, S12 and S16.

### S07 — Resolved (originally High): Forget can remove another wallet after asynchronous password verification

**Status:** Resolved in `840e97f`; reverified on 2026-10-11, including the current contracts-file snapshot handling.

**Locations:** `Signet/ViewModels/WalletViewModel.swift` (`forgetSelectedWallet`, `changeWalletDirectory`); `Signet/Services/WalletStore.swift`; `Signet/Services/TezosClientStore.swift` (`removalSnapshot`, `remove(_:matching:)`).

**Original issue:** Forget validated one account's encrypted key, awaited decryption, then removed its alias from the current store. A directory switch could delete a different account. Capturing only the directory URL and checking the address was insufficient: replacing the encrypted key under the same alias/address during the await still deleted the replacement after validating the old key's password.

**Repair:** Capture the original store, a directory-change revision and an account snapshot before decryption; decrypt the snapshot's key. Every directory switch invalidates the revision, including switching away and back. Under the same wallet lock used for deletion, compare all matching rows across the three octez files and the actual directory identity (resolved path, device and inode), then remove only if unchanged. The in-memory store enforces the same snapshot contract. The current file-backed snapshot also covers matching entries in `contracts`. Unrelated account edits remain allowed.

**Evidence:** Regression tests reject replacement encrypted keys during password verification, directory switches and switches back, edits to each account file, replacement directories at the same path, added keys on watch-only accounts and snapshots from another in-memory store. Successful password-verified deletion and unrelated-account edits also pass. See the current validation below.

**Scope of closure:** This closes deletion of a changed account across password-verification suspension. The existing advisory lock coordinates cooperating wallet writers; broader transaction/serialization repairs are recorded under S09; secret-file permissions are now closed under S10.

### S08 — Resolved (originally Medium): Grant refresh and session authority fail closed

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/DAppConnectionManager.swift; Signet/ViewModels/WalletViewModel.swift; TaquitoBridge/src/octezconnect.js.

**Original residual:** A failed permission refresh could leave cached authority usable, and directory replacement could race the old relay session.

**Repair:** Signing and preparation obtain a fresh throwing permission lookup. Lookup failures deny access and clear display grants. Session invalidation drops authority synchronously before directory replacement; generation checks reject results from obsolete sessions. Each manager has its own bridge/client/storage, and native and JavaScript lifecycle tasks serialize startup and shutdown.

**Evidence:** Native regressions reject cached grants after a lookup failure and deny an invalidated old manager. Existing peer/account/scope/network and revocation tests pass.

**Scope of closure:** Transport authentication remains an SDK trust assumption. Cached permissions are presentation data only; signing authority must continue to use fresh lookups.

### S09 — Resolved (originally Medium): Wallet transactions and backup snapshots serialize and recover

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/TezosClientStore.swift; Signet/Services/WalletBackup.swift; Signet/Services/PrivateFile.swift; proposal storage.

**Original residual:** Process-scoped lockf did not serialize threads in the same process, and backup eligibility/enumeration could precede journal recovery.

**Repair:** A shared lock per canonical directory serializes local threads before acquiring the octez-compatible file lock, using one bounded acquisition deadline. Backup recovery, eligibility, enumeration and reads occur under that lock. Proposal reads fail closed on lock failure. Private-file writes propagate chmod/fsync/directory-sync failures; reads refuse symlinks/nonregular files and enforce byte limits. Pending-operation records are supported valuable backup files.

**Evidence:** Concurrent native lock bodies remain serialized. A backup first read recovers an interrupted transaction before selecting files. Existing transaction, private-file, ownership, pruning and backup-integrity tests pass.

**Scope of closure:** The advisory file lock coordinates cooperating external writers. A hostile local process ignoring that lock remains outside the transaction contract; recovery cannot promise durability beyond the filesystem’s guarantees.

### S10 — Resolved (originally Medium): Secret permissions were applied after writing

**Locations:** `Signet/Services/PrivateFile.swift`; wallet, bridge storage, proposal and backup writers.

**Repair verified:** Secret/state replacements create exclusive, non-following temporary files with mode 0600 before writing any bytes, then replace atomically. Owned directories are hardened to 0700; foreign ownership and symlinked file reads are refused. Temporary cleanup occurs under the wallet lock.

**Evidence:** Native private-file and store-integrity tests pass, including creation permissions and directory hardening. The transient-readable-file issue is closed. Multi-file serialization and crash/durability repairs are recorded under S09; permissions alone do not provide a wallet transaction.

### S11 — Resolved (originally Medium): Routine diagnostics exposed authentication and request contents

**Locations:** `Signet/Services/DeveloperSettings.swift`; `Signet/Services/TaquitoBridge.swift`; `TaquitoBridge/src/polyfills.js`; dApp and Ledger logging.

**Repair verified:** SDK debug/decrypted-relay diagnostics require an explicit one-launch developer setting. Routine fetch logs omit query strings and bodies; dApp events log kind/type; Ledger traces retain APDU headers. Log lines are redacted and capped, files/directories are private, and rotation occurs during writing.

**Evidence:** Native log-redaction regressions pass and the production logging paths were reviewed. This closes routine persistent sensitive diagnostics. Explicitly enabled developer diagnostics are a separate user-selected mode; they should still be used only with disposable identities and requests.

### S12 — Resolved (originally Medium): Chain identity and actual endpoint enforcement cover signing paths

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/MultisigService.swift; Signet/Services/TaquitoChainService.swift; Signet/Models/DAppRequest.swift; PublicHTTPClient.swift; TaquitoBridge/src/index.js.

**Original residual:** Multisig and governance paths lacked uniform pinned-chain checks, and URL identity omitted query components or relied on DNS preflight.

**Repair:** Production multisig services bind to the complete selected Network and verify its RPC endpoint and chain identity before chain-backed reads, estimates, origination or execution. Governance execution verifies chain identity. Endpoint matching includes query components. The dApp bridge requires public HTTPS and uses DNS-pinned connections with automatic redirects disabled; artwork separately revalidates every redirect.

**Evidence:** A wrong-chain multisig mock fails before contract data access. Endpoint-query, mixed public/private DNS and pinned configuration regressions pass alongside existing native chain checks.

**Scope of closure:** An accepted RPC can still lie about data on the expected chain. Local forging, signer checks and approval binding remain necessary. User-selected native local RPCs retain their existing explicit configuration path.

### S13 — Resolved (originally Medium): Artwork connections and underlying work have enforced bounds

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/ImageLoader.swift; Signet/Services/PublicHTTPClient.swift; Signet/Services/EndpointPolicy.swift.

**Original residual:** Concurrency accounting could exceed its cap, and separate DNS validation did not establish the destination of the actual TLS connection.

**Repair:** Artwork acquires one of six download slots inside the actual shared task and hands released slots directly to waiters. In-flight entries, candidates, redirects, response bytes, output dimensions and SVG intrinsic dimensions are bounded. PublicHTTPClient pins validated public DNS answers through system curl --resolve, preserves HTTPS hostname verification, disables proxies/user configuration, and validates each artwork redirect. A global six-worker gate retains slots until underlying DNS/process work returns.

**Evidence:** A native concurrent fixture observes no more than six active artwork downloads. Private/mixed-address destination, curl configuration and response-cap tests pass.

**Scope of closure:** The transport depends on the macOS system TLS client. No hostile DNS server or real HTTPS rebinding experiment was run. Slow resolver calls can consume the bounded worker pool until they return; they cannot spawn unbounded replacement workers.

### S14 — Resolved (originally Medium): Every supported signing path enforces complete approved limits

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** TaquitoBridge/src/operations.js; TaquitoBridge/src/multisig.js; TaquitoBridge/src/index.js; bridge approval regressions.

**Original residual:** Raw operations and direct multisig calls could sign increased gas/storage/reveal costs beyond their displayed estimate.

**Repair:** Multisig origination and submission now use the shared approved preparation, local forging and sign/inject path. Estimates include automatic reveal, total gas/storage and storage burn. Raw execution compares fee, gas and storage against approval and refuses increases before signer access. Existing frozen dApp contents retain exact approved limits.

**Evidence:** The actual multisig origination module is exercised with an estimated reveal of 100 and a later reveal of 101; execution refuses before signing or injection. Raw and ordinary limit-increase regressions and frozen-dApp byte comparisons pass.

**Scope of closure:** Limits bound the approved operation budget; they do not guarantee a successful contract result. Changed counters, branches or estimates require a fresh approval rather than silent rebuilding.

### S15 — Resolved (originally Medium): Uncertain operation outcomes are durable and recoverable

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/OperationJournal.swift; TaquitoBridge/src/operations.js; raw/dApp/multisig/governance execution; SendViewModel.swift; SendSheet.swift.

**Original residual:** HTTP errors after injection, mismatched node hashes, direct multisig injection and restart could discard uncertainty and invite duplicate signing.

**Repair:** Before injection, a private durable journal stores the locally computed hash, exact signed bytes, source, chain, branch, complete contents and derived origination address. Save failures stop before injection. Any failed or mismatched post-injection reply preserves an unknown outcome. Pending intent prevents replacement signing for the same account/chain across endpoint changes. All native manager, multisig, governance and dApp injection paths share this journal. Send resumes watching/rebroadcasting the same bytes after restart. Recovery verifies the hash, source and locally forged contents against saved bytes; inclusion scanning starts from the saved branch/cursor and only verified inclusion removes the record.

**Evidence:** Offline regressions cover HTTP 504, permanent node errors, returned-hash mismatch, journal save failure, identical-byte rebroadcast, altered recovery records and alternate RPC nodes. Native tests verify restart persistence, replacement refusal and owner-only permissions. Existing lost-response/dApp resend tests pass.

**Scope of closure:** Production recovery state is centralized in ~/.signet/pending_operations.json, shared by wallet-directory sessions. A custom-directory backup alone does not carry this central journal. A pruned/unavailable history or an operation whose inclusion cannot be verified remains conservatively pending and may require an archival RPC. No live injection, origination or chain-history recovery was run.

### S16 — Resolved (originally Medium): Multisig asynchronous results bind to the full current context

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/ViewModels/WalletViewModel.swift; Signet/Views/SendSheet.swift; SignetTests/AuditRepairTests.swift.

**Original residual:** Comparing network names did not detect endpoint replacement or switching away and back during asynchronous multisig work.

**Repair:** Account/network changes invalidate an operation-generation token. Create, add, propose, sign and submit capture the complete Network, directory revision and generation; stale results cannot persist a proposal, choose a signer or remove a saved proposal. Send presentation captures its immutable operation network for explorer links and recovery.

**Evidence:** Native fake-service regressions switch to another endpoint with the same network name and switch away/back during preparation; neither persists a proposal. Existing signer/account/directory context tests pass.

**Scope of closure:** External changes to contract state still require the existing counter/script/membership checks. Generation binding protects application context, not a block-pinned chain snapshot.

### S17 — Resolved (originally Medium): Reply failure silently completed a dApp request

**Locations:** `Signet/Services/DAppConnectionManager.swift` (undelivered response handling); `Signet/Views/DAppRequestSheet.swift`; `SignetTests/DAppGrantTests.swift`.

**Repair verified:** A failed response keeps the completed reply and request as undelivered. Approving it again resends that reply without signing or executing again; dismissing drops it explicitly.

**Evidence:** The native regression fails delivery repeatedly, retries it and confirms one signing/execution with multiple response attempts. This closes the original retry/re-execution and silent-completion issue. Recovery is session-local; persistent operation uncertainty remains S15.

### S18 — Resolved (originally Medium): Start and stop serialize the entire relay lifecycle

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** TaquitoBridge/src/octezconnect.js; Signet/Services/DAppConnectionManager.swift; WalletViewModel.swift.

**Original residual:** A start during asynchronous disconnect returned success for the client that stop was about to destroy.

**Repair:** JavaScript starts await the shared stop promise before checking or publishing a client; stop awaits an in-flight start before disconnecting. Native tasks also serialize lifecycle transitions, and directory generations suppress obsolete startup results. Separate manager bridges avoid shared client/storage/event callbacks. Bridge teardown emits stopped and clears native session state.

**Evidence:** An offline fake SDK holds disconnect on a gate: a concurrent start waits, then establishes a new client only after disconnect completes. Grant invalidation and existing startup/pairing regressions pass.

**Scope of closure:** Real relay connectivity was not exercised. Future SDK lifecycle changes must retain the disconnect-gate regression.

### S19 — Resolved (originally Medium): Parsing budgets and timeout cancellation bound underlying work

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/TaquitoBridge.swift; BridgeCallGate.swift; JSONBudget.swift; PublicHTTPClient.swift; PrivateFile.swift; TaquitoBridge/src/octezconnect.js.

**Original residual:** Post-parse checks were too late, and timed-out reads released continuations while underlying JavaScript/fetch work could continue accumulating.

**Repair:** Transport serialization is bounded before decoding/JSON.parse; HTTP JSON is validated for bytes, depth, node count and string size before JavaScript SDK processing. Bridge argument/random allocation, fetch concurrency, queued calls and file reads have limits. Foreground calls serialize; read/preparation cancellation or timeout cancels HTTP and discards the context, with generation fences on late callbacks. Signing/injection and whole Ledger sessions are protected from generic read deadlines. The global public-HTTP worker cap remains occupied until underlying DNS/process work actually returns.

**Evidence:** Offline tests reject excessive serialized messages and depth before parsing. Native budget tests cover depth/string/node excess; a held URLProtocol read times out, cancels its HTTP work and permits a clean context reload. Existing operation/proposal/input budgets pass.

**Scope of closure:** JavaScriptCore cannot preempt arbitrary synchronous third-party code already executing on its queue. These repairs bound the audited attacker-controlled input paths and outstanding work; they are not a general CPU sandbox for dependencies. Protected signing calls rely on durable outcome recovery and Ledger’s native HID timeout.

### S20 — Resolved (originally Medium): Untrusted RPC numbers reached trapping conversions

**Locations:** `Signet/Services/JSONValue.swift` (`intValue`); `Signet/Services/TaquitoChainService.swift`; `Signet/Services/MultisigService.swift`; bridge limit parsing.

**Repair verified:** RPC/bridge integer access checks finite, integral, safely representable values. Native estimates and generic multisig counters/thresholds throw on malformed figures rather than silently using zero; JavaScript operation limits require safe non-negative integers.

**Evidence:** Native checked-number, estimate and multisig tests pass for malformed/extreme values. This closes the reported RPC-controlled trapping conversions. It does not claim every local numeric conversion in the repository was removed; local/device-derived conversions have different input provenance.

### S21 — Resolved (originally Medium): Faucet work was invalid, unbounded and uncancellable

**Locations:** `Signet/Services/FaucetService.swift`; `Signet/Views/FaucetSheet.swift`; `SignetTests/FaucetServiceTests.swift`.

**Repair verified:** Difficulty, count/length, advancing-counter and amount bounds are enforced. Production solving checks cancellation and a deadline, and caps rounds/elapsed work. Selection changes and the sheet can cancel the request.

**Evidence:** Offline invalid-challenge, difficult-work, cancellation and solver regressions pass. No live faucet request or proof-of-work submission was needed. Retain bounded-work tests as the challenge protocol evolves.

### S22 — Resolved (originally Medium): Ledger operations hold a whole-device session lease

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/LedgerSessions.swift; Signet/Services/TaquitoBridge.swift; TaquitoBridge/src/ledger.js; existing LedgerHID.swift failure handling.

**Original residual:** Per-APDU queues permitted concurrent multi-chunk signatures to interleave on one physical device.

**Repair:** A native device-keyed lease spans address verification and the entire signing APDU sequence across distinct bridges. JavaScript also serializes complete signer/address operations, retaining its per-exchange queue. Address identity is rechecked inside the session. Queued leases are bounded/cancellable; context teardown releases leases safely, and generic read cancellation does not abandon a running device session. HID failure/timeout closes the device before another session proceeds.

**Evidence:** A fake transport records contiguous A0/A1 then B0/B1 chunks under concurrent callers. Native tests prove the same device lease excludes a second bridge and retains existing HID framing/timeout regressions.

**Scope of closure:** No physical-device signing was performed. Hardware firmware behavior and user confirmation still need device testing; leases establish application sequencing rather than proving device firmware correctness.

### S23 — Resolved (originally Medium): Purchase trust checks use exact HTTPS origins

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Views/BuyWebView.swift; SignetTests/AuditRepairTests.swift.

**Original residual:** Trusted-host checks ignored ports, granting navigation/media authority to an unexpected service on the provider hostname.

**Repair:** Trusted navigation accepts only the configured HTTPS hosts at the default port (implicit or 443). Media authorization compares both requesting security-origin and frame ports, treating only the default HTTPS port as trusted.

**Evidence:** Native policy tests accept default HTTPS origin forms and reject alternate or mismatched ports alongside existing main-frame/host/scheme rules.

**Scope of closure:** No GUI camera/microphone grant was exercised. The configured provider remains trusted for its accepted origin content.

### S24 — Resolved (originally Medium): Test construction uses memory storage and no default logs

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** Signet/Services/TaquitoBridge.swift; Signet/SignetApp.swift; WalletViewModel.swift; TestHostIsolationTests and AuditRepairTests.

**Original residual:** An in-memory hosted wallet still initialized eager disk-backed bridge storage and default user log paths.

**Repair:** Bridges now default to in-memory storage and no logging, including the shared bridge. Only the production composition root selects disk relay storage, enables its explicit log path and installs the durable operation journal. Hosted test composition disables the default node probe and uses isolated model state. dApp bridges inherit logging only after production explicitly configures it.

**Evidence:** The full hosted Xcode suite launched and passed: 277 tests in 92 suites, with live-network and real-wallet opt-ins unset. Native tests verify default in-memory bridge storage and existing test-host isolation properties. Tests use synthetic keys and temporary files.

**Scope of closure:** Tests that explicitly opt into real wallet/network access retain their opt-in contract; ordinary constructor paths no longer select those resources. No production wallet or log contents were inspected.

### S25 — Resolved (originally Medium): Release publication requires draft state and a signed update feed

**Status:** Repaired on 2026-10-12; included in the repair commit containing this report.

**Locations:** .github/workflows/release.yml; scripts/release.sh.

**Original residual:** Reruns could clobber published release assets separately, and a missing Sparkle key allowed a latest release without its feed.

**Repair:** Tag-scoped workflow concurrency serializes release attempts. The workflow requires a Sparkle signing key before build, runs all bridge regressions and isolated hosted native tests, and verifies the locked rebuilt bundle. Existing published releases are refused. Draft status is checked before uploading the exact version archive and appcast together; publication occurs only after assets are present. Missing signing keys or generated appcasts fail release generation/publication. Explicit local SPARKLE_APPCAST=0 remains available for nonpublication builds.

**Evidence:** Source review confirms checks precede mutation/publication; shell syntax validation passes. All current offline bridge/native gates pass independently. No GitHub release or credentials were used.

**Scope of closure:** CI, signing/notarization, Sparkle generation and deployed update discovery were not executed here. The workflow prevents its normal rerun path from mutating a published release; GitHub asset upload is not a server-side atomic multi-asset transaction.

### S26 — Resolved (originally Low): Portfolio loading concealed errors and truncation

**Locations:** `Signet/Services/TzKTService.swift`; portfolio models/view-model/tab presentation; `SignetTests/PortfolioStateTests.swift`.

**Repair verified:** Tokens/NFTs share a paginated portfolio result, capped at 1,000 rows with explicit complete/partial/unavailable state. Failures retain last-known lists and expose unavailable status; the cap no longer pretends to be complete. Unsupported decimal counts outside 0...36 are not used.

**Evidence:** Native portfolio pagination/state/failure/decimal tests pass; UI consumption of those states was reviewed. Closure covers disclosed completeness/failure handling, not a guarantee that an external indexer's changing data is a block-pinned snapshot.

### S27 — Resolved (originally High): Persisted proposal bytes were not bound to displayed actions

**Locations:** `Signet/ViewModels/WalletViewModel.swift` (proposal signing); `Signet/Services/MultisigService.swift`; `TaquitoBridge/src/multisig.js` and packed-data signer; proposal regression tests.

**Original issue:** A modified saved proposal could display one transfer while supplying another multisig action's bytes, or ordinary operation-watermarked bytes. The earlier audit reproduced both with a synthetic encrypted key through the native saved-proposal signing flow.

**Repair verified:** Signing reconstructs the typed payload from chain, contract, counter and immutable action fields; it does not sign persisted `proposal.bytes`. The model compares reconstructed bytes with the approved proposal, and a dedicated packed-data signing API refuses operation envelopes. Membership/context checks guard the selected signing path.

**Evidence:** Current native proposal/signing regressions pass, including altered stored payload rejection and action-based repacking; canonical packing fixtures remain covered. Resolved in `db6475d`, reverified on 2026-10-11. The separate multisig chain/context/limit repairs are recorded under S12/S14/S16; they do not restore verbatim signing of arbitrary persisted bytes.

### S28 — Resolved (originally Medium): Contracts-only directories were omitted from backups

**Locations:** `Signet/Services/WalletBackup.swift` (`valuableFiles`, `run`); contract/proposal store and backup tests.

**Original issue:** Backup eligibility required `public_key_hashs`, so a directory containing only contracts or multisig proposals was skipped despite those files being in the supported backup list.

**Repair verified:** Any supported valuable wallet, contract or proposal file makes a directory eligible. Contract/proposal-only backups retain that state; `state` alone deliberately does not trigger a generation. Ownership validation and retention rules remain in place.

**Evidence:** Current isolated contract/proposal/backup regressions pass. Resolved in `db6475d`, reverified on 2026-10-11. Concurrent enumeration and journal recovery during snapshots are now repaired under S09.

### S29 — Resolved (originally High): Revealed signer keys were not checked against requested addresses

**Locations:** `Signet/ViewModels/WalletViewModel.swift` (`multisigSignerKey`); `Signet/Services/MultisigService.swift`; `TaquitoBridge/src/multisig.js` (`multisigRevealedKey`).

**Original issue:** A configured RPC could supply a valid public key for a different account while the creation UI retained the requested signer's address. The earlier offline resolver reproduction accepted such a key; replacing enough signers could change control of the new contract.

**Repair verified:** Returned keys are decoded and their public-key hash is derived locally and compared with the requested address. The bridge rejects mismatched RPC-resolved keys; the model also checks locally known/resolved keys before accepting a signer. Invalid or unsupported keys fail before origination.

**Evidence:** Current isolated native multisig signer-resolution tests pass, including well-formed keys for another address and local mapping mismatches. Resolved in `db6475d`, reverified on 2026-10-11. Network identity and payer-operation limit repairs are recorded under S12/S14.

## Validation — 2026-10-12

- **Full hosted macOS suite passed:** `xcodebuild -project Signet.xcodeproj -scheme Signet -destination 'platform=macOS' -derivedDataPath build test`: **277 tests in 92 suites**, with Swift 6 complete strict concurrency. Live-network and real-wallet opt-ins were unset; hosted initialization uses memory state and a disabled default probe.
- **All offline JavaScript regressions passed with `npm test`:** prepared dApp approvals/bytes, authenticated identity/grants/budgets, complete approved limits, injection uncertainty/rebroadcast/recovery integrity, lifecycle serialization, pre-parser limits and whole Ledger sessions. Fixtures use synthetic keys, fake SDK/network/device dependencies and production operation/lifecycle logic.
- **Bundle consistency passed:** a fresh esbuild output from final bridge sources and installed locked dependencies is byte-identical to the regenerated `Signet/Resources/taquito-bridge.js`. No dependency version or lockfile change was made.
- **Project generation passed:** `xcodegen generate` includes the new services and regression suite; the generated project was built/tested rather than hand-edited.
- **Static checks passed:** `sh -n scripts/release.sh`, `git diff --check`, and the final source-manifest comparison.
- The prior 2026-10-11 registry `npm audit` reported zero vulnerabilities across 155 installed dependencies. That advisory result is historical; it was not rerun for these unchanged dependencies and is not a safety proof.

Local logs are `/private/tmp/signet-repairs-final-results.log` and `/private/tmp/signet-repairs-node.log`. The source manifest is `/private/tmp/signet-repairs-source-digests.json`. These temporary artifacts supplement the committed regression sources. The repairs and report are committed together.

## Positive controls and remaining trust boundaries

Local forging, packed-message envelope checks, complete frozen dApp approvals, expected-address signing checks, source-bound backup ownership, proposal repacking and multisig address/key verification remain in place. Native regression coverage and bridge consistency checks passed. Existing multisig script-hash, counter, distinct signer-slot and threshold checks remain useful; they remain complemented by the repaired chain, limit, lifecycle and recovery checks.

Encrypted account defaults and warnings improve key storage, but clear octez-compatible keys remain supported and old clear backups are not retroactively encrypted. Explicit secret export uses the general pasteboard; reducing copied-secret lifetime would be additional hardening. Keep software secrets short-lived and consider separating key custody from the networking/dependency runtime.

No live Tezos multisig/dApp round trip, protocol injection, physical Ledger signing, hostile DNS experiment, GUI/media-permission exercise, deployed updater verification or release publication was performed. Claude's live-test claims are historical assertions and were not independently repeated here. This report is a source and targeted-behavior audit, not formal verification or certification of deployed binaries.

## Follow-up validation

The tracked residuals are repaired; retain the new adversarial regressions in routine CI. Before release, exercise the complete Ledger signing flow on hardware, a synthetic-account test-chain origination/recovery flow, accepted and refused public HTTPS destinations, purchase media permissions, and signed draft-release/updater generation. These are validation limits, not claims that the original vulnerable paths remain open.
