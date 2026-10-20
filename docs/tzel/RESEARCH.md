# TzEL (shielded tez) in Signet: research notes

Written 2026-10-19 from `trilitech/tzel` (main at a2302e2, 12 October 2026), the internal
`trilitech/tzel-infra` repository, the public site https://tzel.tezos.com and live probes of the
Shadownet deployment. Nothing here is implemented yet. The protocol is explicitly experimental:
the README says "do not use for real value", and the rollup can be re-originated at any time,
which changes every address below.

## 1. What TzEL is

TzEL ("Tezos Encrypted Ledger") is a Tezos smart rollup whose WASM kernel keeps a private
UTXO ledger of *notes*. Every spend is proven with a recursive STARK (Stwo, about 300 KB) that
also verifies a hash-based one-time signature (WOTS+ in an XMSS tree), so the proof itself is
the spend authorisation. The cryptography is post-quantum throughout: BLAKE2s for commitments
and nullifiers, ML-KEM-768 plus ChaCha20-Poly1305 for the encrypted note memos, no elliptic
curves anywhere. Proving is delegated to an untrusted proving service; the signature binds the
whole request, so the prover cannot redirect funds. Data goes to the rollup through the DAL.

Three operations exist, and each burns at least 0.1 tez (100000 mutez) and pays a small
"DAL producer fee" note to the operator that publishes the slot:

- **Shield** (public to private): drain a *deposit pool* on the rollup into a private note.
- **Transfer** (private to private): spend 1 to 7 notes, create recipient, change and fee notes.
- **Unshield** (private to public): destroy notes and emit an L1 outbox transfer to a tz or KT1.

Where it runs: it started on Ushuaianet and moved to **Shadownet** in October 2026 (tzel PR 41).
The Ushuaianet rollup (`sr193pvbiGEhrxYnhgKcpaiWVRJmWjWYCaqH`, ticketer
`KT1F8CR34VPaiMVYwSbucpdEYQ2itTJsqV9A`) is stale. Nothing in either repository mentions
Quantumnet, so the Networks switch should treat Shadownet as the only network with shielded
transactions today.

## 2. Live Shadownet parameters (verified 2026-10-19)

| Parameter | Value | How verified |
| --- | --- | --- |
| Layer 1 RPC | `https://rpc.shadownet.teztnets.com` | our default already |
| TzEL rollup address | `sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK` | rollup node `/global/smart_rollup_address` |
| Bridge ticketer (L1 contract) | `KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4` | durable state `/tzel/v1/state/bridge/ticketer` and TzKT |
| Rollup node RPC | `http://rollup.tzel.tezos.com:8932` | answers; **plain HTTP, no TLS** |
| Operator (submissions) | `http://operator.tzel.tezos.com:8787` | `/healthz` ok; `/v1/*` needs a bearer token |
| Proving service | `https://proving.tzel.tezos.com` | `/v1/programs` lists the three circuits |
| DAL producer fee | `100000` mutez | profile |
| DAL fee address | the operator's PaymentAddress JSON (six fields, about 5 KB) | `docs/shadownet/operator-fee-address.json` in tzel |
| `auth_domain` of the deployment | `f1e4e757b5cc5af59690170d4507c78621e520048955613170e0bb5c52dcbe07` | durable state `/tzel/v1/state/auth_domain` |
| Minimum burn per operation | `100000` mutez, doubling per extra private tx in the same inbox level, capped after 6 steps | tutorial; quoted live from `/tzel/v1/state/fees/*` |
| Challenge window | 201600 blocks at 6 s, about **14 days** | L1 `/context/constants` |
| Commitment period | 150 blocks | L1 `/context/constants` |
| Explorer | `https://shadownet.tzkt.io` | |
| Program hashes | shield `655b8fa9…fb00`, transfer `b0de7bf9…3e05`, unshield `39b598a7…ae06` | proving service `/v1/programs` |

State size today: 26 notes in the commitment tree and 9 nullifiers, so a full scan is trivial.

**The operator bearer token.** Every `/v1/rollup/*` call needs `Authorization: Bearer …`. The
token is hardcoded in the tzel wallet Docker image's entrypoint and the infra notes say it "is
not a secret in the cryptographic sense" (every install carries it), but it is deliberately kept
out of the published profile. Signet would need it from the tzel team, and it rotates with the
operator. It must never be committed here.

