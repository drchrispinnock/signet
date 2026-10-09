# Signet security and code-quality audit

**Date:** 2026-10-08  
**Revision:** `7544c50` (`7544c505f8a03a1024493162614db85f5b657f26`; working tree initially clean)  
**Previous audited revision:** `a802c3c`  
**Scope:** Current Swift models, persistence, view models, signing and network services, SwiftUI approval/import/export/buy flows, JavaScript bridge sources and committed bundle, installed signing/dApp dependencies, tests, entitlements, updater and release scripts. This re-audit compares the S02 repair against `a802c3c`, rechecks the existing finding paths, and reruns isolated behavioral checks. Findings retain their original IDs. Only this report was edited during the re-audit; no application source was changed and nothing was committed or pushed.

## Assessment

After the **2026-10-09 S06 and S07 follow-ups**, there are **23 open findings: 3 High, 19 Medium and 1 Low**, plus **3 resolved findings (S02, S06 and S07, originally High)**. S19 remains open with a partial mitigation for message size and nesting. The most urgent remaining issues are RPC-controlled raw-operation signing, incomplete dApp transaction approval and destructive backup pruning. These can lead to unauthorized spending or loss of wallet data under the conditions described below. The revision, scope and validation below describe the original re-audit unless explicitly dated as a follow-up.

I did **not identify an intentional key-stealing backdoor or a deliberate network upload of wallet secret keys** in the application sources reviewed. This does not establish that all dependencies are safe. Software keys, decrypted keys, passwords and recovery phrases enter the same JavaScriptCore runtime that handles network traffic; Ledger secrets remain on the device. A malicious or exploited dependency in that runtime therefore remains a serious trust boundary.

Severity reflects impact and prerequisites. “Confirmed offline” means exercised with synthetic keys, mocked RPC/transport objects or isolated temporary files. Other findings are supported by source review and include their triggering conditions. No real wallet contents, production bridge logs or private release credentials were inspected. No real transaction was injected.

## Finding checklist

Checked items have verified fixes; unchecked items remain open, including partially mitigated findings.

- [ ] **S01 (High)** — Raw-operation signing trusts RPC-supplied forged bytes
- [x] **S02 (High)** — dApp message signing could authorize an ordinary transaction — resolved in `7544c50`
- [ ] **S03 (High)** — dApp approval omits supplied fees and contract effects
- [ ] **S04 (Medium)** — Incoming dApp metadata can override the paired identity
- [ ] **S05 (High)** — Backup pruning deletes unrelated directories
- [x] **S06 (High, resolved)** — Software signing keys are selected by mutable alias without address verification
- [x] **S07 (High, resolved)** — Forgetting an account can delete a different directory's account after an await
- [ ] **S08 (Medium)** — dApp permissions and wallet-directory boundaries are not enforced
- [ ] **S09 (Medium)** — Wallet updates and backups lack a consistent multi-file transaction
- [ ] **S10 (Medium)** — Secret-file permissions are applied after writing
- [ ] **S11 (Medium)** — Persistent diagnostics expose authentication data and private request content
- [ ] **S12 (Medium)** — RPC selection does not verify network identity or validate dApp endpoints
- [ ] **S13 (Medium)** — Untrusted artwork URLs permit local-network requests and unbounded downloads
- [ ] **S14 (Medium)** — Displayed estimates do not constrain what is signed
- [ ] **S15 (Medium)** — Ambiguous injection failure can encourage duplicate payment
- [ ] **S16 (Medium)** — Async refresh and operation flows mix account/network contexts
- [ ] **S17 (Medium)** — Failed dApp replies are treated as completed requests
- [ ] **S18 (Medium)** — dApp startup can report success without an active connection
- [ ] **S19 (Medium)** — dApp and bridge inputs have insufficient resource limits — partially mitigated
- [ ] **S20 (Medium)** — Unchecked numeric conversions can crash the app
- [ ] **S21 (Medium)** — Faucet proof-of-work input can crash or consume CPU indefinitely
- [ ] **S22 (Medium)** — Ledger timeouts leave a reusable channel vulnerable to stale responses
- [ ] **S23 (Medium)** — Embedded buy widget's navigation and permission policy is too broad
- [ ] **S24 (Medium)** — Test execution is not isolated from real wallet state
- [ ] **S25 (Medium)** — Release pipeline can publish an incomplete update and suppress archive errors
- [ ] **S26 (Low)** — Portfolio loading hides failures and silently truncates holdings

## Re-audit changes

- **S02 is resolved for the reported cross-domain transaction-signature attack.** The original `03 + forgedTransfer` reproduction is rejected by the committed bundle. The manager validates before queueing and again before obtaining a signer; the bridge independently validates before constructing its signer. Unknown/raw/operation/missing signing types fail closed.
- **The incomplete-envelope gap from the first repair is addressed.** Both readers now require the `05` prefix followed by exactly one structurally complete expression, enforce declared byte lengths and reject trailing bytes. Prefix-only input, truncated strings/bytes, incomplete integers and malformed sequences/arguments are rejected.
- **The parser recursion regression is addressed.** Both readers enforce root depth zero and a maximum depth of 128, including sequence elements and generic primitive arguments. A 16,000-level nested `Some` payload (64,006 hex characters, below the signing size cap) now returns a refusal instead of crashing Swift or overflowing the JavaScript stack. Boundary depths 128/129 and wide sibling sequences were checked.
- **S19 is only partially mitigated.** Signing payloads are capped at 65,536 hex characters (32 KiB of decoded bytes) and depth 128. Other requests, queues, metadata, HTTP bodies and unfinished asynchronous work remain unbounded at the wallet layer; the signing limits are applied after the full incoming event is parsed.
- **S01, S03, S04, S05, S06, S10, S12 and S21 were reproduced again offline.** The remaining open findings were rechecked against their source paths. Outside the S02-related files, application source is unchanged from `a802c3c`; unchanged findings are not marked fixed merely because the new signing tests pass. No new independently demonstrated security finding was added in this re-audit.

