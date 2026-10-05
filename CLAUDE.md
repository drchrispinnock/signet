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

## Architecture

- **Models** (`Signet/Models`) are plain `Sendable` value types. A `Wallet` is one `Address`
  plus the alias the user gave it, its scheme and public key; the app holds a list of wallets
  and shows one at a time. `Base58.swift` holds Tezos base58check encoding and the byte prefixes. `AddressScheme` lists every tz prefix
  (tz1 through tz6) with an `isSupported` flag so unsupported schemes stay visible in the type
  system rather than being forgotten.
- **`ChainService`** (`Signet/Services`) is the single protocol for everything read from the
  chain or indexers. `MockChainService` returns the numbers from the sketch; views and previews
  are driven by it until live access lands. New data sources go behind this protocol.
- **Keys.** `KeyGenerator` makes tz1 and tz3 keys with CryptoKit and encodes them in Swift, so
  those secrets never enter JavaScript; tz2 and tz4 are generated in the bridge with the same
  `@noble/curves` code Taquito signs with (BLS secrets are little-endian on the wire). Secrets go
  through the `SecretKeyStore` protocol (`KeychainSecretKeyStore` in the app, in-memory in tests);
  the wallet list goes through `WalletStore` (`FileWalletStore` writes `wallets.json` in the
  sandbox's Application Support). Keys are never persisted anywhere else.
- **`WalletViewModel`** is a `@MainActor @Observable` class owning the wallet list, the
  selected wallet and the loaded balances, domains and NFTs, and `createWallet(alias:scheme:)`. `refresh()` fans out all loads concurrently.
- **Views** map one-to-one onto the sketch: `WalletHomeView` composes `WalletHeaderView`
  (the alias is a dropdown that switches wallets; shortened address with copy button; Tezos
  Domains names stacked beneath the address; a hamburger menu reserved for other actions, not
  wallet switching),
  `ActionButtonsView` (Send, Receive, Buy, Sell), `AssetListView` (tez, then Etherlink, then
  other tokens) and `NFTGridView`. `CreateWalletSheet` is reached from the hamburger menu, the
  File menu or Cmd-N; with no wallets `NoWalletsView` replaces the dashboard.
- The project builds with Swift 6 language mode and complete strict concurrency; keep new types
  `Sendable` and UI work on the main actor.
- The app is sandboxed with the network client entitlement only.

## Requirements and open decisions

- Address schemes tz1 through tz4 are supported today. tz5 (ML-DSA-44, post-quantum, added in
  the Ushuaia protocol in June 2026 and live on the Quantumnet testnet) and tz6 are required
  eventually but deferred: as of October 2026 neither Taquito 25 nor Apple CryptoKit (which
  only has ML-DSA-65 and ML-DSA-87) supports ML-DSA-44, and tz6 is not yet publicly specified.
  Do not implement them until the user says so, but keep the account and key model open to them.
- The spec asks for Taquito "where possible". Taquito is TypeScript, so chain access goes
  through a JavaScript bundle run inside JavaScriptCore (see `TaquitoBridge/`). Keep private
  keys and signing in Swift; use the bridge for RPC, forging, encoding and metadata.
- Etherlink address handling is out of scope for now; the Etherlink balance row is a placeholder.
- Networks live in `Network.swift`. Ghostnet was retired in 2026; Shadownet is the long-running
  public testnet and the bridge tests use it. Current RPC URLs are listed at
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