**Signed network profile.** The Docker wallet fetches `https://tzel.tezos.com/profile-shadownet.json`
(minisign-signed) at boot and falls back to the baked copy. That URL currently serves the site's
HTML, not JSON. The profile shape is the `WalletNetworkProfile` below.

## 3. The reference wallet, piece by piece

### Keys and state (the part Signet cannot do with tz keys)

Everything derives from a 32-byte `master_sk`. Per diversified address `j` the wallet derives
`d_j` (diversifier), an **auth tree of 65536 WOTS+ one-time keys** (`auth_root_j`,
`auth_pub_seed_j`), a nullifier key `nk_spend_j` with public tag `nk_tag_j`, and two ML-KEM
key pairs (`ek_v_j` viewing, `ek_d_j` detection). A **payment address** is the JSON record
`{d_j, auth_root, auth_pub_seed, nk_tag, ek_v, ek_d}`; it is about 2.5 KB of hex, not a tz string.

The wallet is **stateful**. `wallet.json` holds `master_sk`, `addresses`, `addr_counter`,
`notes`, `scanned`, `wots_key_indices`, `pending_spends`, `pending_deposits` and
`deposit_nonce`. Reusing a WOTS+ index lets anyone forge a signature and steal the funds, and
the per-deposit blinds and nonces are not on chain, so restoring an old backup is dangerous
(the CLI refuses when it detects it) and losing the file loses the pools and notes (there is a
bounded brute-force `recover-deposits`). This is unlike anything Signet stores today: backups
must capture the live state, and two Signet instances must never share one file.

### Deposit (L1, signed with the user's tz key)

The wallet derives a fresh pool id `pubkey_hash = H_pubkey(auth_domain, auth_root,
auth_pub_seed, blind)` and asks the user to call the ticketer's `mint` entrypoint with the tez
to deposit and the Michelson argument

```
Pair 0x<hex of ASCII "deposit:" + lowercase hex(pubkey_hash)> "sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK"
```

The ticketer mints a `(0, None)` ticket for the amount and forwards it to the rollup with the
recipient bytes. The kernel credits the pool at durable key
`/tzel/v1/state/deposits/balance/<hex pubkey_hash>` (u64 little-endian; absent when zero).
Pools aggregate, so top-ups and dust are harmless. Before sending, the reference wallet checks
three things on the rollup node and refuses otherwise: `verifier_config.bin` exists, the
kernel's `bridge/ticketer` equals the profile's, and `/global/smart_rollup_address` equals the
profile's rollup. Recent real deposits are visible on TzKT as `mint` calls to the ticketer.

This step is ordinary Layer 1 signing: Signet can do it today through the approved-limits path,
as the Etherlink deposit does.

### Shield, transfer, unshield (rollup, needs the PQ wallet)

The wallet builds the transaction and its witness, signs the sighash with the next WOTS+ key,
posts the witness to the proving service (`POST /v1/jobs {program_hash, arguments}` then
`GET /v1/jobs/{id}?wait=30` until `done`, typically 30 to 60 s), and submits the proof bundle
to the operator (`POST /v1/rollup/…`, bearer token). The operator publishes it on the DAL; a
submission moves through `pending_dal`, `commitment_included`, `attested`, `submitted_to_l1`
or `failed`, polled at `/v1/rollup/submissions/<id>`. Shield drains a pool by
`amount + burn fee + producer fee`; the wallet quotes the current burn fee from the rollup's
fee state. An unshield names a tz or KT1 recipient and leaves an outbox message.

### Balance (why "shielded balance" is a local number)

There is no "balance of address" RPC; that is the point. The wallet's private balance is the
sum of the unspent notes it has recognised. `sync` reads the tree size
(`/tzel/v1/state/tree/size`), fetches every published note it has not seen
(`/tzel/v1/state/notes/<index as 16 hex digits>/len` then `/chunk/<8 hex digits>` in 1024-byte
pieces, all through `/global/block/<hash>/durable/wasm_2_0_0/value?key=…`), decodes the
canonical wire form and tries ML-KEM decapsulation with each of its addresses' viewing keys,
then reads the nullifier list (`/tzel/v1/state/nullifiers/count`, `/index/<16 hex>`) to mark
spent notes. All reads are pinned to one block hash. Pool balances come from the deposit keys
above. So a Signet shielded balance means: run the scan and keep the state, not ask a node.

