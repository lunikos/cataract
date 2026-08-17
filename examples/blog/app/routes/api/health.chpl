module ApiHealth {
  use Cataract;
  use PostStore;

  proc get(ctx: Context): Response {
    var body = new JsonBuilder();
    body.beginObject();
    body.field("status", "ok");
    body.field("runtime", "cataract/" + Cataract.version);
    body.field("posts", PostStore.count());
    body.field("requestId", ctx.requestId);
    body.endObject();

    var res = jsonResponse(body.done());
    res.setHeader("Cache-Control", "no-store");
    return res;
  }
}
