module Problem {
  use Cataract;

  /* One error shape, so a client never has to work out which handler failed. */
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
