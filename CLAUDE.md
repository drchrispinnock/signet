# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Signet is a native macOS Tezos wallet written in SwiftUI. The spec is `docs/spec/SPEC.md` and the
hand-drawn mock of the default screen is `docs/spec/EXAMPLE.png`. Read both before changing the UI.

## Commands

The Xcode project is generated from `project.yml` by XcodeGen (`brew install xcodegen`).
Edit `project.yml`, never the `.xcodeproj` directly, then regenerate:

```sh
xcodegen generate
```

Build, test, and run from the command line (output is noisy; grep for `error:` or `** BUILD`):

```sh
xcodebuild -project Signet.xcodeproj -scheme Signet -destination 'platform=macOS' -derivedDataPath build build
xcodebuild -project Signet.xcodeproj -scheme Signet -destination 'platform=macOS' -derivedDataPath build test
open build/Build/Products/Debug/Signet.app
```

Run a single test (Swift Testing, so filter by suite or suite/test):

```sh
xcodebuild -project Signet.xcodeproj -scheme Signet -destination 'platform=macOS' -derivedDataPath build test -only-testing:SignetTests/AddressTests/shortensLongAddresses
```

Tests use the Swift Testing framework (`import Testing`, `@Test`, `#expect`), not XCTest.
Quit any running Signet first: the app sets `LSMultipleInstancesProhibited`, so the test host
(Signet.app itself) cannot launch while one is open and xcodebuild reports "Could not launch".
Function-level `-only-testing` selection can silently run nothing; select suites.

Live tests are opt-in (S24). Everything tagged `.network` also carries the `.liveNetwork`
condition (`SignetTests/LiveTestTraits.swift`) and is skipped unless the runner sets
`SIGNET_NETWORK_TESTS=1`; `xcodebuild` passes it through as
`TEST_RUNNER_SIGNET_NETWORK_TESTS=1 xcodebuild … test`. The few tests that read the developer's
real `~/.tezos-client` or `~/.signet` state need `TEST_RUNNER_SIGNET_REAL_WALLET_TESTS=1` as
well. Tests that swap the shared bridge's storage or event handler wrap themselves in
`SharedBridge.shared.run { … }` so they never overlap. Under the test host the app itself builds
an in-memory model (`SignetApp.makeModel(isTestHost:)`): no wallet directory, backup, dApp
storage or client is touched (`TestHostIsolationTests`). The bridge has its own offline
regressions: `cd TaquitoBridge && npm test` (dApp preparation, dApp identity and grants,
approved limits and injection outcomes).

## Branches

Branching follows `BRANCHES.md`. `main` is the raw development line and `release` is the
current release line (still alpha). Nothing is developed directly on either. Work happens on a
feature branch named `<user>@<feature>`, cut from `main`, where user is `chrispinnock`, `claude`
or `codex` and feature is one word or a short phrase (`claude@offline-signing`). When the
feature is thought done it is merged up into `main`; when `main` is thought ready to ship it is
merged up into `release`, and the version tag goes on `release`. So Claude begins a piece of
work by creating or checking out its `claude@…` branch and commits there; merging into `main`
or `release`, pushing and tagging happen only when asked. `book_preview` and `book_release`
carry the Leanpub book; `transak` holds the widget-based Transak integration that is waiting
for a partner key.

## Releases

The app version comes from git: `scripts/stamp-version.sh` runs as a post-build phase and writes
`git describe --tags` (minus the `v`) into `CFBundleShortVersionString` and the commit count into
`CFBundleVersion`, so the About panel shows `0.2` on the tag and `0.2-3-g<sha>` afterwards. Tag a
release on `release` before building it (merge `main` up into `release` first; see Branches). Copyright and the About credits live in `Signet/Info.plist` and
`Signet/Resources/Credits.rtf`.

`scripts/release.sh [version]` archives a Release build, signs it with `$DEVELOPER_ID` if set
(ad-hoc otherwise), optionally notarises with `$NOTARY_PROFILE`, and writes `dist/Signet-<version>.zip`
plus `dist/appcast.xml`, the Sparkle feed for that one release (see Updates below).
Pushing a `v*` tag runs `.github/workflows/release.yml`, which does the same on a macOS runner and
attaches the zip to a GitHub release; signing and notarisation switch on when the repository
secrets described in the workflow exist. Since 0.4.2 those secrets are set, so tagged releases
are Developer ID signed and notarised (identity `Developer ID Application: Christopher Pinnock
(CP8YGC8C4P)`; local builds use `NOTARY_PROFILE=signet-notary`). Setup notes are in
`scratch/APPLEID.md` (git-ignored). The codesign identity is only valid when Apple's Developer
ID G2 intermediate certificate is in the keychain; the workflow imports it, and it had to be
added by hand on the development Mac.

**Updates (Sparkle).** The app updates itself the way iTerm2 and NetNewsWire do: the Sparkle 2
package (`packages:` in `project.yml`) checks `SUFeedURL` from `Info.plist`, which is
`https://github.com/drchrispinnock/signet/releases/latest/download/appcast.xml`, so the feed is
simply the `appcast.xml` asset of the newest GitHub release. `release.sh` makes it with
`generate_appcast` from the resolved package (`build/packages/artifacts/sparkle/Sparkle/bin`):
one item whose enclosure points at the zip on that release's page, release notes embedded from
`dist/Signet-<version>.md` when present (the workflow writes GitHub's generated notes there),
signed with the EdDSA key. The public half is `SUPublicEDKey` in `Info.plist`; the private half
lives in the development Mac's login keychain (made by Sparkle's `generate_keys`) and must also
be the `SPARKLE_PRIVATE_KEY` repository secret (`generate_keys -x file`, then
`gh secret set SPARKLE_PRIVATE_KEY < file`). The workflow requires this secret and a signed appcast before publication; missing signing
material fails the release. Published release assets are immutable: reruns may reuse drafts only. Sparkle verifies the EdDSA
signature and the Developer ID signature of every download. `sparkle:version` is
`CFBundleVersion`, the commit count, so it only ever grows. In the app `UpdaterService`
(`Signet/Services`) wraps `SPUStandardUpdaterController`; "Check for Updates…" sits under the
app menu, and Settings has an Updates section (automatic check, automatic download, last
checked, Check Now). `SUEnableAutomaticChecks` is on so Sparkle skips its first-run prompt;
automatic download is off by default. The updater is not started under the test host.

## Architecture

