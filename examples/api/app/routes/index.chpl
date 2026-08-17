module ApiIndex {
  use Cataract;
  use TaskStore;

  proc get(ctx: Context): Response {
    var b = new JsonBuilder();
    b.beginObject();
    b.field("service", "tasks-api");
    b.field("runtime", "cataract/" + Cataract.version);
    b.field("tasks", TaskStore.count());
    b.key("endpoints");
    b.beginArray();
    for e in ["GET /tasks", "POST /tasks", "GET /tasks/[id]",
              "PATCH /tasks/[id]", "DELETE /tasks/[id]"] do b.value(e);
    b.endArray();
    b.endObject();

    var res = jsonResponse(b.done());
    res.setHeader("Cache-Control", "no-store");
    return res;
  }
}
