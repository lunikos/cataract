import { defineIsland } from "cataract/client";

defineIsland("fleet", (el, props) => {
  const cells = new Map();
  for (const stat of el.querySelectorAll("[data-stat]"))
    cells.set(stat.dataset.stat, stat.querySelector("dd") ?? stat);

  const show = (name, value) => {
    const cell = cells.get(name);
    if (cell) cell.textContent = String(value);
  };

  const stamp = el.querySelector(".refreshed");
  if (stamp) stamp.textContent = `live, every ${props.everyMillis ?? 0}ms`;

  return {
    update(data) {
      const counts = { healthy: 0, degraded: 0, offline: 0 };
      for (const node of data.nodes ?? [])
        counts[node.status] = (counts[node.status] ?? 0) + 1;

      show("nodes", data.total ?? 0);
      for (const [status, total] of Object.entries(counts)) show(status, total);
      if (stamp) stamp.textContent = `updated ${new Date().toLocaleTimeString()}`;
    },
  };
});