## Findings and suggested solutions

### S01 — High: RPC-supplied bytes are signed without local verification

**Locations:** `TaquitoBridge/src/index.js:467`, `:489`, `:503`; `Signet/Services/TaquitoChainService.swift:161`, `:203`.

The fallback used for unsupported consensus/companion public keys asks the node to forge the operation, then signs that hex directly with the operation watermark. Nothing decodes the returned bytes or checks that their branch, source, kind, key, destination, amount and fee match the intended operation. Simulation and preapplication are performed by the same untrusted server; preapplication even accepts an empty result array.

A compromised or malicious configured RPC can replace an approved consensus-key update with a transfer and obtain a spendable software-key signature. It can inject those signed bytes itself. Ledger transaction display provides an additional defense, so this is not a demonstrated extraction of Ledger secrets.

**Evidence:** Confirmed offline. A stub RPC returned locally forged transaction bytes for an `update_consensus_key` request. `sendRawOperation` signed and passed the substituted transfer to the stub injector; the signed bytes exactly matched a separately signed transfer.

**Solution:** Forge supported operations locally. For new protocol encodings, implement a trusted local encoder/decoder and compare the complete decoded operation with an immutable approved intent before signing. If that cannot be done, disable this fallback and direct the user to a tool that supports the encoding. Require complete simulation/preapply results with matching contents and applied statuses, but do not use those server assertions as the signing integrity check. Add a regression test where the RPC substitutes a transaction, source, branch, key or fee and verify that no signing occurs.

### S02 — Resolved (originally High): “Sign message” could produce a transaction signature

**Status:** Resolved in `7544c50`; original exploit and repair regressions checked against the current sources and committed bundle.

**Locations:** `Signet/Models/DAppRequest.swift:123`; `Signet/Models/Micheline.swift:17`; `Signet/Services/DAppConnectionManager.swift:127`, `:181`; `TaquitoBridge/src/octezconnect.js:192`, `:202`; `TaquitoBridge/src/micheline.js:46`; `SignetTests/DAppTests.swift:86`.

**Original issue:** At `a802c3c`, the message API signed caller bytes unchanged without enforcing the signing type or safe data envelope. The payload `03 + forgedTransfer` produced exactly the signature for `signer.sign(forgedTransfer, [3])`, allowing an ordinary transaction to be authorized through the “Sign message” approval.

**Current behavior:** Only the exact `micheline` type is accepted. Payloads must be even-length hex within the 65,536-character cap, begin with packed-data prefix `05`, and contain exactly one structurally complete Micheline expression. The Swift and JavaScript readers check lengths, child structure, full consumption and depth 128. Swift validates before queueing and before signer lookup; JavaScript validates before `signerFor`. These checks reject the transaction watermark input regardless of its claimed type. Missing signing types are also rejected by the bridge, and the request parser defaults a missing type to the refused `raw` type.

**Evidence:** The current committed bundle rejected the original forged-transfer payload for `micheline`, `operation`, `raw`, unknown and missing types. Valid packed messages still matched direct synthetic-key signatures. The malformed-envelope and depth boundary/crash cases passed in isolated Swift tests, the Node bundle harness, and a JavaScriptCore harness using the shipped resource. The bridge rejects invalid payloads even with an invalid signer specification, demonstrating that rejection precedes signer access. A fresh bundle rebuild was byte-identical to the committed resource.

**Scope of closure:** This closes the ordinary operation-signature confusion. The readers validate binary structure rather than Michelson types: primitive identifiers and string/annotation semantics are not fully validated. Further syntax correctness hardening may reject unknown primitive identifiers or invalid UTF-8, but those accepted structures still retain the `05` data prefix and did not restore the demonstrated attack. Arbitrary packed-data signatures can have application-specific authorization meaning; closure does not imply every accepted message is merely proof of account control. Peer grants, request identity, account binding and operation approval remain covered by S04, S06, S08 and S03. Keep the rejection regressions as release gates.

### S03 — High: Approval hides fees and contract effects that execution preserves

**Locations:** `TaquitoBridge/src/octezconnect.js:153`, `:176`, `:211`; `Signet/Services/DAppConnectionManager.swift:222`; `Signet/Views/DAppRequestSheet.swift:85`.

Transaction conversion preserves caller-supplied `fee`, `gas_limit`, `storage_limit` and full contract parameters. The summary shows only the top-level tez amount, destination and entrypoint. An operation sending zero tez can carry a large fee or transfer valuable tokens, approve an operator, or change contract permissions. Origination summaries likewise omit script and initial storage. The UI says fees are estimated when approving, although explicit caller fees are accepted.

**Evidence:** Confirmed offline: a request with a **100 tez** fee and a hidden contract parameter recipient omits both from the summary, while the execution adapter preserves the fee in the batch passed to Taquito.

**Solution:** Prepare the complete transaction before approval and display exact fee, storage burn, total tez debit and decoded contract effects. Reject or cap supplied fee/gas/storage values; show unsupported contract calls as an explicit advanced approval with full parameters and simulation details. Prevent approval until preparation succeeds. Sign the same immutable prepared transaction the user reviewed. Add tests for zero-tez FA2 transfers, operator approvals, high fees and originations.

### S04 — Medium: Request metadata can impersonate another dApp

