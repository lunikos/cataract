const ISLAND_ATTR = "data-cataract-island";
const PROPS_ATTR = "data-cataract-props";

const registry = new Map();
const mounted = new WeakSet();

export function defineIsland(name, factory) {
  registry.set(name, factory);
  if (document.readyState !== "loading") mountAll(document);
}

function readProps(el) {
  const raw = el.getAttribute(PROPS_ATTR);
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.error(`[cataract] bad props on island "${el.getAttribute(ISLAND_ATTR)}"`, err);
    return {};
  }
}

function mount(el) {
  if (mounted.has(el)) return;
  const name = el.getAttribute(ISLAND_ATTR);
  const factory = registry.get(name);
  if (!factory) return;

  mounted.add(el);
  try {
    factory(el, readProps(el));
  } catch (err) {
    mounted.delete(el);
    console.error(`[cataract] island "${name}" failed to mount`, err);
  }
}

function mountAll(root) {
  for (const el of root.querySelectorAll(`[${ISLAND_ATTR}]`)) mount(el);
}

// Picks up islands added later by navigation or by an island's own DOM writes.
const observer = new MutationObserver((records) => {
  for (const record of records) {
    for (const node of record.addedNodes) {
      if (node.nodeType !== 1) continue;
      if (node.hasAttribute(ISLAND_ATTR)) mount(node);
      mountAll(node);
    }
  }
});

function boot() {
  mountAll(document);
  observer.observe(document.documentElement, { childList: true, subtree: true });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}

globalThis.Cataract = { defineIsland };
