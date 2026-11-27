// FA2 (TZIP-12) and FA1.2 (TZIP-7) token transfers from the account itself: one FA2 `transfer`
// call per contract, each carrying every token of that contract going to the recipient, and
// one FA1.2 `transfer` per FA1.2 token, all in one operation
// group through the approved-limits path (S14, S15). A burn is the same transfer to the
// conventional burn address, which nobody holds the key to.
import { TezosToolkit } from "@tezos-x/octez.js";
import { signerFor, readOnlySigner } from "./signers.js";
import { approvedBatchEstimate, sendApprovedBatch, parseBatchLimits } from "./operations.js";

/** The address marketplaces burn to: no key hashes to it, so what goes there never moves again. */
export const BURN_ADDRESS = "tz1burnburnburnburnburnburnburjAYjjX";
/** At most this many tokens in one transfer, so the operation stays well inside the node's limits. */
export const MAX_TOKENS_PER_TRANSFER = 100;

const isContract = (s) => typeof s === "string" && /^KT1[1-9A-HJ-NP-Za-km-z]{33}$/.test(s);
const isAccount = (s) => typeof s === "string" && /^(tz[1-6]|KT1)[1-9A-HJ-NP-Za-km-z]{33}$/.test(s);
const isNat = (s) => typeof s === "string" && /^(0|[1-9][0-9]*)$/.test(s) && s.length <= 40;
const isMutez = (s) => typeof s === "string" && /^[1-9][0-9]*$/.test(s) && Number.isSafeInteger(Number(s));

/**
 * The FA2 `transfer` parameters: `[{ from_, txs: [{ to_, token_id, amount }] }]`, one call per
 * contract in the order the contracts first appear, the tokens in the order given. Checked
 * before any signer or node is touched: `to` an account, every contract a KT1, token ids and
 * amounts whole non-negative numbers (an amount of 0 is refused: it would move nothing).
 *
 * Move Assets adds `tezMutez`: a plain tez transfer of that many mutez to the same recipient,
 * last in the group, so the tokens and the tez sweep go out under one signature. With it the
 * token list may be empty; without it there must be at least one token.
 */
export function tokenTransferParams(source, to, transfersJson, tezMutez = null, recordsJson = null) {
  const transfers = typeof transfersJson === "string" ? JSON.parse(transfersJson) : transfersJson;
  if (tezMutez === "") tezMutez = null;
  const records = recordsJson == null || recordsJson === "" ? [] : (typeof recordsJson === "string" ? JSON.parse(recordsJson) : recordsJson);
  if (!isAccount(source)) throw new Error(`Not an account: ${source}`);
  if (!isAccount(to)) throw new Error(`Not an account to send tokens to: ${to}`);
  if (tezMutez != null && !isMutez(tezMutez)) throw new Error(`Not an amount of tez: ${tezMutez}`);
  if (!Array.isArray(records)) throw new Error("Not a list of domain records");
  if (!Array.isArray(transfers) || (transfers.length === 0 && tezMutez == null && records.length === 0)) throw new Error("No tokens to transfer");
  if (transfers.length > MAX_TOKENS_PER_TRANSFER) throw new Error(`At most ${MAX_TOKENS_PER_TRANSFER} tokens can be transferred at once`);
  // FA2: one call per contract, at the contract's first transfer, carrying every token of it.
  // FA1.2: one call per transfer, `transfer (pair (address :from) (pair (address :to) (nat :value)))`.
  // Tezos Domains `update_record` calls come first: only the current owner may make them, so
  // they must run before the name's token leaves the account.
  const calls = records.map((r) => domainRecordCall(r));
  const fa2 = new Map();
  const standards = new Map();
  for (const t of transfers) {
    if (!isContract(t?.contract)) throw new Error(`Not a token contract: ${t?.contract}`);
    if (!isNat(t?.tokenId)) throw new Error(`Not a token id: ${t?.tokenId}`);
    if (!isNat(t?.amount) || t.amount === "0") throw new Error(`Not an amount of tokens: ${t?.amount}`);
    const standard = t.standard == null ? "fa2" : t.standard;
    if (standard !== "fa2" && standard !== "fa1.2") throw new Error(`Not a token standard: ${t.standard}`);
    if (standards.has(t.contract) && standards.get(t.contract) !== standard) throw new Error(`One contract named as two standards: ${t.contract}`);
    standards.set(t.contract, standard);
    if (standard === "fa1.2") {
      if (t.tokenId !== "0") throw new Error(`An FA1.2 token has no token id: ${t.tokenId}`);
      calls.push({ kind: "transaction", to: t.contract, amount: 0, mutez: true,
        parameter: { entrypoint: "transfer", value: { prim: "Pair", args: [{ string: source }, { prim: "Pair", args: [{ string: to }, { int: t.amount }] }] } } });
      continue;
    }
    const tx = { prim: "Pair", args: [{ string: to }, { prim: "Pair", args: [{ int: t.tokenId }, { int: t.amount }] }] };
    if (fa2.has(t.contract)) { fa2.get(t.contract).push(tx); continue; }
    const txs = [tx];
    fa2.set(t.contract, txs);
    calls.push({ kind: "transaction", to: t.contract, amount: 0, mutez: true,
      parameter: { entrypoint: "transfer", value: [{ prim: "Pair", args: [{ string: source }, txs] }] } });
  }
  if (tezMutez != null) calls.push({ kind: "transaction", to, amount: Number(tezMutez), mutez: true });
  return calls;
}