**Locations:** `Signet/Models/DAppRequest.swift:48`; `TaquitoBridge/src/octezconnect.js:54`; installed `@tezos-x/octez.connect-wallet/dist/cjs/interceptors/IncomingRequestInterceptor.js:90`.

The installed legacy interceptor combines trusted metadata and the incoming message as `Object.assign({ appMetadata }, message)`, allowing the message to override registered metadata. The Swift parser trusts `appMetadata.name`, `appUrl`, `icon` and even `senderId` ahead of the outer sender. It discards authenticated transport context. The wrapped path also spreads blockchain payload fields after identity/envelope fields, which deserves explicit sanitization.

**Evidence:** The installed v2 interceptor was exercised offline: a paired peer's operation request emerged with the attacker's replacement name and sender metadata. A malicious paired dApp can impersonate a familiar service in the approval sheet. This finding does not establish that the attacker can decrypt another peer's traffic.

**Solution:** Derive identity from authenticated transport/peer state. Strip request-supplied envelope and identity fields before normalization, then apply trusted values last. Preserve authenticated context into Swift and use it for permission lookup and display. Names and icons remain self-asserted branding, not identity proofs. Test identity overrides in both v2 and wrapped requests.

### S05 — High: Backup retention deletes directories it does not own

**Locations:** `Signet/Services/WalletBackup.swift:77`, `:116`, `:130`; `Signet/Services/BackupSettings` is defined in the same file.

`generations(in:)` considers every non-hidden directory under the chosen backup destination to be a backup generation. Retention recursively deletes the oldest of these. Selecting a shared folder or a parent containing unrelated documents can therefore delete those documents during a routine or startup backup. Multiple wallet directories also share the same generation namespace.

**Evidence:** Confirmed with the current `WalletBackup` implementation: creating an unrelated `000-unrelated-documents` folder, retaining one generation and forcing a backup deleted that folder and its contents.

**Solution:** Use a dedicated application-owned root, per-wallet subdirectories and a validated ownership marker/manifest for each generation. Prune only recognized owned generations that remain within the expected root. Reject unsafe overlap with the source wallet, require explicit migration before adopting an existing unrelated directory, and use non-following filesystem operations. Test shared destinations and unrelated directories. The earlier audit's separate symlink-to-outside-root deletion claim did **not** reproduce on this macOS runtime and is not counted as confirmed here.

### S06 — High: A stale wallet object can sign with another account's key

**Status:** Resolved by the signing-boundary repair committed with this report on 2026-10-09, completing the partial mitigation in `77f81f8`.

**Locations:** `Signet/Services/TezosClientStore.swift:182`; `Signet/ViewModels/WalletViewModel.swift:693`; `Signet/ViewModels/SendViewModel.swift:75`, `:186`; `TaquitoBridge/src/signers.js:10`.

**Original issue:** Send captured its original wallet and chain, but its signer provider read the view model's current wallet store. Secret lookup used only the alias. Switching directories, replacing files externally or reusing an alias could therefore return a different account's secret while the sheet still identified the original sender. Software signer specifications contained no expected address check.

**Original evidence:** Native lookup with temporary files retrieved another account's synthetic secret under the same alias. Transfer submission derived the actual source from that signer rather than requiring the displayed sender.

**Repair:** Native lookup verifies the alias/address mapping. Swift software signing specifications require the approved address. The shared JavaScript signer factory requires a nonempty string expected address before loading a secret, then unconditionally derives and compares the key's public key hash before returning the signer. Replacing the secret after native lookup cannot bypass that final check. All software signing callers use this factory.

**Evidence:** Offline rebuilt-bundle checks reject mismatched clear and encrypted keys for tz1–tz5 and allow matching keys. Missing, null, empty, whitespace-only and non-string expected addresses are rejected. Native regression tests cover stale wallets after directory changes and alias/address replacement. See the dated validation below.

**Scope of closure:** This prevents substitution of another account's software signing key. Network identity, dApp grants and other changes to approval context remain covered by S08, S12 and S20.

### S07 — High: Forget can remove another wallet after asynchronous password verification

**Status:** Resolved by the S07 repair committed with this report on 2026-10-09.

**Locations:** `Signet/ViewModels/WalletViewModel.swift` (`forgetSelectedWallet`, `changeWalletDirectory`); `Signet/Services/WalletStore.swift`; `Signet/Services/TezosClientStore.swift` (`removalSnapshot`, `remove(_:matching:)`).

**Original issue:** Forget validated one account's encrypted key, awaited decryption, then removed its alias from the current store. A directory switch could delete a different account. Capturing only the directory URL and checking the address was insufficient: replacing the encrypted key under the same alias/address during the await still deleted the replacement after validating the old key's password.

**Repair:** Capture the original store, a directory-change revision and an account snapshot before decryption; decrypt the snapshot's key. Every directory switch invalidates the revision, including switching away and back. Under the same wallet lock used for deletion, compare all matching rows across the three octez files and the actual directory identity (resolved path, device and inode), then remove only if unchanged. The in-memory store enforces the same snapshot contract. Unrelated account edits remain allowed.

**Evidence:** Regression tests reject replacement encrypted keys during password verification, directory switches and switches back, edits to each account file, replacement directories at the same path, added keys on watch-only accounts and snapshots from another in-memory store. Successful password-verified deletion and unrelated-account edits also pass. See the dated validation below.

**Scope of closure:** This closes deletion of a changed account across password-verification suspension. The existing advisory lock coordinates cooperating wallet writers; broader multi-file transaction and filesystem permission issues remain S09–S10.

### S08 — Medium: dApp grants do not bound signing, and directory changes retain old sessions

