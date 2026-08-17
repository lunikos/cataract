module ApiTask {
  use Cataract;
  use TaskStore;
  use TaskJson;
  use JsonField;
  use Problem;

  proc get(ctx: Context): Response {
    const id = ctx.paramInt("id", -1);
    if id < 0 then return problem(400, "id must be a positive integer");

    var t: TaskStore.Task;
    if !TaskStore.find(id, t) then return problem(404, "no task with id " + id: string);

    var b = new JsonBuilder();
    writeTask(b, t);
    return jsonResponse(b.done());
  }

  proc patch(ctx: Context): Response throws {
    const id = ctx.paramInt("id", -1);
    if id < 0 then return problem(400, "id must be a positive integer");

    const payload = ctx.request.bodyText();
    if !JsonField.present(payload, "done") then
      return problem(422, "expected {\"done\": true} or {\"done\": false}");

    var t: TaskStore.Task;
    if !TaskStore.setDone(id, JsonField.flag(payload, "done", false), t) then
      return problem(404, "no task with id " + id: string);

    var b = new JsonBuilder();
    writeTask(b, t);
    return jsonResponse(b.done());
  }

  /* `delete` is a Chapel keyword; DELETE is spelled `del`. */
  proc del(ctx: Context): Response {
    const id = ctx.paramInt("id", -1);
    if id < 0 then return problem(400, "id must be a positive integer");
    if !TaskStore.remove(id) then return problem(404, "no task with id " + id: string);
    return noContent();
  }
}
