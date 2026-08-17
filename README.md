<img src="assets/emblem.png" alt="" width="72" align="left">

# Cataract

A full-stack web framework for [Chapel](https://chapel-lang.org). File-system
routing, server-side rendering, partial hydration and an HTTP/1.1 server on raw
BSD sockets, compiled into one binary. Application code is Chapel throughout —
there is no template language.

<br clear="left">

Requires Chapel 2.x with `chpl` on `PATH`, and a POSIX host with a C compiler.

```
make                                  # builds bin/cataract
export CATARACT_RUNTIME=$PWD/src/runtime
cataract new blog && cd blog && cataract build && ./dist/blog
```

A page is a module exporting `page`; the file's location gives it a path.

```chapel
module PageIndex {
  use Cataract;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Posts";
    var h = new MarkupBuilder();
    h.el("h1", "Posts");
    for p in PostStore.all() do h.el("a", p.title, "href", "/posts/" + p.id);
    return h.done();
  }
}
```

`build`, `dev` (rebuild and restart on change), `routes` (print the table in
match order) and `new` are the whole CLI. Every server setting is a Chapel
`config const`, so a built binary is reconfigurable without a rebuild:
`./dist/blog --port=8080 --logLevel=debug`.

## Documentation

- [Project layout and configuration](documentation/project.md)
- [Routing and handlers](documentation/routing.md)
- [Pages, layouts, islands and assets](documentation/rendering.md)
- [Architecture and security](documentation/internals.md)

## Examples

Four standalone projects under [`examples/`](examples): `blog` (the full stack),
`api` (headless JSON, mutable shared state), `docs` (catch-all routes, route
groups, two layouts), `dashboard` (query filters, status codes from a page).
`make examples` builds all four; `make run-blog` runs one.

## Contributing

`make` builds the toolchain and `make examples` exercises it end to end; both
must pass. Keep comments to architectural context and C-interop caveats, open an
issue before changing the public API, and report security issues privately.

Version 0.1.0. The public API is not yet stable.