- **Models** (`Signet/Models`) are plain `Sendable` value types. A `Wallet` is one `Address`
  plus the alias the user gave it, its scheme and public key; the app holds a list of wallets
  and shows one at a time. In the UI these are called **accounts** ("Create account…", "My
  accounts", default alias "My Account"); the code keeps the `Wallet` name. Say "account" in any
  new user-facing text; "wallet" is reserved for the whole key directory and the app itself. `Base58.swift` holds Tezos base58check encoding and the byte prefixes. `AddressScheme` lists every tz prefix
  (tz1 through tz6) with an `isSupported` flag so unsupported schemes stay visible in the type
  system rather than being forgotten.
- **`ChainService`** (`Signet/Services`) is the single protocol for everything read from the
  chain or indexers. `MockChainService` returns the numbers from the sketch; views and previews
  are driven by it until live access lands. New data sources go behind this protocol.
- **Wallet storage is `~/.signet`, in octez-client's format.** `TezosClientStore` reads and writes
  `{public_key_hashs,public_keys,secret_keys}` exactly as octez-client lays them out,
  joining entries by alias, appending only, replacing files atomically and holding `wallet_lock`
  while writing. A shared per-directory in-process lock also serializes threads, since `lockf`
  alone only excludes other processes. Reads take the lock too, and so do recovered backup snapshots (S09); the lock is tried with a
  5 s deadline (`StoreError.locked`), never waited for forever. A change that touches several
  files writes `wallet_journal` first (previous contents of every file, base64) and removes it
  after the last replacement; a journal found by any later read or write means the change was
  cut short and the files are rolled back before anything else happens, so the key files always
  agree with each other. Every file holding secrets or state (`PrivateFile.write`, S10) is
  created `O_CREAT|O_EXCL|O_NOFOLLOW` with mode 0600 before a byte is written, fsynced, renamed
  into place with the directory synced, and reads refuse symlinks; directories we write into
  are hardened to 0700 when we own them and refused otherwise; stale `.<file>.<uuid>.tmp`
  leftovers are swept under the lock. `OctezConnectStorage`, `FileAppStateStore`,
  `FileMultisigProposalStore` and `WalletBackup` use the same primitive. Proposal changes go
  through `MultisigProposalStore.update(_:)`, which merges into what is on disk under the lock,
  and oversized proposals another program wrote are left out (S19). A `Wallet` is therefore an octez alias; `keyKind` records whether its secret is
  unencrypted, encrypted, on a ledger, remote or absent. Clear, encrypted and ledger keys can sign
  (`KeyKind.canSign`); remote signers cannot yet. `WalletStore.add(_:locator:)` writes any
  `secret_keys` locator; `add(_:secretKey:)` is the convenience for keys on disk.
  `importWallets(from:)` (S09) first takes the source's own locks and rolls back any journal it
  finds there, copies all three key files as one snapshot, releases that lock and only then takes
  this directory's lock to merge (no nested locks, so opposite imports cannot deadlock); a
  directory cannot be imported into itself (`StoreError.sameDirectory`).
  `secretKey(for:)` and `remove(_:)` take the whole `Wallet` and fail with
  `StoreError.addressMismatch` unless `public_key_hashs` still maps its alias to its address: a
  sheet's `Wallet` can outlive a directory switch, and the alias alone must never pick a key or
  choose what to delete.
  The directory can be changed in Settings; that pointer is the one thing kept in UserDefaults
  (`WalletDirectorySettings`), because it cannot live inside the directory it names. Switching
  rebuilds both stores through the `storeFactory` the app passes to the view model.
  `WalletBackup` copies the wallet files (plus `state`, `contracts` and the multisig proposals)
  into a timestamped generation under `~/.signet_backups` on launch, after key creation/rename
  and on directory change, skipping when unchanged and keeping the newest N (default 10); folder
  and N are `BackupSettings` in UserDefaults and editable in Settings. The files are read as one
  locked snapshot and written into a uniquely named `.<uuid>.partial` staging folder that is
  removed if the job fails. A generation is worth
  writing when any key file, `contracts` or proposals file exists (S28). Each generation carries
  a `.signet-backup` manifest (version, date, source directory, files), and pruning (S05) deletes
  only stamp-named, non-symlink generations directly under the backup folder with a supported,
  complete manifest for the current wallet directory. Unmarked legacy generations, extra
  documents, unknown manifest versions and other wallets' generations are preserved.
  A backup folder that is the wallet directory, inside it or around it is refused
  (`BackupError.overlapsWallet`).
  If `~/.signet` already has keys the app opens on the dashboard. On a cold start (no keys)
  `NoWalletsView` offers four ways in: import `~/.tezos-client` when one exists (an exact file
  copy, shown first and highlighted), create a new account, import an existing key or phrase, or
  connect a Ledger. The merge
  path in `TezosClientStore.importWallets` remains but is not exposed in the menu. The app is
  deliberately not sandboxed so it can reach both directories.
- **Keys.** `KeyGenerator` makes tz1 and tz3 keys with CryptoKit and encodes them in Swift, so
  those secrets never enter JavaScript; tz2 and tz4 are generated in the bridge with the same
  `@noble/curves` code Taquito signs with (BLS secrets are little-endian on the wire). New keys
  are written as `unencrypted:` entries, or as octez-format `encrypted:` entries (edesk/spesk/
  p2esk/BLesk: 8-byte salt, PBKDF2-HMAC-SHA512 ×32768, NaCl secretbox, zero nonce) when the user
  sets a password; the bridge's `encryptSecretKey` does the encryption and Taquito's
  `InMemorySigner(key, passphrase)` opens it. Create wallet defaults to encrypted on mainnet and
  clear on testnets and warns that clear keys are unprotected on disk. Send asks for the password
  on the confirm step for encrypted senders; a wrong one surfaces as `ChainError.wrongPassphrase`.
- **`WalletViewModel`** is a `@MainActor @Observable` class owning the wallet list, the
  selected wallet and the loaded balances, domains and NFTs, and `createWallet(alias:scheme:)`.
- **Send.** `SendSheet` + `SendViewModel`: recipient is an address, a `.tez` name (forward lookup via
  `TezosDomainsService.resolve`) or a pick from our wallets/address book; the confirm step shows
  sender → recipient with avatars, the recipient named from our records (verified) or from the
  TzProfiles data TzKT carries in `extras.profile` ("Not verified"), plus fee/allocation/total from
  `estimateTransfer`, which runs in the bridge with a read-only signer so no secret is needed to
  estimate. **The approved estimate is the execution limit (S14).** `TransferEstimate.limits`
  (`OperationLimits`: fee, gas, storage, plus the reveal Taquito will prepend for an unrevealed
  account, priced as it will be sent) travels with the send: `sendTransfer(…limits:)`,
  `performStaking(…limits:)`, `multisigOriginate`/`multisigSubmit` take it and the bridge
  (`src/operations.js`: `prepareApproved`, `checkApproved`, `signAndInject`) prepares the
  operation again with exactly those limits, refuses it if any figure differs or the reveal
  would cost more, forges and signs locally, preapplies and injects; nothing is re-estimated
  after approval. Raw execution refuses increased fee, gas or storage budgets; estimates include
  its storage burn. Multisig uses the same checked preparation and local signing pipeline. A send without limits
  is refused (`SendError.notEstimated`, `WalletError.notEstimated`). **A lost node reply is an
  unknown outcome, not a failure (S15):** the operation hash is computed from the signed bytes
  before injection (`injectSigned`). Signed bytes, source, chain, branch, contents and any originated
  contract address are persisted privately in `~/.signet/pending_operations.json` before the node
  is contacted. Any injection error, including gateway/HTTP errors and mismatched node hashes, returns
  `SentOperation(hash:, injected: false, signedBytes:)`; `SendViewModel` goes to `.unknown`,
  watches the chain (`waitForConfirmation`) and offers "Send the same operation again" (`rebroadcast`, the same
  bytes, so it cannot pay twice). Opening Send restores outstanding work, verifies its locally
  forged intent/hash/source and can resume block scanning or replay identical bytes. Outstanding
  work prevents replacement signing for that account/chain even after an RPC-node change.
  Scan cursors survive restarts; inclusion removes the record. Pre-injection validation failures
  still throw without injection. Multisig, governance, raw and staking paths share this recovery
  boundary; origination confirmation errors retain the computed contract address. Every signing call (`sendTransfer`, `performStaking`, `proofOfPossession`, the dApp
  `octezConnectExecute`/`octezConnectSign`) takes a `SigningKey`: `.secret(key, passphrase:, address:)` or
  `.ledger(LedgerKey, address:)`, serialised by `bridgeSpec` into the JSON the bridge's
  `signerFor` (`src/signers.js`) turns into an `InMemorySigner` or a `LedgerSigner` for the one
  operation. `WalletViewModel.signingKey(for:passphrase:)` builds it from the wallet's kind. Both
  kinds carry the expected address; software `signerFor` requires a nonempty string address
  before loading the key and refuses a key that derives another one
  (`ChainError.keyAddressMismatch` for secrets, `ledgerWrongDevice` for Ledgers).
  `waitForConfirmation` waits for the operation's block (the bridge's `waitForRawOperation` block watcher, up to 15 blocks; every operation is forged locally, so there is nothing for Taquito to track). `ChainError.fromBridgeMessage` maps the bridge's error
  text (wrong password, Ledger declined / locked / app not open / not connected) to typed errors
  so every sheet words them the same way.
- **Import (0.6).** "Import account…" (burger and Operations menus above Connect Ledger, welcome
  screen, Cmd-Shift-I) opens `ImportAccountSheet` with two tabs, Secret key first (a `SecureField`). *Recovery phrase*: any BIP39
  length (12 to 24 words), optional BIP39 passphrase, curve (ed25519 default, secp256k1, P-256,
  BIP32-Ed25519) and HD path (default `44'/1729'/0'/0'`, account stepper), plus the legacy
  fundraiser derivation (email + password); the address is previewed as you type and the key comes
  from Taquito's `InMemorySigner.fromMnemonic` / `fromFundraiser` in the bridge (`keyFromMnemonic`,
  `keyFromFundraiser`, `validateMnemonic`). *Secret key*: any base58 secret (edsk seed or 64-byte,
  spsk, p2sk, BLsk, mdsk) or an octez-encrypted one (edesk… with its password; stored as is);
  `inspectSecretKey` reports the address and reduces a 64-byte edsk to its seed so it can be
  stored in octez format. Both paths end in `WalletViewModel.importAccount(alias:material:…)`,
  which can encrypt the key for storage like Create account. `KeyImporter` is the protocol
  (`BridgeKeyImporter`, `MockKeyImporter`). **Session-only keys (0.8.3).** The sheet's "Keep the key" choice (in the wallet directory, or only until Signet quits) makes a paper key: `importAccount(…keepForSession: true)` puts it in `SessionKeyStore` (`Signet/Services/SessionKeys.swift`, `mlock`ed bytes wiped on forget) instead of the store, `Wallet.isSessionOnly` marks it, and `WalletViewModel.wallets` is the stored list plus `sessionWallets`. It signs, exports, renames and forgets like a stored key (encrypted in memory too when a password is given) but is never written to the directory or a backup and is gone at quit; the header tags it with an orange "Session only" lozenge. "Remember key…" (both menus, above Forget, shown only while the selected account is session-only: `canRememberSelectedKey`) opens `RememberKeySheet` and `rememberSelectedWallet(storePassphrase:)` moves the key into the directory as it is held, or encrypts a clear one with the password offered there (on by default on mainnet); the session entry is pinned first, removed only if unchanged after the encryption wait, and put back if the store refuses it. `SignetApp.init` sets `RLIMIT_CORE` to 0 so no core dump can carry it. Every entry has an identity and a generation that each change bumps, `add` never replaces a taken alias or address, and Forget pins a `RemovalSnapshot` before the password check and removes only that exact entry afterwards (`remove(matching:)`, S07); `importAccount` rechecks alias and address after its encryption await.
