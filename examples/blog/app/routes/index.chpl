module PageIndex {
  use Cataract;
  use PostStore;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Cataract";
    meta.description = "A full-stack meta-framework written in Chapel.";

    var h = new MarkupBuilder();
    h.el("h1", "A meta-framework in Chapel");
    h.el("p", "File-system routes, server-rendered pages, and a task-parallel " +
              "HTTP/1.1 engine built directly on <sys/socket.h>.");

    h.raw(counter(meta));

    h.el("h2", "Latest");
    h.open("ul", "class", "posts");
    for p in PostStore.all() {
      if p.published <= "2026-01-31" then continue;
      h.open("li");
      h.el("a", p.title, "href", "/posts/" + p.id);
      h.el("span", p.published, "class", "date");
      h.close();
    }
    h.close();

    h.open("p");
    h.el("a", "All " + PostStore.count():string + " posts", "href", "/posts");
    h.close();

    return h.done();
  }

  private proc counter(ref meta: PageMeta): string {
    var props = new JsonBuilder();
    props.beginObject();
    props.field("start", PostStore.count());
    props.field("label", "posts loaded");
    props.endObject();

    var fallback = new MarkupBuilder();
    fallback.el("button", PostStore.count():string + " posts loaded",
                "class", "counter", "type", "button");

    return island(meta, "counter", props.done(), fallback.done());
  }
}
