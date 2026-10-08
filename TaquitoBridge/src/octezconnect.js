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
import { InMemorySigner } from "@taquito/signer";

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
  return { started: true };
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
export async function octezConnectExecute(rpcUrl, secretKey, passphrase, operationsJson) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(new InMemorySigner(secretKey, passphrase || undefined));
  const ops = JSON.parse(operationsJson).map(toTaquitoParams);
  const batch = tk.contract.batch(ops);
  const op = await batch.send();
  return { hash: op.hash };
}

/** Signs a payload for a sign_payload request. `payload` is the hex the dApp sent. */
export async function octezConnectSign(secretKey, passphrase, payload) {
  const signer = new InMemorySigner(secretKey, passphrase || undefined);
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