- **Export (0.6).** "Export secret key…" (both menus, after Rename; enabled for clear and
  encrypted keys only) opens `ExportKeySheet`: a warning, the password for encrypted keys (the
  bridge's `decryptSecretKey` opens them; the clear key is shown and the encrypted form can be
  copied too), then the key masked with a reveal toggle and a Copy button. `WalletViewModel.
  exportSecretKey(passphrase:)` returns `ExportedKey(clear:encrypted:)`; nothing is written anywhere.
- **Forget (0.6).** "Forget account…" (both menus, under Add address) opens `ForgetAccountSheet`:
  one warning for everything, a second one when Signet holds the secret key (clear or encrypted;
  Ledger and watch-only entries get only the first), the password for encrypted keys (checked by
  decrypting), and a note that earlier backups under the backup folder still hold the key.
  `WalletViewModel.forgetSelectedWallet(passphrase:)` captures the store, directory revision and
  `WalletStore.removalSnapshot(for:)` before checking the snapshot's encrypted key. It aborts
  with `WalletError.directoryChanged` after any directory switch, including switching back.
  `WalletStore.remove(_:matching:)` checks the directory identity and a fingerprint of every
  matching account entry under the deletion lock, refusing changed keys or metadata. It drops
  the alias from all three octez files like `octez-client forget address --force`, then the model
  selects the next account and takes a backup of the pruned files.
- **Ledger (0.4).** USB HID is native: `LedgerHID` (IOKit, vendor 0x2c97, usage page 0xFFA0,
  64-byte reports framed by `LedgerFraming`: channel 0x0101, tag 0x05, sequence, length) runs on
  its own run-loop thread, one exchange per device at a time, and answers on the bridge queue.
  The bridge's `NativeLedgerTransport` (`src/ledger.js`) subclasses `@ledgerhq/hw-transport` over
  `__signet.ledgerExchange` / `__signet.ledgerDevices`, and Taquito's `@taquito/ledger-signer`
  does the APDUs (get public key with or without prompt, sign). The Tezos Wallet app on the device
  shows each operation for approval, so the sheets show "Confirm on your Ledger…" while a
  `.ledger` key signs (`LedgerPromptLabel`); exchanges wait up to five minutes. `LedgerKey` is
  octez-client's `ledger://<root id>/<curve>/<path>` (curves ed25519, secp256k1, P-256, bip25519;
  path relative to `44'/1729'`, `h` or `'` for hardened); existing octez ledger aliases load with
  `Wallet.ledgerKey` and just work. "Connect Ledger…" (burger menu, welcome screen, Cmd-Shift-L)
  opens `ConnectLedgerSheet`: polls `LedgerService.devices()` (the real one is
  `BridgeLedgerService`, `MockLedgerService` for tests/previews), checks the app with
  `ledgerAppVersion` (CLA 0x80 INS 0x00; the Baking app is refused), previews the address for
  the chosen curve and account index without a prompt, and on Add derives it again with a prompt
  so the user approves the address on the device before `connectLedger` writes the alias (root id =
  the ed25519 address at `44'/1729'`, as octez names devices, so octez-client can use the entry).
  Before signing, `ledgerSignerFor` checks the connected device derives the wallet's address and
  fails with "does not hold this key" otherwise. Trezor is not supported: Taquito has no Trezor
  signer and Trezor's SDK needs its Bridge daemon and a browser popup.
- **Staking and baking (0.3).** `StakingOperation` (delegate/remove, registerAsBaker, stake,
  unstake, finalizeUnstake, updateConsensusKey, updateCompanionKey) is estimated with a read-only
  signer and sent via the bridge's `estimateStakingOperation` / `sendStakingOperation` (Taquito
  `contract.setDelegate/registerDelegate/stake/unstake/finalizeUnstake/updateConsensusKey/
  updateCompanionKey`). `getDelegateInfo` reads the delegate and, for bakers, the delegate record
  (consensus/companion keys, grace period) plus whether the delegate accepts stakers. tz4 keys need a
  BLS proof of possession (`provePossession` via `InMemorySigner.provePossession`) to become
  consensus or companion keys, so only our own tz4 wallets can be chosen for that. UI:
  `DelegateRowView` under the balances, `StakingSheet` behind the Stake tile, `BakingSheet` from the
  burger menu; `TzKTService.bakers` feeds the baker picker. Staking parameters (`StakingParameters`:
  limit of staking over baking in millionths, edge of baking over staking in billionths) are read
  from `active_staking_parameters`/`pending_staking_parameters` and set with a transaction to self
  on the `set_delegate_parameters` entrypoint. Keys Taquito cannot encode (tz6 `xmpk`) go through
  the bridge's raw path (`prepareRaw`/`sendRawOperation`/`waitForRawOperation`): the node simulates
  and preapplies, but the bytes are forged locally by `src/rawforge.js` (reveal,
  update_consensus_key and update_companion_key only, from octez's `operation_repr.ml`; public
  key tags 0 to 5 for edpk/sppk/p2pk/BLpk/mdpk/xmpk) and the node's forging must match them byte
  for byte or nothing is signed (`verifyRawForging`), so a lying node cannot swap in a transfer.
  `RawForgingTests` checks the encoder against Taquito's `LocalForger` for every key kind it
  knows, and an xmpk against the Quantumnet node's forge helper (network test).
  `TaquitoChainService.rawContents` picks that path. Quantumnet hides the companion-key section (none there; consensus keys may be tz6).
  Baking and Staking sheets are read-only for wallets Signet cannot sign for (watch-only, remote)
  and the wording says so; Ledger wallets operate normally with approval on the device.
- **Buy (0.5, proof of concept).** The on-ramp is a "Provider" dropdown at the top of the Buy
  sheet (`BuyProvider`, remembered in UserDefaults `buyProvider`; Settings has nothing about it):
  Mt Pelerin (default, a widget), Coinbase, Kraken or Transak (0.9.4, no widget: `usesWidget`
  false, `browserPage` the exchange's tez page or Transak's consumer page `transak.com/buy/xtz`).
  Changing the provider resets the sheet to its first step. For a hand-off the sheet shows the
  account address with a copy button and a QR code, the three steps (buy, then
  `deliveryStep`: Withdraw/Send with the address pasted on the Tezos network for an exchange,
  the address given during the purchase for Transak, then wait a block) and an "Open …" button;
  nothing is embedded and no partner agreement or key is needed, which is why they are the US
  options. Every
  widget on-ramp (Transak, Mercuryo, Wert, Meld) needs a partner account under a legal entity
  with the credential on a server, which Signet has neither of; the Transak *widget* (global.
  transak.com with an `apiKey`) sits on the `transak` branch for the day one exists and would
  replace the hand-off case. `BuySheet` shows a widget provider's hosted page inside the app in a
  `WKWebView` (`BuyWebView`: grants camera/microphone to mtpelerin.com only for its identity
  checks, opens `window.open` targets and foreign hosts in the browser; Info.plist carries the
  camera/microphone usage strings), with an "Open in browser" fallback (`MtPelerin.buyURL`:
  `widget.mtpelerin.com`, `type=webview` or `direct-link`, `bdc=XTZ`, `dnet`/`net`
  `tezos_mainnet`, fiat `bsc` from the locale, `addr` pre-filled). When we can sign for the account
  the address is pre-validated: a 4-digit `code`, the Micheline-packed string
  `Tezos Signed Message: MtPelerin-<code>` (`MtPelerin.packedMessage`, 0x05 0x01 length bytes) signed
  with no watermark through the bridge's `signPayload`, and the six-line armored block
  (`MtPelerin.armoredBlock`) passed as `hash`, exactly as Temple does. No activation key is sent
  (`_ctkn`); add `MtPelerin.activationKey` if Mt Pelerin issues one. MoonPay was rejected: Tezos is
  suspended there and address pre-fill needs server-side URL signing. Mt Pelerin does not serve US
  persons; Transak is the fallback if that matters.