### Unshield completion (L1 again, after about 14 days)

An unshield's outbox message appears at `/local/outbox/pending` on the rollup node (a `burn`
call on the ticketer paying the recipient). Once the commitment covering it is cemented, the
proof comes from `/global/block/head/helpers/proofs/outbox/<level>/messages?index=<i>`
(`commitment` and `proof`) and someone signs a Layer 1 `smart_rollup_execute_outbox_message`
with them. Status is read from `/global/block/head/outbox/<level>/messages`. The reference
daemon keeps a local `outbox.json` of its own withdrawals because the node cannot list "my"
messages. The tzel notes say Temple cannot reliably sign this operation kind; Signet forges
locally and can.

## 4. Options for Signet

The post-quantum key handling, note scanning, witness building and WOTS+ signing all live in
the Rust `tzel-wallet` CLI (`apps/wallet/src/lib.rs`, 14 000 lines, nightly toolchain
`nightly-2025-07-14`, pulling Stwo and circuit crates through `tzel-verifier`). The Docker
wallet that Trilitech ships is a daemon that **spawns that CLI as a subprocess per operation**
(`--json --wallet <path> [--proving-service-url …] <subcommand>`, JSON envelope on stdout, phase
events on stderr; see tzel-infra ADR-002) and does the Layer 1 parts in the browser with Temple.

- **A. Bundle the CLI and drive it the same way.** Signet ships a macOS build of `tzel-wallet`
  inside the app and runs it exactly as the daemon does, doing the two Layer 1 steps itself
  (`deposit --prepare-only` gives the `mint` parameters; outbox execution from the rollup node's
  proof). No cryptography is reimplemented and we track upstream by rebuilding. Costs: nobody
  publishes macOS binaries (Linux images only), so we build it ourselves (verified: section 7),
  the embedded binary must be signed and notarised with the app, and the JSON envelope is a
  contract the tzel team may change. The proving service's
  `/v1/programs` means the `reprove` binary and Cairo executables are not needed at runtime.
- **B. Talk to the user's tzel Docker wallet.** It serves `/api/*` on `127.0.0.1:8080`
  (`balance`, `shield`, `send`, `unshield`, `withdraw`, `deposits`, `deposit/prepare`,
  `deposit/submitted`, `outbox`, `outbox/{id}/prepare`, `outbox/{id}/executed`, `jobs/{id}`,
  `wallet/receive`, `wallet/addresses`, `history`). Signet would replace Temple as the Layer 1
  signer. Cheap, but it requires Docker, the daemon lives in an internal repository, and the
  keys sit in `~/.tzel-wallet`, outside Signet's directory and backups.
- **C. Reimplement in Swift or in the Taquito bridge.** BLAKE2s, ML-KEM-768 (CryptoKit has none),
  WOTS+/XMSS with state, the canonical wire format, Cairo witness arguments for three circuits,
  against a 787-line spec that is still moving. Months of work on an unstable target.

A is the only one that gives Signet a real shielded account without new cryptography; B is a
way to demonstrate the flow quickly. Even the balance alone needs the ML-KEM scan, so there is
no cheap read-only path without one of them. **Decision (Chris, 2026-10-19): C, our own
implementation, no bundled CLI.** Section 8 has the plan and what is done.

## 5. What goes into Settings when the switch is on

Per network, alongside the existing node fields:

| Setting | Default (Shadownet) | Notes |
| --- | --- | --- |
| Rollup node | `http://rollup.tzel.tezos.com:8932` | our node policy refuses plain `http` for public hosts; needs an exception or TLS from the team |
| Rollup address | `sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK` | pinned per network and checked against the node like the chain id |
| Bridge ticketer | `KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4` | checked against durable state before any deposit |
| Operator URL and bearer token | `http://operator.tzel.tezos.com:8787` + token | token is a secret field, never written to the repo |
| Proving service | `https://proving.tzel.tezos.com` | |
| DAL producer fee and fee address | 100000 mutez + the operator's PaymentAddress | ship the JSON as a resource, allow replacing it |
| Expected `auth_domain` | `f1e4e7…be07` | detects a re-originated rollup; the CLI compares it at shield time |
| Wallet file | `~/.signet/tzel/<network>/wallet.json` (+ `.network.json` profile) | must be in `WalletBackup`; one writer at a time |

