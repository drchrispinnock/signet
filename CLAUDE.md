# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Signet is a native macOS Tezos wallet written in SwiftUI. The spec is `spec/SPEC.md` and the
hand-drawn mock of the default screen is `spec/EXAMPLE.png`. Read both before changing the UI.

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

## Releases

The app version comes from git: `scripts/stamp-version.sh` runs as a post-build phase and writes
`git describe --tags` (minus the `v`) into `CFBundleShortVersionString` and the commit count into
`CFBundleVersion`, so the About panel shows `0.2` on the tag and `0.2-3-g<sha>` afterwards. Tag a
release before building it. Copyright and the About credits live in `Signet/Info.plist` and
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
`gh secret set SPARKLE_PRIVATE_KEY < file`). Without the secret the workflow still releases but
attaches no appcast, so that release is never offered as an update. Sparkle verifies the EdDSA
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
  while writing. A `Wallet` is therefore an octez alias; `keyKind` records whether its secret is
  unencrypted, encrypted, on a ledger, remote or absent. Clear, encrypted and ledger keys can sign
  (`KeyKind.canSign`); remote signers cannot yet. `WalletStore.add(_:locator:)` writes any
  `secret_keys` locator; `add(_:secretKey:)` is the convenience for keys on disk.
  The directory can be changed in Settings; that pointer is the one thing kept in UserDefaults
  (`WalletDirectorySettings`), because it cannot live inside the directory it names. Switching
  rebuilds both stores through the `storeFactory` the app passes to the view model.
  `WalletBackup` copies the wallet files (plus `state`) into a timestamped generation under
  `~/.signet_backups` on launch, after key creation/rename and on directory change, skipping
  when unchanged and keeping the newest N (default 10); folder and N are `BackupSettings` in
  UserDefaults and editable in Settings.
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
  estimate. Every signing call (`sendTransfer`, `performStaking`, `proofOfPossession`, the dApp
  `octezConnectExecute`/`octezConnectSign`) takes a `SigningKey`: `.secret(key, passphrase:)` or
  `.ledger(LedgerKey, address:)`, serialised by `bridgeSpec` into the JSON the bridge's
  `signerFor` (`src/signers.js`) turns into an `InMemorySigner` or a `LedgerSigner` for the one
  operation. `WalletViewModel.signingKey(for:passphrase:)` builds it from the wallet's kind.
  `waitForConfirmation` waits one block. `ChainError.fromBridgeMessage` maps the bridge's error
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
  (`BridgeKeyImporter`, `MockKeyImporter`).
- **Export (0.6).** "Export secret key…" (both menus, after Rename; enabled for clear and
  encrypted keys only) opens `ExportKeySheet`: a warning, the password for encrypted keys (the
  bridge's `decryptSecretKey` opens them; the clear key is shown and the encrypted form can be
  copied too), then the key masked with a reveal toggle and a Copy button. `WalletViewModel.
  exportSecretKey(passphrase:)` returns `ExportedKey(clear:encrypted:)`; nothing is written anywhere.
- **Forget (0.6).** "Forget account…" (both menus, under Add address) opens `ForgetAccountSheet`:
  one warning for everything, a second one when Signet holds the secret key (clear or encrypted;
  Ledger and watch-only entries get only the first), the password for encrypted keys (checked by
  decrypting), and a note that earlier backups under the backup folder still hold the key.
  `WalletStore.remove(alias:)` drops the alias from all three octez files like
  `octez-client forget address --force`; `WalletViewModel.forgetSelectedWallet(passphrase:)` then
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
  the bridge's raw path (`prepareRaw`/`sendRawOperation`/`waitForRawOperation`): the node simulates,
  forges and preapplies, Signet signs with the baker's key; `TaquitoChainService.rawContents` picks
  that path. Quantumnet hides the companion-key section (none there; consensus keys may be tz6).
  Baking and Staking sheets are read-only for wallets Signet cannot sign for (watch-only, remote)
  and the wording says so; Ledger wallets operate normally with approval on the device.