**Locations:** `Signet/Services/DAppConnectionManager.swift:102`, `:162`, `:181`, `:212`; `Signet/ViewModels/WalletViewModel.swift:293`, `:340`; `Signet/Models/DAppRequest.swift:78`.

Approval finds any locally held source account, rather than requiring an active grant for the authenticated peer, exact account, network and requested scope. The installed SDK receive path forwards requests without that wallet-level authorization check. Removing a permission does not invalidate queued requests. Changing wallet directories replaces the wallet provider's accounts but retains the existing manager/storage/peers, so old sessions can ask about new-directory accounts.

User approval is still required; this is not a silent signing bypass by itself. It undermines the account/scope/revocation boundary and compounds the still-open S03–S04. The S02 repair does not establish authenticated peer grants.

**Solution:** Check active peer/account/network/scope grants before queueing and again immediately before signing. Revocation must invalidate pending requests. Treat a directory change as a new wallet session: stop the old client, clear pending requests, construct storage for the new directory and reconnect explicitly. `restart()` alone retains the manager's immutable old storage. Test requests for unshared accounts, revoked scopes, changed networks and changed directories.

### S09 — Medium: Atomic individual files do not make a wallet transaction atomic

**Locations:** `Signet/Services/TezosClientStore.swift:80`, `:119`, `:139`, `:151`, `:234`; `Signet/Services/WalletBackup.swift:77`; `Signet/ViewModels/WalletViewModel.swift:311`.

Add writes hashes, public keys and secret keys separately. Rename/remove/import do the same. Failure or termination between replacements can leave an alias without its recoverable secret or break the joins used to find existing keys. `load()` and backup copying do not acquire the wallet lock, so they can observe/copy different stages of a mutation. Detached backups can overlap; same-second jobs can choose the same staging directory and remove it while another job is using it.

**Solution:** Serialize local mutations and backup jobs in a storage coordinator. Preserve octez-client locking, add a recoverable journal for multi-file changes, and verify/recover incomplete transactions on startup. Take a locked snapshot for readers/backups and use UUID staging names with cleanup on failure. Avoid blocking the main actor indefinitely on `lockf(F_LOCK)`; perform lock acquisition and disk I/O on a dedicated worker. Test failure between each replacement and concurrent backup/mutation.

### S10 — Medium: Secrets are written before restrictive permissions are set

**Locations:** `Signet/Services/TezosClientStore.swift:234`; `Signet/Services/OctezConnectStorage.swift:43`; `Signet/Services/AppStateStore.swift:35`; `Signet/Services/WalletBackup.swift:78`.

Secret and relay-seed files are created through Foundation atomic writes and only subsequently chmodded. Existing directories are not hardened by `createDirectory(...0700)`. An imported or chosen permissive directory can make new temporary secrets readable by other local users before chmod; final-file metadata preservation can create another transition. A crash can leave a temporary secret behind. With a correctly private parent directory, traversal protection reduces this risk substantially.

**Evidence:** Native Foundation checks under a normal umask produced a `0644` atomic-write temporary file. Calling `createDirectory(...0700)` on an existing `0755` directory left it `0755`.

**Solution:** Create temporary secret files with `O_CREAT | O_EXCL`, mode `0600` and non-following flags before any bytes are written; fsync and atomically rename them. Validate parent ownership/mode and explicitly harden application-owned directories. For shared octez directories, reject unsafe permissions or provide a clear remediation without unexpectedly changing third-party ownership. Clean up failed staging files and verify final permissions. Test creation and failure paths, not only final modes.

### S11 — Medium: Diagnostics persist credentials and private request content

**Locations:** `Signet/Services/TaquitoBridge.swift:174`, `:285`, `:339`, `:355`, `:365`; `Signet/Services/DAppConnectionManager.swift:59`, `:114`; `TaquitoBridge/src/octezconnect.js:69`.

Production starts the SDK with debug enabled. Bridge fetch tracing stores complete URLs and response prefixes; Matrix authentication replies can place access tokens in those prefixes. Relay diagnostics decrypt messages and log their contents, while incoming event logs include payload prefixes. The rolling log uses default directory/file permissions, and its size is checked only when the handle opens, allowing indefinite growth during a long session. Support transcripts can inadvertently disclose sessions or sensitive signed messages.

**Solution:** Default diagnostics to off. Log structured event names, status and timing only; redact credentials, query secrets, message bodies and signatures before any sink. Gate decrypting relay diagnostics behind an explicit temporary developer mode, create logs privately, cap each line and rotate by size during writes. Add redaction tests using synthetic login responses and signing requests. This review did not read actual logs or demonstrate that wallet private keys are currently logged. The initialization log's “transport” value is an SDK transport-type string, not a demonstrated serialized private key.

### S12 — Medium: Network labels do not establish the chain being signed on

**Locations:** `Signet/Models/Network.swift:75`; `Signet/Models/DAppRequest.swift:78`; `Signet/Services/NodeMonitor.swift:105`; `TaquitoBridge/src/index.js:218`, `:234`.

Node configuration accepts HTTP and does not verify the node's chain ID against the selected network. A user can label a mainnet-serving endpoint as a testnet and receive a valid branch for that real chain. dApp custom RPC URLs bypass the settings parser entirely, including loopback/private endpoints. Known custom-network matching compares only hosts, ignoring scheme, port and path. The approval sheet generally shows a network name or host rather than a verified chain identity.

**Evidence:** The native dApp mapper accepted a custom `http://127.0.0.1:8732` endpoint. No live request to that endpoint was made.

