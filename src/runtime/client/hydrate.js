const ISLAND_ATTR = "data-cataract-island";
const PROPS_ATTR = "data-cataract-props";
const SOURCE_ATTR = "data-cataract-src";
const INTERVAL_ATTR = "data-cataract-every";
const LIVE_ATTR = "data-cataract-live";
const PATH_ATTR = "data-path";

const MOUNT_SELECTOR = `[${ISLAND_ATTR}],[${LIVE_ATTR}]`;
const DELTA_PROTOCOL = "cataract.delta.v1";
const TICK = "tick";

const OP_SET_TEXT = 0x01;
const OP_SET_ATTR = 0x02;
const OP_REMOVE_ATTR = 0x03;
const OP_INSERT_NODE = 0x04;
const OP_REMOVE_NODE = 0x05;
const OP_REPLACE_NODE = 0x06;
const OP_FULL_RENDER = 0xff;

const HEADER_BYTES = 5;
const RECONNECT_FLOOR_MS = 500;
const RECONNECT_CEILING_MS = 30000;

const registry = new Map();
const state = new WeakMap();
const warned = new Set();

const decoder = new TextDecoder();
const encoder = new TextEncoder();

const warn = (message, ...rest) => {
  if (warned.has(message)) return;
  warned.add(message);
  console.warn(`[cataract] ${message}`, ...rest);
};

export function defineIsland(name, factory) {
  if (typeof name !== "string" || name === "") {
    console.error("[cataract] defineIsland needs a non-empty name", name);
    return;
  }
  if (typeof factory !== "function") {
    console.error(`[cataract] island "${name}" was given no factory`, factory);
    return;
  }
  if (registry.has(name)) warn(`island "${name}" was defined more than once`);

  registry.set(name, factory);
  if (document.readyState !== "loading") mountName(name, document);
}

function readProps(el, name) {
  const raw = el.getAttribute(PROPS_ATTR);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    if (parsed === null || typeof parsed !== "object") {
      console.error(`[cataract] props for island "${name}" are not an object`, parsed);
      return {};
    }
    return parsed;
  } catch (err) {
    console.error(`[cataract] bad props on island "${name}"`, err);
    return {};
  }
}

function readHandle(returned) {
  if (typeof returned === "function") return { update: null, patched: null, cleanup: returned };
  if (returned && typeof returned === "object") {
    return {
      update: typeof returned.update === "function" ? returned.update : null,
      patched: typeof returned.patched === "function" ? returned.patched : null,
      cleanup: typeof returned.destroy === "function" ? returned.destroy : null,
    };
  }
  return { update: null, patched: null, cleanup: null };
}

// The server already rendered the region, so a failed fetch leaves it as it is.
function refresh(el, entry) {
  const source = el.getAttribute(SOURCE_ATTR);
  if (!source || !entry.update) return;

  entry.aborter = new AbortController();
  fetch(source, {
    headers: { Accept: "application/json" },
    credentials: "same-origin",
    signal: entry.aborter.signal,
  })
    .then((response) => {
      if (!response.ok) throw new Error(`${response.status} from ${source}`);
      return response.json();
    })
    .then((data) => {
      if (state.get(el) !== entry) return;
      entry.update(data);
    })
    .catch((err) => {
      if (err.name === "AbortError") return;
      warn(`island "${entry.name}" kept its server-rendered markup`, err);
    });
}

function everyMillis(el) {
  const every = Number(el.getAttribute(INTERVAL_ATTR) ?? 0);
  return Number.isFinite(every) && every > 0 ? every : 0;
}

function schedule(el, entry) {
  const every = everyMillis(el);
  if (every === 0 || !entry.update) return;
  entry.timer = setInterval(() => refresh(el, entry), every);
}

function decodeOps(buffer) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const ops = [];
  let at = 0;

  while (at + HEADER_BYTES <= bytes.length) {
    const code = view.getUint8(at);
    const path = view.getUint16(at + 1);
    const length = view.getUint16(at + 3);
    at += HEADER_BYTES;
    if (at + length > bytes.length) {
      warn("a mutation frame ended mid-operation and was dropped");
      return ops;
    }
    ops.push({ code, path, data: bytes.subarray(at, at + length) });
    at += length;
  }
  if (at !== bytes.length) warn("a mutation frame carried a partial header");
  return ops;
}

