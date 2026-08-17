module PagePost {
  use Cataract;
  use PostStore;

  proc page(ctx: Context, ref meta: PageMeta): string {
    const id = ctx.pathParam("id");
    var post: PostStore.Post;

    var h = new MarkupBuilder();

    if !PostStore.find(id, post) {
      meta.title = "Post not found";
      meta.status = 404;
      h.el("h1", "Post not found");
      h.open("p");
      h.text("No post is published under the id ");
      h.el("code", id);
      h.text(".");
      h.close();
      h.el("a", "Back to all posts", "href", "/posts");
      return h.done();
    }

    meta.title = post.title;
    meta.description = post.summary;

    h.open("article");
    h.el("h1", post.title);
    h.el("p", "Published " + post.published, "class", "date");
    h.el("p", post.body);
    h.close();

    h.el("a", "Back to all posts", "href", "/posts");
    return h.done();
  }
}
