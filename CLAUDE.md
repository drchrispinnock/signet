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

## Releases

The app version comes from git: `scripts/stamp-version.sh` runs as a post-build phase and writes
`git describe --tags` (minus the `v`) into `CFBundleShortVersionString` and the commit count into
`CFBundleVersion`, so the About panel shows `0.2` on the tag and `0.2-3-g<sha>` afterwards. Tag a
release before building it. Copyright and the About credits live in `Signet/Info.plist` and
`Signet/Resources/Credits.rtf`.

`scripts/release.sh [version]` archives a Release build, signs it with `$DEVELOPER_ID` if set
(ad-hoc otherwise), optionally notarises with `$NOTARY_PROFILE`, and writes `dist/Signet-<version>.zip`.
Pushing a `v*` tag runs `.github/workflows/release.yml`, which does the same on a macOS runner and
attaches the zip to a GitHub release; signing and notarisation switch on when the repository
secrets described in the workflow exist. The app is only ad-hoc signed until a Developer ID
certificate is configured, so downloads will trip Gatekeeper for ordinary users.

## Architecture

- **Models** (`Signet/Models`) are plain `Sendable` value types. A `Wallet` is one `Address`
  plus the alias the user gave it, its scheme and public key; the app holds a list of wallets
  and shows one at a time. `Base58.swift` holds Tezos base58check encoding and the byte prefixes. `AddressScheme` lists every tz prefix
  (tz1 through tz6) with an `isSupported` flag so unsupported schemes stay visible in the type
  system rather than being forgotten.
- **`ChainService`** (`Signet/Services`) is the single protocol for everything read from the
  chain or indexers. `MockChainService` returns the numbers from the sketch; views and previews
  are driven by it until live access lands. New data sources go behind this protocol.
- **Wallet storage is `~/.signet`, in octez-client's format.** `TezosClientStore` reads and writes
  `{public_key_hashs,public_keys,secret_keys}` exactly as octez-client lays them out,
  joining entries by alias, appending only, replacing files atomically and holding `wallet_lock`
  while writing. A `Wallet` is therefore an octez alias; `keyKind` records whether its secret is
  unencrypted, encrypted, on a ledger, remote or absent. Only unencrypted secrets can be used.
  The directory can be changed in Settings; that pointer is the one thing kept in UserDefaults
  (`WalletDirectorySettings`), because it cannot live inside the directory it names. Switching
  rebuilds both stores through the `storeFactory` the app passes to the view model.
  `WalletBackup` copies the wallet files (plus `state`) into a timestamped generation under
  `~/.signet_backups` on launch, after key creation/rename and on directory change, skipping
  when unchanged and keeping the newest N (default 10); folder and N are `BackupSettings` in
  UserDefaults and editable in Settings.
  If `~/.signet` already has keys the app opens on the dashboard. On a cold start (no keys) the
  welcome screen offers to import `~/.tezos-client` when one exists (an exact file copy). The merge
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
  estimate. `sendTransfer` hands the clear-text secret to Taquito's `InMemorySigner` for the one
  operation (native signing is a planned improvement); `waitForConfirmation` waits one block.
  Clear-text and encrypted keys can send; ledger and remote signers cannot yet.
- **dApps (Octez Connect / TZIP-10).** The Beacon-fork wallet SDK runs inside the bridge
  (`TaquitoBridge/src/octezconnect.js`) with a `NativeStorage` backed by `OctezConnectStorage`
  (`<wallet dir>/octez-connect.json`) and events pushed to Swift via `__signet.octezConnectEvent`.
  Pairing is Umami-style: the user pastes the dApp's "pair wallet on another device" code
  (`ConnectDAppSheet`, burger menu, Cmd-Shift-D). `DAppConnectionManager` parses requests
  (`DAppRequest`), queues them, and `DAppRequestSheet` approves/rejects: permission (pick a wallet),
  operation (Taquito `contract.batch` from the partial operations, password for encrypted keys),
  sign_payload (`InMemorySigner.sign`). dApp network types map to ours via `DAppRequest.network`.
- **Appearance.** `Appearance` (OS / Light / Dark) lives in UserDefaults and is applied app-wide via
  `NSApp.appearance` by the `appliesStoredAppearance()` modifier on the root views.
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
  `ActionButtonsView` (Send, Receive, Buy/Get, Sell; Receive opens `ReceiveSheet` with a Core Image QR
  code of the address; on testnets Buy becomes Get and opens `FaucetSheet`, which drives
  `WalletViewModel.requestTestTez(amount:)`; Buy and Sell are disabled until their flows exist), `AssetListView` (tez, then Etherlink, then
  other tokens) and `ActivityTabsView`, a segmented bottom section: `TransactionListView` (last 25
  operations from TzKT `/v1/accounts/{address}/operations`, parsed by `TzKTService.parseOperations`
  into `TezosTransaction`; rows show the counterparty's avatar and name, our alias with a green seal
  when it is one of ours, else TzKT's alias, via `WalletViewModel.displayName`) and `NFTGridView` (a scrolling grid fed by `TzKTService`: tokens with zero
  decimals and an image, `ipfs://` expanded to one URL per gateway by `IPFS.candidateURLs` and loaded by `ImageLoader`, which tries them in order and downsamples (ipfs.io rate-limits, Filebase is fast), displayUri preferred
  over thumbnailUri because marketplaces often use a generic thumbnail). `CreateWalletSheet` is reached from the hamburger menu, the
  File menu or Cmd-N; with no wallets `NoWalletsView` replaces the dashboard. `AddAddressSheet`
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
  through a JavaScript bundle run inside JavaScriptCore (see `TaquitoBridge/`). Keep private
  keys and signing in Swift; use the bridge for RPC, forging, encoding and metadata.
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

`TaquitoBridge/` is a small npm package that bundles Taquito plus JavaScriptCore polyfills
(`src/polyfills.js`: timers, fetch, TextEncoder, crypto.getRandomValues, Buffer) into
`Signet/Resources/taquito-bridge.js`, which is committed and shipped as an app resource.
After changing anything under `TaquitoBridge/src` or bumping Taquito, rebuild it:

```sh
cd TaquitoBridge && npm install && npm run build      # minified; `npm run build:dev` keeps a source map
```

On the Swift side `TaquitoBridge.swift` owns the `JSContext` on a serial queue, installs the
`__signet` native object the polyfills call for timers, HTTP (URLSession) and randomness, and
exposes `call(name, args)` which unwraps promises into a `Sendable` `JSONValue`. Promise
callbacks must be attached with `invokeMethod("then", ...)`, never a bare `then.call`, or the
continuation leaks and the caller hangs forever. `TaquitoChainService` uses the bridge for live
data and delegates anything not yet implemented to a fallback `ChainService`.
