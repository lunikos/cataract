module ApiNodes {
  use Cataract;
  use Fleet;

  /* Same tree as the pages: method handlers make this an API route. */
  proc get(ctx: Context): Response {
    const status = ctx.queryParam("status");
    if !status.isEmpty() && !Fleet.isKnownStatus(status) {
      var e = new JsonBuilder();
      e.beginObject();
      e.field("error", "unknown_status");
      e.field("detail", status);
      e.endObject();
      return jsonResponse(e.done(), 400);
    }

    var b = new JsonBuilder();
    b.beginObject();
    b.key("nodes");
    b.beginArray();
    var total = 0;
    for n in Fleet.matching(status, ctx.queryParam("region")) {
      total += 1;
      b.beginObject();
      b.field("id", n.id);
      b.field("region", n.region);
      b.field("status", n.status);
      b.field("cpu", n.cpu);
      b.field("memory", n.memory);
      b.field("uptimeHours", n.uptimeHours);
      b.endObject();
    }
    b.endArray();
    b.field("total", total);
    b.endObject();
    return jsonResponse(b.done());
  }
}
