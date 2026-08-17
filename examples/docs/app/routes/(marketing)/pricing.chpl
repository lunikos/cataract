module PagePricing {
  use Cataract;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Pricing";
    meta.description = "There is no pricing.";

    var h = new MarkupBuilder();
    h.el("h1", "Pricing");
    h.open("p");
    h.text("This page lives at ");
    h.el("code", "app/routes/(marketing)/pricing.chpl");
    h.text(" and serves ");
    h.el("code", "/pricing");
    h.text(". A directory wrapped in parentheses groups files on disk without " +
           "contributing a path segment.");
    h.close();
    return h.done();
  }
}
