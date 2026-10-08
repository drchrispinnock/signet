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

// ---- localStorage ----------------------------------------------------------------------------
// The Octez Connect SDK peeks at localStorage (e.g. updateRelayServer checks for a dApp peer
// list) even when it was given its own storage. Without this, that access throws a
// ReferenceError inside an unobserved promise and every incoming dApp message is silently lost.
if (typeof g.localStorage === "undefined") {
  const store = new Map();
  g.localStorage = {
    getItem: (k) => (store.has(String(k)) ? store.get(String(k)) : null),
    setItem: (k, v) => { store.set(String(k), String(v)); },
    removeItem: (k) => { store.delete(String(k)); },
    clear: () => store.clear(),
    key: (i) => [...store.keys()][i] ?? null,
    get length() { return store.size; },
  };
  g.sessionStorage ??= g.localStorage;
}
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

// ---- Browser globals the Octez Connect SDK touches -----------------------------------------------
// Enough of window/document/navigator/location for the wallet SDK to initialise; the PostMessage
// (browser-extension) transport finds no listeners and stays idle, which is what we want.
if (typeof g.location === "undefined") {
  g.location = { origin: "signet://app", href: "signet://app/", protocol: "signet:", host: "app", hostname: "app", pathname: "/", search: "", hash: "" };
}
if (typeof g.navigator === "undefined") {
  g.navigator = { userAgent: "Signet (macOS; JavaScriptCore)", onLine: true, language: "en", platform: "MacIntel" };
}
if (typeof g.document === "undefined") {
  g.document = {
    visibilityState: "visible",
    hidden: false,
    readyState: "complete",
    addEventListener() {},
    removeEventListener() {},
    createElement() { return { style: {}, setAttribute() {}, appendChild() {}, remove() {} }; },
    getElementById() { return null; },
    querySelector() { return null; },
    body: { appendChild() {}, removeChild() {} },
    head: { appendChild() {}, removeChild() {} },
  };
}
const noop = () => {};
if (typeof g.addEventListener !== "function") g.addEventListener = noop;
if (typeof g.removeEventListener !== "function") g.removeEventListener = noop;
if (typeof g.dispatchEvent !== "function") g.dispatchEvent = () => true;
if (typeof g.postMessage !== "function") g.postMessage = noop;
if (typeof g.CustomEvent === "undefined") {
  g.CustomEvent = class CustomEvent { constructor(type, init) { this.type = type; this.detail = init?.detail; } };
}
if (typeof g.Event === "undefined") {
  g.Event = class Event { constructor(type) { this.type = type; } };
}

// ---- More Web APIs the relay transport may use ----------------------------------------------------
if (typeof g.AbortSignal === "undefined") {
  // Expose the signal class used by our AbortController, plus AbortSignal.timeout().
  g.AbortSignal = Object.getPrototypeOf(new g.AbortController().signal).constructor;
}
if (typeof g.AbortSignal.timeout !== "function") {
  g.AbortSignal.timeout = (ms) => {
    const controller = new g.AbortController();
    g.setTimeout(() => controller.abort(new Error("The operation timed out.")), ms);
    return controller.signal;
  };
}
if (typeof g.AbortSignal.any !== "function") {
  g.AbortSignal.any = (signals) => {
    const controller = new g.AbortController();
    for (const s of signals) {
      if (s.aborted) { controller.abort(s.reason); break; }
      s.addEventListener("abort", () => controller.abort(s.reason));
    }
    return controller.signal;
  };
}
if (typeof g.crypto.randomUUID !== "function") {
  g.crypto.randomUUID = () => {
    const b = g.crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  };
}
if (typeof g.Request === "undefined") {
  g.Request = class Request {
    constructor(input, init = {}) {
      this.url = typeof input === "string" ? input : input?.url ?? String(input);
      this.method = (init.method || "GET").toUpperCase();
      this.headers = new g.Headers(init.headers);
      this.body = init.body ?? null;
      this.signal = init.signal ?? null;
    }
  };
}
if (typeof g.performance === "undefined") {
  g.performance = { now: () => Date.now() };
}
if (typeof g.structuredClone !== "function") {
  g.structuredClone = (v) => JSON.parse(JSON.stringify(v));
}