- **Governance.** `GovernanceSheet` (burger and Operations menus, "Governance…", shown only when
  `WalletViewModel.canGovern`: the selected account is a baker and we hold a signing key). The
  bridge's `getGovernanceInfo` reads `/votes/{current_period,proposals,current_proposal,listings,
  ballots,ballot_list,total_voting_power,current_quorum,proposal_count/<pkh>}` into
  `GovernanceInfo` (period kind/index/remaining, proposals with voting power, our voting power from
  the listings, tallies, our ballot, upvotes used of 20). In a proposal period the sheet lists
  proposals to tick and upvote and takes a new `P…` hash (`GovernanceOperation.isProposalHash`);
  in exploration/promotion it offers Yay / Nay / Pass; cooldown/adoption, no listing, or an
  already-cast ballot just say so. `sendGovernanceOperation` uses Taquito `contract.proposals` /
  `contract.ballot`; voting operations carry no fee, so there is no estimate step.
- **dApps (Octez Connect / TZIP-10).** The Beacon-fork wallet SDK runs inside the bridge
  (`TaquitoBridge/src/octezconnect.js`) with a `NativeStorage` backed by `OctezConnectStorage`
  (`<wallet dir>/octez-connect.json`) and events pushed to Swift via `__signet.octezConnectEvent`.
  Pairing is Umami-style: the user pastes the dApp's "pair wallet on another device" code
  (`ConnectDAppSheet`, "dApps…" in the burger and Operations menus, Cmd-Shift-D), or a `signet://?type=tzip10&data=<code>` link
  opens the app (the `signet` URL scheme is registered in Info.plist; `DAppPairingLink.code(from:)`
  parses it, `WalletViewModel.handleIncomingURL` stores it in `pendingPairingCode` and the sheet
  pairs with it and dismisses itself when the dApp's first request arrives, since only one sheet
  can be presented at a time; the app is a single `Window` scene and sets `LSMultipleInstancesProhibited`, so a
  link reuses the running app and window instead of opening another). That link shape is exactly what Beacon's / Octez Connect's wallet list opens for
  desktop wallets (`deepLink + "?type=tzip10&data=" + payload`); Signet appears in dApps' lists
  only once a `signet_desktop` entry with `deepLink: "signet://"` is merged upstream. `DAppConnectionManager` parses requests
  (`DAppRequest`), queues them, and `DAppRequestSheet` approves/rejects: permission (pick a wallet),
  operation, sign_payload (`signer.sign`). An operation request is prepared before it can be
  approved (S03): `DAppConnectionManager.prepare` calls the bridge's `octezConnectPrepare`, which
  simulates the batch with a read-only signer (`tk.estimate.batch`) and returns
  `DAppPreparedBatch`: per operation the exact fee and storage burn, the decoded effects for
  standard token calls (`contractEffects`: FA2/FA1.2 `transfer`, `update_operators`, `approve`),
  an `opaque` flag for contract calls it cannot read, the raw parameters, and totals (amount,
  fee, burn, debit) plus a reveal line for unrevealed accounts, and `preparedJSON`, the exact
  operation contents, including the actual reveal, branch, counters and fee/gas/storage limits. The dApp's own `fee`/`gas_limit`/
  `storage_limit` are never used (a higher requested fee is shown as ignored). The sheet shows
  all of it, keeps Approve disabled until preparation succeeds, and `approveOperation(_:prepared:
  passphrase:)` executes `preparedJSON` through `octezConnectExecute`, which refuses any batch
  whose operations lack fee, gas and storage. Execution locally forges those frozen contents,
  verifies the source and reveal key, signs and preapplies them, then injects without rebuilding
  or re-estimating (password for encrypted keys, Ledger approval on the device). `ShadownetDAppPrepareTests` is the live prepare-then-execute round trip.
  A sign_payload is only accepted
  when its type is `micheline` and the hex is `05` followed by exactly one well-formed Micheline
  expression (`MichelineBinary`, a strict reader of the binary encoding; the bridge's
  `micheline.js` is its twin): the signature is over the raw bytes, so `03…` would be an
  operation signature the dApp could inject. `DAppSignPayload.refusal` rejects anything else
  before it is queued (the dApp gets `SIGNATURE_TYPE_NOT_SUPPORTED`) and the bridge's
  `octezConnectSign` applies the same rule.
  Wrong password or a Ledger that is not ready leaves the request up for a retry. dApp network types map to ours via `DAppRequest.network`.
  **Identity and grants (S04, S08).** The bridge forwards nothing the SDK hands it as is:
  `sanitizeIncomingRequest` (pure, tested offline by `test/dapp-identity.cjs`) rebuilds every
  request from authenticated state only: the peer whose session key decrypted the message
  (`context.id`), the sender id derived from that peer's public key, the app metadata the SDK
  stored for that sender at permission time and the wallet's current permissions. A message
  whose own `senderId` or `appMetadata.senderId` claims another sender is refused outright (the
  SDK records grants under the id the message claims, so correcting it would be unsafe);
  branding comes from the pairing record or the stored grant, never from the request; only
  allow-listed fields survive. Operation and sign requests need a stored grant for that exact
  sender, account and scope (and, for operations, the same network type and custom endpoint),
  else `NOT_GRANTED_ERROR`. Swift takes the sender id from the message's own field (the one
  the bridge set), never from `appMetadata`, and `DAppConnectionManager.grant(for:)` checks the
  grant again, freshly read, right before signing. Revoking a grant (`disconnect`) refuses the
  queued requests it covered; a wallet directory change stops the old client (aborting its
  queue) and builds a new manager on the new directory's storage (`dappStorageFactory`), so
  sessions never cross directories. **Budgets (S19):** `REQUEST_LIMITS` in the bridge (message
  256 KB, 64 operations, id/text/URL lengths, 64 KB sign payload, 4 pending requests per peer)
  are enforced before anything is queued; Swift keeps at most 16 pending requests;
  the SDK serializer checks serialized size/depth before parsing, and native HTTP replies have
  byte/string/depth/node budgets before SDK parsing/decryption. Foreground bridge calls are
  serialized and bounded; read/preparation timeout or cancellation tears down the context and
  its HTTP/timers, while signing/injection and Ledger sessions retain their outcome boundary.
  Stale callbacks cannot enter a new context. Replies are capped at 32 MB (`maxResponseBytes`). **Replies (S17):** a
  completed request whose reply the relay did not take is kept in `undelivered` with its
  response; the sheet offers "Send reply again" or Dismiss and never signs or injects a second
  time (`redeliver`). **Startup (S18):** the bridge publishes the client only after `connect()`
  succeeds and shares one in-flight start (`starting`); starts await full stop/disconnection.
  Swift shares start/stop tasks, and each directory manager owns a separate bridge/client/storage;
  invalidation is synchronous at directory replacement and failed grant lookups deny signing;
  pairing returns at once and reports `paired` / `error` events (`DAppConnectionManager.pairing`).
  **Endpoints (S12):** a dApp's custom RPC must be public HTTPS without credentials
  (`EndpointPolicy`), or exactly one of our networks' default endpoints (scheme, host, port and
  path and query; `DAppRequest.sameEndpoint`); the sheet shows the endpoint for custom networks.
