module Problem {
  use Cataract;

  proc problem(status: int, detail: string): Response {
    var b = new JsonBuilder();
    b.beginObject();
    b.field("error", reason(status));
    b.field("status", status);
    b.field("detail", detail);
    b.endObject();
    return jsonResponse(b.done(), status);
  }
}