// ---- URL and URLSearchParams ----------------------------------------------------------------------
// JavaScriptCore has neither. The relay client builds every query string with URLSearchParams.
if (typeof g.URLSearchParams === "undefined") {
  const enc = (s) => encodeURIComponent(s).replace(/%20/g, "+");
  const dec = (s) => decodeURIComponent(s.replace(/\+/g, " "));
  g.URLSearchParams = class URLSearchParams {
    constructor(init) {
      this._list = [];
      if (init == null) return;
      if (typeof init === "string") {
        for (const part of init.replace(/^\?/, "").split("&")) {
          if (!part) continue;
          const i = part.indexOf("=");
          this._list.push(i < 0 ? [dec(part), ""] : [dec(part.slice(0, i)), dec(part.slice(i + 1))]);
        }
      } else if (init instanceof URLSearchParams) {
        this._list = init._list.map(([k, v]) => [k, v]);
      } else if (Array.isArray(init)) {
        for (const [k, v] of init) this._list.push([String(k), String(v)]);
      } else {
        for (const [k, v] of Object.entries(init)) this._list.push([String(k), String(v)]);
      }
    }
    append(k, v) { this._list.push([String(k), String(v)]); }
    delete(k) { this._list = this._list.filter(([key]) => key !== k); }
    get(k) { const hit = this._list.find(([key]) => key === k); return hit ? hit[1] : null; }
    getAll(k) { return this._list.filter(([key]) => key === k).map(([, v]) => v); }
    has(k) { return this._list.some(([key]) => key === k); }
    set(k, v) { this.delete(k); this.append(k, v); }
    sort() { this._list.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)); }
    forEach(fn, thisArg) { for (const [k, v] of this._list) fn.call(thisArg, v, k, this); }
    keys() { return this._list.map(([k]) => k)[Symbol.iterator](); }
    values() { return this._list.map(([, v]) => v)[Symbol.iterator](); }
    entries() { return this._list.map(([k, v]) => [k, v])[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
    get size() { return this._list.length; }
    toString() { return this._list.map(([k, v]) => `${enc(k)}=${enc(v)}`).join("&"); }
  };
}
if (typeof g.URL === "undefined") {
  const RE = /^([a-zA-Z][a-zA-Z0-9+.-]*):(?:\/\/(?:([^@/?#]*)@)?(\[[^\]]*\]|[^:/?#]*)(?::(\d*))?)?([^?#]*)(\?[^#]*)?(#.*)?$/;
  g.URL = class URL {
    constructor(input, base) {
      let text = String(input);
      if (!RE.test(text) && base !== undefined) {
        const b = new URL(base);
        if (text.startsWith("//")) text = `${b.protocol}${text}`;
        else if (text.startsWith("/")) text = `${b.origin}${text}`;
        else if (text.startsWith("?")) text = `${b.origin}${b.pathname}${text}`;
        else if (text.startsWith("#")) text = `${b.origin}${b.pathname}${b.search}${text}`;
        else text = `${b.origin}${b.pathname.replace(/[^/]*$/, "")}${text}`;
      }
      const m = RE.exec(text);
      if (!m) throw new TypeError(`Invalid URL: ${input}`);
      this.protocol = `${m[1].toLowerCase()}:`;
      const userinfo = m[2] ?? "";
      this.username = userinfo.split(":")[0] ?? "";
      this.password = userinfo.includes(":") ? userinfo.slice(userinfo.indexOf(":") + 1) : "";
      this.hostname = (m[3] ?? "").toLowerCase();
      this.port = m[4] ?? "";
      this.pathname = m[5] || (m[3] !== undefined ? "/" : "");
      this.search = m[6] && m[6] !== "?" ? m[6] : "";
      this.hash = m[7] && m[7] !== "#" ? m[7] : "";
      this.searchParams = new g.URLSearchParams(this.search);
    }
    get host() { return this.port ? `${this.hostname}:${this.port}` : this.hostname; }
    get origin() { return this.hostname ? `${this.protocol}//${this.host}` : "null"; }
    get href() {
      const search = this.searchParams.size ? `?${this.searchParams.toString()}` : "";
      const auth = this.username ? `${this.username}${this.password ? ":" + this.password : ""}@` : "";
      return `${this.protocol}//${auth}${this.host}${this.pathname}${search}${this.hash}`;
    }
    toString() { return this.href; }
    toJSON() { return this.href; }
    static canParse(u, b) { try { new URL(u, b); return true; } catch { return false; } }
  };
}
