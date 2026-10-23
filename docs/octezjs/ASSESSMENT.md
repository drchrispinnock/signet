# Replacing Taquito with octez.js: assessment

Written 2026-10-23 against Taquito 25.1.0-beta0 (what the bridge ships) and
`@tezos-x/octez.js` 25.0.0 (released 2026-10-21). Nothing here is implemented; the bridge still
builds on Taquito. The experiment lived in a scratch copy of `TaquitoBridge/` and is
reproducible from section 3.

## 1. Verdict

octez.js is a drop-in replacement for everything the bridge uses. No feature Signet depends on
is missing, forged bytes and live estimates are identical, and every offline bridge suite passes
on it. The choice is about which maintainer to bet on, not about capability. The recommendation
is to stay on Taquito for now and keep this as a one-afternoon switch (section 5) to make when
octez.js carries something Taquito lacks, or when Taquito stops tracking protocols.

## 2. What octez.js is

- Trilitech's and Nomadic Labs' fork of Taquito, published under the `@tezos-x` scope, Apache-2.0,
  Node 22+. Since 25.0.0 the major version tracks the Octez node release line.
- Package for package it mirrors Taquito: `octez.js` (toolkit), `-signer`, `-ledger-signer`,
  `-local-forging`, `-michel-codec`, `-michelson-encoder`, `-rpc`, `-utils`, `-core`,
  `-http-utils`, plus `-remote-signer`, `-sapling`, `-timelock`, `-tzip12`, `-tzip16`,
  `-wallet-connect`, `-dapp-wallet` (the dApp side of Octez Connect; irrelevant to a wallet) and
  `-contracts-library`.