The user-facing pieces the switch will reveal: a **Shielded** balance row (local scan state,
with "syncing" and "pools awaiting credit" states), **Shield tez** (deposit through `mint`, then
shield after the pool is credited: two steps, minutes apart), **Unshield tez** (one rollup step,
then a Layer 1 execution about 14 days later: needs a persisted list of pending withdrawals like
the daemon's `outbox.json`, and an "execute" action when cemented), and later **Send shielded**
(recipients are payment-address JSON blobs, so an address book with fingerprints is needed, as
the web UI has).

## 6. Questions for the tzel team

1. TLS for `rollup.tzel.tezos.com:8932`, or is plain HTTP intended?

Chris says: 8932 is the smart rollup port. It serves HTTP.
TF01007: {1003} curl http://rollup.tzel.tezos.com:8932/version
{"version":"Octez 0.0+dev (build: 0)","store_version":"v5_sqlite","context_version":"0"}

2. How should a third-party wallet obtain and rotate the operator bearer token?

CHRIS: I have the token. Put it as a configuration item please.

3. Will `tzel-wallet` be published for macOS (arm64 and x86_64), or as a library crate with a
   stability promise? Is the `--json` envelope (schema_version 1) considered stable?

CHRIS: I have the source code for all of the tzel stuff in ../tzel

4. Where will the signed profile live (the documented URL serves HTML today), and how are re-originations announced?
CHRIS: don't know but do you need this to start?

5. Any plan for Quantumnet or Ushuaianet again?

CHRIS: Yes - Quantumnet soon. Don't know about U, but focus on Shadownet please.

## Sources

- https://github.com/trilitech/tzel (README, `docs/shadownet_tutorial.md`, `specs/spec.md`,
  `apps/wallet/src/lib.rs`, `tezos/tez_bridge_ticketer.tz`, `docs/wallet-install.sh`)
- `trilitech/tzel-infra` (internal): `ARCHITECTURE.md`, `docs/adrs/002-daemon-as-cli-wrapper.md`,
  `docs/tzel-wallet-design.md`, `docker/wallet-bundle/*`, `services/wallet/src/*`
- https://tzel.tezos.com/wallet.html
- Live: rollup node, operator, proving service, Shadownet RPC and TzKT, all on 2026-10-19

## 7. Verified on this Mac (2026-10-19): the CLI builds and reads a balance

The wallet binary does **not** need the nightly toolchain; only `reprove` (local proving) does,
and the proving service replaces it. From the clone in `../tzel` (a2302e2):

```sh
cargo +1.94.0 build --release -p tzel-wallet-app --bin tzel-wallet
# 4 min 18 s, 471 crates, target/release/tzel-wallet: 30 MB Mach-O arm64
```

The balance flow, with every file in a scratch directory and no token:

```sh
tzel-wallet --json -w $D/wallet.json init
tzel-wallet --json -w $D/wallet.json profile init-shadownet \
  --rollup-node-url http://rollup.tzel.tezos.com:8932 \
  --rollup-address sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK \
  --bridge-ticketer KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4 \
  --dal-fee 100000 --dal-fee-address docs/shadownet/operator-fee-address.json \
  --source-alias signet --public-account tz1… --octez-client-dir $D/octez-client
tzel-wallet --json -w $D/wallet.json check-network   # OK: profile matches the live rollup
tzel-wallet --json -w $D/wallet.json sync            # 1.1 s for the 26 notes, 4 fetchers
tzel-wallet --json -w $D/wallet.json balance
# {"command":"balance","result":{"private_available":0,"private_tracked_total":0,
#   "private_pending_outgoing":0,"tracked_notes":0,"pending_operations":0,
#   "deposit_pools_funded":0,"deposit_pools_total_mutez":0,
#   "deposit_pools_awaiting_credit":0,"deposit_pools_drained_pending_prune":0},"schema_version":1}
```

Things learned on the way:

