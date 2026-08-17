module ApiTasks {
  use Cataract;
  use TaskStore;
  use TaskJson;
  use JsonField;
  use Problem;

  proc get(ctx: Context): Response {
    const status = ctx.queryParam("status");
    if !status.isEmpty() && status != "open" && status != "done" then
      return problem(400, "status must be open or done");

    var limit = 0;
    const rawLimit = ctx.queryParam("limit");
    if !rawLimit.isEmpty() {
      try {
        limit = rawLimit: int;
      } catch {
        return problem(400, "limit must be an integer");
      }
      if limit < 1 then return problem(400, "limit must be at least 1");
    }

    const tasks = TaskStore.snapshot();
    var emitted = 0;

    var b = new JsonBuilder();
    b.beginObject();
    b.key("tasks");
    b.beginArray();
    for t in tasks {
      if status == "open" && t.done then continue;
      if status == "done" && !t.done then continue;
      if limit > 0 && emitted >= limit then break;
      writeTask(b, t);
      emitted += 1;
    }
    b.endArray();
    b.field("returned", emitted);
    b.field("total", tasks.size);
    b.endObject();

    return jsonResponse(b.done());
  }

  /* `throws`, so an escaped error becomes a 500 rather than an unwind. */
  proc post(ctx: Context): Response throws {
    const payload = ctx.request.bodyText();
    if payload.isEmpty() then return problem(400, "expected a JSON body");

    const title = JsonField.text(payload, "title");
    if title.isEmpty() then return problem(422, "title is required");
    if title.size > 120 then return problem(422, "title must be 120 characters or fewer");

    const created = TaskStore.add(title);

    var b = new JsonBuilder();
    writeTask(b, created);

    var res = jsonResponse(b.done(), 201);
    res.setHeader("Location", "/tasks/" + created.id: string);
    return res;
  }
}
