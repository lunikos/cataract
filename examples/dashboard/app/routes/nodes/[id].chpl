module PageNode {
  use Cataract;
  use Fleet;

  param layout = "focus";

  proc page(ctx: Context, ref meta: PageMeta): string {
    const id = ctx.pathParam("id");
    var node: Fleet.Node;

    if !Fleet.find(id, node) {
      meta.status = 404;
      meta.title = "No such node";
      var e = new MarkupBuilder();
      e.el("h1", "No such node");
      e.el("p", "Nothing in the fleet answers to \"" + id + "\".");
      e.el("a", "Back to all nodes", "href", "/nodes");
      return e.done();
    }

    meta.title = node.id + " — " + node.status;
    meta.description = node.region + ", " + node.uptimeHours:string + "h uptime";

    var h = new MarkupBuilder();
    h.open("h1");
    h.text(node.id);
    h.raw(" ");
    h.el("span", node.status, "class", "pill " + node.status);
    h.close();

    h.open("dl", "class", "detail");
    row(h, "region", node.region);
    row(h, "cpu", node.cpu:string + "%");
    row(h, "memory", node.memory:string + "%");
    row(h, "uptime", node.uptimeHours:string + "h");
    h.close();

    h.raw(uptimeIsland(meta, node));

    h.el("a", "All nodes", "href", "/nodes");
    return h.done();
  }

  private proc uptimeIsland(ref meta: PageMeta, const ref node: Fleet.Node): string {
    var props = new JsonBuilder();
    props.beginObject();
    props.field("node", node.id);
    props.field("hours", node.uptimeHours);
    props.field("live", node.status != "offline");
    props.endObject();

    var fallback = new MarkupBuilder();
    fallback.open("p", "class", "uptime");
    fallback.text(node.uptimeHours:string + "h since last restart");
    fallback.close();

    return island(meta, "uptime", props.done(), fallback.done());
  }

  private proc row(ref h: MarkupBuilder, title: string, value: string) {
    h.el("dt", title);
    h.el("dd", value);
  }
}