function pathOf(el) {
  const raw = el.getAttribute(PATH_ATTR);
  return raw === null ? null : Number(raw);
}

function indexTree(root, index) {
  const own = pathOf(root);
  if (own !== null) index.set(own, root);
  for (const el of root.querySelectorAll(`[${PATH_ATTR}]`)) {
    const path = pathOf(el);
    if (path !== null) index.set(path, el);
  }
}

function dropTree(root, index) {
  const own = pathOf(root);
  if (own !== null) index.delete(own);
  for (const el of root.querySelectorAll(`[${PATH_ATTR}]`)) {
    const path = pathOf(el);
    if (path !== null) index.delete(path);
  }
}

function applyOp(root, index, op) {
  const el = index.get(op.path);
  if (!el) {
    warn(`no element carries ${PATH_ATTR}="${op.path}"; the region will resync`);
    return false;
  }

  switch (op.code) {
    case OP_SET_TEXT:
      el.textContent = decoder.decode(op.data);
      return true;

    case OP_SET_ATTR: {
      const nameLength = op.data[0];
      const name = decoder.decode(op.data.subarray(1, 1 + nameLength));
      el.setAttribute(name, decoder.decode(op.data.subarray(1 + nameLength)));
      return true;
    }

    case OP_REMOVE_ATTR:
      el.removeAttribute(decoder.decode(op.data));
      return true;

    case OP_INSERT_NODE: {
      const at = (op.data[0] << 8) | op.data[1];
      const html = decoder.decode(op.data.subarray(2));
      const follower = el.children[at];
      if (follower) follower.insertAdjacentHTML("beforebegin", html);
      else el.insertAdjacentHTML("beforeend", html);
      const added = follower ? follower.previousElementSibling : el.lastElementChild;
      if (added) indexTree(added, index);
      return true;
    }

    case OP_REMOVE_NODE:
      if (el === root) return false;
      dropTree(el, index);
      el.remove();
      return true;

    case OP_REPLACE_NODE: {
      if (el === root) return false;
      el.insertAdjacentHTML("beforebegin", decoder.decode(op.data));
      const added = el.previousElementSibling;
      dropTree(el, index);
      el.remove();
      if (added) indexTree(added, index);
      return true;
    }

    case OP_FULL_RENDER:
      for (const child of el.children) dropTree(child, index);
      el.innerHTML = decoder.decode(op.data);
      indexTree(el, index);
      return true;
  }

  warn(`unknown mutation opcode 0x${op.code.toString(16)}`);
  return false;
}