- It is not a rewrite. A weekly `taquito-sync` job backports upstream Taquito commits, each
  tagged with an `Upstream-Commit:` trailer (PR #145); PR #137 backported ten commits including
  tz5 (ML-DSA-44). The high-water mark on 2026-10-18 was Taquito commit `784879487`.
- Its own additions: Tezos X cross-runtime helpers in `-utils` (`getEthereumAlias`,
  `getTezosAlias`, `buildMichelsonToEvmCall`, `buildEvmToMichelsonCall`, NAC constants; these
  pull in `viem`), a configurable confirmation look-back, `OCTEZJS_*` diagnostic variables
  (`TAQUITO_*` still work, deprecated), and removal of the Tallinnnet and Ghostnet constants.
- Maintenance picture. ECAD Labs says the Tezos Foundation stopped funding Taquito and
  Signatory, that Taquito continues "best effort", and that the Foundation suggested Trilitech or
  Nomadic take it over; it also says the fork predates the end of its funding and that pressure
  on funded teams to migrate "was walked back". The Beacon docs team switched to octez.js,
  reverted when Taquito turned out to still be maintained, and proposed switching for good on
  2026-10-08 (PR closed the same day as opened by mistake). Both repositories had four
  contributors in their last hundred commits; octez.js had 100 commits and Taquito 57 in the
  month to 2026-10-22. Taquito 25.1.0 final shipped 2026-10-19.

## 3. What was checked

A copy of `TaquitoBridge/` (without `node_modules`) with every import rewritten:
`@taquito/taquito` to `@tezos-x/octez.js`, `@taquito/<pkg>` to `@tezos-x/octez.js-<pkg>`, in the
8 sources, 7 tests and `package.json`; `^25.1.0-beta0` to `^25.0.0`.

| Check | Result |
|---|---|
| `npm run build` (esbuild, safari17 target) | builds; 1,225,973 bytes against 1,206,215 shipped (+20 KB) |
| `viem` in the bundle | tree-shaken out; none of its symbols appear |
| `npm test`, all 12 suites (dApp prepared/identity, approved limits, audit boundaries, bridge, signing-exports scan, confirmation, read-only signer, tzel shield/unshield/transfer) | all pass |
| `test/tzel-vectors.cjs` with `TZEL_VECTORS` | 173 checks pass |
| Export names of `signer`, `ledger-signer`, `local-forging`, `rpc`, `michel-codec` | identical |
| `utils` exports | superset (26 Tezos X additions, nothing removed) |
| `TezosToolkit.estimate` / `prepare` / `contract` methods | 29 / 39 / 29 in both; `prepare.getAutomaticRevealFee` renamed `getRevealLimits` (not used by the bridge) |
| `RpcClient` methods | 63 in both, same names |
| `InMemorySigner.fromMnemonic`, `fromFundraiser` | same addresses |
| `localForger.forge` for transfer, transfer with parameters, reveal tz1/tz2/tz3, delegation, undelegation, origination, update_consensus_key, update_companion_key, ballot, proposals, smart_rollup_execute_outbox_message | identical bytes (and identical refusals of invalid inputs) |
| `getPkhfromPk`, `validateAddress` | identical |
| Ledger signer dist | differs only in package names and error base class |
| Live Shadownet: `estimateTransfer` and `estimateStakingOperation(setDelegate)` through both built bundles for the same funded account | identical fee, gas, storage and limits |

Octez Connect is untouched: Signet already takes `@tezos-x/octez.connect-wallet` 5.0.4 from the
same organisation, and octez.js's `-dapp-wallet` is the dApp side.

## 4. Differences and gaps found

- **octez.js trails Taquito by its backport lag.** 25.0.0 was cut from an older base than
  Taquito 25.1.0; Taquito already maps protocol 026 to ProtoALpha, octez.js does not.
- **tz5 reveal gas constant** is 212 in Taquito and 213 in octez.js. Harmless under the
  approved-limits path (S14), but tz5 figures shown in the UI would move by one gas unit.
- **Dependency hoisting differs.** The bridge imports `@scure/bip39`, `@noble/curves`,
  `@noble/hashes`, `@noble/post-quantum`, `@noble/ciphers`, `@stablelib/nacl` and `bs58check`
  directly but only declares what Taquito drags in; with octez.js `@scure/bip39` was not hoisted
  and the build failed until they were declared. They should be declared either way.
- **Documentation is thin**: octez-js.tezos.com has a quick start, wallet API and contracts
  pages and no migration guide. Taquito's docs remain the reference for both.
- **`viem`** (63 MB in `node_modules`) becomes a transitive dependency of `-utils`. It does not
  reach the bundle, but it widens the supply chain the lockfile pins.

## 5. What a switch would take

1. The import rewrite above, plus the explicit crypto dependencies, in `TaquitoBridge/`.
2. `npm install && npm run build`, commit the bundle (the release workflow checks it matches a
   clean build of the lockfile).
3. Live runs on Shadownet: `BLSSendTests`, `ShadownetMultisigTests`, `ShadownetDAppPrepareTests`,
   `ShadownetBridgeTests`, `EtherlinkLiveTests`, `ShadownetShieldTests`, and a Ledger signing by
   hand.
4. Optional: the 44 Swift files naming `TaquitoBridge`, `TaquitoChainService` and
   `taquito-bridge.js` can keep their names; CLAUDE.md, the About credits and this document would
   want a sentence.

Things octez.js would give that Taquito does not, should they become wanted: the Tezos X alias
and NAC call helpers (Signet computes the Etherlink alias itself in `Keccak.swift` /
`EtherlinkAlias`) and release numbering aligned with the Octez node and Octez Connect.

## 6. Sources

- https://github.com/trilitech/octez.js and its v25.0.0 release notes
- https://github.com/trilitech/octez.js/pull/137 (backports and tz5), /pull/145 (taquito-sync)
- https://www.npmjs.com/package/@tezos-x/octez.js
- https://github.com/ecadlabs/taquito/releases
- https://github.com/airgap-it/beacon-docs/pull/71
- https://forum.tezosagora.org/t/signatory-remote-signer-end-of-ecad-labs-maintenance/7093
- https://octez-js.tezos.com/
