# Project layout and configuration

## Directories

```
cataract.toml
app/
  routes/          pages, API routes and sockets; the tree is the route table
  layouts/         document chrome; every page names one
  lib/             shared modules
  islands/         client-side components
  public/          static files, content-addressed at build time
  db/              schema.sql, queries.sql and seed.sql
.cataract/         generated sources, processed assets and the build cache
dist/              the compiled binary, and dist/static from `build --static`
data/              row files, when [database] path is set
```

Only `cataract.toml` and `app/routes` are required. A project with no pages needs
no `app/layouts`.

Every file under `app/` must declare its module explicitly:

```chapel
module PagePosts {
  use Cataract;

  proc page(ctx: Context, ref meta: PageMeta): string {
    return "";
  }
}
```

Chapel would otherwise derive the module name from the file name, and two
`index.chpl` files in different directories would collide. The scanner reads the
declared name back and generates code that calls it, so it must be unique across
the project.

`.cataract/generated` holds the emitted modules, rewritten on every build and
safe to delete:

| module | holds |
| --- | --- |
| `CataractAssets.chpl` | the `asset` lookup |
| `GeneratedRoutes.chpl` | one handler class per route, and `staticTargets` |
| `CataractUrls.chpl` | the `Route` enum and `url` |
| `CataractSchema.chpl` | records and query procedures, when a schema exists |
| `CataractMain.chpl` | `main`, the middleware stack and every `config const` |

Files no longer emitted are pruned, so a stale module cannot survive a rebuild.

## Commands

```
cataract build            scan routes, generate sources, compile a binary
cataract build --static   render every static route to a directory of files
cataract dev              rebuild and restart on change
cataract routes           print the route table in match order
cataract new NAME         scaffold an application
```

```
--root <dir>       project root (default: .)
--config <file>    config file relative to root (default: cataract.toml)
--port <n>         override server.port for this invocation
--watch-ms <n>     dev poll interval in milliseconds (default: 400)
--static           render every static route to files and exit
--static-out <dir> where --static writes (default: dist/static)
--force            rebuild even when nothing changed
--grace-ms <n>     dev shutdown grace period (default: 5000)
--notes            include notes in diagnostic output
```

Errors, warnings and a successful build are coloured when the output is a
terminal; `NO_COLOR` turns that off.

### Incremental builds

Chapel compiles a whole program, so the way to make a rebuild fast is not to run
the compiler. Every build fingerprints exactly what `chpl` reads — Chapel and C
sources, the SQL files, the generated modules, the flags — and compares it with
the last build:

```
built    dist/blog  (4 pages, 2 api routes, 0 sockets, 0 tables, 2 assets) in 11.92s
current  dist/blog  (4 pages, 2 api routes, 0 sockets, 0 tables, 2 assets) unchanged
restored dist/blog  (4 pages, 2 api routes, 0 sockets, 0 tables, 2 assets) from the cache
```

`current` means the digest matched and the binary is already right. `restored`
means the digest matched a binary in `.cataract/cache`, which is what makes
undoing an edit instant instead of a recompile; the last eight are kept.
`--force` bypasses both.

### dev

`dev` rebuilds without `--fast`, because an optimising compile costs more than
it saves on a binary replaced seconds later.

It also emits the asset table without version markers, since a versioned URL
means nothing while the static file cache is off. Editing a stylesheet or an
island therefore changes no compiled input at all: the files are copied, the
running server picks them up, and nothing restarts.

```
assets updated; the server keeps running
```

