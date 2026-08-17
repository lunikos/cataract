module Pages {
  record Doc {
    var slug: string;
    var section: string;
    var title: string;
    var summary: string;
    var body: string;
  }

  /* Never mutated, so every task reads it without synchronisation. */
  private const docs = [
    new Doc("guide/install", "Guide", "Installing",
            "Chapel 2.x on a POSIX host, and nothing else.",
            "Cataract needs `chpl` on PATH and a C toolchain for the socket " +
            "shim. There is no package manager, no lockfile, and no node_modules."),
    new Doc("guide/routing", "Guide", "File-system routing",
            "Directory layout is the route table.",
            "A module exporting `page` is a page and one exporting HTTP-named " +
            "procedures is an API route. `[id]` captures one segment, `[...path]` " +
            "the rest, and a `(group)` directory adds no segment."),
    new Doc("guide/islands", "Guide", "Islands",
            "Ship JavaScript only where behaviour lives.",
            "A page renders to final markup on the server and ships no client " +
            "bundle until it declares an island. Only declared regions hydrate."),
    new Doc("reference/context", "Reference", "Context",
            "What a handler actually receives.",
            "`ctx.pathParam`, `ctx.queryParam`, `ctx.request.header` and " +
            "per-request locals. No descriptors, no buffers, no C pointers."),
    new Doc("reference/config", "Reference", "Configuration",
            "cataract.toml, and the config consts it bakes in.",
            "Every server knob becomes a Chapel `config const`, so a built " +
            "binary is redeployable without a rebuild: --port, --logLevel.")
  ];

  const sections = ["Guide", "Reference"];

  iter all() {
    for d in docs do yield d;
  }

  iter inSection(name: string) {
    for d in docs do
      if d.section == name then yield d;
  }

  proc count(): int do return docs.size;

  proc find(slug: string, ref result: Doc): bool {
    for d in docs {
      if d.slug == slug {
        result = d;
        return true;
      }
    }
    return false;
  }
}
