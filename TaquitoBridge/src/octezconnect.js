// Octez Connect (TZIP-10, the Beacon fork) wallet side, running inside JavaScriptCore.
//
// Swift owns the UI and the keys. This module owns the WalletClient: pairing with dApps over the
// Matrix relay, receiving requests, and sending responses. Requests are forwarded to Swift through
// `__signet.octezConnectEvent(json)`; Swift answers with `respond(json)`. Storage is a key/value
// file Swift provides through `__signet.storageGet/Set/Delete` so sessions survive restarts.

import { WalletClient } from "@tezos-x/octez.connect-wallet";
import { Serializer, setDebugEnabled } from "@tezos-x/octez.connect-core";
import { Storage, defaultValues as storageDefaults } from "@tezos-x/octez.connect-types";
import { TezosToolkit } from "@taquito/taquito";
import { signerFor } from "./signers.js";
import { RpcClient } from "@taquito/rpc";
import { localForger } from "@taquito/local-forging";

class NativeStorage extends Storage {
  static async isSupported() { return true; }
  async get(key) {
    const raw = globalThis.__signet.storageGet(key);
    if (raw == null) {
      // Missing keys must yield the SDK's typed defaults (e.g. [] for peer lists), as its own
      // LocalStorage does; a fresh copy so the SDK cannot mutate the shared default.
      const fallback = storageDefaults[key];
      return fallback === undefined ? undefined : JSON.parse(JSON.stringify(fallback));
    }
    try { return JSON.parse(raw); } catch { return raw; }
  }
  async set(key, value) { globalThis.__signet.storageSet(key, JSON.stringify(value)); }
  async delete(key) { globalThis.__signet.storageDelete(key); }
  async subscribeToStorageChanged() {}
  getPrefixedKey(key) { return key; }
}

let client = null;
const peersById = new Map();

function emit(event) {
  globalThis.__signet.octezConnectEvent(JSON.stringify(event));
}

/** Creates the WalletClient, restores stored peers and starts listening. Idempotent. */
export async function octezConnectStart(appName, iconUrl, debug) {
  if (client) return { started: true };
  if (debug) setDebugEnabled(true);
  const fresh = new WalletClient({ name: appName, iconUrl: iconUrl || undefined, storage: new NativeStorage() });
  let transport;
  try {
    transport = await fresh.init();
  } catch (error) {
    console.error("octez.connect: init failed", error);
    throw error;
  }
  client = fresh;
  console.log("octez.connect: wallet client initialised, transport", transport);
  await client.connect((message, context) => {
    console.log("octez.connect: request received", message?.type, message?.id, "from", message?.appMetadata?.name);
    try {
      emit({ kind: "request", message, context: { origin: context?.origin, id: context?.id } });
    } catch (error) {
      console.error("octez.connect: failed to forward request", error);
    }
  });
  console.log("octez.connect: listening for dApp requests");
  installRelayDiagnostics(client).catch((e) => console.warn("octez.connect: diagnostics not installed", e?.message ?? e));
  return { started: true };
}

/**
 * Logs every relay message as it arrives and tries the SDK's own decryption for each known peer,
 * so a message the SDK drops silently (it swallows decryption errors) shows up with a reason.
 */