- The wallet path must be absolute: `init` with a bare `wallet.json` fails on "open parent dir".
- `profile init-shadownet` resolves `--source-alias` by running `octez-client` against
  `~/.tezos-client` unless `--public-account` is a tz address; Signet must always pass the
  address (and an `--octez-client-dir` of its own) so the CLI never reads the user's octez
  directory. The alias and account are only used by the CLI's own L1 deposit path, which Signet
  replaces. (On this Mac that lookup failed anyway: the installed `octez-client` cannot parse
  `~/.tezos-client/public_key_hashs`, "Unexpected data (Signature.Public_key_hash)".)
- Files written next to the wallet: `wallet.json` (0600), `wallet.json.network.json` (the
  profile, 5.6 KB because it embeds the fee PaymentAddress), `wallet.json.xmss-floor` (the
  one-time-signature floor; part of the state that must be backed up with the wallet).
- `sync` and `balance` need only the rollup node; the operator bearer token is used by
  shield, send, unshield and status. `init --at-tree-size N` skips the historical scan for a
  fresh key; never pass it for an imported key.
- The master key is `random_felt()`: there is no derivation from a tz key, so the shielded
  account is a second secret Signet must create, store and back up.

## 8. Own implementation: plan and progress

The protocol is specified normatively (`specs/spec.md`, 787 lines) with a shared vector file
(`specs/ocaml_vectors/protocol_v1.json`, 16 sections, generated by the Rust reference and
consumed by Trilitech's independent OCaml implementation), so a clean-room implementation is
the intended route. Note the tzel `LICENSE`: all rights reserved, no reproduction without
written permission, so neither the vectors nor the Rust code may be copied into this
repository. Our tests read the vectors from a tzel checkout (`TZEL_VECTORS`, or the sibling
clone `../tzel`) and skip when there is none.

**Where it lives.** The primitives are in the Taquito bridge (`TaquitoBridge/src/tzel.js`),
because the bridge already ships what the protocol needs and CryptoKit does not: ML-KEM-768
with seed-based key generation (`@noble/post-quantum`, as for tz5), BLAKE2s with
personalization (`@noble/hashes`) and ChaCha20-Poly1305 (`@noble/ciphers`). CryptoKit gained
ML-KEM only in macOS 26 and Signet targets macOS 15. Secrets follow the spec's capability
levels: scanning gets `incoming_seed` (viewing) and `nk` (nullifiers); `ask_base` (signing)
enters the bridge only for the one operation it signs, like a tz secret key.

**Done (2026-10-19), `tzel.js` + `test/tzel-vectors.cjs`, 173 checks, all 16 vector sections:**
felt tags and encodings, BLAKE2s-251 with every personalization, the key hierarchy, per-address
diversifier / nullifier keys / owner tag, ML-KEM seeds, deterministic keygen, deterministic
encapsulation and decapsulation, the note AEAD (key, derived nonce, encrypt, decrypt), detection
tags, `memo_ct_hash`, the cross-implementation note end to end (encrypt with fixed coins, then
decrypt and detect with our keys), WOTS+ (w = 4, 133 chains: key seed, leaf, sign, recover),
the full 65536-leaf XMSS auth root with paths, commitment-tree Merkle roots and paths, note
commitments and position-dependent nullifiers, note acceptance, sighash folds, account ids,
and the canonical wire forms (PaymentAddress, EncryptedNote, PublishedNote, NoteMemo) both
ways. `TZEL_FULL=1` also rebuilds the three vector auth roots.

**Known cost.** An address's auth tree is about 44 million BLAKE2s hashes. noble's BLAKE2s does
about 190 000 a second in Node, so a tree takes 4 minutes there; the Rust CLI says "tens of
seconds". Address creation must therefore be a native job: a Swift BLAKE2s and a parallel leaf
builder (the 65536 leaves are independent, so an M-series Mac should do it in seconds), with
the leaves kept in the wallet file so signing paths never need a rebuild. One address serves
many deposits: a fresh per-deposit `blind` already makes each pool id unlinkable, so Signet
does not need the reference wallet's fresh-address-per-deposit habit.

**Done (2026-10-19, evening): balance and Shield tez.**

- *Native signing tree.* `Signet/Services/tzel_blake2s.c` (BLAKE2s-256 and the WOTS+ leaf and
  tree node, compiled with `-O3` in every configuration through `project.yml`) behind
  `Blake2s.swift` and `XMSSAuthTree.swift`: the 65536 leaves are built across every core in
  about 2 s on an M-series Mac (235 s in unoptimised Swift, 4 minutes in the bridge), and the
  root equals the vectors' `addresses[0].auth_root`. Leaves live in
  `<wallet dir>/tzel-<chain>-auth<j>.bin` and are rebuilt from the master key when missing.
- *Wallet.* One `ShieldedWallet` per tz account (Chris, 2026-10-19 evening: a network-wide
  wallet showed the same shielded balance under every account), all in
  `<wallet dir>/tzel-<chain>.json` (version 2: the operator token and a wallet per address; a
  version 1 file is adopted by the account that funded its deposit, found through TzKT),
  a private file backed up with the key files. Each wallet: master key
  (clear, like an unencrypted tz key; a password is still to do), addresses with their next
  WOTS+ index, deposit pools (`pubkey_hash`, blind, address, `auth_domain`, L1 operation,
  the shield's commitment), notes (position, cm, rseed, nullifier, value, spent), the scan
  cursors. `FileShieldedWalletStore` / `InMemoryShieldedWalletStore`.
- *Services.* `ShieldedService.swift`: `ShieldedConfig` per network (`Network.shielded`, set
  for Shadownet), the `ShieldedRollup` protocol and `RollupNodeService` over `BoundedHTTP`:
  durable reads pinned to one block (absent keys come back as JSON `null`, not 404; notes are
  chunked at 1024 bytes under `notes/<idx>/len` and `/chunk/<k>`), the fee rule
  (`required_tx_fee_for_private_tx_count`: 0.1 tez doubling per private tx beyond the second
  in a level, cap 6.4 tez), the proving service (`/v1/programs`, `POST /v1/jobs`,
  `GET /v1/jobs/<id>?wait=30&if_state_changed_from=`), and the operator
  (`POST /v1/rollup/submissions` with the bearer token, polled to `submitted_to_l1`).
- *Bridge.* `src/shield.js`: `estimateShieldDeposit` / `sendShieldDeposit` (the ticketer's
  `mint (pair (bytes %receiver) (address %rollup))` through the approved-limits path, the
  receiver being the ASCII of `deposit:<hex>`), `tzelAccount`, `tzelAddressKeys`,
  `tzelDepositPool` (the reference wallet's blind `H("tzel-deposit-blind" ‖ master_sk ‖
  u32 address ‖ u64 nonce)`), `tzelScan`, `tzelBuildShield` (both output notes with their
  outgoing-recovery records, the sighash, the signature, the 171-word witness; refuses a pool
  id, signing seed or auth path that does not belong to the address) and
  `tzelEncodeShieldMessage` (kernel inbox wire version 17, checked byte for byte against the
  reference crate's encoding of a sample message in `test/tzel-shield.cjs`, and refusing a
  proof whose public outputs are not the nine the witness was built for). Found and fixed on
  the way: the outgoing-recovery role byte is numbered from 1 in the reference (shield_output
  1, producer_fee 2, transfer_recipient 3, transfer_change 4, unshield_change 5); the earlier
  module had its own order and no vector covers it.
- *Flow.* `WalletViewModel+Shielded.swift`: `prepareShield` (rollup address, verifier,
  ticketer and `auth_domain` checked, the wallet and address made, a pool reserved and saved
  before any tez move), `estimateShield`, `shieldTez` (refused without the operator token so
  no tez are parked unshieldable; the deposit's hash is saved before the block is waited for;
  then `shieldPool`), `shieldPool` (waits for the credit, takes the fee of the moment, spends
  the key index on disk *before* signing, builds, proves, encodes, delivers, records the cm),
  and the scan behind the Shielded row (notes, nullifiers, pool balances; a drained pool whose
  note is seen is retired). `ShieldSheet` and "Shield tez…" in both menus; the operator token
  field in the Networks sheet. Tests: `SignetTests/ShieldedTests.swift` (BLAKE2s against the
  RFC, noble and the vectors; leaves against the bridge; the full root against the vectors;
  the store; the whole flow against an in-memory rollup that pins the public outputs and
  applies the shield; and the live Shadownet round trip `ShadownetShieldTests`).

- *Transport.* Shadownet's rollup node (`:8932`) and operator (`:8787`) serve plain HTTP.
  macOS App Transport Security blocks that from an app (curl is not subject to it), so
  `Signet/Info.plist` carries an `NSExceptionDomains` entry for exactly those two hosts.
  Note that the operator's bearer token therefore travels in the clear, as it does from the
  reference CLI; worth asking the tzel team for HTTPS on the operator before real funds.

**Done (2026-10-20): Unshield tez.**

- *Wire.* The unshield body (tag 4) is itself length-prefixed under the version and tag:
  `root ‖ nullifiers ‖ v_pub u64le ‖ fee u64le ‖ recipient ‖ cm_change ‖ proof ‖ change note? ‖
  cm_fee ‖ fee note`. The nullifier list is `u32be(36n) ‖ (u32be(32) ‖ felt)×n` (every felt in
  a list carries its own length, unlike the fixed felts of the struct), the recipient is
  `u32be(len) ‖ UTF-8`, a note is `u32be(3455) ‖ record`, and the optional change note is
  `0x00` or `0xff ‖ note`. Verified byte for byte against the reference crate's encoding of a
  two-input sample with and without change (the scratch Rust probe again; 7233 and 3774
  bytes, SHA-256s in `test/tzel-unshield.cjs`).
- *Sighash and witness.* `fold(0x02, auth_domain, root, nf_0 … nf_{n-1}, v_pub, fee,
  recipient_id, cm_change, mh_change, cm_fee, mh_fee)` with `recipient_id = H(UTF-8 of the
  tz/KT1 address)` (`accountId`); the witness is `[len, n, auth_domain, root, v_pub, fee,
  recipient_id, 9 felts per input (nf, nk_spend, auth_root, auth_pub_seed, key_idx, d_j, v,
  rseed, position), 48 commitment-path siblings per input, 16 auth-path siblings per input,
  133 signature chains per input, has_change and the change note's 7 fields (zeros when
  none), the producer note's 7 fields]`, 6 + 206n + 15 words; the kernel checks the proof's
  `2 + n + 7` public outputs in that order, bootloader-wrapped by the proving service like the
  shield's. Each input is signed with the next WOTS+ key of *its* address, so an unshield can
  spend several keys of one address. One to seven inputs, largest notes first (the reference
  wallet's selection). Change goes to a fresh address of ours (role `unshield_change`), whose
  signing tree is built first; the producer note is as for a shield.
- *Commitment-tree paths.* The reference wallet reads every note to rebuild the tree; Signet
  keeps every commitment it has scanned in the wallet (`leafCms`, 32 bytes a note) so the
  paths come from the bridge's `merklePath` with no second read, and a wallet from before the
  copy existed reads again from where the copy ends. The builder refuses a copy that does not
  hash to the rollup's `tree/root`. The kernel keeps a window of valid roots, so the head root
  is used.
- *After the rollup.* The rollup node's `/local/outbox/pending` lists every outbox message not
  yet executed: for an unshield, the ticketer's `burn` with the recipient forged as a
  Michelson contract (`00 00 ‖ pkh` for tz1, and so on; `Address.forgedContract`) and the
  amount, at an `outbox_level`. The scan marks a withdrawal applied when its nullifiers are
  spent, then matches it to the first pending message with that receiver and amount at or
  after the level it was submitted at. `/global/block/cemented/level` says how far cementation
  has come (Shadownet: head minus about 201 600 levels, the 14-day refutation window), and
  `/global/block/cemented/helpers/proofs/outbox/<level>/messages?index=<i>` returns
  `{commitment, proof}` (a `sc_rollup.node.outbox_level_not_cemented` error before then).
  Executing is Taquito's `smartRollupExecuteOutboxMessage` through the approved-limits path
  (`estimateOutboxExecution` / `sendOutboxExecution`, a signing call), from the selected
  account, which pays the fee; anyone could execute it. Not exercised live yet: nothing of
  ours is 14 days old.
- *Flow and UI.* `estimateUnshield` (fee of the moment, note selection), `unshieldTez` (scans
  again so the tree copy and the inputs are current, refuses a changed rollup fee or a spent
  input, builds the change address, spends every key index on disk before signing, proves,
  encodes, submits, and records the withdrawal as soon as the operator has it; an operator
  failure drops the record so the notes are free again, a timeout keeps it),
  `estimateWithdrawalExecution` / `executeWithdrawal`, `forgetWithdrawal` for one the operator
  never delivered. The Shielded row's figure stays the unspent notes with a "Leaving in an
  unshield" detail line for reserved ones; `UnshieldSheet` lists the withdrawals with their
  state (with the operator, queued, waiting with the time left, ready with an Execute button,
  executed with the explorer link).

**Done (2026-10-20, afternoon): Send shielded.**

- *Recipient.* The reference has no short shielded address: `tzel-wallet receive` mints a
  fresh address and prints the `PaymentAddress` JSON (`d_j`, `auth_root`, `auth_pub_seed`,
  `nk_tag`, `ek_v`, `ek_d`; the two ML-KEM-768 keys make it 2496 bytes canonical), and
  `send --to bob-address.json` takes that file. Nothing on the rollup names the recipient: a
  note is found only by the recipient's detection key. Signet therefore takes the JSON
  (pasted, or from the reference CLI's `{index, address}` wrapper), names it by a
  fingerprint, `H(canonical record)` (our convention, not the reference's, which has none),
  keeps an address book per chain in `tzel-<chain>.json`, and hands out the account's newest
  address the same way with a "New address" button that builds another signing tree.
- *Wire.* Tag 3, length-prefixed body `root ‖ nullifiers ‖ fee ‖ cm_1 ‖ cm_2 ‖ cm_3 ‖ proof ‖
  note_1 ‖ note_2 ‖ note_3`, verified against the reference crate's encoding of a
  three-input sample (10711 bytes). Sighash `fold(0x01, auth_domain, root, nf…, fee, cm_1,
  cm_2, cm_3, mh_1, mh_2, mh_3)`; witness `[len, n, auth_domain, root, fee, inputs as for an
  unshield, 3 × (cm, d_j, v, rseed, auth_root, auth_pub_seed, nk_tag, mh)]`, 4 + 206n + 24;
  public outputs `[auth_domain, root, nf…, fee, cm_1..3, mh_1..3]`. Exactly three outputs
  always: the change note is made even for zero change. Roles `transfer_recipient` (with the
  memo, up to 1024 bytes) and `transfer_change`.
- *Flow.* `prepareSpend` (shared with unshield), `estimateSendShielded`, `sendShielded`,
  `ShieldedTransfer` records (reserved notes, applied by the scan), `forgetTransfer`.
  `SendShieldedFlowTests` moves 1 tz between two accounts of one directory through the mock
  rollup and reads the memo on the other side.

**Live on Shadownet (2026-10-20, evening).** `ShadownetShieldTests` ran with the operator
token: a faucet-funded account shielded 1 tz (0.8 tz note after the two fees), unshielded
0.3 tz (applied by the rollup, change note back, outbox message waiting about 201700 blocks
for cementation), and a second test shielded 1 tz on one account and sent 0.5 tz with a memo
to another account's address; the recipient's scan found the note with the memo. Two things
learned: the teztnets faucet refuses requests in quick succession ("An error occurred"), so
the second account is funded by the first on layer 1; and two submissions through the
operator at once collide on its single injecting key (HTTP 502 with octez-client's
"Asynchronous injection failed"), so the suite is `.serialized`. Signet handles that failure
by dropping the record, which frees the notes. The third run caught a real bug: the test's
check that the first address had signed twice failed because `refreshAfterOperation` starts a
refresh 6 s and 15 s after the shield, that scan read the wallet before the unshield spent the
next WOTS+ key index, and its save at the end wrote the old index back; the next signature
would have reused a one-time key. Fixed the same evening: `ShieldedWalletStore.update` is
one locked read-change-write of the wallet on file, every key spend takes its index from that
(never from a copy read before an `await`) and checks the input is still unspent and
unreserved, the change address and new wallets go on the same way, and the scan writes with
`ShieldedWallet.merging(scan:since:)`, a three-way merge that never rolls an index, address,
pool or record back. Only the layer 1 outbox execution remains untried live, until the first
withdrawal cements in about 14 days.

**Next, in order:**