// Mutations are applied in one requestAnimationFrame, so a burst of messages
// costs a single layout pass rather than one per frame that arrived.
function connectLive(el, entry) {
  const target = el.getAttribute(LIVE_ATTR);
  const rootPath = pathOf(el);
  if (!target || rootPath === null) {
    warn(`live region on ${LIVE_ATTR}="${target}" has no ${PATH_ATTR}`, el);
    return null;
  }

  const index = new Map();
  indexTree(el, index);

  const live = {
    socket: null,
    frame: 0,
    queue: [],
    tick: 0,
    retryTimer: 0,
    retries: 0,
    closed: false,
  };

  const flush = () => {
    live.frame = 0;
    const batch = live.queue;
    live.queue = [];
    for (const op of batch) applyOp(el, index, op);
    if (!entry.patched) return;
    try {
      entry.patched();
    } catch (err) {
      console.error(`[cataract] island "${entry.name}" failed after a patch`, err);
    }
  };

  const enqueue = (ops) => {
    for (const op of ops) live.queue.push(op);
    if (live.queue.length === 0 || live.frame) return;
    live.frame = requestAnimationFrame(flush);
  };

  const open = () => {
    if (live.closed) return;
    let socket;
    try {
      socket = new WebSocket(socketUrl(target), DELTA_PROTOCOL);
    } catch (err) {
      warn(`live region could not open ${target}`, err);
      return;
    }
    socket.binaryType = "arraybuffer";
    live.socket = socket;

    socket.addEventListener("open", () => {
      live.retries = 0;
      const every = everyMillis(el);
      if (every > 0) live.tick = setInterval(() => send(TICK), every);
    });

    socket.addEventListener("message", (event) => {
      if (event.data instanceof ArrayBuffer) enqueue(decodeOps(event.data));
      else enqueue([{ code: OP_FULL_RENDER, path: rootPath, data: encoder.encode(String(event.data)) }]);
    });

    socket.addEventListener("close", () => {
      if (live.tick) clearInterval(live.tick);
      live.tick = 0;
      live.socket = null;
      if (live.closed) return;
      const wait = Math.min(RECONNECT_FLOOR_MS * 2 ** live.retries, RECONNECT_CEILING_MS);
      live.retries += 1;
      live.retryTimer = setTimeout(open, wait);
    });
  };

  const send = (text) => {
    if (live.socket && live.socket.readyState === WebSocket.OPEN) live.socket.send(text);
  };

  open();

  return {
    send,
    close() {
      live.closed = true;
      if (live.frame) cancelAnimationFrame(live.frame);
      if (live.tick) clearInterval(live.tick);
      if (live.retryTimer) clearTimeout(live.retryTimer);
      if (live.socket) live.socket.close();
    },
  };
}

function socketUrl(target) {
  const url = new URL(target, location.href);
  if (url.protocol === "http:") url.protocol = "ws:";
  else if (url.protocol === "https:") url.protocol = "wss:";
  return url.href;
}

function mount(el) {
  // `failed` is kept, not cleared: retrying on every mutation only spams.
  if (state.has(el)) return;

  const name = el.getAttribute(ISLAND_ATTR);
  const factory = name === null ? null : registry.get(name);
  if (name !== null && !factory) {
    warn(`no island is defined for "${name}"; it was left server-rendered`, el);
    return;
  }

  const entry = {
    name,
    cleanup: null,
    update: null,
    patched: null,
    timer: null,
    aborter: null,
    live: null,
  };
  state.set(el, entry);

  if (factory) {
    try {
      const handle = readHandle(factory(el, readProps(el, name)));
      entry.cleanup = handle.cleanup;
      entry.update = handle.update;
      entry.patched = handle.patched;
    } catch (err) {
      state.set(el, { name, cleanup: null, failed: true });
      console.error(`[cataract] island "${name}" failed to mount`, err);
      return;
    }
  }

  if (el.hasAttribute(LIVE_ATTR)) entry.live = connectLive(el, entry);
  else {
    refresh(el, entry);
    schedule(el, entry);
  }
}

function unmount(el) {
  const entry = state.get(el);
  if (!entry) return;
  state.delete(el);
  if (entry.timer) clearInterval(entry.timer);
  if (entry.aborter) entry.aborter.abort();
  if (entry.live) entry.live.close();
  if (!entry.cleanup) return;
  try {
    entry.cleanup();
  } catch (err) {
    console.error(`[cataract] island "${entry.name}" failed to unmount`, err);
  }
}

function eachIsland(root, selector, fn) {
  if (root.nodeType === 1 && root.matches(selector)) fn(root);
  if (typeof root.querySelectorAll !== "function") return;
  for (const el of root.querySelectorAll(selector)) fn(el);
}

function mountAll(root) {
  eachIsland(root, MOUNT_SELECTOR, mount);
}

function mountName(name, root) {
  eachIsland(root, `[${ISLAND_ATTR}="${CSS.escape(name)}"]`, mount);
}

const observer = new MutationObserver((records) => {
  for (const record of records) {
    for (const node of record.removedNodes) eachIsland(node, MOUNT_SELECTOR, unmount);
    for (const node of record.addedNodes) mountAll(node);
  }
});

function boot() {
  mountAll(document.documentElement);
  observer.observe(document.documentElement, { childList: true, subtree: true });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}

globalThis.Cataract = { defineIsland };
