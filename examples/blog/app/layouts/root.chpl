module RootLayout {
  use Cataract;
  use CataractAssets;

  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {
    meta.icon = asset("/favicon.svg");

    var h = new MarkupBuilder();
    h.el("a", "Skip to content", "class", "skip", "href", "#content");

    h.open("header", "class", "site");
    h.el("a", "Cataract", "class", "brand", "href", "/");
    h.open("nav");
    h.el("a", "Posts", "href", "/posts");
    h.el("a", "About", "href", "/about");
    h.el("a", "Health", "href", "/api/health");
    h.close();
    h.close();

    h.open("main", "id", "content");
    h.raw(slot);
    h.close();

    h.open("footer");
    h.el("span", "Rendered on the server by Chapel.");
    h.close();

    return h.done();
  }
}