- **Multisig (0.8).** Octez-client's generic multisig, driven through Taquito. Menu section
  (burger and Operations, after dApps): Create multisig, Add multisig, Sign multisig
  transaction, Submit multisig transaction. Contract aliases are octez-client's `contracts` file in
  the wallet directory (`TezosClientStore.loadContracts`/`addContract`), so `octez-client` can use
  the same names, and `load()` joins them into the wallet list as watch-only KT1 entries: a
  created or added multisig appears in the account dropdown under "Contracts" (tagged
  "Contract") and is selected, with its balance (the bridge reads a KT1's `balance`, since the
  node refuses `full_balance` for contracts) and its delegate row. `WalletViewModel.
  multisigContracts` is derived from `wallets`. Aliases are unique across `contracts` and the
  three key files; rename and Forget work on contract aliases too. A KT1 given to Add address
  also goes to `contracts`: octez-client refuses to read a `public_key_hashs` holding one. The
  faucet button and prompt are off for contracts (faucets fund implicit accounts only).
  Proposals awaiting signatures are `multisig-proposals.json` beside it
  (`FileMultisigProposalStore`); both are backed up. The bridge (`src/multisig.js`) embeds the
  script from octez's `client_proto_multisig.ml` as JSON (`src/multisig-script.json`, made with
  `octez-client convert script … from michelson to json`); its `Script_expr_hash`
  `exprub9UzpxmhedNQnsv1J1DazWGJnj1dLhtG1fxkUoWSdFLBGLqJ4` is what octez-client recognises, and
  `multisigInfo` computes the hash of any contract's code to decide whether it is a multisig
  (legacy multisig scripts are refused). A proposal carries a `MultisigAction`: a transfer, or
  `setDelegate` (a baker, or `nil` to withdraw). A transfer is a lambda built exactly as octez's
  `managed_contract.ml` writes it (bytes literals, `ASSERT_SOME` expanded); a delegate change is
  `client_proto_multisig.ml`'s `Change_delegate` lambda (`DROP; NIL operation; PUSH key_hash
  <bytes>; SOME; SET_DELEGATE; CONS`, or `NONE key_hash` to withdraw). `MultisigScriptTests`
  checks all three against bytes `octez-client prepare multisig transaction … --bytes-only`
  printed. Every signer signs
  `pack (Pair (Pair chain_id contract) (Pair counter (Left lambda)))` with no watermark, so
  signatures from Signet and `octez-client sign multisig transaction` combine; `multisigSubmit`
  places each signature in its key's slot by verification (any order), calls `main` with
  `(Pair (Pair counter (Left lambda)) sigs)` and refuses when the counter moved. `MultisigService`
  (`BridgeMultisigService`, `MockMultisigService`); `WalletViewModel` has `createMultisig` (an optional initial balance, `amount`, is moved in by the origination itself: the bridge passes it as `balance` with `mutez: true`, so the estimate's limits cover it; the sheet's "Initial balance" field defaults to 0),
  `multisigSignerKey(from:)` (a signer given as a public key, one of our accounts, an address-book
  entry or a pasted tz address; addresses resolve to the key they revealed on chain via
  `multisigRevealedKey`, else `MultisigError.notRevealed`; the node is not trusted to say whose
  key it is: the bridge and the model both derive the key's address locally and refuse one that
  does not hash to the address asked for, S29, `MultisigError.keyAddressMismatch`),
  `addMultisig` (must be generic and one of our keys among its signers), `proposeMultisig(_:from:)`
  (`proposeMultisigTransfer` is the transfer shorthand; `signMultisigProposal` treats the
  proposal file as untrusted, S27: it re-prepares the action against the chain and requires the
  same chain id, counter, keys, threshold and bytes, then signs through the bridge's
  `multisigSign`, which builds the packed payload itself from chain/contract/counter/action and
  never accepts bytes, and the bytes it returns must equal the stored ones; the directory
  revision is rechecked after the password wait; the Sign sheet has an action picker,
  Transfer / Set delegate / Remove delegate, and opens on `signMultisigPreset` when the delegate
  row of a selected contract is clicked),
  `signMultisigProposal`, `addMultisigSignature`, `submitMultisig`. `ShadownetMultisigTests` is the
  live 2-of-3 round trip (a transfer, then a delegate change) and checks local packing against
  the node's `pack_data`.
- **Appearance.** `Appearance` (OS / Light / Dark) lives in UserDefaults and is applied app-wide via
  `NSApp.appearance` by the `appliesStoredAppearance()` modifier on the root views.
- **Menus.** The burger menu (`AppMenuButton`) and the menu-bar "Operations" menu in `SignetApp`
  share one item list, `OperationsMenuItems` in `WalletHeaderView.swift` (Create account, Import account, Connect Ledger, Rename account, Export secret key | Add address, Remember key when session-only, Forget account |
  dApps | Create multisig, Add multisig, Sign multisig transaction, Submit multisig
  transaction | Baking, Governance when applicable | Networks, Shielded settings, Settings, Refresh); only the Settings shortcut differs, since the app menu already
  has Cmd-comma. File has Create Backup (`backUp(force: true)`).
- **Disclaimer.** `showsLaunchDisclaimer()` (`DisclaimerAlert.swift`) puts up the "very new
  software" alert (OK / Exit) when the main window appears; the `showsDisclaimer` UserDefault,
  toggled in Settings under Appearance, turns it off. Suppressed under the test host.
- **Node status.** `NodeMonitor` polls `/chains/main/blocks/head/header` every 30 s and
  classifies the reply (green fresh head, yellow stale/slow/HTTP error/odd payload, red no
  connection); `NodeStatusBar` pins it to the bottom of the window (light and host only while healthy; the
  level, head age and latency are in the tooltip, and problems are written out); while the network has Layer 2 on a
  second line beneath it shows the Layer 2 Michelson node (`WalletViewModel.l2Monitor`, a
  `NodeMonitor` with `layer: .two`, idle and grey when there is no Layer 2 node), and a header
  naming another chain than the pinned one is red. `evaluate` is pure for tests.
  **Chain identity (S12).** Long-lived networks pin `Network.expectedChainID` (mainnet
  `NetXdQprcVkpaWU`, Shadownet `NetXsqzbfFenSTS`, Bakingnet `NetXvNVUNbWHxGt`, Ushuaianet
  `NetXpX8WSZkAZZA`; Weeklynet, Quantumnet and Custom pin nothing); before any estimate or signing
  `TaquitoChainService.verifyChain` and the dApp prepare/execute calls ask the node for
  `/chains/main/chain_id` through the bridge's `assertChain` and refuse a node serving another
  chain. The Networks sheet asks a newly typed node (layer 1 or Layer 2) the same question
  before Apply adopts it (`WalletViewModel.checkNode` → `NodeMonitor.identity`, a `NodeIdentity`:
  `unpinned`, `matches`, `mismatch`, `unchecked`): a node on another chain, or one that cannot be
  asked, is warned about in orange under the field with a Use Anyway button instead of being
  applied; unpinned networks are not asked. The Networks node field (`Network.nodeURL(from:)`) takes `https` anywhere, plain `http`
  only for this machine or the local network, and refuses credentials and other schemes
  (`nodeURLProblem` words the refusal). `EndpointPolicy` (`Signet/Services`) is the one place
  that decides what counts as local or private (loopback, link-local, RFC 1918, CGNAT, ULA,
  `.local`, bare names) and can resolve a host to check it.
- **Balances.** The node's `balance` is only the spendable part. `TezBalance` carries spendable,
  staked, unstaked-frozen and unstaked-finalizable tez; the tez row shows the total (the node's
  `full_balance`) and expands into those lines. Fetched via Taquito's RPC client for tz1 to tz4
  and by direct RPC for tz5/tz6. The node refuses `full_balance` with a 500 "missing_key" storage
  error for an account it has never seen; both paths map that to `ChainError.accountNotOnChain`,
  which the dashboard shows as "Key not found on chain" in place of the balance rows, with a
  "Get test tez" button on testnets and a Receive/buy prompt on mainnet. `FaucetService` speaks the
  teztnets faucet API directly (`/info`, `/challenge`, SHA-256 proof-of-work, `/verify`, as the
  `get-tez` CLI does, no captcha, with strict challenge validation, a bounded, cancellable
  solver and capped rounds, S21); `WalletViewModel.requestTestTez` drives it and polls until the
  account appears. Faucet URLs are `Network.faucetURL` from teztnets.json. `refresh()` fans out all loads concurrently.
  **Native HTTP (S19).** Every `URLSession` read outside the bridge (node RPC in
  `TaquitoChainService`, TzKT, the node monitor's probe, the faucet, Tezos Domains) goes through
  `BoundedHTTP.data(for:session:limit:json:)` (`Signet/Services/BoundedHTTP.swift`): the body is
  collected by a task-local delegate that rejects oversized headers/chunks and explicitly
  cancels the underlying request on rejection or caller cancellation. A
  JSON body must also fit `JSONBudget` depth/node/string limits (`.small`, `.record`, `.page`)
  before it is parsed; page readers also cut rows to the requested limit. Caps are per purpose
  (16 KB for a balance or chain id, 256 KB for an account record, 4 MB for a page).
- **Views** map one-to-one onto the sketch: `WalletHomeView` composes `WalletHeaderView`
  (the alias is a dropdown that switches wallets; shortened address with copy button; Tezos
  Domains name stacked beneath the address, a round `AccountAvatarView` on the left fed by TzKT's
  avatar service `services.tzkt.io/v1/avatars/<address>` (TzProfiles or known-account logo, else
  an identicon; WebP, decoded by ImageIO) via `Profiles.avatarURL(for:)`; avatars and TzProfiles names always come from mainnet
  services whatever network is selected, because a TzProfile is a mainnet identity), fetched live from the Tezos Domains GraphQL API by
  `TezosDomainsService` and omitted when the address has no reverse record; a hamburger menu
  reserved for other actions, not wallet switching),
  `ActionButtonsView` (Send, Receive, Buy/Get, Stake; Receive opens `ReceiveSheet` with a Core Image QR
  code of the address, and with Layer 2 on the logo at its top left is a menu that switches to
  the account's address on Etherlink's EVM side, `EtherlinkAlias.address(for:)`: the first 20
  bytes of Keccak-256 over the base58 address string, as the EVM node's
  `tez_getTezosEthereumAddress` answers, computed by `Keccak.swift` since CryptoKit has none; on testnets Buy becomes Get and opens `FaucetSheet`, which drives
  `WalletViewModel.requestTestTez(amount:)`; on Mainnet Buy opens `BuySheet`. Sell was dropped for good: it would mean handling bank accounts), `AssetListView` (tez, then Etherlink, then
  other tokens) and `ActivityTabsView`, a segmented bottom section: `TransactionListView` (last 25
  operations from TzKT `/v1/accounts/{address}/operations`, parsed by `TzKTService.parseOperations`
  into `TezosTransaction`; an internal operation a contract made because we called it, such as a multisig payout (sender the contract, `initiator` us), is outgoing with `via` the contract, not money coming in from it; rows show the counterparty's avatar and name, our alias with a green seal
  when it is one of ours, else TzKT's alias, via `WalletViewModel.displayName`), `TokenListView`
  (the Assets tab: fungible/DeFi tokens from the same TzKT `/v1/tokens/balances` call via
  `TzKTService.fungibleTokens`: anything with decimal places or FA1.2, amount divided by the
  decimals, logo from thumbnailUri/icon, kept in `WalletViewModel.tokens`, not in the top balance
  list) and `NFTGridView` (a scrolling grid fed by `TzKTService`: tokens with zero
  decimals and an image, `ipfs://` expanded to one URL per gateway by `IPFS.candidateURLs` and loaded by `ImageLoader`, which tries them in order and downsamples (ipfs.io rate-limits, Filebase is fast), displayUri preferred
  over thumbnailUri because marketplaces often use a generic thumbnail). `CreateWalletSheet` (key type is a dropdown of the supported
  schemes, tz1 first and recommended; tz6 is not offered) is reached from the hamburger menu, the
  Operations menu or Cmd-N; with no wallets `NoWalletsView` replaces the dashboard. `AddAddressSheet`
  (hamburger menu, Cmd-Shift-N) adds an address-book entry: an octez watch-only alias written to
  `public_key_hashs` only, validated by `Address.isValidAccount` (base58 checksum, so tz5/tz6 and
  KT1 pass without Taquito). Adding an address offers its TzProfiles name as the alias, and Rename has
  "Sync with TzProfile" (both via `WalletViewModel.profileName(for:)`). The wallet dropdown shows
  these under "Address book" and the header tags them "Watch only".