async function installRelayDiagnostics(wallet) {
  const transport = await wallet.transport;
  const p2p = transport?.client;
  const matrix = await p2p?.client?.promise;
  if (!matrix || typeof matrix.subscribe !== "function") { console.log("octez.connect: no matrix client to watch"); return; }
  matrix.subscribe("message", async (event) => {
    try {
      const m = event?.content?.message ?? {};
      const body = String(m.content ?? "");
      console.log("relay message:", "room", event?.content?.roomId, "sender", m.sender, "len", body.length, "head", body.slice(0, 24));
      if (!/^[0-9a-f]+$/i.test(body)) { console.log("relay message: not hex, pairing/channel-open traffic"); return; }
      const peers = await wallet.getPeers();
      const keyPair = p2p.keyPair;
      for (const peer of peers) {
        const expectedSender = `@${await getHexHash(Buffer.from(peer.publicKey, "hex"))}:${peer.relayServer}`;
        const sameSender = m.sender === expectedSender || String(m.sender).startsWith(expectedSender.split(":")[0]);
        try {
          const keys = await createReceiverSessionKey(keyPair, peer.publicKey);
          const text = await decryptCryptoboxPayload(Buffer.from(body, "hex"), keys.receive);
          console.log("relay message: decrypts for peer", peer.name, "sender match", sameSender, "expected", expectedSender, "text head", String(text).slice(0, 80));
        } catch (e) {
          console.log("relay message: does NOT decrypt for peer", peer.name, "sender match", sameSender, "expected", expectedSender, "reason", e?.message ?? String(e));
        }
      }
    } catch (e) {
      console.log("relay diagnostics error", e?.message ?? e);
    }
  });
  console.log("octez.connect: relay diagnostics installed");
}

/** Pairs with a dApp from the code it shows under "pair with another wallet". */
export async function octezConnectPair(pairingCode) {
  if (!client) throw new Error("Octez Connect is not started");
  const peer = await new Serializer().deserialize(pairingCode.trim());
  if (!peer || !peer.publicKey || !peer.relayServer) throw new Error("That is not an Octez Connect pairing code");
  // addPeer with sendPairingResponse waits for the dApp to join the relay room, which can take a
  // while (or never happen if the dApp was closed). Do not hold the UI on it.
  client.addPeer(peer, true).catch((error) => {
    emit({ kind: "error", message: `Pairing with ${peer.name} failed: ${error?.message ?? error}` });
  });
  peersById.set(peer.id, peer);
  return { id: peer.id, name: peer.name, icon: peer.icon ?? null, appUrl: peer.appUrl ?? null, relayServer: peer.relayServer };
}

export async function octezConnectRespond(responseJson) {
  if (!client) throw new Error("Octez Connect is not started");
  await client.respond(JSON.parse(responseJson));
  return { ok: true };
}

export async function octezConnectPermissions() {
  if (!client) return [];
  return client.getPermissions();
}

export async function octezConnectRemovePermission(accountIdentifier, senderId) {
  if (!client) return { ok: false };
  await client.removePermission(accountIdentifier, senderId);
  return { ok: true };
}

export async function octezConnectPeers() {
  if (!client) return [];
  return client.getPeers();
}

export async function octezConnectRemovePeer(peerJson) {
  if (!client) return { ok: false };
  await client.removePeer(JSON.parse(peerJson), true);
  return { ok: true };
}

export async function octezConnectRemoveAll() {
  if (!client) return { ok: false };
  await client.removeAllPeers(true);
  await client.removeAllPermissions();
  return { ok: true };
}

// ---- Doing what dApps ask --------------------------------------------------------------------

/** Maps a TZIP-10 partial operation onto Taquito batch params (without fee, gas or storage). */
function toTaquitoParams(op) {
  switch (op.kind) {
    case "transaction":
      return {
        kind: "transaction",
        to: op.destination,
        amount: Number(op.amount || 0),
        mutez: true,
        ...(op.parameters ? { parameter: op.parameters } : {}),
      };
    case "delegation":
      return { kind: "delegation", delegate: op.delegate || undefined };
    case "origination":
      return { kind: "origination", code: op.script?.code, init: op.script?.storage, balance: Number(op.balance || 0), mutez: true };
    default:
      throw new Error(`Operation kind "${op.kind}" is not supported by Signet yet`);
  }
}

function readOnlySigner(publicKey, address) {
  return {
    publicKey: async () => publicKey,
    publicKeyHash: async () => address,
    secretKey: async () => undefined,
    sign: async () => { throw new Error("read-only signer cannot sign"); },
  };
}