**Solution:** Associate supported networks with expected chain IDs and verify them when selecting an endpoint and before preparing a signature. Show verified chain identity plus the actual endpoint for custom networks. Validate scheme, userinfo, port and full normalized endpoint; require a deliberate advanced choice for insecure/local nodes. A dApp's remote endpoint should not inherit privileges from user-configured local RPCs. Handle legitimate localhost development as an explicit opt-in rather than banning it globally.

### S13 — Medium: Artwork loading has no destination or download-size boundary

**Locations:** `Signet/Services/IPFS.swift:61`; `Signet/Services/ImageLoader.swift:33`, `:43`; `Signet/Services/TzKTService.swift:89`.

Token/NFT metadata supplies image URLs. HTTP(S) destinations pass through without blocking loopback, link-local or private addresses; redirects are followed. Loading attacker-created assets can generate requests to local services and disclose wallet viewing activity to tracking endpoints. `data(from:)` buffers the complete response before downsampling, so thumbnail limits do not limit downloaded bytes or decode input. IPFS relative references also need validation so a purported content path cannot escape the intended gateway origin.

**Solution:** Apply an artwork-specific public HTTPS policy, validate resolved destinations and redirect hops, and validate IPFS CID/path syntax. Use a streaming byte limit with cancellation, content-type checks and bounded decode work; limit concurrent loads and cache cost by bytes. Consider optional remote-image privacy controls. Test private targets, public-to-private redirects, oversized responses and invalid content paths. This is a client-side local-network request/privacy issue, not a demonstrated arbitrary file read.

### S14 — Medium: The reviewed estimate is not an execution limit

**Locations:** `Signet/ViewModels/SendViewModel.swift:156`, `:186`; `TaquitoBridge/src/index.js:218`, `:234`, `:370`, `:379`; `Signet/Views/StakingSheet.swift:273`; `Signet/ViewModels/WalletViewModel.swift:623`.

Send estimates an operation, then separately submits a transfer without the approved fee/gas/storage values or a maximum debit. Taquito can re-estimate during submission. Staking follows the same pattern, including the raw path, which re-simulates and re-forges. Changed chain state or malicious estimates can increase what the user pays beyond the displayed confirmation. S03 separately covers explicit hidden dApp fees.

**Solution:** Create an immutable prepared operation, calculate its maximum fee and storage burn, and approve those limits together with sender/network/destination/amount. Sign that exact preparation. If rebuilding changes material terms, require a new approval. Cap protocol-derived values locally and test increased fees, allocation burn and state changes between review and execution.

### S15 — Medium: Unknown injection outcomes can lead to duplicate payments

**Locations:** `Signet/ViewModels/SendViewModel.swift:186`; `TaquitoBridge/src/index.js:234`; `Signet/Services/DAppConnectionManager.swift:162`.

If an injection reaches a node but its reply is lost, Send receives an exception and returns from `.sending` to `.confirm`. A retry constructs another operation, potentially with a new counter after the first was included. The user can then pay twice. dApp execution also does not retain a locally computed hash/signed payload for recovery from an ambiguous result.

**Solution:** Compute and persist the operation hash and signed bytes before injection. Represent unknown submission outcome separately from definite rejection; query pending/included status before retrying and rebroadcast the same signed bytes when appropriate. Never create a new payment merely because an HTTP response was lost. Test accepted-injection/lost-response and reconnect scenarios.

### S16 — Medium: Async work can publish data into the wrong account/network

**Locations:** `Signet/ViewModels/WalletViewModel.swift:110`, `:340`, `:386`, `:623`, `:669`; `Signet/Views/StakingSheet.swift:273`.

`refresh()` assigns `tezBalance` before checking the selected address. Its later guard only checks the address, not the network or directory, and subsequent awaited assignments have no renewed check. A delayed mainnet refresh can populate a testnet view for the same address, or stale account data can arrive after selection changes. Network/directory changes clear only some fields; account-not-on-chain handling leaves old balance/delegate state. Overlapping refreshes also share one loading flag.

Staking/governance read the mutable chain again after injection to wait for confirmation, potentially polling a different network. Their confirmation flows use the live selection rather than a captured account intent.

**Solution:** Capture one chain, account, directory revision and refresh generation. Await a complete snapshot, then publish it atomically only if the generation still matches. Cancel superseded work and clear all dependent fields on context changes. Capture immutable operation context for estimate, approval, signing and confirmation. Test delayed responses with account/network changes and overlapping refreshes.

### S17 — Medium: Reply failure is reported as successful request completion

**Locations:** `Signet/Services/DAppConnectionManager.swift:134`, `:162`, `:181`, `:235`.

`respond()` catches transmission failures and returns normally. Callers then remove the request and set “Connected”, “Sent” or “Signed” success messages. A transaction may have been injected while the dApp never receives its hash; repeating the action can duplicate its effects. Permission and signature response failures similarly lose recoverable state.

**Solution:** Return a typed delivery result or throw. Track execution and reply delivery separately, retain the already-created response and retry only sending it. Store the hash/signature in a completed-request cache keyed by authenticated peer and request ID. Test a successful operation followed by failed response delivery and ensure no second signing/injection occurs.

### S18 — Medium: Failed or concurrent startup leaves a false connected state

**Locations:** `TaquitoBridge/src/octezconnect.js:40`, `:52`, `:232`; `Signet/Services/DAppConnectionManager.swift:51`, `:78`.

JavaScript assigns the global client before awaiting `connect()`. If connection fails, the next start sees a non-null client and reports success without reconnecting. Swift guards only `isStarted`, so concurrent start calls can both enter while the first is awaiting. Concurrent initialization can produce multiple clients/listeners against one storage and overwrite the global client. Pairing also reports success before asynchronous `addPeer` completes.

