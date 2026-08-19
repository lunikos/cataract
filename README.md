<img src="assets/emblem.png" alt="" width="72" align="right">

# Cataract

A full-stack web framework for [Chapel](https://chapel-lang.org). File-system
routing, server-side rendering, partial hydration, WebSockets and an HTTP/1.1
server on raw BSD sockets, in one binary. Chapel throughout; no templates.

<br clear="right">

Requires Chapel 2.x with `chpl` on `PATH`, and a POSIX host with a C compiler.
Source-only for now, no package manager, clone and build:

```
git clone https://github.com/lunikos/cataract.git && cd cataract
make                                   # builds bin/cataract
export CATARACT_RUNTIME=$PWD/src/runtime
cataract new blog && cd blog && cataract build && ./dist/blog
```

A page is a module exporting `page`; the file's location gives it a path.

```chapel
module PageIndex {
  use Cataract;
  use CataractUrls;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Posts";
    var h = new MarkupBuilder();
    h.el("h1", "Posts");
    for p in PostStore.all() do
      h.el("a", p.title, "href", url(Route.postsId, p.id));
    return h.done();
  }
}
```

A module exporting `get`, `post` and friends is an API route; one exporting
`socket` is a WebSocket endpoint.

```chapel
proc socket(ctx: Context, ws: shared WebSocket) throws {
  Rooms.join("lobby", ws);
  defer Rooms.leave("lobby", ws);

  var incoming = new Message();
  while ws.receive(incoming) do
    Rooms.broadcast("lobby", incoming.text(), ws.id);
}
```

What the toolchain works out before the server runs:

- **routes** — the tree under `app/routes` is the route table, and every route
  is also a `Route` enum constant, so `url(Route.postsId, id)` is checked, with
  its argument count, at compile time
- **queries** — `app/db/schema.sql` becomes typed Chapel records, `queries.sql`
  becomes procedures with each `:param` typed by the column it is compared
  against, and a misspelled column fails the build rather than a request
- **middleware** — a `[middleware]` section declares groups by path prefix, with
  built-in rate limiting, CORS and CSRF
- **assets** — `app/public` is hashed and content-addressed, and islands are
  concatenated into one client bundle

`build`, `dev` (rebuild and restart on change), `routes` (print the table in
match order) and `new` are the whole CLI; `build --static` writes every static
route out as files. A rebuild skips the compiler when nothing it reads changed,
and `dev` leaves the server up for a change that only touches assets.

Every server setting is a Chapel `config const`, so a built binary is
reconfigurable without a rebuild: `./dist/blog --port=8080 --logLevel=debug`.

## Documentation

- [Project layout and configuration](documentation/project.md)
- [Routing and handlers](documentation/routing.md)
- [Pages, layouts, islands and assets](documentation/rendering.md)
- [WebSockets and rooms](documentation/realtime.md)
- [Compile-time SQL](documentation/data.md)
- [Middleware](documentation/middleware.md)
- [Static export, locales and shutdown](documentation/deployment.md)
- [Architecture and security](documentation/internals.md)

## Examples

Four standalone projects under [`examples/`](examples): `blog` (the full stack,
reverse-routed links, a CSRF-guarded API), `api` (headless JSON on a generated
schema), `docs` (catch-all routes, route groups, two layouts, static export) and
`dashboard` (a WebSocket room, an island that refreshes itself). `make examples`
builds all four; `make run-blog` runs one and `make static` exports one.

## Contributing

`make` builds the toolchain, `make examples` exercises it end to end and
`make lint` runs chplcheck against the project's own rules; all three must pass.
Chapel sources carry no comments — names and structure are the explanation, and
anything that needs prose belongs in `documentation/`. Open an issue before
changing the public API, and report security issues privately.

Version 0.3.0. The public API is not yet stable.
