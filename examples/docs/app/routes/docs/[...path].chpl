module PageDoc {
  use Cataract;
  use List;
  use Pages;

  param layout = "doc";

  proc staticPaths(): list(string) throws {
    var known: list(string);
    for doc in Pages.all() do known.pushBack("/docs/" + doc.slug);
    return known;
  }

  proc page(ctx: Context, ref meta: PageMeta): string {
    /* A catch-all arrives whole: "guide/routing", not two parameters. */
    const slug = ctx.pathParam("path");
    var doc: Pages.Doc;

    var h = new MarkupBuilder();

    if !Pages.find(slug, doc) {
      meta.title = "No such page";
      meta.status = 404;
      h.el("h1", "No such page");
      h.open("p");
      h.text("Nothing is published at ");
      h.el("code", "/docs/" + slug);
      h.text(".");
      h.close();
      h.el("a", "Back to the index", "href", "/docs");
      return h.done();
    }

    meta.title = doc.title;
    meta.description = doc.summary;

    h.open("article");
    h.el("p", doc.section + " / " + doc.title, "class", "crumb");
    h.el("h1", doc.title);
    h.el("p", doc.summary, "class", "summary");
    h.el("p", doc.body);
    return h.done();
  }
}