const mutezString = (v) => String(BigInt(Math.round(Number(v) || 0)));

/**
 * Fills in fee, gas and storage for every operation from the node's simulation and sums up what
 * the account will pay. The dApp's own fee/gas/storage are not used: the fee is the node's
 * estimate (a dApp asking for more is reported, not obeyed), and gas/storage are what the
 * simulation needed. `estimates` is one per operation, with a reveal estimate first when the
 * account has not revealed its key yet. Returns the exact params to execute plus the figures.
 */
export function buildPrepared(ops, estimates) {
  const params = ops.map(toTaquitoParams);
  let reveal = null;
  let perOp = estimates;
  if (estimates.length === params.length + 1) {
    reveal = estimates[0];
    perOp = estimates.slice(1);
  } else if (estimates.length !== params.length) {
    throw new Error(`The node returned ${estimates.length} estimates for ${params.length} operations`);
  }
  let amount = 0n, fee = 0n, burn = 0n;
  const prepared = params.map((p, i) => {
    const e = perOp[i];
    const withLimits = { ...p, fee: Number(e.suggestedFeeMutez), gasLimit: Number(e.gasLimit), storageLimit: Number(e.storageLimit) };
    fee += BigInt(withLimits.fee);
    burn += BigInt(mutezString(e.burnFeeMutez));
    if (p.kind === "transaction") amount += BigInt(mutezString(p.amount));
    if (p.kind === "origination") amount += BigInt(mutezString(p.balance));
    return withLimits;
  });
  const operations = ops.map((op, i) => {
    const e = perOp[i];
    const requested = op.fee != null ? BigInt(mutezString(op.fee)) : null;
    return {
      ...describeOperation(op),
      feeMutez: String(prepared[i].fee),
      burnMutez: mutezString(e.burnFeeMutez),
      gasLimit: Number(e.gasLimit),
      storageLimit: Number(e.storageLimit),
      requestedFeeMutez: requested != null && requested > BigInt(prepared[i].fee) ? String(requested) : null,
    };
  });
  let revealFee = null;
  if (reveal) {
    revealFee = { feeMutez: String(reveal.suggestedFeeMutez), burnMutez: mutezString(reveal.burnFeeMutez) };
    fee += BigInt(revealFee.feeMutez);
    burn += BigInt(revealFee.burnMutez);
  }
  return {
    operations,
    reveal: revealFee,
    totalAmountMutez: String(amount),
    totalFeeMutez: String(fee),
    totalBurnMutez: String(burn),
    totalDebitMutez: String(amount + fee + burn),
    prepared: JSON.stringify(prepared),
  };
}

/** Test hook for `buildPrepared` with synthetic estimates. */
export async function octezConnectBuildPrepared(operationsJson, estimatesJson, operationJson) {
  const ops = JSON.parse(operationsJson), estimates = JSON.parse(estimatesJson);
  return operationJson == null ? buildPrepared(ops, estimates) : freezePrepared(ops, estimates, JSON.parse(operationJson));
}

/** Bind the approval figures to the actual contents, including Taquito's automatic reveal. */
function freezePrepared(ops, estimates, operation) {
  const contents = operation.contents;
  const hasReveal = contents?.[0]?.kind === "reveal";
  if (!Array.isArray(contents) || contents.length !== ops.length + (hasReveal ? 1 : 0)) throw new Error("Unexpected prepared operation count");
  const perOp = estimates.length === ops.length + 1 ? estimates.slice(1) : estimates;
  if (perOp.length !== ops.length) throw new Error("Unexpected estimate count");
  const actualEstimates = contents.map((c, i) => ({
    suggestedFeeMutez: checkedLimit(c.fee), gasLimit: checkedLimit(c.gas_limit), storageLimit: checkedLimit(c.storage_limit),
    burnFeeMutez: hasReveal && i === 0 ? 0 : perOp[i - (hasReveal ? 1 : 0)].burnFeeMutez,
  }));
  const result = buildPrepared(ops, actualEstimates);
  result.prepared = JSON.stringify(operation);
  return result;
}

