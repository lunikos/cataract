const ISLAND_ATTR = "data-cataract-island";
const PROPS_ATTR = "data-cataract-props";

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

function mount(el) {
  // `failed` is kept, not cleared: retrying on every mutation only spams.
  if (state.has(el)) return;

  const name = el.getAttribute(ISLAND_ATTR);
  const factory = registry.get(name);
  if (!factory) {
    warn(`no island is defined for "${name}"; it was left server-rendered`, el);
    return;
  }

  state.set(el, { name, cleanup: null });
  try {
    const cleanup = factory(el, readProps(el, name));
    if (typeof cleanup === "function") state.get(el).cleanup = cleanup;
  } catch (err) {
    state.set(el, { name, cleanup: null, failed: true });
    console.error(`[cataract] island "${name}" failed to mount`, err);
  }
}

function unmount(el) {
  const entry = state.get(el);
  if (!entry) return;
  state.delete(el);
  if (!entry.cleanup) return;
  try {
    entry.cleanup();
  } catch (err) {
    console.error(`[cataract] island "${entry.name}" failed to unmount`, err);
  }
}

// Called with a Document, an Element, or a removed node of any type.
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
