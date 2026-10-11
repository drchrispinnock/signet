// Octez Connect (TZIP-10, the Beacon fork) wallet side, running inside JavaScriptCore.
//
// Swift owns the UI and the keys. This module owns the WalletClient: pairing with dApps over the
// Matrix relay, receiving requests, and sending responses. Requests are forwarded to Swift through
// `__signet.octezConnectEvent(json)`; Swift answers with `respond(json)`. Storage is a key/value
// file Swift provides through `__signet.storageGet/Set/Delete` so sessions survive restarts.

import { WalletClient } from "@tezos-x/octez.connect-wallet";
import { Serializer, setDebugEnabled, getSenderId } from "@tezos-x/octez.connect-core";
import { Storage, defaultValues as storageDefaults } from "@tezos-x/octez.connect-types";
import { TezosToolkit } from "@taquito/taquito";
import { signerFor } from "./signers.js";
import { RpcClient } from "@taquito/rpc";
import { localForger } from "@taquito/local-forging";
import { assertChain, injectSigned, checkedLimit } from "./operations.js";

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
/** The start in progress, so concurrent starts share one attempt and a failed one leaves no client (S18). */
let starting = null;
/** Request id → authenticated sender id, for the per-peer in-flight budget (S19). */
const inflight = new Map();

function emit(event) {
  globalThis.__signet.octezConnectEvent(JSON.stringify(event));
}

// ---- What a paired dApp may ask (S04, S08, S19) ---------------------------------------------------

/** Budgets for untrusted input from a paired peer. */
export const REQUEST_LIMITS = Object.freeze({
  messageChars: 256 * 1024,   // the whole decrypted request as JSON
  operations: 64,             // operations in one batch
  idChars: 128,
  textChars: 256,             // names, scopes, signing types
  urlChars: 2048,
  payloadHex: 64 * 1024,      // sign_payload hex (the signing rule applies the same bound)
  pendingPerPeer: 4,          // requests a peer may have waiting for the user
});

const REQUEST_TYPES = ["permission_request", "operation_request", "sign_payload_request"];
const OPERATION_KINDS = ["transaction", "delegation", "origination"];

const clipText = (value, max = REQUEST_LIMITS.textChars) => (typeof value === "string" && value.length <= max ? value : null);
function httpURL(value) {
  if (typeof value !== "string" || value.length > REQUEST_LIMITS.urlChars) return null;
  try { const u = new URL(value); return u.protocol === "https:" || u.protocol === "http:" ? u.href : null; } catch { return null; }
}
/** A dApp's `network` field, reduced to what the wallet reads. */
function cleanNetwork(network) {
  if (!network || typeof network !== "object") return null;
  const type = clipText(network.type, 64);
  if (!type) return null;
  const out = { type };
  const rpcUrl = httpURL(network.rpcUrl);
  if (rpcUrl) out.rpcUrl = rpcUrl;
  const name = clipText(network.name, 64);
  if (name) out.name = name;
  return out;
}
const sameNetwork = (a, b) => !!a && !!b && a.type === b.type && (a.type !== "custom" || httpURL(a.rpcUrl) === httpURL(b.rpcUrl));

/**
 * Rebuilds an incoming request from authenticated state only (S04, S08, S19). Pure, so it can be
 * tested offline. `auth` is what the transport proved: the peer whose session key decrypted the
 * message (`peer`, the record the user pasted when pairing), its `senderId` (derived from that
 * peer's public key here, not read from the message), the app metadata the SDK stored for that
 * sender at permission time, and the wallet's current permissions.
 *
 * Returns `{ request }` with only allow-listed fields, every identity field replaced by the
 * authenticated one, or `{ refused, errorType }` naming why the request must be answered with an
 * error instead of shown. Identity fields the message itself carries (`senderId`,
 * `appMetadata.senderId`) must agree with the authenticated sender: the SDK records grants under
 * the id the message claims, so a mismatch is refused outright rather than corrected.
 */