A change to Chapel source does rebuild, and then the server is restarted through
`SIGTERM` so it drains what it is holding; `--grace-ms` bounds the wait before
`SIGKILL`. Ctrl-C takes the same path — see
[Shutdown](deployment.md#graceful-shutdown).

## cataract.toml

Read as a flat key/value subset of TOML: `[section]` headers, `key = value`, `#`
comments, quoted or bare scalars. Nested tables and arrays are rejected rather
than half-supported.

```toml
[project]
name = "blog"                # the binary's name under dist/
version = "0.1.0"

[paths]
runtime = "../../src/runtime"

[server]
host = "127.0.0.1"
port = 3000
max_concurrency = 512        # connection tasks in flight
max_body_bytes = 1048576     # a larger body is rejected with 413
keep_alive_ms = 5000         # idle time between pipelined requests
header_timeout_ms = 10000    # per-recv timeout
request_timeout_ms = 20000   # whole-request budget, armed at the first byte
drain_seconds = 10           # how long shutdown waits for connections in flight
log_level = "info"           # debug, info, warn, error

socket_max_message_bytes = 1048576   # a larger WebSocket message closes with 1009
socket_idle_timeout_ms = 300000      # silence before a socket is dropped
socket_send_timeout_ms = 10000       # how long one frame may take to write
socket_subprotocols = ""             # comma-separated, negotiated if asked

[database]
path = "data"                # one file per table; unset means memory only

[distribution]
affinity = "pinned"          # pinned, round-robin, path, client, sticky
sticky_key = "sid"           # query parameter or cookie read by sticky
listeners = "single"         # single, or per-locale
expose_locale = false        # adds X-Cataract-Locale to every response

[middleware]
groups = "api"               # each named group gets its own section

[middleware.api]
match = "/api"               # path prefix the group covers
use = "cors, rate-limit"     # stages, in the order they run
cors_origins = "https://app.example"
rate_limit_requests = 120
rate_limit_window_ms = 60000

[build]
optimize = true              # passes --fast to chpl; `dev` never does
chpl_flags = ""

[security]
csp = "default-src 'self'; object-src 'none'; frame-ancestors 'none'"
hsts_seconds = 0
allowed_origins = ""         # comma-separated
```

`[middleware]` is covered in [Middleware](middleware.md), `[database]` in
[Compile-time SQL](data.md) and `[distribution]` in
[Locales](deployment.md#locales-and-affinity).

`header_timeout_ms` bounds a single read; `request_timeout_ms` bounds the whole
request, which is what a dripping client cannot restart.

### paths

`app`, `routes`, `layouts`, `islands`, `lib`, `public`, `db`, `out`, `dist` all
default to the tree above and can be moved. `runtime` must point at the framework's
`src/runtime`, and is resolved relative to the directory holding
`cataract.toml`. If it is unset or missing, `CATARACT_RUNTIME` is used; a
configured path that exists always wins, so a vendored copy is never bypassed by
the environment.

## Runtime overrides

Every server setting becomes a Chapel `config const`, so a compiled binary is
reconfigurable without a rebuild:

```
./dist/blog --port=8080 --host=0.0.0.0 --logLevel=debug
./dist/blog --maxConcurrency=2048 --requestTimeoutMillis=5000
./dist/blog --staticRoot=/srv/blog/public
```

| flag | from |
| --- | --- |
| `--host` `--port` `--logLevel` | the matching `server` keys |
| `--maxConcurrency` `--maxBodyBytes` | `max_concurrency`, `max_body_bytes` |
| `--keepAliveMillis` `--headerTimeoutMillis` `--requestTimeoutMillis` | the matching timeouts |
| `--hstsSeconds` `--allowedOrigins` | the matching `security` keys |
| `--drainSeconds` | `drain_seconds` |
| `--socketMaxMessageBytes` `--socketIdleTimeoutMillis` | the matching `server` keys |
| `--socketSendTimeoutMillis` `--socketSubprotocols` | the matching `server` keys |
| `--affinity` `--stickyKey` `--listeners` `--exposeLocale` | the `distribution` keys |
| `--databaseDir` | `database.path` |
| `--staticRoot` | the built asset directory |
| `--staticOut` | render every static route into this directory and exit |
| `--devMode` | disables the static file cache |
| `--serverToken` | the `Server` response header |

`--staticRoot` matters in deployment: the built-in value is the path the asset
directory had at build time, so a binary moved to another machine needs it set,
or needs to be run from the build root.
