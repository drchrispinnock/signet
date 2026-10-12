// Tez between Tezos layer 1 and the Michelson interface of Etherlink (Tezos X).
//
// A deposit is an ordinary layer 1 transfer to Etherlink's bridge helper contract
// (`deposit %evm_address %l2_address`, tez attached): the helper wraps the tez in a ticket and
// hands it to the Smart Rollup with routing data. For a Michelson-interface account the routing
// data is version 1 RLP naming the implicit receiver, exactly as baking-bad's
// `xtz_deposit_michelson.py` builds it: `0x01 ++ rlp([[0x01, forged tz address], []])`. The
// kernel refuses originated (KT1) receivers, and tz4 keys are not on the rollup yet.
// Withdrawals from Michelson-interface accounts are not offered by Etherlink yet (October 2026).

import { TezosToolkit } from "@taquito/taquito";
import { signerFor } from "./signers.js";
import { encodedPublicKeyHash } from "./rawforge.js";
import { approvedEstimate, sendApproved, parseLimits } from "./operations.js";

function readOnlySigner(publicKey, address) {
  return {
    publicKey: async () => publicKey,
    publicKeyHash: async () => address,
    secretKey: async () => undefined,
    sign: async () => { throw new Error("read-only signer cannot sign"); },
  };
}

/** RLP of a byte string (RLP spec: single bytes below 0x80 stand for themselves). */
function rlpBytes(bytes) {
  if (bytes.length === 1 && bytes[0] < 0x80) return bytes;
  if (bytes.length > 55) throw new Error("routing data item too long");
  return new Uint8Array([0x80 + bytes.length, ...bytes]);
}

/** RLP of a list whose encoded payload is short (under 56 bytes), which is all the bridge needs. */
function rlpList(items) {
  const payload = items.flatMap((item) => Array.from(item));
  if (payload.length > 55) throw new Error("routing data too long");
  return new Uint8Array([0xc0 + payload.length, ...payload]);
}

const hex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
const fromHex = (text) => Uint8Array.from(text.match(/../g), (b) => parseInt(b, 16));

/**
 * The `l2_address` bytes for a deposit to `receiver` on the Michelson interface, as hex.
 * Only tz1, tz2 and tz3 receivers: the rollup has no tz4 yet and refuses contracts.
 */
export function michelsonRoutingData(receiver) {
  if (!/^tz[123][1-9A-HJ-NP-Za-km-z]{33}$/.test(receiver)) {
    throw new Error(`The Etherlink receiver must be a tz1, tz2 or tz3 account, not ${receiver}`);
  }
  // Octez's forged implicit address: 0x00 (implicit) ++ curve tag ++ 20-byte hash.
  const forged = fromHex("00" + encodedPublicKeyHash(receiver));
  const routing = rlpList([rlpList([rlpBytes(new Uint8Array([1])), rlpBytes(forged)]), rlpList([])]);
  return "01" + hex(routing);
}

function checkedMutez(amountMutez) {
  const text = String(amountMutez);
  if (!/^\d{1,20}$/.test(text) || BigInt(text) === 0n) throw new Error(`Invalid deposit amount: ${JSON.stringify(amountMutez)}`);
  return Number(text);
}

function depositParams(helper, rollup, receiver, amountMutez) {
  if (!/^KT1[1-9A-HJ-NP-Za-km-z]{33}$/.test(helper)) throw new Error(`Not a bridge contract: ${helper}`);
  if (!/^sr1[1-9A-HJ-NP-Za-km-z]{33}$/.test(rollup)) throw new Error(`Not a Smart Rollup address: ${rollup}`);
  return {
    to: helper,
    amount: checkedMutez(amountMutez),
    mutez: true,
    parameter: { entrypoint: "deposit", value: { prim: "Pair", args: [{ string: rollup }, { bytes: michelsonRoutingData(receiver) }] } },
  };
}

/** Fee, burn and limits for depositing `amountMutez` from `source` to `receiver` on Etherlink. */
export async function estimateEtherlinkDeposit(rpcUrl, source, publicKey, helper, rollup, receiver, amountMutez) {
  const params = depositParams(helper, rollup, receiver, amountMutez);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  return approvedEstimate(tk, "transaction", params, await tk.estimate.transfer(params));
}

/** Signs and injects the deposit with exactly the approved limits (S14); `{ hash, injected, signedBytes }` (S15). */
export async function sendEtherlinkDeposit(rpcUrl, signerSpec, helper, rollup, receiver, amountMutez, limitsJson) {
  const params = depositParams(helper, rollup, receiver, amountMutez);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  return sendApproved(tk, rpcUrl, "transaction", params, parseLimits(limitsJson));
}
