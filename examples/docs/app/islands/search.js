import { defineIsland } from "cataract/client";

// Props carry the list the server rendered, so filtering needs no request.
defineIsland("search", (el, props) => {
  const input = el.querySelector("input");
  const items = [...el.querySelectorAll(".results li")];
  const pages = props.pages ?? [];

  if (!input) return;

  const haystacks = items.map((li, i) => {
    const page = pages[i] ?? {};
    return `${page.title ?? ""} ${page.section ?? ""} ${page.summary ?? ""}`.toLowerCase();
  });

  const apply = () => {
    const needle = input.value.trim().toLowerCase();
    let shown = 0;

    items.forEach((li, i) => {
      const match = needle === "" || haystacks[i].includes(needle);
      li.hidden = !match;
      if (match) shown += 1;
    });

    input.setAttribute("aria-label", `Filter articles, ${shown} of ${items.length} shown`);
  };

  input.addEventListener("input", apply);
  apply();
});
