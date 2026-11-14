# Secure Enclave keys

A tz3 account whose key is made inside the Mac's Secure Enclave and never leaves it. Built in
the Mac app first (branch `claude@enclave`) so that Signet Go (iOS) can take it through the
submodule.

Decided (2026-11-14, Chris): this is **one more key type, chosen per account**, never a policy
for the wallet. Software keys (tz1 to tz5, clear or encrypted, exportable, octez-compatible)
are untouched. The earlier plan to *seal* software keys with the Enclave (encrypt them to an
Enclave key, keep the ciphertext in the Keychain, on by default) was dropped for the Mac: it
protected keys only at rest, broke octez-client compatibility by default and needed a
provisioning profile. Signet Go may still want it; see the end.

Decided (2026-11-13): no files are shared from the Mac to the iOS app, and Signet Go keeps no
keys in iCloud.

## What it is

- The Secure Enclave holds **P-256** keys only, so an Enclave account is always **tz3**.
- The key is generated in the Enclave. The secret never exists outside it: not on disk, not in
  a backup, not in JavaScript. Every signature needs Touch ID or the login password, checked by
  the Enclave (`.privateKeyUsage` + `.userPresence`).
- **It cannot be exported, backed up or recovered.** A lost, erased or repaired Mac loses the
  account. The Create sheet says so and asks for an "I understand" toggle. It is meant for
  spending money, or as one signer of a multisig whose other signers can be recovered.

## How it is built

- **No Keychain, no entitlement.** CryptoKit's `SecureEnclave.P256.Signing.PrivateKey` hands
  back the Enclave's wrapped form of the key (`dataRepresentation`, 284 to 427 bytes), which
  only this machine's Enclave can use. We store that blob ourselves, so no
  `keychain-access-groups` entitlement or provisioning profile is needed and ad-hoc builds
  work. (A permanent `SecKey` in the data-protection Keychain fails with -34018 without a
  profile; that was the old plan's "Mac-specific catch".) The blob is not tied to Signet: any
  process of the user could ask the Enclave to use it, and the presence check is the gate.
- **Locator.** `secret_keys` holds `signet-enclave:<base64 blob>`; `public_keys` and
  `public_key_hashs` are written as usual. The wallet directory stays self-contained, and a
  copy elsewhere (backup, another Mac) holds nothing usable. octez-client still lists the
  alias but cannot sign for it. `KeyKind.enclave` (`canSign` true), `Wallet.enclaveKey`
  (`EnclaveKey`, `Signet/Models/EnclaveKey.swift`).
- **Service.** `EnclaveKeyService` (`Signet/Services/EnclaveKeys.swift`): `isAvailable`,
  `create()`, `isUsable(_:)` (can this Enclave load the blob, no prompt), `sign(digest:with:
  reason:)`. `SecureEnclaveKeys` is the hardware; `SoftwareEnclaveKeys` (plain P-256 in
  memory) is for tests and previews; `UnavailableEnclaveKeys` is the model's default and what
  Linux gets. `EnclaveKeys.platform` picks the real one.
- **Signing.** Tezos signs the Blake2b-256 digest of the watermarked bytes; CryptoKit has no
  Blake2b, so the digest is wrapped in `RawDigest` (our own `Digest` type) and signed as it is.
  The Enclave returns high-S about half the time; `P256Signature.lowS` normalises, since
  Taquito signs low-S. A fresh `LAContext` per signature (`localizedReason`, no reuse).
- **Bridge.** `SigningKey.enclave(key, publicKey:, address:)` becomes `{kind: "enclave", key,
  publicKey, address}`; `enclaveSignerFor` (`src/signers.js`) refuses a public key that does
  not hash to the address, computes the digest, calls `__signet.enclaveSign` (answered through
  `__signet_enclaveDone`), and **verifies the returned signature against the account's public
  key** before returning it, so a swapped or foreign blob cannot sign. `TaquitoBridge.enclave`
  is the service the native call uses (the platform's unless a test replaces it). Every
  signing path goes through `signerFor`, so sends, staking, dApps, multisig, governance and
  payload signing all work without further change.
- **Model and UI.** `WalletViewModel.createEnclaveWallet(alias:)`, `canCreateEnclaveKey`,
  `isEnclaveKeyPresent(_:)`. Create account's key-type picker gains "tz3 · in this Mac's
  Secure Enclave" (only where there is an Enclave, never the default). The header shows a
  "Secure Enclave" tag, or an orange "Key not on this Mac" when the Enclave cannot load the
  blob. Export is off (`canExportSelectedKey`). Forget asks the Enclave for a signature first
  (Touch ID) when the key is usable, and says that Signet's backups on this Mac can bring the
  entry back here and nowhere else.
- **Errors.** `EnclaveError` (unavailable, notOnThisMac, cancelled, failed); through the bridge
  they become `ChainError.enclaveCancelled` / `.enclaveKeyMissing`.

## Tests

`EnclaveKeyTests` (locator, low-S, the store holding no secret, the model's create / sign /
forget, a foreign key, the bridge round trip and its refusals, and the real Enclave with a key
that asks for no presence, skipped where there is none). `EnclaveSendTests` is the live
Shadownet round trip (reveal, then two transfers), signed by the hardware where there is one.

## Not yet checked

- **The prompt itself.** Tests use keys with no presence requirement, since nobody can answer
  Touch ID there. Making a guarded key works; signing with one (the prompt, its wording,
  Cancel giving "Not signed") needs a hand run in the app.
- "When unlocked" keys could not be made from a shell session here (-25308), so
  `SecureEnclaveKeys` falls back to "after first unlock"; which one the app gets is unchecked.
  The presence check per signature is the same either way.
- Whether a blob from another Mac really fails to load (assumed; tested with garbage only).
- Sparkle updates and re-signing: the blob is the Enclave's, not the app's, so a new build
  should keep working. Unchecked.

## Then, in Signet Go

Bump the submodule and inject `EnclaveKeys.platform`; add `NSFaceIDUsageDescription`. The same
tz3 key type then works on the phone. Whether the phone also *seals* its software keys (the
dropped phase 1) is a decision for Signet Go alone: there is no octez-client there to stay
compatible with, and that design would live in Signet Go's own vault, not here.