function checkedLimit(value) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) throw new Error("Invalid operation limit");
  return number;
}

/**
 * Simulates a dApp's operation request from `source` (read-only: no key involved) so the
 * approval sheet can show exact fees, burn, totals and effects before anything is signed.
 */
export async function octezConnectPrepare(rpcUrl, source, publicKey, operationsJson) {
  const ops = JSON.parse(operationsJson);
  if (!Array.isArray(ops) || ops.length === 0) throw new Error("The dApp sent no operations");
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  const estimates = await tk.estimate.batch(ops.map(toTaquitoParams));
  const figures = buildPrepared(ops, estimates);
  const perOp = estimates.length === ops.length + 1 ? estimates.slice(1) : estimates.slice();
  const { opOb } = await tk.prepare.batch(JSON.parse(figures.prepared), perOp);
  // Local forging must succeed before the user can approve this immutable operation.
  await localForger.forge({ branch: opOb.branch, contents: opOb.contents });
  return freezePrepared(ops, estimates, opOb);
}

/**
 * Signs and injects a prepared batch, exactly as prepared: every operation must carry the fee,
 * gas and storage the user saw, so nothing is re-estimated or taken from the dApp here.
 */
export async function octezConnectExecute(rpcUrl, signerSpec, preparedJson) {
  const operation = JSON.parse(preparedJson);
  const { branch, contents, protocol } = operation;
  if (typeof branch !== "string" || typeof protocol !== "string" || !Array.isArray(contents) || contents.length === 0) throw new Error("This batch was not prepared");
  for (const [i, op] of contents.entries()) {
    if (!["transaction", "delegation", "origination"].includes(op.kind) && !(i === 0 && op.kind === "reveal")) throw new Error(`Operation kind "${op.kind}" is not supported`);
    for (const field of ["fee", "gas_limit", "storage_limit", "counter"]) checkedLimit(op[field]);
  }
  const forged = await localForger.forge({ branch, contents });
  const signer = await signerFor(signerSpec);
  const source = await signer.publicKeyHash();
  if (contents.some(c => c.source !== source)) throw new Error("The prepared source is not the signing account");
  if (contents[0].kind === "reveal" && contents[0].public_key !== await signer.publicKey()) throw new Error("The prepared reveal is not the signing key");
  const { prefixSig, sbytes } = await signer.sign(forged, new Uint8Array([3]));
  const rpc = new RpcClient(rpcUrl);
  const replies = await rpc.preapplyOperations([{ branch, contents, protocol, signature: prefixSig }]);
  const results = replies.flatMap(r => r.contents ?? []);
  if (results.length !== contents.length || results.some(c => c.metadata?.operation_result?.status !== "applied")) throw new Error("The prepared batch was not applied; prepare it again before approving");
  return { hash: await rpc.injectOperation(sbytes) };
}

// ---- Describing operations --------------------------------------------------------------------

/** A Pair tree flattened into its leaves, right-comb style: Pair a (Pair b c) → [a, b, c]. */
function pairLeaves(node) {
  if (node?.prim === "Pair" && Array.isArray(node.args)) {
    const out = [];
    node.args.forEach((a, i) => { if (i === node.args.length - 1) out.push(...pairLeaves(a)); else out.push(a); });
    return out;
  }
  return [node];
}
const text = (node) => (typeof node?.string === "string" ? node.string : typeof node?.bytes === "string" ? "0x" + node.bytes : typeof node?.int === "string" ? node.int : JSON.stringify(node));
const isInt = (node) => typeof node?.int === "string";
const isAddr = (node) => typeof node?.string === "string" || typeof node?.bytes === "string";

/**
 * What a contract call does, for the standards a wallet must not hide: FA2 and FA1.2 transfers,
 * FA2 operator changes and FA1.2 allowances. Anything else is described by entrypoint only; the
 * raw parameters are shown alongside either way.
 */
