module ApiPosts {
  use Cataract;
  use PostStore;

  proc get(ctx: Context): Response {
    const limit = ctx.queryParam("limit");
    var take = PostStore.count();
    if !limit.isEmpty() {
      try {
        take = min(take, max(0, limit: int));
      } catch {
        return jsonResponse("{\"error\":\"limit must be an integer\"}", 400);
      }
    }

    var body = new JsonBuilder();
    body.beginObject();
    body.key("posts");
    body.beginArray();
    var emitted = 0;
    for p in PostStore.all() {
      if emitted >= take then break;
      body.beginObject();
      body.field("id", p.id);
      body.field("title", p.title);
      body.field("summary", p.summary);
      body.field("published", p.published);
      body.endObject();
      emitted += 1;
    }
    body.endArray();
    body.field("total", PostStore.count());
    body.endObject();

    return jsonResponse(body.done());
  }

  proc post(ctx: Context): Response throws {
    const payload = ctx.request.bodyText();
    if payload.isEmpty() then
      return jsonResponse("{\"error\":\"empty body\"}", 400);

    const id = extractField(payload, "id");
    if id.isEmpty() then
      return jsonResponse("{\"error\":\"id is required\"}", 422);

    if PostStore.exists(id) then
      return jsonResponse("{\"error\":\"id already exists\"}", 409);

    var body = new JsonBuilder();
    body.beginObject();
    body.field("accepted", true);
    body.field("id", id);
    body.endObject();

    var res = jsonResponse(body.done(), 202);
    res.setHeader("Location", "/posts/" + id);
    return res;
  }

  private proc extractField(payload: string, name: string): string throws {
    const key = "\"" + name + "\"";
    const at = payload.find(key);
    if at == -1 then return "";

    const afterKey = payload[(at + key.numBytes)..];
    const colon = afterKey.find(":");
    if colon == -1 then return "";

    const afterColon = afterKey[(colon + 1)..];
    const open = afterColon.find("\"");
    if open == -1 then return "";

    const value = afterColon[(open + 1)..];
    const close = value.find("\"");
    if close == -1 then return "";

    return value[..<close];
  }
}
