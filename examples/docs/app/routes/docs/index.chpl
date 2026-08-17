module PageDocsIndex {
  use Cataract;
  use Pages;

  param layout = "doc";

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Docs";
    meta.description = "Every article in the tree.";

    var h = new MarkupBuilder();
    h.el("h1", "Documentation");
    h.el("p", Pages.count():string + " articles, all rendered from one " +
              "catch-all route.");
    h.raw(island(meta, "search", catalog(), results()));
    return h.done();
  }

  private proc catalog(): string {
    var j = new JsonBuilder();
    j.beginObject();
    j.key("pages");
    j.beginArray();
    for d in Pages.all() {
      j.beginObject();
      j.field("title", d.title);
      j.field("section", d.section);
      j.field("summary", d.summary);
      j.field("href", "/docs/" + d.slug);
      j.endObject();
    }
    j.endArray();
    j.endObject();
    return j.done();
  }

  private proc results(): string {
    var h = new MarkupBuilder();
    h.open("input", "class", "search", "type", "search",
           "placeholder", "Filter articles", "aria-label", "Filter articles");
    h.open("ul", "class", "results");
    for d in Pages.all() {
      h.open("li");
      h.el("a", d.title, "href", "/docs/" + d.slug);
      h.el("span", d.section, "class", "section");
      h.el("p", d.summary);
      h.close();
    }
    return h.done();
  }
}
