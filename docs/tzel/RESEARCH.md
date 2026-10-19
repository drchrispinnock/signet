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
  publishes macOS binaries (Linux images only), the nightly toolchain and git-pinned Stwo
  dependencies make the build heavy, the embedded binary must be signed and notarised with the
  app, and the JSON envelope is a contract the tzel team may change. The proving service's
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

A is the only one that gives Signet a real shielded account; B is a way to demonstrate the
flow quickly. Even the balance alone needs the ML-KEM scan, so there is no cheap read-only path
without the CLI.

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
2. How should a third-party wallet obtain and rotate the operator bearer token?
3. Will `tzel-wallet` be published for macOS (arm64 and x86_64), or as a library crate with a
   stability promise? Is the `--json` envelope (schema_version 1) considered stable?
4. Where will the signed profile live (the documented URL serves HTML today), and how are
   re-originations announced?
5. Any plan for Quantumnet or Ushuaianet again?

## Sources

- https://github.com/trilitech/tzel (README, `docs/shadownet_tutorial.md`, `specs/spec.md`,
  `apps/wallet/src/lib.rs`, `tezos/tez_bridge_ticketer.tz`, `docs/wallet-install.sh`)
- `trilitech/tzel-infra` (internal): `ARCHITECTURE.md`, `docs/adrs/002-daemon-as-cli-wrapper.md`,
  `docs/tzel-wallet-design.md`, `docker/wallet-bundle/*`, `services/wallet/src/*`
- https://tzel.tezos.com/wallet.html
- Live: rollup node, operator, proving service, Shadownet RPC and TzKT, all on 2026-10-19