**Solution:** Maintain a single shared startup promise and explicit stopped/starting/connected/failed states. Publish the client only after connection succeeds; clean up failed attempts. Serialize stop/start and expose pairing progress/failure accurately rather than treating queued work as a completed connection. Test delayed and failed connect, simultaneous start calls and stop during startup.

### S19 — Medium: Untrusted dApp/bridge input lacks bounded resource budgets

**Locations:** `Signet/Services/DAppConnectionManager.swift:114`; `Signet/Models/DAppRequest.swift:34`; `Signet/Services/TaquitoBridge.swift:64`, `:285`; `TaquitoBridge/src/octezconnect.js:102`, `:153`.

There are no wallet-level limits on queued requests, operation count, overall incoming event bytes or metadata length. The S02 repair now limits sign_payload hex to 65,536 characters and its Micheline nesting to 128, but it does not bound operation batches or event parsing before that validation. A paired malicious peer can send unique IDs, oversized payloads or huge batches and consume memory/UI/JavaScript time. The installed SDK deduplicates pending IDs, but that does not bound unique requests. Bridge HTTP bodies are buffered without a response-size cap. Swift task cancellation does not cancel the continuation's JavaScript work, and unresolved promises can retain operations indefinitely.

**Partial mitigation:** The new signing readers reject excessive depth before recursive descent; the previously observed in-cap parser crash is fixed. These protections apply only to the sign_payload validation path.

**Remaining solution:** Validate and cap message bytes, string lengths, operation count, nesting and per-peer pending/in-flight work before parsing or approval. Add bounded network bodies and operation-specific timeouts/cancellation. Distinguish cancellation before signing from an unknown post-injection outcome. Reject rate-limited requests explicitly. Test floods, oversized payloads and unresolved bridge promises.

### S20 — Medium: Server-controlled numbers reach trapping Swift conversions

**Locations:** `Signet/Services/TaquitoChainService.swift:102`, `:127`, `:140`, `:188`, `:248`; `Signet/Services/JSONValue.swift:15`.

Several RPC-derived values are converted with `Int(double)` or `.map(Int.init)` without finite/range validation. Swift traps on non-finite or out-of-range values. JavaScript calculations and malicious RPC responses can supply such numbers, turning a service failure into an application crash. Defaults of zero and permissive missing-field handling can also make malformed estimates look valid.

**Solution:** Centralize strict finite, integer and protocol-range decoding; use checked conversions and reject unexpected shapes. Validate nonnegative fees/gas/storage, result counts and statuses on the JavaScript side too. Test negative, fractional, very large and non-finite values and missing simulation entries, with an error outcome instead of a process trap.

### S21 — Medium: Faucet challenges are not bounded or cancellable

**Locations:** `Signet/Services/FaucetService.swift:87`, `:104`, `:136`; `Signet/ViewModels/WalletViewModel.swift:600`.

The parser accepts any integer difficulty. Negative difficulty reaches `String(repeating:count:)`, which traps; extreme values allocate excessive memory. Hard/impossible work loops forever with no cancellation check, deadline or total challenge bound. Verification can return an unlimited sequence of challenges. Running it in a detached task prevents UI blocking but does not prevent sustained CPU consumption or allow reliable cancellation.

**Evidence:** The current parser accepted a synthetic challenge with difficulty `-1`. The crashing solver was deliberately not invoked.

**Solution:** Enforce a practical maximum difficulty and valid challenge counters/counts, bound challenge length and elapsed work, check cancellation periodically, and cap total rounds. Reject invalid progress sequences. Validate finite positive faucet amounts/limits as well. Test negative/excessive difficulty and cancellation of a difficult challenge.

### S22 — Medium: Timed-out Ledger exchanges can contaminate the next exchange

**Locations:** `Signet/Services/LedgerHID.swift:198`, `:242`, `:248`; `TaquitoBridge/src/ledger.js:33`, `:63`.

Timeout clears the pending callback but leaves the HID device/channel open. The next exchange resets framing and starts another pending request on the same channel. If the first response arrives late, it can satisfy the new request because response framing does not carry an exchange identifier. Per-APDU busy checks also do not guarantee serialization of an entire multi-APDU signing session.

**Solution:** Treat timeout/write failure as loss of transport synchronization. Close/reset and discard stale reports before permitting another session, or require reconnection. Serialize complete signer sessions per device, not just individual APDUs, and validate response shapes and signature/key consistency. Add a fake-transport test that delivers an old response after a retry starts. Source-supported; no physical Ledger timing experiment or Ledger-key extraction was performed.

### S23 — Medium: Embedded purchase content has excessive navigation/media privileges

**Locations:** `Signet/Views/BuyWebView.swift:36`, `:76`, `:88`, `:93`; `Signet/Services/BuyProvider.swift:36`.

Foreign top-level navigation is redirected to the browser only for `.linkActivated`; forms, redirects and script-driven navigation can remain inside the wallet's embedded purchase UI without an origin indicator. `window.open` forwards arbitrary URL schemes to `NSWorkspace.open`. Camera/microphone permission is auto-granted based on hostname alone, including every provider subdomain, without checking scheme/port or the initiating frame.

A compromised provider/subdomain or navigation to attacker content can exploit these broader privileges or impersonate purchase/verification UI. This is not evidence that web content can directly call the wallet's signing bridge.

**Solution:** Check all main-frame navigations and redirects against a narrowly defined HTTPS origin allowlist. Show the current origin, route foreign pages to a browser, and allow external application schemes only after a deliberate user action and explicit validation. Restrict media access to specific verified origins/frames and retain an appropriate user permission prompt. Test redirects, form posts, script navigation, custom schemes and foreign frames.

### S24 — Medium: Hosted tests can access live wallet identity and mutate backup state