- **Buy (0.5, proof of concept).** The on-ramp is a Settings choice (`BuyProvider`, UserDefaults
  `buyProvider`, "Buy tez with"); Mt Pelerin is the only case so far and a US-serving provider
  (Transak) is the intended second: add a case and its URL builder, trusted hosts and ownership
  payload. `BuySheet` shows the provider's hosted widget inside the app in a
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
  (`ConnectDAppSheet`, burger menu, Cmd-Shift-D), or a `signet://?type=tzip10&data=<code>` link
  opens the app (the `signet` URL scheme is registered in Info.plist; `DAppPairingLink.code(from:)`
  parses it, `WalletViewModel.handleIncomingURL` stores it in `pendingPairingCode` and the sheet
  pairs with it and dismisses itself when the dApp's first request arrives, since only one sheet
  can be presented at a time; the app is a single `Window` scene and sets `LSMultipleInstancesProhibited`, so a
  link reuses the running app and window instead of opening another). That link shape is exactly what Beacon's / Octez Connect's wallet list opens for
  desktop wallets (`deepLink + "?type=tzip10&data=" + payload`); Signet appears in dApps' lists
  only once a `signet_desktop` entry with `deepLink: "signet://"` is merged upstream. `DAppConnectionManager` parses requests
  (`DAppRequest`), queues them, and `DAppRequestSheet` approves/rejects: permission (pick a wallet),
  operation (Taquito `contract.batch` from the partial operations, password for encrypted keys,
  Ledger approval on the device), sign_payload (`signer.sign`). Wrong password or a Ledger that is
  not ready leaves the request up for a retry. dApp network types map to ours via `DAppRequest.network`.
- **Appearance.** `Appearance` (OS / Light / Dark) lives in UserDefaults and is applied app-wide via
  `NSApp.appearance` by the `appliesStoredAppearance()` modifier on the root views.
- **Menus.** The burger menu (`AppMenuButton`) and the menu-bar "Operations" menu in `SignetApp`
  carry the same items (Create account, Import account, Connect Ledger, Rename account, Export secret key | Add address, Forget account |
  Connect to dApp | Baking, Governance when applicable | Settings, Refresh); keep them in step. File has Create Backup (`backUp(force: true)`).
- **Disclaimer.** `showsLaunchDisclaimer()` (`DisclaimerAlert.swift`) puts up the "very new
  software" alert (OK / Exit) when the main window appears; the `showsDisclaimer` UserDefault,
  toggled in Settings under Appearance, turns it off. Suppressed under the test host.
- **Node status.** `NodeMonitor` polls `/chains/main/blocks/head/header` every 30 s and
  classifies the reply (green fresh head, yellow stale/slow/HTTP error/odd payload, red no
  connection); `NodeStatusBar` pins it to the bottom of the window. `evaluate` is pure for tests.
- **Balances.** The node's `balance` is only the spendable part. `TezBalance` carries spendable,
  staked, unstaked-frozen and unstaked-finalizable tez; the tez row shows the total (the node's
  `full_balance`) and expands into those lines. Fetched via Taquito's RPC client for tz1 to tz4
  and by direct RPC for tz5/tz6. The node refuses `full_balance` with a 500 "missing_key" storage
  error for an account it has never seen; both paths map that to `ChainError.accountNotOnChain`,
  which the dashboard shows as "Key not found on chain" in place of the balance rows, with a
  "Get test tez" button on testnets and a Receive/buy prompt on mainnet. `FaucetService` speaks the
  teztnets faucet API directly (`/info`, `/challenge`, SHA-256 proof-of-work, `/verify`, as the
  `get-tez` CLI does, no captcha); `WalletViewModel.requestTestTez` drives it and polls until the
  account appears. Faucet URLs are `Network.faucetURL` from teztnets.json. `refresh()` fans out all loads concurrently.
