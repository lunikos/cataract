import { defineIsland } from "cataract/client";

defineIsland("counter", (el, props) => {
  const button = el.querySelector("button") ?? el;
  let value = Number.isFinite(props.start) ? props.start : 0;
  const label = props.label ?? "clicks";

  const render = () => {
    button.textContent = `${value} ${label}`;
  };

  button.addEventListener("click", () => {
    value += 1;
    render();
  });

  render();
});
