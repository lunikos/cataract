module PagePosts {
  use Cataract;
  use PostStore;

  proc page(ctx: Context, ref meta: PageMeta): string {
    const total = PostStore.count();
    meta.title = "Posts (" + total:string + ")";
    meta.description = "Everything published so far.";

    var h = new MarkupBuilder();
    h.el("h1", "Posts");

    if total == 0 {
      h.el("p", "Nothing published yet.", "class", "empty");
      return h.done();
    }

    h.open("ul", "class", "posts");
    for p in PostStore.all() {
      h.open("li");
      h.el("a", p.title, "href", "/posts/" + p.id);
      h.el("p", p.summary);
      h.el("span", p.published, "class", "date");
      h.close();
    }
    return h.done();
  }
}