export function contractEffects(destination, entrypoint, value) {
  const effects = [];
  const warn = (t) => effects.push({ text: t, warning: true });
  const note = (t) => effects.push({ text: t, warning: false });
  try {
    if (entrypoint === "transfer" && Array.isArray(value)) {
      // FA2: list of (from_, list of (to_, token_id, amount)).
      for (const batch of value) {
        const [from, txs] = pairLeaves(batch);
        if (!isAddr(from) || !Array.isArray(txs)) return [];
        for (const tx of txs) {
          const [to, tokenId, amount] = pairLeaves(tx);
          if (!isAddr(to) || !isInt(tokenId) || !isInt(amount)) return [];
          warn(`Send ${text(amount)} of token ${text(tokenId)} in ${destination} from ${text(from)} to ${text(to)}`);
        }
      }
      return effects;
    }
    if (entrypoint === "transfer") {
      // FA1.2: (from, to, value).
      const [from, to, amount] = pairLeaves(value);
      if (isAddr(from) && isAddr(to) && isInt(amount)) { warn(`Send ${text(amount)} units of the token ${destination} from ${text(from)} to ${text(to)}`); return effects; }
      return [];
    }
    if (entrypoint === "update_operators" && Array.isArray(value)) {
      for (const change of value) {
        const add = change?.prim === "Left", remove = change?.prim === "Right";
        if (!add && !remove) return [];
        const [owner, operator, tokenId] = pairLeaves(change.args?.[0]);
        if (!isAddr(owner) || !isAddr(operator) || !isInt(tokenId)) return [];
        if (add) warn(`Allow ${text(operator)} to move token ${text(tokenId)} in ${destination} owned by ${text(owner)}`);
        else note(`Stop ${text(operator)} moving token ${text(tokenId)} in ${destination} owned by ${text(owner)}`);
      }
      return effects;
    }
    if (entrypoint === "approve") {
      const [spender, amount] = pairLeaves(value);
      if (isAddr(spender) && isInt(amount)) { warn(`Allow ${text(spender)} to spend ${text(amount)} units of the token ${destination}`); return effects; }
      return [];
    }
  } catch {
    return [];
  }
  return [];
}

function describeOperation(op) {
  switch (op.kind) {
    case "transaction": {
      const entrypoint = op.parameters?.entrypoint ?? (typeof op.destination === "string" && op.destination.startsWith("KT1") ? "default" : null);
      const value = op.parameters?.value;
      const isContract = typeof op.destination === "string" && op.destination.startsWith("KT1");
      return {
        kind: "transaction",
        destination: op.destination,
        amountMutez: mutezString(op.amount),
        entrypoint,
        parameters: op.parameters ? JSON.stringify(op.parameters.value ?? op.parameters, null, 1) : isContract ? JSON.stringify({ prim: "Unit" }) : null,
        effects: isContract && entrypoint ? contractEffects(op.destination, entrypoint, value) : [],
        // A call to a contract Signet cannot read is something the user approves blind.
        opaque: isContract && (!entrypoint || contractEffects(op.destination, entrypoint, value).length === 0),
      };
    }
    case "delegation": return { kind: "delegation", delegate: op.delegate || null, parameters: null, effects: [], opaque: false };
    case "origination": return {
      kind: "origination", balanceMutez: mutezString(op.balance),
      parameters: op.script ? JSON.stringify({ code: op.script.code, storage: op.script.storage }, null, 1) : null,
      effects: [{ text: "Deploys a new contract with the code and storage shown", warning: true }], opaque: true,
    };
    default: return { kind: op.kind, parameters: null, effects: [], opaque: true };
  }
}

/** Summary of a batch for the approval sheet, without the node (no fees); `octezConnectPrepare` adds those. */
export function octezConnectDescribe(operationsJson) {
  return JSON.parse(operationsJson).map(describeOperation);
}