**Locations:** `Signet/SignetApp.swift:5`; `Signet/ViewModels/WalletViewModel.swift:246`, `:291`; `SignetTests/DAppStartupTests.swift:10`; `SignetTests/StakingTests.swift:169`; `SignetTests/OctezConnectEndToEnd.swift:9`.

The test-host guards disable dApp startup and Sparkle, but the app still constructs real configured stores, loads wallet state and schedules a backup. Given S05, running tests can prune the user's configured backup destination. `DAppStartupTests` deliberately copies the real relay seed/session into a networked client; the live baker test reads the user's real octez public keys and can assign one as a testnet consensus key. Several tests share and mutate the singleton bridge while Swift Testing can run suites concurrently. Network tags alone do not make tests opt-in. Some integration harness paths are machine-specific.

**Solution:** Construct an entirely isolated test app model before any live store, backup or network service initializes. Replace real persisted sessions/keys with fixtures and make live/hardware tests explicitly opt-in in a separate scheme/target. Inject per-test bridge instances/storage and serialize genuinely shared resources. Use configurable temporary harness locations. Add a launch-isolation check verifying that no real wallet/backup paths are opened. Do not rely solely on disabling the dApp client.

### S25 — Medium: Release publication is not fail-closed

**Locations:** `.github/workflows/release.yml:69`, `:95`; `scripts/release.sh:58`; `Signet/Info.plist:9`; `project.yml:12`.

The workflow creates a public GitHub release before building and uploading its assets. Because the updater reads `releases/latest/download/appcast.xml`, a build failure or missing signing configuration can make the latest release lack the feed, disrupting automatic updates. Reruns replace ZIP and appcast separately, temporarily exposing mismatched assets. The archive command is piped through `grep ... || true`, losing the actual build status; checking that an app directory exists is weaker than checking successful archive completion. The release workflow has no test or source/bundle consistency gate.

**Solution:** Generate notes without publishing a final release, build and validate first, upload all signed assets to a draft, then publish. Require update signing for update-bearing releases and avoid mutating published version assets. Capture `xcodebuild`'s status before filtering its log and fail on any archive failure. Run isolated security regressions and a locked `npm ci` bundle comparison in CI; retain the SPM lock and consider action SHA pinning. The existing HTTPS feed and embedded EdDSA verification key are positive controls; no updater signature bypass was demonstrated.

### S26 — Low: Portfolio failures and truncation look like complete empty holdings

**Locations:** `Signet/Services/TzKTService.swift:46`, `:80`; `Signet/Services/TaquitoChainService.swift:71`, `:258`, `:281`.

Token/NFT loading fetches only the most recently updated 200 balances without pagination. Separate fungible/NFT calls duplicate that request. Indexer errors become empty successful arrays, hiding the distinction between “none” and “unavailable.” Attacker token spam can push older legitimate holdings outside the returned page. Metadata decimals are not range-validated, allowing nonsensical or non-finite displayed amounts.

**Solution:** Fetch one paginated snapshot, retain explicit completeness/error state, preserve the last known data with an unavailable indicator, and validate metadata/numeric ranges. Bound pagination while clearly marking partial results. Test accounts above the page limit, indexer failures and malformed decimals. This is a display/correctness finding; the current code does not establish a direct asset-spending exploit from pagination.

## Validation performed on `7544c50`

All cryptographic checks used synthetic keys and offline mocks. Native filesystem checks used UUID-named temporary directories and artificial secret strings. No live operation, real wallet backup, real relay login, production log inspection or hardware exchange was performed. The npm vulnerability query was the dependency check's only required external service.

| Check | Result |
| --- | --- |
| Fresh `npm audit --json` in `TaquitoBridge` | **0 reported vulnerabilities** across 155 dependencies; this is not a source audit or proof of safety |
| Rebuild bridge to a temporary output with the installed native esbuild binary; `cmp` with committed resource | **Byte-identical** |
| Original message-signing transaction payload against the committed bundle | **S02 fix verified**: refused for safe, raw, operation, unknown and missing signing types |
| Swift request parsing, signing validation and nesting suites in an isolated temporary Swift package | **15 tests in 3 suites passed**, including parameterized envelope/type vectors; production helpers copied into the package, no hosted application launched |
| Committed-bundle signing/type/hex/length/envelope and depth checks under Node | **Passed**, including depth 128 acceptance, depth 129 refusal, nested sequences/generic primitives, wide siblings and the 16,000-level original crash input |
| Committed bundle evaluated in native JavaScriptCore | **Passed**: transaction input, malformed envelopes and over-depth payloads refused before signer access; valid messages and depth 128 reached the signer boundary with an intentionally invalid signer specification |
| Hidden fee/parameter summary using committed bundle; execution mapping with a mocked toolkit | **Reproduced S03**: 100 tez fee and parameter recipient omitted from the summary, fee preserved for execution |
| Installed Octez Connect v2 interceptor with replacement metadata | **Reproduced S04** |
| Raw-operation source with real synthetic signer/local forging and a mocked RPC | **Reproduced S01**: substituted transfer signed and passed to the stub injector |
| Encrypt/decrypt round trips and wrong-password rejection for tz1, tz2, tz3, tz4 and tz5 in the committed bundle | **Passed** |
| Compile and exercise current Swift backup/store/faucet/dApp mapping code in a standalone harness | **Reproduced S05, S06, S10, S12 and S21**: unrelated-directory deletion, stale alias lookup, permissive temporary-file mode/existing directory, loopback custom RPC and negative faucet difficulty acceptance |
| `xcodebuild ... -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile build-for-testing` | **Succeeded** for current app and test targets; sandbox compiler/package-cache denial required an authorized retry. Existing CoreDevice/CoreSimulator tooling warnings did not prevent the macOS build |
| Hosted/full/live/hardware test suite | **Not run**, due the real-state and live-operation behavior described in S24 |

