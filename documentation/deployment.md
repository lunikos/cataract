# Static export, locales and shutdown

Three ways of putting an application somewhere: as a directory of files, as one
process, or as several locales of one program.

## Static export

```
cataract build --static
cataract build --static --static-out public/
```

`--static` compiles the project as usual, then runs the binary with
`--staticOut`, which routes every exportable path through the real request
pipeline — middleware, layouts, the lot — and writes the responses to disk
instead of to a socket. The default output is `dist/static`.

```
dist/static/
  index.html                    <- /
  about/index.html              <- /about
  posts/index.html              <- /posts
  posts/hello-chapel/index.html <- /posts/hello-chapel
  api/health                    <- /api/health, verbatim
  404.html
  styles.css
  _cataract/client.js
```

A page becomes `<path>/index.html`, so its URL keeps working on any static host
without a rewrite rule. A `GET` API route keeps its exact path, which is what
lets an island's `fetch` endpoint survive the export — note that most static
hosts will serve an extensionless file as `application/octet-stream` unless you
tell them otherwise. `404.html` comes from a deliberate miss against the router,
so it is the same document a running server would send. Everything under
`.cataract/public` is copied alongside.

A route with dynamic segments exports only if its module says which paths exist:

```chapel
module PagePost {
  use Cataract;
  use CataractUrls;
  use List;
  use PostStore;

  proc staticPaths(): list(string) throws {
    var known: list(string);
    for post in PostStore.all() do known.pushBack(url(Route.postsId, post.id));
    return known;
  }

  proc page(ctx: Context, ref meta: PageMeta): string {
    return renderPost(ctx.pathParam("id"));
  }
}
```

Building `url` from the same `Route` constant the links use means a typo in a
static path is a compile error, not a page that exports to the wrong name.

A dynamic route with no `staticPaths` is reported by name during the build:

```
warning: app/routes/posts/[id].chpl: /posts/[id] has no static form and was not exported
       hint: declare `proc staticPaths(): list(string)` listing the paths to render
```

A path whose handler answers anything outside `2xx` is skipped and logged, and
the export's exit code is non-zero only if a file could not be written.

Sockets are skipped: a WebSocket route has no static form.

## Locales and affinity

Chapel replicates module-level variables per locale, so which locale runs a
handler decides which copy of that state it sees. Affinity is the rule that
decides.

```toml
[distribution]
affinity = "path"        # pinned | round-robin | path | client | sticky
sticky_key = "sid"       # query parameter or cookie read by sticky
listeners = "single"     # single | per-locale
expose_locale = false    # adds X-Cataract-Locale to every response
```

| affinity | the handler runs on |
| --- | --- |
| `pinned` | the locale that accepted the connection; nothing moves |
| `round-robin` | the next locale in turn |
| `path` | a locale chosen by hashing the request path |
| `client` | a locale chosen by hashing `clientIp()` |
| `sticky` | a locale chosen by hashing `sticky_key` from the query string or a cookie, falling back to the client |

`pinned` is the default and costs nothing: no remote task, no `on` statement.
Under every other mode the accept loop, the parse and the response write stay on
the accepting locale, and only the handler moves — so a per-route cache built by
`path` affinity, or a per-session cache built by `sticky`, is reached by the
same locale every time.

`listeners = "per-locale"` is the other shape: every locale binds its own
listener on `port + locale.id` and serves its own connections, for a fleet
behind a load balancer. State is per-locale there too, with no affinity rule
mediating it, so a service in that mode should keep its state outside the
process.

Both need a Chapel built with communication enabled and a locale count on the
command line:

```
./dist/app -nl 4
```

Built with `CHPL_COMM=none`, `numLocales` is 1, every affinity rule resolves to
the local locale and the `on` statements never fire. The same binary is correct
either way.

`--exposeLocale=true` adds `X-Cataract-Locale` to each response, which is how to
check that placement is doing what the configuration says.

## Graceful shutdown

`SIGINT` and `SIGTERM` set a flag; the handler does nothing else. The accept
loop notices, closes the listener so the port is free immediately, stops
renewing keep-alive on connections in flight, and waits for them to finish:

```
info   shutdown requested; draining 3 connection(s)
info   stopped after 1841 request(s), 210 connection(s)
```

`server.drain_seconds` (default 10) bounds the wait. Passing the deadline logs a
warning and keeps waiting rather than cutting a response in half, because a
supervisor's own timeout is the right place to give up.

```toml
[server]
drain_seconds = 10
```

`cataract dev` installs the same pair. Ctrl-C stops the watcher, sends `SIGTERM`
to the server it spawned, waits up to `--grace-ms` (default 5000) for it to
drain, and only then sends `SIGKILL`. A restart caused by an edit takes the same
path, so a rebuild never leaves a half-served request or a held port behind.

## Deploying one process

The built binary carries its configuration as `config const`s, so a build can be
reconfigured without rebuilding:

```
./dist/blog --port=8080 --host=0.0.0.0 --logLevel=warn \
            --staticRoot=/srv/blog/public --drainSeconds=30
```

`--staticRoot` matters most: its built-in value is the path the asset directory
had at build time, so a binary moved to another machine needs it set, or needs
to be run from the build root. With `[database] path` set, the same applies to
the row files, which are resolved relative to the project root at build time.

Cataract terminates no TLS. Put it behind a proxy, and have that proxy set
`X-Forwarded-Proto` so `security.hsts_seconds` takes effect.
