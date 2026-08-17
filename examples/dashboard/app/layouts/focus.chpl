module FocusLayout {
  use Cataract;

  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {
    meta.bodyClass = "focus";

    var h = new MarkupBuilder();
    h.open("header", "class", "top");
    h.el("a", "← fleet", "class", "brand", "href", "/nodes");
    h.close();

    h.open("main", "class", "narrow");
    h.raw(slot);
    h.close();

    return h.done();
  }
}
