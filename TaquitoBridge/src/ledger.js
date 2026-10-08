// Ledger hardware wallets. The USB HID traffic is done natively (IOKit, see LedgerHID.swift);
// this file adapts that to @ledgerhq/hw-transport's Transport so Taquito's LedgerSigner can
// drive the Tezos Wallet app on the device. Secrets never leave the Ledger.

import Transport from "@ledgerhq/hw-transport";
import { LedgerSigner, DerivationType } from "@taquito/ledger-signer";

const g = globalThis;
const native = g.__signet;

// ---- Native exchange: one APDU out, one response (data ‖ status word) back ------------------
const pendingExchanges = new Map();
let nextExchangeId = 1;

g.__signet_ledgerDone = (id, responseHex, errorMessage) => {
  const p = pendingExchanges.get(id);
  if (!p) return;
  pendingExchanges.delete(id);
  if (errorMessage) p.reject(new Error(errorMessage));
  else p.resolve(Buffer.from(responseHex, "hex"));
};

/** How long we wait for the device: the user may need a while to read and approve on it. */
export const LEDGER_EXCHANGE_TIMEOUT_MS = 5 * 60 * 1000;

export class NativeLedgerTransport extends Transport {
  constructor(deviceId) {
    super();
    this.deviceId = deviceId;
    this.setExchangeTimeout(LEDGER_EXCHANGE_TIMEOUT_MS);
  }

  exchange(apdu, { abortTimeoutMs } = {}) {
    return new Promise((resolve, reject) => {
      const id = nextExchangeId++;
      pendingExchanges.set(id, { resolve, reject });
      native.ledgerExchange(id, this.deviceId, Buffer.from(apdu).toString("hex"), abortTimeoutMs || LEDGER_EXCHANGE_TIMEOUT_MS);
    });
  }

  setScrambleKey() {}

  close() {
    return Promise.resolve();
  }
}

/** Connected Ledger devices as the host sees them: [{ id, name, model }]. */
export function ledgerDevices() {
  const list = JSON.parse(native.ledgerDevices() || "[]");
  return Array.isArray(list) ? list : [];
}

const transports = new Map();

/** A transport for `deviceId`, or for the only/first connected Ledger when it is empty. */
function transportFor(deviceId) {
  let id = deviceId;
  if (!id) {
    const devices = ledgerDevices();
    if (devices.length === 0) throw new Error("No Ledger is connected. Plug it in, unlock it and open the Tezos app.");
    id = devices[0].id;
  }
  let t = transports.get(id);
  if (!t) {
    t = new NativeLedgerTransport(id);
    transports.set(id, t);
  }
  return t;
}

/** The Tezos Wallet app's version, or an error if another app (or the dashboard) is showing. */
export async function ledgerAppVersion(deviceId) {
  const r = await transportFor(deviceId).send(0x80, 0x00, 0x00, 0x00);
  // appclass (0 = Tezos Wallet, 1 = Tezos Baking), major, minor, patch
  return { appClass: r[0], version: `${r[1]}.${r[2]}.${r[3]}`, isWallet: r[0] === 0 };
}

/**
 * Public key and address at `path` ("44'/1729'/0'/0'") for a derivation type
 * (0 ed25519, 1 secp256k1, 2 P-256, 3 BIP32-ed25519). With `prompt` the device shows the
 * address and waits for the user to approve it.
 */
export async function ledgerGetAddress(deviceId, path, derivationType, prompt) {
  const signer = new LedgerSigner(transportFor(deviceId), path, !!prompt, Number(derivationType));
  return { publicKey: await signer.publicKey(), address: await signer.publicKeyHash() };
}

/** A signer for a ledger spec `{ deviceId?, path, derivationType, address? }`. */
export async function ledgerSignerFor(spec) {
  const signer = new LedgerSigner(transportFor(spec.deviceId || ""), spec.path, false, Number(spec.derivationType ?? DerivationType.ED25519));
  if (spec.address) {
    const found = await signer.publicKeyHash();
    if (found !== spec.address) {
      throw new Error(`The connected Ledger does not hold this key: it derives ${found} where ${spec.address} was expected. Is it the right device?`);
    }
  }
  return signer;
}