export function sanitizeIncomingRequest(message, auth) {
  const refuse = (refused, errorType = "NOT_GRANTED_ERROR") => ({ refused, errorType });
  if (!message || typeof message !== "object") return refuse("not an object", "PARAMETERS_INVALID_ERROR");
  if (!auth?.peer || typeof auth.senderId !== "string" || auth.senderId.length === 0) return refuse("message from a peer that is not paired");
  const id = clipText(message.id, REQUEST_LIMITS.idChars);
  const type = clipText(message.type, 64);
  if (!id || !type) return refuse("no request id or type", "PARAMETERS_INVALID_ERROR");
  if (!REQUEST_TYPES.includes(type)) return refuse(`"${type}" requests are not supported`);
  let size = 0;
  try { size = JSON.stringify(message).length; } catch { return refuse("unreadable message", "PARAMETERS_INVALID_ERROR"); }
  if (size > REQUEST_LIMITS.messageChars) return refuse(`the request is too large (${size} characters)`, "PARAMETERS_INVALID_ERROR");
  if (typeof message.senderId === "string" && message.senderId !== auth.senderId) return refuse("the message claims another sender id");
  const claimed = message.appMetadata?.senderId;
  if (typeof claimed === "string" && claimed !== auth.senderId) return refuse("the message's app metadata claims another sender id");
  const pendingHere = Number(auth.pendingFromPeer ?? 0);
  if (pendingHere >= REQUEST_LIMITS.pendingPerPeer) return refuse(`${pendingHere} requests from this dApp are already waiting`, "ABORTED_ERROR");

  // Branding is self-asserted, but it must be the branding the user paired with or granted to.
  const peer = auth.peer;
  const stored = auth.storedMetadata && typeof auth.storedMetadata === "object" ? auth.storedMetadata : null;
  const network = cleanNetwork(message.network);
  const base = { type, id, version: clipText(message.version, 16) ?? "2", senderId: auth.senderId };

  if (type === "permission_request") {
    const offered = message.appMetadata && typeof message.appMetadata === "object" ? message.appMetadata : {};
    const appMetadata = {
      senderId: auth.senderId,
      name: clipText(offered.name) ?? clipText(peer.name) ?? "dApp",
      icon: httpURL(offered.icon) ?? httpURL(peer.icon) ?? undefined,
      appUrl: httpURL(offered.appUrl) ?? httpURL(peer.appUrl) ?? undefined,
    };
    const scopes = Array.isArray(message.scopes) ? message.scopes.filter((s) => clipText(s, 64)).slice(0, 16) : [];
    if (!network) return refuse("no network in the permission request", "PARAMETERS_INVALID_ERROR");
    return { request: { ...base, appMetadata, network, scopes } };
  }

  // Everything else needs a grant for this exact peer, account and scope (S08).
  const appMetadata = {
    senderId: auth.senderId,
    name: clipText(stored?.name) ?? clipText(peer.name) ?? "dApp",
    icon: httpURL(stored?.icon) ?? httpURL(peer.icon) ?? undefined,
    appUrl: httpURL(stored?.appUrl) ?? httpURL(peer.appUrl) ?? undefined,
  };
  const sourceAddress = clipText(message.sourceAddress, 64);
  if (!sourceAddress) return refuse("no source address", "PARAMETERS_INVALID_ERROR");
  const scope = type === "operation_request" ? "operation_request" : "sign";
  const permissions = Array.isArray(auth.permissions) ? auth.permissions : [];
  const grant = permissions.find((p) => p?.senderId === auth.senderId && p?.address === sourceAddress && Array.isArray(p?.scopes) && p.scopes.includes(scope));
  if (!grant) return refuse(`${appMetadata.name} has no permission to ${scope === "sign" ? "sign messages" : "request operations"} for ${sourceAddress}`);

  if (type === "operation_request") {
    if (!network) return refuse("no network in the operation request", "PARAMETERS_INVALID_ERROR");
    if (!sameNetwork(network, grant.network)) return refuse(`the permission is for ${grant.network?.type ?? "another network"}, not ${network.type}`);
    const ops = message.operationDetails;
    if (!Array.isArray(ops) || ops.length === 0) return refuse("no operations", "PARAMETERS_INVALID_ERROR");
    if (ops.length > REQUEST_LIMITS.operations) return refuse(`${ops.length} operations in one request`, "TOO_MANY_OPERATIONS");
    if (ops.some((op) => !op || typeof op !== "object" || !OPERATION_KINDS.includes(op.kind))) return refuse("an operation of an unsupported kind", "PARAMETERS_INVALID_ERROR");
    return { request: { ...base, appMetadata, network, sourceAddress, operationDetails: ops } };
  }

  const payload = message.payload;
  if (typeof payload !== "string" || payload.length === 0 || payload.length > REQUEST_LIMITS.payloadHex) return refuse("the payload is missing or too long", "SIGNATURE_TYPE_NOT_SUPPORTED");
  return { request: { ...base, appMetadata, sourceAddress, signingType: clipText(message.signingType, 32) ?? "raw", payload } };
}

/** What the transport proved about an incoming message, gathered from the SDK's state. */
async function authenticatedContext(wallet, context) {
  const publicKey = typeof context?.id === "string" ? context.id : null;
  if (!publicKey) return null;
  const peers = await wallet.getPeers();
  const peer = peers.find((p) => p?.publicKey === publicKey);
  if (!peer) return null;
  const senderId = await getSenderId(publicKey);
  const [storedMetadata, permissions] = await Promise.all([wallet.getAppMetadata(senderId).catch(() => null), wallet.getPermissions()]);
  let pendingFromPeer = 0;
  for (const owner of inflight.values()) if (owner === senderId) pendingFromPeer++;
  return { peer, senderId, storedMetadata, permissions, pendingFromPeer };
}

async function refuseRequest(wallet, message, refused, errorType) {
  console.warn("octez.connect: refused request", message?.type, message?.id, refused);
  emit({ kind: "refused", id: message?.id ?? null, type: message?.type ?? null, reason: refused });
  if (typeof message?.id !== "string") return;
  try { await wallet.respond({ type: "error", id: message.id, errorType }); } catch (error) { console.warn("octez.connect: could not answer refused request", error?.message ?? error); }
}

