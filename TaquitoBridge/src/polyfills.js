// Minimal browser-API polyfills for JavaScriptCore. Loaded before Taquito.
//
// Pure-JS pieces live here. Anything that needs the OS (timers, HTTP, randomness) calls into
// the `__signet` native object that Swift installs before evaluating this bundle; Swift calls
// the `__signet_*` callbacks defined here when work completes.

import { Buffer } from "buffer";

const g = globalThis;
const native = g.__signet;
if (!native) {
  throw new Error("TaquitoBridge: __signet native object missing; install it before loading the bundle");
}

if (typeof g.Buffer === "undefined") g.Buffer = Buffer;
if (typeof g.self === "undefined") g.self = g;
if (typeof g.window === "undefined") g.window = g;

// ---- Timers ----------------------------------------------------------------------------------
const timers = new Map();
let nextTimerId = 1;

function schedule(fn, ms, args, repeat) {
  const id = nextTimerId++;
  timers.set(id, { fn, args, repeat, ms });
  native.setTimer(id, Math.max(0, Number(ms) || 0));
  return id;
}

g.setTimeout = (fn, ms, ...args) => schedule(fn, ms, args, false);
g.setInterval = (fn, ms, ...args) => schedule(fn, ms, args, true);
g.clearTimeout = g.clearInterval = (id) => {
  if (timers.delete(id)) native.clearTimer(id);
};
g.queueMicrotask ??= (fn) => Promise.resolve().then(fn);

g.__signet_timerFired = (id) => {
  const t = timers.get(id);
  if (!t) return;
  if (t.repeat) native.setTimer(id, t.ms);
  else timers.delete(id);
  t.fn(...t.args);
};

// ---- Text encoding ---------------------------------------------------------------------------
if (typeof g.TextEncoder === "undefined") {
  g.TextEncoder = class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(str = "") { return new Uint8Array(Buffer.from(String(str), "utf8")); }
  };
}
if (typeof g.TextDecoder === "undefined") {
  g.TextDecoder = class TextDecoder {
    constructor(label = "utf-8") { this.encoding = label; }
    decode(bytes) {
      if (bytes == null) return "";
      const view = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : bytes;
      return Buffer.from(view.buffer, view.byteOffset, view.byteLength).toString("utf8");
    }
  };
}

// ---- Randomness ------------------------------------------------------------------------------
if (typeof g.crypto === "undefined") g.crypto = {};
if (typeof g.crypto.getRandomValues !== "function") {
  g.crypto.getRandomValues = (array) => {
    const bytes = native.randomBytes(array.byteLength);
    const view = new Uint8Array(array.buffer, array.byteOffset, array.byteLength);
    for (let i = 0; i < view.length; i++) view[i] = bytes[i];
    return array;
  };
}

// ---- AbortController -------------------------------------------------------------------------
if (typeof g.AbortController === "undefined") {
  class AbortSignal {
    constructor() { this.aborted = false; this._listeners = []; this.reason = undefined; }
    addEventListener(type, fn) { if (type === "abort") this._listeners.push(fn); }
    removeEventListener(type, fn) { this._listeners = this._listeners.filter((l) => l !== fn); }
    _abort(reason) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason;
      for (const l of this._listeners) l({ type: "abort" });
    }
  }
  g.AbortController = class AbortController {
    constructor() { this.signal = new AbortSignal(); }
    abort(reason) { this.signal._abort(reason ?? new Error("Aborted")); }
  };
}

// ---- fetch -----------------------------------------------------------------------------------
class Headers {
  constructor(init) {
    this._map = new Map();
    if (init) {
      const entries = init instanceof Headers ? init.entries() : Array.isArray(init) ? init : Object.entries(init);
      for (const [k, v] of entries) this.set(k, v);
    }
  }
  get(name) { return this._map.get(String(name).toLowerCase()) ?? null; }
  has(name) { return this._map.has(String(name).toLowerCase()); }
  set(name, value) { this._map.set(String(name).toLowerCase(), String(value)); }
  entries() { return this._map.entries(); }
  forEach(fn) { for (const [k, v] of this._map) fn(v, k, this); }
  toJSON() { return Object.fromEntries(this._map); }
}

class Response {
  constructor(bodyText, { status = 200, statusText = "", headers = {}, url = "" } = {}) {
    this._body = bodyText ?? "";
    this.status = status;
    this.statusText = statusText;
    this.headers = new Headers(headers);
    this.url = url;
    this.ok = status >= 200 && status < 300;
    this.bodyUsed = false;
  }
  async text() { this.bodyUsed = true; return this._body; }
  async json() { return JSON.parse(await this.text()); }
  async arrayBuffer() { return new Uint8Array(Buffer.from(await this.text(), "utf8")).buffer; }
}

const inflight = new Map();
let nextFetchId = 1;

g.Headers ??= Headers;
g.Response ??= Response;

g.fetch = (input, init = {}) => {
  const url = typeof input === "string" ? input : input?.url ?? String(input);
  const method = (init.method || "GET").toUpperCase();
  const headers = new Headers(init.headers).toJSON();
  let body = init.body;
  if (body != null && typeof body !== "string") {
    body = body instanceof Uint8Array || body instanceof ArrayBuffer ? Buffer.from(body).toString("utf8") : JSON.stringify(body);
  }
  return new Promise((resolve, reject) => {
    const id = nextFetchId++;
    inflight.set(id, { resolve, reject, url });
    if (init.signal) {
      if (init.signal.aborted) {
        inflight.delete(id);
        reject(abortError());
        return;
      }
      init.signal.addEventListener("abort", () => {
        if (inflight.delete(id)) {
          native.cancelFetch(id);
          reject(abortError());
        }
      });
    }
    native.fetch(id, url, method, JSON.stringify(headers), body ?? null);
  });
};

function abortError() {
  const e = new Error("The operation was aborted.");
  e.name = "AbortError";
  return e;
}

g.__signet_fetchDone = (id, status, statusText, headersJSON, bodyText, errorMessage) => {
  const req = inflight.get(id);
  if (!req) return;
  inflight.delete(id);
  if (errorMessage) {
    const e = new TypeError(errorMessage);
    e.name = "TypeError";
    req.reject(e);
    return;
  }
  req.resolve(new Response(bodyText, { status, statusText, headers: JSON.parse(headersJSON || "{}"), url: req.url }));
};
