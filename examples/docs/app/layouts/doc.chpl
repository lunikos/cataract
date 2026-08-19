module DocLayout {
  use Cataract;
  use CataractAssets;
  use Chrome;
  use Pages;

  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {
    meta.icon = asset("/img/logo.svg");

    var h = new MarkupBuilder();
    h.raw(Chrome.header(asset("/img/logo.svg")));

    h.open("div", "class", "shell");
    h.raw(island(meta, "toc", tocProps(), tocMarkup()));

    h.open("main", "id", "content");
    h.raw(slot);
    h.close();
    h.close();

    h.raw(Chrome.footer());
    return h.done();
  }

  private proc tocProps(): string {
    var j = new JsonBuilder();
    j.beginObject();
    j.key("sections");
    j.beginArray();
    for name in Pages.sections {
      j.beginObject();
      j.field("name", name);
      j.key("pages");
      j.beginArray();
      for d in Pages.inSection(name) {
        j.beginObject();
        j.field("title", d.title);
        j.field("href", "/docs/" + d.slug);
        j.endObject();
      }
      j.endArray();
      j.endObject();
    }
    j.endArray();
    j.endObject();
    return j.done();
  }

  private proc tocMarkup(): string {
    var h = new MarkupBuilder();
    h.open("nav", "class", "toc", "aria-label", "Documentation");
    for name in Pages.sections {
      h.el("h2", name);
      h.open("ul");
      for d in Pages.inSection(name) {
        h.open("li");
        h.el("a", d.title, "href", "/docs/" + d.slug);
        h.close();
      }
      h.close();
    }
    return h.done();
  }
}
