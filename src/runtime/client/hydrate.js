const ISLAND_ATTR = "data-cataract-island";
const PROPS_ATTR = "data-cataract-props";
const SOURCE_ATTR = "data-cataract-src";
const INTERVAL_ATTR = "data-cataract-every";

const registry = new Map();
const state = new WeakMap();
const warned = new Set();

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
  if (typeof returned === "function") return { update: null, cleanup: returned };
  if (returned && typeof returned === "object") {
    return {
      update: typeof returned.update === "function" ? returned.update : null,
      cleanup: typeof returned.destroy === "function" ? returned.destroy : null,
    };
  }
  return { update: null, cleanup: null };
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

function schedule(el, entry) {
  const every = Number(el.getAttribute(INTERVAL_ATTR) ?? 0);
  if (!Number.isFinite(every) || every <= 0) return;
  entry.timer = setInterval(() => refresh(el, entry), every);
}

function mount(el) {
  // `failed` is kept, not cleared: retrying on every mutation only spams.
  if (state.has(el)) return;

  const name = el.getAttribute(ISLAND_ATTR);
  const factory = registry.get(name);
  if (!factory) {
    warn(`no island is defined for "${name}"; it was left server-rendered`, el);
    return;
  }

  const entry = { name, cleanup: null, update: null, timer: null, aborter: null };
  state.set(el, entry);
  try {
    const handle = readHandle(factory(el, readProps(el, name)));
    entry.cleanup = handle.cleanup;
    entry.update = handle.update;
  } catch (err) {
    state.set(el, { name, cleanup: null, failed: true });
    console.error(`[cataract] island "${name}" failed to mount`, err);
    return;
  }

  refresh(el, entry);
  schedule(el, entry);
}

function unmount(el) {
  const entry = state.get(el);
  if (!entry) return;
  state.delete(el);
  if (entry.timer) clearInterval(entry.timer);
  if (entry.aborter) entry.aborter.abort();
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
  eachIsland(root, `[${ISLAND_ATTR}]`, mount);
}

function mountName(name, root) {
  eachIsland(root, `[${ISLAND_ATTR}="${CSS.escape(name)}"]`, mount);
}

const observer = new MutationObserver((records) => {
  for (const record of records) {
    for (const node of record.removedNodes) eachIsland(node, `[${ISLAND_ATTR}]`, unmount);
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
