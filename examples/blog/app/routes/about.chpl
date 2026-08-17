module PageAbout {
  use Cataract;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "About Cataract";
    meta.description = "How the toolchain and the runtime fit together.";

    var h = new MarkupBuilder();
    h.el("h1", "About");
    h.el("p", "Cataract is two layers with one seam between them.");

    h.el("h2", "The toolchain");
    h.el("p", "cataract-cli walks app/routes, turns file names into route " +
              "patterns, content-addresses the assets, and emits a small set of " +
              "generated modules that chpl links into one binary.");

    h.el("h2", "The runtime");
    h.el("p", "cataract-runtime owns the socket. The accept loop hands each " +
              "connection to a Chapel task through a bounded gate, the parser " +
              "works over a sliding window in that connection's own buffer, and " +
              "the router resolves a path through a static hash lookup before " +
              "falling back to a specificity-ordered walk.");

    h.el("h2", "What a route sees");
    h.el("p", "A handler receives a Context: a parsed request, decoded path " +
              "parameters, a query map, and per-request locals. There is no file " +
              "descriptor, no buffer, and no C pointer anywhere in that surface.");

    return h.done();
  }
}
