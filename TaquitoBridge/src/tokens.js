// FA2 (TZIP-12) token transfers from the account itself: one `transfer` call per contract,
// each carrying every token of that contract going to the recipient, all in one operation
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
export function tokenTransferParams(source, to, transfersJson, tezMutez = null) {
  const transfers = typeof transfersJson === "string" ? JSON.parse(transfersJson) : transfersJson;
  if (!isAccount(source)) throw new Error(`Not an account: ${source}`);
  if (!isAccount(to)) throw new Error(`Not an account to send tokens to: ${to}`);
  if (tezMutez != null && !isMutez(tezMutez)) throw new Error(`Not an amount of tez: ${tezMutez}`);
  if (!Array.isArray(transfers) || (transfers.length === 0 && tezMutez == null)) throw new Error("No tokens to transfer");
  if (transfers.length > MAX_TOKENS_PER_TRANSFER) throw new Error(`At most ${MAX_TOKENS_PER_TRANSFER} tokens can be transferred at once`);
  const groups = new Map();
  for (const t of transfers) {
    if (!isContract(t?.contract)) throw new Error(`Not a token contract: ${t?.contract}`);
    if (!isNat(t?.tokenId)) throw new Error(`Not a token id: ${t?.tokenId}`);
    if (!isNat(t?.amount) || t.amount === "0") throw new Error(`Not an amount of tokens: ${t?.amount}`);
    if (!groups.has(t.contract)) groups.set(t.contract, []);
    groups.get(t.contract).push({ prim: "Pair", args: [{ string: to }, { prim: "Pair", args: [{ int: t.tokenId }, { int: t.amount }] }] });
  }
  const calls = [...groups].map(([contract, txs]) => ({
    kind: "transaction",
    to: contract,
    amount: 0,
    mutez: true,
    parameter: { entrypoint: "transfer", value: [{ prim: "Pair", args: [{ string: source }, txs] }] },
  }));
  if (tezMutez != null) calls.push({ kind: "transaction", to, amount: Number(tezMutez), mutez: true });
  return calls;
}

/** Fee and limits for moving `transfersJson` from `source` to `to`; nothing is signed. */
export async function estimateTokenTransfer(rpcUrl, source, publicKey, to, transfersJson, tezMutez = null) {
  const params = tokenTransferParams(source, to, transfersJson, tezMutez);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  return approvedBatchEstimate(tk, params, await tk.estimate.batch(params));
}

/**
 * Signs and injects the transfer with exactly the approved limits (S14); `{ hash, injected,
 * signedBytes }` (S15). The tokens move from the signing account: `from_` is the signer's own
 * address, so a key cannot be used to move someone else's tokens.
 */
export async function sendTokenTransfer(rpcUrl, signerSpec, to, transfersJson, limitsJson, tezMutez = null) {
  const limits = parseBatchLimits(limitsJson);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const params = tokenTransferParams(await tk.signer.publicKeyHash(), to, transfersJson, tezMutez);
  return sendApprovedBatch(tk, rpcUrl, params, limits);
}
