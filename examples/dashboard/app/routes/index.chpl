module PageIndex {
  use Cataract;
  use Fleet;
  use FleetView;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Fleet overview";
    meta.description = "Six nodes across three regions.";

    var h = new MarkupBuilder();
    h.el("h1", "Overview");
    h.raw(counts(meta));

    h.el("h2", "Live");
    h.open("section", "class", "live");
    h.raw(islandLive(meta, statsTree(), "/ws/fleet", FleetView.stepMillis));
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

  private proc counts(ref meta: PageMeta): string {
    param everyMillis = 5000;

    var props = new JsonBuilder();
    props.beginObject();
    props.field("everyMillis", everyMillis);
    props.endObject();

    var rendered = new MarkupBuilder();
    rendered.open("dl", "class", "stats");
    stat(rendered, "nodes", Fleet.count());
    stat(rendered, "healthy", Fleet.countByStatus("healthy"));
    stat(rendered, "degraded", Fleet.countByStatus("degraded"));
    stat(rendered, "offline", Fleet.countByStatus("offline"));
    rendered.close();
    rendered.el("p", "server-rendered", "class", "refreshed");

    return islandFetch(meta, "fleet", props.done(), rendered.done(), "/api/nodes",
                       everyMillis);
  }

  private proc stat(ref h: MarkupBuilder, title: string, value: int) {
    h.open("div", "class", "stat " + title, "data-stat", title);
    h.el("dt", title);
    h.el("dd", value);
    h.close();
  }
}