- The project builds with Swift 6 language mode and complete strict concurrency; keep new types
  `Sendable` and UI work on the main actor.

## Requirements and open decisions

- Address schemes tz1 through tz5 are supported. tz5 (ML-DSA-44, public keys `mdpk`, secret
  `mdsk` = 2560-byte secret key ‖ 1312-byte public key, signatures `mdsig`) came with Taquito
  25.1.0-beta0 (October 2026): keys are generated in the bridge with `@noble/post-quantum`
  (CryptoKit has no ML-DSA-44) and signed by Taquito's `MLDSAKey` as pure ML-DSA over the Blake2b
  digest, like Octez. tz5 is live on testnets but feature-flagged on mainnet; the create sheet
  says so. tz6 (XMSS, public keys `xmpk`, stateful; octez keeps `xmss_slots`) is shown with a
  balance when present but cannot be created or signed with; Taquito rejects tz6 addresses, so
  `TaquitoChainService` fetches its balance by direct RPC.
- Quantumnet (Nomadic Labs' post-quantum testnet, tz5 enabled, 6 s blocks) is not on teztnets.com:
  RPC `quantumnet.pqpark.dal.nomadic-labs.com/rpc`, its own TzKT and explorer, and a PQPark faucet
  (`Network.FaucetKind.pqpark`: `GET /info`, `POST /send {to, amount}`, no proof of work) which
  `FaucetService` speaks alongside the teztnets protocol. `Network.explorerURL(operation:)` links
  operations per network (tzkt.io on mainnet, the self-hosted TzKT on Quantumnet). The Networks sheet
  has a network dropdown that picks whose node is being edited (not the network in use) and a
  Custom network defaulting to `http://localhost:8732`; nodes are shown as full URLs.
- The spec asks for Taquito "where possible". Taquito is TypeScript, so chain access goes
  through a JavaScript bundle run inside JavaScriptCore (see `TaquitoBridge/`). Key generation for
  tz1/tz3 is in Swift; secrets enter the bridge only for the one operation they sign (Taquito's
  `InMemorySigner`), and Ledger keys never leave the device. Use the bridge for RPC, forging,
  encoding, metadata and the Ledger APDU protocol.
- **Etherlink (0.9).** The layer 2 rollup is reached through its Tezos-style ("michelson")
  RPC, where tz1, tz2 and tz3 keys are used directly (tz4 and tz5 are not accepted by the
  rollup yet). `Network.l2DefaultRPCURL` ships the endpoint for Mainnet
  (`michelson.etherlink.mainnet.octez.io`, chain `NetXohUVN5QWR4f`) and Shadownet
  (`michelson.etherlink.shadownet.octez.io`, chain `NetXtLrzvQDobza`); `l2Enabled` is off by
  default everywhere (the user turns it on per network), and `l2RPCURL` is the node in use. The Networks sheet has "Enable Layer 2"
  and a "Layer 2 Michelson node" field per network (same URL policy as the layer 1 node; the
  word Etherlink is kept for the dashboard row only),
  saved in `AppState.l2Enabled` / `l2NodeURLs` only where they differ from the defaults.
  `TaquitoChainService.etherlinkBalance` checks the pinned Etherlink chain id, then reads
  `…/contracts/<pkh>/balance` from the Etherlink node (an unseen account is 0; reveal state is
  not shown). `WalletViewModel.etherlinkRow` adds the Etherlink row (logo `EtherlinkLogo`,
  symbol tz, no breakdown) under the tez row only when `network.hasL2` and the key is usable
  there and the account is on layer 1 (the "Key not found on chain" state shows no rows); an
  unreachable Etherlink node blanks that row alone (`AssetBalance.unavailable`). **Bridge (0.9.1).** "Bridge…" (burger and Operations
  menus, shown when `WalletViewModel.canBridge`: `Network.canDepositToL2`, a tz1 to tz3 account
  we can sign for) opens `BridgeSheet`: Tezos left, Etherlink right, the arrow between them the
  direction, an amount, and Fast / Slow for Etherlink → Tezos. A deposit is a layer 1 transfer
  to Etherlink's bridge helper (`Network.l2BridgeHelper`, `deposit %evm_address %l2_address`,
  mainnet `KT1Wj8SUGmnEPFqyahHAcjcNQwe6YGhEXJb5`, Shadownet `KT19aBsSWvWtvEkbiqReJnD8UzQMWcD8SHUD`)
  naming the Smart Rollup (`l2Rollup`) and routing data for the same tz address on the
  Michelson interface, `0x01 ++ rlp([[0x01, forged address], []])` as baking-bad's
  `xtz_deposit_michelson.py` builds it (`src/bridge.js`, `michelsonRoutingData`; vectors in
  `test/bridge.cjs`); `estimateEtherlinkDeposit` / `sendEtherlinkDeposit` go through the
  approved-limits path and `WalletViewModel.bridgeToEtherlink` waits for the layer 1 block (the
  rollup credits the account within about a minute). Etherlink → Tezos is shown but disabled:
  Etherlink does not yet offer withdrawals from Michelson-interface accounts (October 2026);
  wire it up when it does (standard withdrawals take 15 days, fast ones about a minute for a
  fee). `ShadownetBridgeTests` is the live deposit round trip. **Send on Etherlink.** `Network.layer2`
  is the Michelson interface as a network of its own (the Layer 2 node, its pinned chain id,
  Etherlink's TzKT `api.etherlink.tzkt.io` / `api.shadownet.etherlink.tzkt.io` and explorer,
  `layerNumber` 2) and `WalletViewModel.layer2Chain` a chain service for it; the Send sheet's
  `ChainSidePicker` (the same logo-and-pop-up as Receive, `Signet/Views/ChainSidePicker.swift`)
  rebuilds its `SendViewModel` on that service with `implicitAccountsOnly`, so on Etherlink the
  recipient must be a tz1, tz2 or tz3 account (contracts and tz4 are refused and never
  suggested), the spendable figure is the Etherlink balance, and estimate, send, confirmation
  wait, journal and explorer links all go through the Layer 2 node unchanged. Each side is one
  immutable `SendSheet.SideContext` (network, chain service, spendable, recipient rule) captured
  by `SendSheet.capture(model)` when the sheet opens (S31): the network shown and linked to is
  always the one the service talks to, Settings changes after opening change nothing in the
  sheet, and there is no Etherlink side at all (no fallback to layer 1) unless both its network
  and service existed then. Deposits are bound the same way: `estimateBridgeDeposit` returns a
  `BridgeEstimate` carrying the `BridgeContext` (account, whole network with node and Layer 2
  settings, directory revision and context generation) it was made in, plus its approved amount.
  Switching away and back invalidates the estimate too; it is refused if the context moved during
  the estimate, and
  `bridgeToEtherlink(amount:approved:passphrase:)` throws `WalletError.contextChanged` unless the
  context and amount are still the same; `BridgeSheet` re-estimates whenever they change and
  retains the submitted account/network/amount for the result and explorer link.
  `EtherlinkLiveTests.sendsTezBetweenAccountsOnEtherlink` is the live round trip.
  **EVM alias (0.9.3).** The account's EVM-side address is a pure function of the tz address, but
  the rollup only creates the account behind it (EIP-7702 delegation to the shared
  AliasForwarder, which passes tez on to the tz account) when the account makes its first
  cross-interface call; before that, tez sent to the alias sit at an address nobody controls,
  a later link does not sweep them, and a layer 1 deposit into a linked alias fails OutOfGas
  on the current kernel (only an EVM-side transfer with enough gas forwards). So Receive shows
  the 0x address only when the gateway's `resolveAddress` view (Tezos runtime 0 → Ethereum 1)
  on the Layer 2 node says it is recorded (`EtherlinkAliasStatus.linked`; derived is
  `.unlinked`), and otherwise offers "Link to Etherlink": a zero-tez `%call_evm` no-op from the
  account to the Michelson gateway `Network.etherlinkGateway`
  (`KT18oDJJKXMKhfE1bSuAPGp92pYcwVDiqsPw`, the same on every Etherlink network), paid on
  Etherlink, through the approved-limits path (`src/bridge.js` `linkParams` /
  `estimateEtherlinkLink` / `sendEtherlinkLink`; `sendEtherlinkLink` is a signing call).
  `ChainService.etherlinkAliasStatus` / `estimateEtherlinkLink` / `sendEtherlinkLink` exist on
  a Layer 2 service only (`ChainError.notALayer2Service` otherwise) and
  `WalletViewModel.etherlinkAliasStatus` / `estimateEtherlinkLink` / `linkToEtherlink` use
  `layer2Chain`. `EtherlinkLiveTests.linksAFreshAccountToItsEtherlinkAlias` is the live check.