/**
 * Creates the WalletClient, restores stored peers and starts listening. Concurrent calls share
 * one attempt; the client is published only once the transport is connected, so a failed start
 * leaves nothing behind and the next call tries again (S18).
 */
export async function octezConnectStart(appName, iconUrl, debug) {
  if (client) return { started: true };
  if (starting) return starting;
  starting = (async () => {
    if (debug) setDebugEnabled(true);
    const fresh = new WalletClient({ name: appName, iconUrl: iconUrl || undefined, storage: new NativeStorage() });
    try {
      const transport = await fresh.init();
      console.log("octez.connect: wallet client initialised, transport", transport);
      await fresh.connect(async (message, context) => {
        const auth = await authenticatedContext(fresh, context);
        const result = sanitizeIncomingRequest(message, auth);
        if (result.refused) { await refuseRequest(fresh, message, result.refused, result.errorType); return; }
        const request = result.request;
        inflight.set(request.id, request.senderId);
        console.log("octez.connect: request received", request.type, request.id, "from", request.appMetadata?.name);
        try {
          emit({ kind: "request", message: request, context: { origin: context?.origin, senderId: request.senderId } });
        } catch (error) {
          console.error("octez.connect: failed to forward request", error);
        }
      });
    } catch (error) {
      console.error("octez.connect: start failed", error?.message ?? error);
      try { const t = await fresh.transport; await t?.disconnect?.(); } catch {}
      throw error;
    }
    client = fresh;
    console.log("octez.connect: listening for dApp requests");
    if (debug) installRelayDiagnostics(client).catch((e) => console.warn("octez.connect: diagnostics not installed", e?.message ?? e));
    return { started: true };
  })();
  try { return await starting; } finally { starting = null; }
}

/**
 * Developer diagnostics only (S11): logs every relay message and tries the SDK's own decryption for
 * each known peer, so a message the SDK drops silently shows up with a reason. Decrypted text is
 * logged, so this is installed only when the app was started with debug on.
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
      console.log("relay message:", "room", event?.content?.roomId, "sender", m.sender, "len", body.length);
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

/**
 * Pairs with a dApp from the code it shows under "pair with another wallet". Returns at once with
 * the dApp's name; the pairing itself (the dApp joining the relay room) finishes later and is
 * reported with a `paired` or `error` event, so the UI never shows queued work as done (S18).
 */
export async function octezConnectPair(pairingCode) {
  if (!client) throw new Error("Octez Connect is not started");
  const peer = await new Serializer().deserialize(pairingCode.trim());
  if (!peer || !peer.publicKey || !peer.relayServer) throw new Error("That is not an Octez Connect pairing code");
  const name = clipText(peer.name) ?? "dApp";
  // addPeer with sendPairingResponse waits for the dApp to join the relay room, which can take a
  // while (or never happen if the dApp was closed). Do not hold the UI on it.
  client.addPeer(peer, true).then(
    () => emit({ kind: "paired", id: peer.id, name }),
    (error) => emit({ kind: "error", message: `Pairing with ${name} failed: ${error?.message ?? error}` }),
  );
  return { id: peer.id, name, icon: httpURL(peer.icon), appUrl: httpURL(peer.appUrl), relayServer: peer.relayServer, pending: true };
}

export async function octezConnectRespond(responseJson) {
  if (!client) throw new Error("Octez Connect is not started");
  const response = JSON.parse(responseJson);
  await client.respond(response);
  if (typeof response?.id === "string") inflight.delete(response.id);
  return { ok: true };
}

/** Request ids still waiting for an answer, by authenticated sender id (S19 budget). */
export function octezConnectInflight() {
  return Array.from(inflight, ([id, senderId]) => ({ id, senderId }));
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

/**
 * Simulates a dApp's operation request from `source` (read-only: no key involved) so the
 * approval sheet can show exact fees, burn, totals and effects before anything is signed.
 */
export async function octezConnectPrepare(rpcUrl, source, publicKey, operationsJson, expectedChainId) {
  const ops = JSON.parse(operationsJson);
  if (!Array.isArray(ops) || ops.length === 0) throw new Error("The dApp sent no operations");
  if (ops.length > REQUEST_LIMITS.operations) throw new Error(`The dApp sent ${ops.length} operations; at most ${REQUEST_LIMITS.operations} are accepted`);
  await assertChain(rpcUrl, expectedChainId);
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
export async function octezConnectExecute(rpcUrl, signerSpec, preparedJson, expectedChainId) {
  const operation = JSON.parse(preparedJson);
  const { branch, contents, protocol } = operation;
  if (typeof branch !== "string" || typeof protocol !== "string" || !Array.isArray(contents) || contents.length === 0) throw new Error("This batch was not prepared");
  await assertChain(rpcUrl, expectedChainId);
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
  return injectSigned(rpc, sbytes);
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
  if (starting) { try { await starting; } catch {} }
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
  inflight.clear();
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
