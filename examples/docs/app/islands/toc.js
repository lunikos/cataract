import { defineIsland } from "cataract/client";

// The server rendered the contents; this only adds behaviour.
defineIsland("toc", (el, props) => {
  const here = window.location.pathname;

  for (const link of el.querySelectorAll("a")) {
    if (link.getAttribute("href") === here) {
      link.setAttribute("aria-current", "page");
    }
  }

  for (const heading of el.querySelectorAll("h2")) {
    const list = heading.nextElementSibling;
    if (!list) continue;

    heading.tabIndex = 0;
    heading.setAttribute("role", "button");
    heading.setAttribute("aria-expanded", "true");

    const toggle = () => {
      const open = heading.getAttribute("aria-expanded") === "true";
      heading.setAttribute("aria-expanded", String(!open));
      list.hidden = open;
    };

    heading.addEventListener("click", toggle);
    heading.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        toggle();
      }
    });
  }

  const total = (props.sections ?? []).reduce((n, s) => n + s.pages.length, 0);
  el.dataset.pages = String(total);
});