Current supporting artifacts are under `/private/tmp/signet-reaudit-7544c50/`: `check.cjs`, `s02-depth.cjs`, `main.swift`, `native-checks`, `jsc-check.swift`, `jsc-checks`, the rebuilt bundle, isolated `swift-tests/` package and `build.log`. Older evidence at `/private/tmp/signet-audit-20261008/` describes the pre-fix revision. The rerun symlink check again returned **false** for deletion outside the backup root; S05 remains the confirmed deletion of unrelated actual directories inside that root.

## S07 follow-up validation — 2026-10-09 working tree

- **35 tests in 7 suites passed** in an isolated Swift package using copies of the production stores and view models and the repository's store, directory and import tests. Wallet fixtures used temporary directories; bridge storage was in memory, logs were redirected to temporary storage, and networking was disabled in the temporary harness. Production Forget and snapshot logic was unchanged in that harness.
- **Xcode `build-for-testing` succeeded** for the app and test targets with the resolved dependencies. Hosted/full/live tests were not run because of S24.
- **`git diff --check` passed.** No bridge source was changed by the S07 repair.

Artifacts: `/private/tmp/signet-s07-isolated-tests/tests.log` and its isolated package; `/private/tmp/signet-s06-s07-review/build-s07.log`. This follow-up closes S07 only; it is not a fresh audit of all remaining findings.

## S06 follow-up validation — 2026-10-09

- **9 tests in the WalletDirectoryTests suite passed**, including six parameterized missing/invalid-address cases, rejection before key loading, mismatched-key rejection, successful matching-key signing, stale-wallet checks and S07 directory/key replacement regressions. The same isolated harness described above was used with the rebuilt bundle.
- **Offline Node checks against the rebuilt app bundle passed** for mismatched clear/encrypted keys and matching clear keys across tz1–tz5, plus seven absent/invalid expected-address cases. Only synthetic keys were used and network access was prohibited by the harness.
- **`npm run build` succeeded**, regenerating `Signet/Resources/taquito-bridge.js`; **Xcode `build-for-testing` succeeded** and **`git diff --check` passed**. Hosted/full/live tests were not run because of S24.

Artifacts: `/private/tmp/signet-s06-s07-review/s06-fixed.cjs`, `/private/tmp/signet-s06-s07-review/build-s06.log`, and `/private/tmp/signet-s07-isolated-tests/s06-tests.log`. This follow-up closes the remaining S06 signing-boundary gap; it is not a fresh audit of all remaining findings.

## Previous-audit reconciliation and positive controls

The earlier unrestricted dApp transaction-signature issue (S02), software key substitution (S06) and account deletion across password-verification suspension (S07) are now resolved. Hidden operation terms, metadata overrides, missing permission enforcement, backup pruning, temporary secret permissions, unbound estimates, ambiguous retries, artwork loading, production diagnostics and faucet work remain open, along with raw RPC forging, other asynchronous account/operation races, Ledger transport recovery, embedded-widget policy, test isolation and release publication. This report preserves those IDs and updates the evidence and status rather than renumbering the remaining findings.

Mainnet account creation and import now default to encrypted storage and display an unencrypted-key warning. Clear storage remains available and existing clear keys/backups remain clear; this is a disclosed policy choice rather than proof of remote key theft. Encryption round trips succeeded for all five supported software schemes. Generated native keys use CryptoKit and JavaScript randomness is backed by Security framework randomness. Wallet file replacement and octez-compatible advisory locking are implemented, though their transaction/permission gaps need the fixes above. Ledger signing checks the expected derived address and does not export device secrets. Swift 6 complete concurrency checking and the current app/test compilation are positive controls, but actor isolation alone does not prevent state changes across `await`.

Sparkle resolves to **2.10.0**, with a committed package resolution and embedded public EdDSA update key. A signing verification key is public by design. No malicious update feed or bypass of archive signature verification was demonstrated. Native UI and the purchase WKWebView are separate from the JavaScriptCore signer context; no remote script evaluation into the signer was found in the reviewed application paths.

Additional hardening after the findings: isolate networking/dApp code from software-key custody, correct the stale “Private keys never enter the JavaScript runtime” comment in `TaquitoBridge.swift`, and reduce secret lifetime. Export explicitly copies clear keys to the general pasteboard; consider concealed/transient pasteboard metadata and conditional expiry without clearing newer user clipboard content. Protect existing backups when introducing encrypted defaults, since new encryption does not retroactively encrypt older copies.

## Recommended repair order

1. Disable or locally verify raw forging (S01) and approve exact dApp operation costs/effects (S03). Preserve the verified S02 type/envelope/depth rejection checks.
2. Make backup pruning ownership-safe (S05), and preserve the S06 signer-address and S07 snapshot/deletion regressions.
3. Enforce authenticated dApp identity/grants (S04, S08), make storage transactions and secret-file creation safe (S09–S10), and remove sensitive diagnostics (S11).
4. Add the adversarial regression tests described above, then address network identity, resource limits, async state, response recovery, Ledger synchronization and widget policy.
5. Isolate hosted/live tests before using them as release gates, and publish only fully validated signed releases.

This is a source and targeted-behavior audit of the checked-out revision, not a formal verification, physical hardware assessment, comprehensive dependency cryptanalysis or certification of deployed binaries. Findings requiring hostile services, timing races or local access state those prerequisites; absence of a finding is not a guarantee that a path is secure.
