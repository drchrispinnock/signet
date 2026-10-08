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

/** Maps TZIP-10 partial operations onto Taquito batch params. */
function toTaquitoParams(op) {
  switch (op.kind) {
    case "transaction":
      return {
        kind: "transaction",
        to: op.destination,
        amount: Number(op.amount || 0),
        mutez: true,
        ...(op.parameters ? { parameter: op.parameters } : {}),
        ...(op.fee ? { fee: Number(op.fee) } : {}),
        ...(op.gas_limit ? { gasLimit: Number(op.gas_limit) } : {}),
        ...(op.storage_limit ? { storageLimit: Number(op.storage_limit) } : {}),
      };
    case "delegation":
      return { kind: "delegation", delegate: op.delegate || undefined };
    case "origination":
      return { kind: "origination", code: op.script?.code, init: op.script?.storage, balance: Number(op.balance || 0), mutez: true };
    default:
      throw new Error(`Operation kind "${op.kind}" is not supported by Signet yet`);
  }
}

/** Signs and injects a dApp's operation request. Returns the operation hash. */
export async function octezConnectExecute(rpcUrl, signerSpec, operationsJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  const ops = JSON.parse(operationsJson).map(toTaquitoParams);
  const batch = tk.contract.batch(ops);
  const op = await batch.send();
  return { hash: op.hash };
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

/** Human summary of a batch for the approval sheet. */
export function octezConnectDescribe(operationsJson) {
  return JSON.parse(operationsJson).map((op) => {
    switch (op.kind) {
      case "transaction": {
        const entrypoint = op.parameters?.entrypoint;
        return { kind: "transaction", destination: op.destination, amountMutez: String(op.amount || 0), entrypoint: entrypoint || null };
      }
      case "delegation": return { kind: "delegation", delegate: op.delegate || null };
      case "origination": return { kind: "origination", balanceMutez: String(op.balance || 0) };
      default: return { kind: op.kind };
    }
  });
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
