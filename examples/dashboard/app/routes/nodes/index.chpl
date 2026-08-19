module PageNodes {
  use Cataract;
  use Fleet;

  proc page(ctx: Context, ref meta: PageMeta): string {
    const status = ctx.queryParam("status");
    const region = ctx.queryParam("region");

    if !status.isEmpty() && !Fleet.isKnownStatus(status) {
      meta.status = 400;
      meta.title = "Unknown status";
      var e = new MarkupBuilder();
      e.el("h1", "Unknown status");
      e.el("p", "\"" + status + "\" is not one of healthy, degraded, offline.");
      e.el("a", "All nodes", "href", "/nodes");
      return e.done();
    }

    meta.title = if status.isEmpty() then "Nodes" else "Nodes: " + status;

    var h = new MarkupBuilder();
    h.el("h1", "Nodes");

    h.open("p", "class", "filters");
    filter(h, "All", "/nodes", status.isEmpty() && region.isEmpty());
    filter(h, "Healthy", "/nodes?status=healthy", status == "healthy");
    filter(h, "Degraded", "/nodes?status=degraded", status == "degraded");
    filter(h, "Offline", "/nodes?status=offline", status == "offline");
    h.close();

    var shown = 0;
    h.open("table");
    h.open("thead");
    h.open("tr");
    for column in ["node", "region", "status", "cpu", "memory"] do
      h.el("th", column, "scope", "col");
    h.close();
    h.close();

    h.open("tbody");
    for n in Fleet.matching(status, region) {
      shown += 1;
      h.open("tr", "class", classList("warn", n.status == "degraded",
                                      "down", n.status == "offline"));
      h.open("td");
      h.el("a", n.id, "href", "/nodes/" + n.id);
      h.close();
      h.el("td", n.region);
      h.el("td", n.status);
      h.el("td", n.cpu:string + "%");
      h.el("td", n.memory:string + "%");
      h.close();
    }
    h.close();
    h.close();

    if shown == 0 then h.el("p", "No nodes match that filter.", "class", "empty");
    return h.done();
  }

  private proc filter(ref h: MarkupBuilder, title: string, href: string, active: bool) {
    if active then h.el("a", title, "href", href, "aria-current", "true");
    else h.el("a", title, "href", href);
    h.raw(" ");
  }
}