/**
 * Why a sign_payload request must not be signed, or null. Signing hashes the raw bytes, and so
 * does the chain for operations (with a 03 watermark in front), so hex starting with 03 is an
 * operation signature. Only `micheline` payloads starting with 05, the packed-data prefix no
 * operation uses, and that decode as exactly one Micheline expression, are signed. Swift applies
 * the same rule before the request is shown.
 */
export function signPayloadRefusal(signingType, payload) {
  if (signingType !== "micheline") return `Signet only signs "micheline" messages, not "${signingType}"`;
  if (typeof payload !== "string" || payload.length === 0 || payload.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(payload)) return "the message is not valid hex";
  if (payload.length > 64 * 1024) return "the message is too long";
  if (!payload.startsWith("05")) return "the message is not packed Michelson data (no 05 prefix), so it could be an operation";
  if (!isPackedMicheline(payload)) return "the message is not one complete packed Michelson expression";
  return null;
}

/** Signs a payload for a sign_payload request. `payload` is the hex the dApp sent. */
export async function octezConnectSign(signerSpec, payload, signingType) {
  const why = signPayloadRefusal(signingType, payload);
  if (why) throw new Error(`refused to sign: ${why}`);
  const signer = await signerFor(signerSpec);
  const { prefixSig } = await signer.sign(payload);
  return { signature: prefixSig };
}

/** Test helper: a pairing code for a synthetic dApp, as a dApp's SDK would produce. */
export async function octezConnectMakePairingCode(peerJson) {
  return new Serializer().serialize(JSON.parse(peerJson));
}


/** Stops the wallet client so a later start creates a fresh one (tests, storage changes). */
export async function octezConnectStop() {
  if (!client) return { stopped: false };
  // Never call destroy(): it wipes the SDK's storage (seed, peers, permissions). Just drop the
  // transport connection and forget the instance.
  try {
    const transport = await client.transport;
    await transport?.disconnect?.();
  } catch (error) {
    console.warn("octez.connect: disconnect failed", error?.message ?? error);
  }
  client = null;
  peersById.clear();
  return { stopped: true };
}

// ---- Diagnostics -------------------------------------------------------------------------------
import { getKeypairFromSeed, createSenderSessionKey, createReceiverSessionKey, encryptCryptoboxPayload, decryptCryptoboxPayload, sealCryptobox, openCryptobox, toHex, getHexHash } from "@tezos-x/octez.connect-utils";
import { isPackedMicheline } from "./micheline.js";

/**
 * Round-trips the SDK's own crypto inside this runtime: a "dApp" keypair seals a pairing payload
 * for the "wallet", then both derive session keys and the dApp's secretbox message is opened by
 * the wallet. Surfaces the error the SDK would otherwise swallow when a message cannot be read.
 */
export async function octezConnectCryptoSelfTest() {
  const wallet = await getKeypairFromSeed("signet-selftest-wallet");
  const dapp = await getKeypairFromSeed("signet-selftest-dapp");
  const walletPk = toHex(wallet.publicKey);
  const dappPk = toHex(dapp.publicKey);
  const sealed = await sealCryptobox(JSON.stringify({ hello: "wallet" }), Buffer.from(walletPk, "hex"));
  const opened = await openCryptobox(Buffer.from(sealed, "hex"), wallet.publicKey, wallet.secretKey);
  const dappSend = await createSenderSessionKey(dapp, walletPk);     // dApp → wallet
  const walletRecv = await createReceiverSessionKey(wallet, dappPk); // wallet ← dApp
  const encrypted = await encryptCryptoboxPayload("permission please", dappSend.send);
  const decrypted = await decryptCryptoboxPayload(Buffer.from(encrypted, "hex"), walletRecv.receive);
  return { sealedRoundTrip: opened === JSON.stringify({ hello: "wallet" }), sessionRoundTrip: decrypted === "permission please", walletPk, dappPk };
}