- **Views** map one-to-one onto the sketch: `WalletHomeView` composes `WalletHeaderView`
  (the alias is a dropdown that switches wallets; shortened address with copy button; Tezos
  Domains name stacked beneath the address, a round `AccountAvatarView` on the left fed by TzKT's
  avatar service `services.tzkt.io/v1/avatars/<address>` (TzProfiles or known-account logo, else
  an identicon; WebP, decoded by ImageIO) via `Profiles.avatarURL(for:)`; avatars and TzProfiles names always come from mainnet
  services whatever network is selected, because a TzProfile is a mainnet identity), fetched live from the Tezos Domains GraphQL API by
  `TezosDomainsService` and omitted when the address has no reverse record; a hamburger menu
  reserved for other actions, not wallet switching),
  `ActionButtonsView` (Send, Receive, Buy/Get, Stake; Receive opens `ReceiveSheet` with a Core Image QR
  code of the address; on testnets Buy becomes Get and opens `FaucetSheet`, which drives
  `WalletViewModel.requestTestTez(amount:)`; on Mainnet Buy opens `BuySheet`. Sell was dropped for good: it would mean handling bank accounts), `AssetListView` (tez, then Etherlink, then
  other tokens) and `ActivityTabsView`, a segmented bottom section: `TransactionListView` (last 25
  operations from TzKT `/v1/accounts/{address}/operations`, parsed by `TzKTService.parseOperations`
  into `TezosTransaction`; rows show the counterparty's avatar and name, our alias with a green seal
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
  operations per network (tzkt.io on mainnet, the self-hosted TzKT on Quantumnet). Settings has a
  network dropdown that picks whose node is being edited (not the network in use) and a Custom
  network defaulting to `http://localhost:8732`; nodes are shown as full URLs.
- The spec asks for Taquito "where possible". Taquito is TypeScript, so chain access goes
  through a JavaScript bundle run inside JavaScriptCore (see `TaquitoBridge/`). Key generation for
  tz1/tz3 is in Swift; secrets enter the bridge only for the one operation they sign (Taquito's
  `InMemorySigner`), and Ledger keys never leave the device. Use the bridge for RPC, forging,
  encoding, metadata and the Ledger APDU protocol.
- Etherlink is out of scope for now. The row is hidden behind `WalletViewModel.showsEtherlinkBalance`;
  the asset kind, logo asset and fetch path are kept so it can be switched back on.
- Networks live in `Network.swift` (`Network.all` is what Settings offers). Ghostnet was retired in
  2026; Shadownet is the long-running public testnet and the bridge tests use it. Weeklynet
  restarts every Wednesday and its hosts carry the launch date, so `Network.weeklynet` builds the
  URL from the most recent Wednesday (UTC). Each `Network` has a `defaultRPCURL` and the `rpcURL`
  in use: Settings shows the network as a dropdown with a free-text node field beneath it, and
  `WalletViewModel.setNode` / `useDefaultNode` replace the node for the current network only.
  Custom nodes are kept per network name in `AppState.nodeURLs`; `switchNetwork(to:)` applies
  the saved one (assigning `network` directly uses whatever node the value carries). The chosen
  network, node and selected wallet are remembered in `~/.signet/state` (`FileAppStateStore`); `WalletViewModel.network` rebuilds the chain service via
  `chainFactory` when it changes. `SettingsView` is the standard macOS Settings scene (Cmd-comma),
  also reachable from the burger menu. Current RPC URLs are listed at
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
exposes `call(name, args)` which unwraps promises into a `Sendable` `JSONValue`. Promise
callbacks must be attached with `invokeMethod("then", ...)`, never a bare `then.call`, or the
continuation leaks and the caller hangs forever. `TaquitoChainService` uses the bridge for live
data and delegates anything not yet implemented to a fallback `ChainService`.