- **Shielded transactions (TzEL).** "Shielded settings…" (both menus, under Networks;
  `ShieldSettingsSheet`, `isPresentingShieldSettings`) has a layer 1 network dropdown, then
  for that network the switch (`Network.shieldedEnabled`, off by default, saved in
  `AppState.shieldedEnabled` only where on; `WalletViewModel.isShieldedEnabled(for:)` /
  `setShieldedEnabled(_:for:)`, `Network.usingShielded(enabled:)`), a field per item of the
  deployment (`ShieldedConfig.Setting`: rollup node, rollup, bridge ticketer, operator,
  proving service, producer fee, producer address as the producer's payment-address JSON;
  each validated by `Setting.normalised`, applied through `setShieldedSetting` /
  `useDefaultShieldedSetting`, kept in `AppState.shieldedSettings` only where it differs from
  what Signet ships, blank where it ships nothing) and the operator token.
  `Network.shieldedDefault` is the shipped deployment (`ShieldedConfig`, Shadownet only, its
  producer address the bundled `tzel-shadownet-producer.json`) and `shielded` the one in use:
  `AppState.resolved` overlays the saved items on the shipped ones (`shieldedFields`) and
  builds `ShieldedConfig(fields:)`, `nil` until every item is there, so any network can be
  filled in by hand and shields once complete (`shieldedAvailable` only says a network is
  known to have shielded transactions). The Networks and Shielded settings sheets explain their sections
  through an ⓘ beside each title (`SectionHeader` in `NetworkSettingsControls.swift`, a
  popover on hover) rather than footer paragraphs; `SettingField` is the shared text setting. With the switch on and a config, the
  dashboard's **Shielded** row (`AssetBalance.Kind.shielded`, logo `ShieldLogo`, under
  Etherlink or tez, hidden when the account is not on chain) is the wallet's unspent notes,
  found by scanning the rollup (`WalletViewModel.scanShielded`: new tree positions since the
  saved cursor decrypted in the bridge with the viewing keys, nullifiers that spend ours, the
  deposit pools' balances as a detail line; an unreachable rollup blanks the row); without a
  config it is the 0 placeholder. **The protocol is implemented here, not bundled** (Chris's
  decision): the primitives are in the bridge, `TaquitoBridge/src/tzel.js` (felts and tags,
  BLAKE2s-251 with the spec's personalizations, key hierarchy, ML-KEM-768 via noble, note
  AEAD, detection tags, memo hash, WOTS+ w=4 and the 65536-leaf XMSS auth tree, Merkle roots
  and paths, commitments, nullifiers, note acceptance, sighash fold, canonical wire forms,
  deposit pools, the shield sighash and witness, kernel inbox wire version 17), checked by
  `test/tzel-vectors.cjs` against the tzel repository's cross-implementation vectors read from
  a checkout (`TZEL_VECTORS` or `../tzel`; skipped without one; `TZEL_FULL=1` also builds the
  three full auth roots in JavaScript, minutes each) and by `test/tzel-shield.cjs` (the
  ticketer call, pool ids, notes, signature, witness and the wire bytes of a sample shield
  message against the reference crate's encoding). The tzel licence forbids copying its code
  or vectors into this repository. **Native hashing.** An address's auth tree is 44 million
  BLAKE2s hashes, so `Signet/Services/tzel_blake2s.c` (BLAKE2s-256, the WOTS+ leaf, the tree
  node; compiled `-O3` in every configuration via `project.yml`, reached through
  `Signet/Signet-Bridging-Header.h`) builds the leaves across every core in about 2 s
  (`XMSSAuthTree.buildLeaves`; `Blake2s` wraps the hash); `ShieldedTests` checks it against
  the RFC vector, the bridge's leaves and the vectors' roots. **Wallet state.**
  Each tz account has its own shielded wallet (`ShieldedWallet`,
  `Signet/Services/ShieldedWallet.swift`: a random master key, clear like an unencrypted tz
  key; addresses with their payment-address fields and next WOTS+ key index; deposit pools;
  notes; scan cursors), so the Shielded row is that account's. They share one file per chain
  in the wallet directory, `tzel-<chain>.json` (`ShieldedWalletFile`, version 2, a
  `PrivateFile` in the backup file list), keyed by address, which also holds the network's
  operator bearer token (entered in the Networks sheet, never in the app state or the
  repository). A version 1 file (one wallet for the whole network) is read as `legacy` and
  adopted on the next refresh by the account that funded its first deposit (TzKT's sender of
  the pool's operation), else the selected account (`adoptLegacyShieldedWallet`). The 2 MB
  leaves are `tzel-<chain>-<account>-auth<j>.bin` beside it, not backed up, rebuilt from the
  master key when missing. `FileShieldedWalletStore` / `InMemoryShieldedWalletStore` behind
  `ShieldedWalletStore`; the model takes a `shieldedStoreFactory` and a
  `shieldedRollupFactory` (`ShieldedRollup`: `RollupNodeService` over `BoundedHTTP`, or the
  tests' `MockShieldedRollup`). **Shield tez** ("Shield tez…" in both menus when
  `WalletViewModel.canShield`; `ShieldSheet`) is two steps run back to back
  (`WalletViewModel+Shielded.swift`): `prepareShield` checks the rollup node serves the
  configured rollup, has its verifier installed and names our ticketer, makes the wallet and
  its first address if needed, and reserves a deposit pool (`pubkey_hash =
  fold(0x04, auth_domain, auth_root, pub_seed, blind)`, the blind derived as the reference
  wallet does) that is on file before any tez move; `estimateShield` prices the layer 1 call
  (`estimateShieldDeposit` / `sendShieldDeposit` in `src/shield.js`: the ticketer's
  `mint (pair (bytes %receiver) (address %rollup))` with the ASCII of `deposit:<hex>`, through
  the approved-limits path, S14/S15) and reads the rollup's fee of the moment; `shieldTez` is
  refused without the operator token (so no tez are parked unshieldable), records the deposit
  hash before waiting for the block, then `shieldPool` waits for the rollup to credit the pool,
  takes the rollup fee (`RollupState.requiredTxFee`, 0.1 tez doubling per private transaction
  beyond the second in a level) and the producer fee off the balance, spends the address's next
  key index on disk *before* signing, has the bridge build the two output notes (to ourselves
  with an outgoing-recovery record, and the producer-fee note), the sighash, the WOTS+
  signature and the 171-word Cairo witness (`tzelBuildShield`, which also checks the pool id,
  signing seed and native auth path against the address), sends the witness to the proving
  service (`POST /v1/jobs`, long-polled), encodes the kernel message
  (`tzelEncodeShieldMessage`, refusing a proof whose public outputs are not the nine signed)
  and hands it to the operator with the bearer token, polling to `submitted_to_l1`. A deposit
  whose shield did not finish stays listed in the sheet ("Deposits waiting to be shielded")
  for `shieldPool` to retry; a drained pool whose note the scan has seen is retired.
  `ShadownetShieldTests` is the live round trip (with `SIGNET_TZEL_OPERATOR_TOKEN` the note is
  seen in the scan; without it the operator's refusal is the expected end and the pool stays
  funded). The rollup node and operator speak plain HTTP, exempted from App Transport
  Security for those two hosts alone in `Info.plist`. **Unshield tez** ("Unshield tez…"
  beside Shield; `UnshieldSheet`) spends one to seven of the account's notes (largest first,
  `selectNotes`) for `v_pub` tez to a tz or KT1 account on layer 1: `estimateUnshield` reads
  the rollup's fee of the moment and picks the notes; `unshieldTez` scans again (the wallet
  keeps every commitment it has read, `leafCms`, so the 48-deep Merkle paths come from the
  bridge's `merklePath` and the builder refuses a copy that does not hash to the rollup's
  `tree/root`), refuses a changed fee or a spent input, makes a fresh address for the change
  and builds its tree, spends every input's next WOTS+ key index on disk *before* signing,
  then `tzelBuildUnshield` (sighash `fold(0x02, auth_domain, root, nullifiers…, v_pub, fee,
  recipient_id, cm_change, mh_change, cm_fee, mh_fee)`, one signature per input from its own
  address, the `6 + 206n + 15`-word witness; `test/tzel-unshield.cjs` checks it and the tag 4
  wire against the reference crate's bytes), `run_unshield` at the proving service,
  `tzelEncodeUnshieldMessage` and the operator. The withdrawal (`ShieldedWithdrawal`) is on
  file as soon as the operator has it and its notes stay reserved (the row's "Leaving in an
  unshield" line; `availableNotes`) until the scan sees their nullifiers; it is then matched
  to the rollup node's pending outbox message (`/local/outbox/pending`, the ticketer's `burn`
  for the recipient as forged, `Address.forgedContract`, and the amount) and, once
  `/global/block/cemented/level` has passed its level (about 14 days), the sheet's Execute
  button runs `estimateWithdrawalExecution` / `executeWithdrawal`: the node's outbox proof
  and Taquito's `smartRollupExecuteOutboxMessage` through the approved-limits path
  (`sendOutboxExecution` is a signing call). An operator failure drops the record so the
  notes are free again; `forgetWithdrawal` does the same by hand for one never delivered.
  The layer 1 execution has not been exercised live yet. **Send shielded** ("Send
  shielded…"; `SendShieldedSheet`) is a private transfer: the same preparation as an unshield
  (`prepareSpend`, always with a change address, since the kernel takes exactly three output
  notes), then `tzelBuildTransfer` (sighash `fold(0x01, auth_domain, root, nullifiers…, fee,
  cm_1, cm_2, cm_3, mh_1, mh_2, mh_3)`, the `4 + 206n + 24`-word `run_transfer` witness, the
  recipient's note with the memo and role `transfer_recipient`, the change note, the producer
  note; `test/tzel-transfer.cjs` checks it and the tag 3 wire against the reference crate's
  bytes), `run_transfer` at the proving service, `tzelEncodeTransferMessage` and the operator;
  the transfer (`ShieldedTransfer`) is on file as soon as the operator has it and its notes
  stay reserved until the scan sees them spent. **A shielded recipient is the payment address
  itself**, the 2496-byte record (diversifier, auth root, public seed, nullifier tag, two
  ML-KEM-768 keys): the protocol has no short form, so wallets exchange the reference JSON and
  compare a fingerprint, the BLAKE2s-251 of the canonical record (`tzelPaymentAddress`,
  `WalletViewModel.shieldedRecipient(from:)`). "Shielded address…" (`ShieldedAddressSheet`)
  shows the account's newest address as that JSON with its fingerprint and a Copy button
  (`shieldedReceiveAddress`), makes a fresh one on request (`makeShieldedAddress`, so two
  payers cannot tell they paid the same wallet), and keeps the network's shielded address
  book (`ShieldedContact`, in `tzel-<chain>.json` beside the token, shared by every account;
  `addShieldedContact` / `removeShieldedContact`). A received note keeps its memo
  (`ShieldedNote.memo`). The research, verified Shadownet
  parameters and the step plan are in `docs/tzel/RESEARCH.md` (section 8); the spec note is
  `docs/spec/shield.md` and the protocol is https://github.com/trilitech/tzel/.
- Networks live in `Network.swift` (`Network.all` is what Settings offers). Ghostnet was retired in
  2026; Shadownet is the long-running public testnet and the bridge tests use it. Weeklynet
  restarts every Wednesday and its hosts carry the launch date, so `Network.weeklynet` builds the
  URL from the most recent Wednesday (UTC). The protocol-proposal testnet is listed under its own name (`Network.ushuaianet`, chain id pinned) rather than teztnets.com's "currentnet" alias, because TzKT names its instance after the protocol (api.ushuaianet.tzkt.io) and the alias has no indexer; replace the entry when the next proposal's network appears. Shadownet, Bakingnet and Ushuaianet link to their tzkt.io explorers.
  Each `Network` has a `defaultRPCURL` and the `rpcURL`
  in use: the Networks sheet (`NetworksSheet`, "Networks…" in the burger and Operations menus
  and at the foot of the network badge, `isPresentingNetworks`) shows the network as a dropdown
  with a free-text node field beneath it, plus a Links section where the TzKT API, block
  explorer and faucet of each network can be replaced or turned off (`Network.Service`,
  `tzktURL`/`explorerURL`/`faucetURL` beside their `default…` twins, saved in
  `AppState.serviceURLs` only where they differ, "" for off; mainnet never offers a faucet,
  `Network.offers(_:)`), and
  `WalletViewModel.setNode` / `useDefaultNode` replace the node for the current network only.
  Custom nodes are kept per network name in `AppState.nodeURLs`; `switchNetwork(to:)` applies
  the saved one (assigning `network` directly uses whatever node the value carries). The chosen
  network, node and selected wallet are remembered in `~/.signet/state` (`FileAppStateStore`); `WalletViewModel.network` rebuilds the chain service via
  `chainFactory` when it changes. `SettingsView` is the standard macOS Settings scene (Cmd-comma),
  also reachable from the burger menu; it holds appearance, Buy, wallet directory, backups,
  updates and developer settings, nothing about nodes. Current RPC URLs are listed at
  https://teztnets.com/teztnets.json.

## Taquito bridge

`TaquitoBridge/` is a small npm package that bundles Taquito (plus `@taquito/ledger-signer` and
`@ledgerhq/hw-transport`) and JavaScriptCore polyfills
(`src/polyfills.js`: timers, fetch, TextEncoder, crypto.getRandomValues, Buffer) into
`Signet/Resources/taquito-bridge.js`, which is committed and shipped as an app resource.
After changing anything under `TaquitoBridge/src` or bumping Taquito, rebuild it:

```sh
cd TaquitoBridge && npm install && npm run build      # minified; `npm run build:dev` keeps a source map
```

On the Swift side `TaquitoBridge.swift` owns the `JSContext` on a serial queue, installs the
`__signet` native object the polyfills call for timers, HTTP (URLSession), randomness and Ledger
HID exchanges (`LedgerHID`), and
exposes `call(name, args, timeout:)` which unwraps promises into a `Sendable` `JSONValue`.
**Call policy (S30).** `TaquitoBridge.signingCalls` names every export that signs, injects or
holds a Ledger session (`kind(of:)` is `.signing` for them); those calls get no deadline and are
never cancelled, whichever entry point they come through, while reads time out (60 s by default)
and discard the context. Swift calls them through `bridge.sign(name, args)`, which refuses a name
not on the list, and `npm test` (`test/signing-exports.cjs`) parses every bridge module with Acorn,
follows references, aliases, imports and re-exports from index.js's public surface, and checks
that exports reaching `signerFor`, `sendApproved`, `signAndInject`, `injectSigned`,
`ledgerSignerFor` or `LedgerSigner` match the native policy exactly (`ledgerAppVersion` is
declared for its device lease alone). esbuild independently checks the full export inventory.
Formatting, comments, regular expressions and template expressions are parsed as JavaScript;
unsupported linkage (including local namespace/default imports, dynamic code/imports, hoisted
`var` bindings and public classes) fails explicitly. This is conservative source reachability,
not an analysis of arbitrary SDK behavior. Promise
callbacks must be attached with `invokeMethod("then", ...)`, never a bare `then.call`, or the
continuation leaks and the caller hangs forever. `TaquitoChainService` uses the bridge for live
data. Numbers from the
bridge or the node go through `JSONValue.intValue` (finite, whole, within 2^53; S20) and
estimates through `TaquitoChainService.estimate(from:)`, so a bad reply is an error, never a
trap. **Logging (S11).** The bridge log (`~/Library/Logs/Signet/bridge.log`, 0600 in a 0700
folder, rotated to `.1` at 5 MB during writes) records fetches as method, host and path only
(query strings carry relay tokens), status and byte count, no bodies; every line goes through
`redactedLine` (long hex runs and base58 keys or signatures replaced, 1 KB cap). `record` is the
only sink: the system log (`NSLog`), `consoleLines` and the file all get the same redacted line,
and the JavaScript console and uncaught-exception handlers go through it too; nothing calls
`NSLog` directly. The SDK's
debug mode and the decrypting relay diagnostics run only when "Verbose dApp log on the next
launch" was armed in Settings > Developer (`DeveloperSettings`, consumed at that launch). Ledger
traces show the APDU header and length only.


## Audit repair boundaries (2026-10-12)

- `BridgeMultisigService.forNetwork` binds chain-backed multisig calls to the complete selected
  network/endpoint and verifies pinned chain identity. Multisig async publication/removal/signing
  also checks a changing context generation, catching same-name node changes and away/back switches.
- Untrusted artwork and dApp networking use `PublicHTTPClient`: the system `/usr/bin/curl` TLS
  client connects only to validated public DNS answers supplied via `--resolve`, retaining hostname
  certificate validation/SNI. User curl configuration, proxies and automatic redirects are disabled.
  Artwork redirects are separately validated/pinned; dApp RPC redirects are refused. Streaming
  byte/time limits and six process-wide slots bound work, including DNS workers awaiting cancellation.
  Configuration files are private and removed on completion. Native user-selected local RPCs remain
  supported through the ordinary bridge session.
- Artwork acquires its slot before DNS/download work, transfers slots directly to waiters, caps its
  queue/candidate count and downsamples with bounded sizes. `JSONBudget` checks HTTP response
  structure/string budgets before JavaScript. `PrivateFile.read` accepts bounded regular files only.
- Ledger sessions have both a JavaScript whole-operation queue and a process-wide native
  `LedgerSessions` lease, so separate bridge contexts cannot interleave device APDUs.
- Purchase navigation/media authority includes the effective HTTPS port (443). Alternate ports
  do not inherit provider trust. Default bridge construction uses in-memory storage and no log
  directory; only the production composition root selects disk stores/logging.
- The 2026-10-16 slop report's follow-up fixes and current evidence are in
  `audit/AI_SLOP_REPORT_20261016.md`. F07 still requires interactive comparison of both menus;
  do not describe that acceptance check as complete. The F23 opt-in synthetic benchmark lives
  in `WalletLockMeasurementTests`; run it with `TEST_RUNNER_SIGNET_LOCK_BENCHMARK=1` and
  `TEST_RUNNER_SIGNET_LOCK_BENCHMARK_OUTPUT=/private/tmp/signet-lock-measurement.json` on the
  xcodebuild test command. It records 80 initialization measurements (1/1,000 aliases; no lock,
  250 ms, one second and timeout; ten repeats). It never reads real wallets.
- `AuditRepairTests` and `BridgeBoundaryRepairTests` cover locking/recovery, current grants,
  persistence, connection pinning, response limits, exact origins, test isolation and native device
  leases. `MultisigContextRepairTests` exercises same-name endpoint and away/back switches.
  `npm test` also runs `test/audit-boundaries.cjs`, substituting SDK/device dependencies only,
  to exercise lifecycle ordering, pre-parser limits, complete Ledger sessions and multisig reveals.
