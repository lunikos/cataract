module PageIndex {
  use Cataract;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Cataract";
    meta.description = "A full-stack meta-framework written in Chapel.";

    var h = new MarkupBuilder();
    h.el("h1", "Documentation, server-rendered");
    h.el("p", "This example exercises the parts of the router the blog example " +
              "does not: catch-all segments, route groups, a second layout, and " +
              "an island that lives in the layout rather than in a page.");

    h.el("h2", "Routes in this example");
    h.open("ul", "class", "routes");
    entry(h, "/", "this page, root layout");
    entry(h, "/docs", "the index, doc layout");
    entry(h, "/docs/[...path]", "every article, one catch-all route");
    entry(h, "/pricing", "inside (marketing)/, which contributes no path segment");
    h.close();

    h.open("p");
    h.el("a", "Read the docs", "href", "/docs");
    h.close();
    return h.done();
  }

  private proc entry(ref h: MarkupBuilder, pattern: string, note: string) {
    h.open("li");
    h.el("code", pattern);
    h.text(" — " + note);
    h.close();
  }
}
