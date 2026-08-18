import { defineIsland } from "cataract/client";

defineIsland("uptime", (el, props) => {
  const line = el.querySelector("p") ?? el;
  const started = Date.now() - (props.hours ?? 0) * 3600_000;

  const format = (ms) => {
    const hours = Math.floor(ms / 3600_000);
    const minutes = Math.floor((ms % 3600_000) / 60_000);
    const seconds = Math.floor((ms % 60_000) / 1000);
    return `${hours}h ${minutes}m ${seconds}s`;
  };

  const render = () => {
    line.textContent = `${format(Date.now() - started)} since last restart`;
  };

  render();
  if (!props.live) return;

  const timer = setInterval(render, 1000);
  return () => clearInterval(timer);
});
