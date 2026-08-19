module RootLayout {
  use Cataract;
  use Fleet;

  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {
    var h = new MarkupBuilder();

    h.open("header", "class", "top");
    h.open("a", "class", "brand", "href", "/");
    h.el("strong", "fleet");
    h.raw(" ");
    h.el("span", Fleet.overall(), "class", "pill " + Fleet.overall());
    h.close();

    h.open("nav");
    navLink(h, ctx, "/", "Overview");
    navLink(h, ctx, "/nodes", "Nodes");
    navLink(h, ctx, "/api/nodes", "API");
    h.close();
    h.close();

    h.open("main");
    h.raw(slot);
    h.close();

    h.open("footer");
    h.text("Rendered by Cataract " + version + ".");
    h.close();

    return h.done();
  }

  private proc navLink(ref h: MarkupBuilder, const ref ctx: Context,
                       href: string, title: string) {
    if ctx.path() == href then h.el("a", title, "href", href, "aria-current", "page");
    else h.el("a", title, "href", href);
  }
}
