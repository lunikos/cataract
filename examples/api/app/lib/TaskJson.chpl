module TaskJson {
  use Cataract;
  use TaskStore only Task;

  proc writeTask(ref b: JsonBuilder, const ref t: Task) {
    b.beginObject();
    b.field("id", t.id);
    b.field("title", t.title);
    b.field("done", t.done);
    b.endObject();
  }
}
