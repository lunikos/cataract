module PageIndex {
  use Cataract;
  use Fleet;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Fleet overview";
    meta.description = "Six nodes across three regions.";

    var h = new MarkupBuilder();
    h.el("h1", "Overview");

    h.open("dl", "class", "stats");
    stat(h, "nodes", Fleet.count());
    stat(h, "healthy", Fleet.countByStatus("healthy"));
    stat(h, "degraded", Fleet.countByStatus("degraded"));
    stat(h, "offline", Fleet.countByStatus("offline"));
    h.close();

    h.el("h2", "Regions");
    h.open("ul", "class", "regions");
    for region in Fleet.regions() {
      h.open("li");
      h.el("a", region, "href", "/nodes?region=" + region);
      h.close();
    }
    h.close();

    return h.done();
  }

  private proc stat(ref h: MarkupBuilder, title: string, value: int) {
    h.open("div", "class", "stat " + title);
    h.el("dt", title);
    h.el("dd", value);
    h.close();
  }
}