const isHex = (s) => typeof s === "string" && /^([0-9a-f]{2})*$/.test(s) && s.length <= 4096;
const hexOf = (text) => Array.from(new TextEncoder().encode(text), (b) => b.toString(16).padStart(2, "0")).join("");
const compareBytes = (a, b) => {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  for (let i = 0; i < Math.min(x.length, y.length); i++) if (x[i] !== y[i]) return x[i] - y[i];
  return x.length - y.length;
};

/**
 * Tezos Domains' `update_record` on its UpdateRecord proxy:
 * `pair (bytes %name) (option %address address) (address %owner) (map %data string bytes)`.
 * The name is its UTF-8 bytes; the data map replaces the record's data as a whole, so callers
 * send the existing entries back. Map keys go in byte order, as Michelson requires.
 */
export function domainRecordCall(r) {
  if (!isContract(r?.proxy)) throw new Error(`Not a Tezos Domains contract: ${r?.proxy}`);
  if (typeof r.name !== "string" || r.name.length === 0 || r.name.length > 255 || r.name !== r.name.toLowerCase()) throw new Error(`Not a domain name: ${r?.name}`);
  if (!isAccount(r.owner)) throw new Error(`Not an owner: ${r.owner}`);
  if (r.address != null && !isAccount(r.address)) throw new Error(`Not an address for the domain: ${r.address}`);
  const data = r.data ?? {};
  if (typeof data !== "object" || Array.isArray(data)) throw new Error("Not domain data");
  const keys = Object.keys(data).sort(compareBytes);
  for (const k of keys) if (!isHex(data[k])) throw new Error(`Not domain data bytes: ${k}`);
  return {
    kind: "transaction", to: r.proxy, amount: 0, mutez: true,
    parameter: { entrypoint: "update_record", value: { prim: "Pair", args: [
      { bytes: hexOf(r.name) },
      { prim: "Pair", args: [
        r.address == null ? { prim: "None" } : { prim: "Some", args: [{ string: r.address }] },
        { prim: "Pair", args: [{ string: r.owner }, keys.map((k) => ({ prim: "Elt", args: [{ string: k }, { bytes: data[k] }] }))] },
      ] },
    ] } },
  };
}

/** Fee and limits for moving `transfersJson` from `source` to `to`; nothing is signed. */
export async function estimateTokenTransfer(rpcUrl, source, publicKey, to, transfersJson, tezMutez = null, recordsJson = null) {
  const params = tokenTransferParams(source, to, transfersJson, tezMutez, recordsJson);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  return approvedBatchEstimate(tk, params, await tk.estimate.batch(params));
}

/**
 * Signs and injects the transfer with exactly the approved limits (S14); `{ hash, injected,
 * signedBytes }` (S15). The tokens move from the signing account: `from_` is the signer's own
 * address, so a key cannot be used to move someone else's tokens.
 */
export async function sendTokenTransfer(rpcUrl, signerSpec, to, transfersJson, limitsJson, tezMutez = null, recordsJson = null) {
  const limits = parseBatchLimits(limitsJson);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const params = tokenTransferParams(await tk.signer.publicKeyHash(), to, transfersJson, tezMutez, recordsJson);
  return sendApprovedBatch(tk, rpcUrl, params, limits);
}
