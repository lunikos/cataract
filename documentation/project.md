# Project layout and configuration

## Directories

```
cataract.toml
app/
  routes/          pages and API routes; the tree is the route table
  layouts/         document chrome; every page names one
  lib/             shared modules
  islands/         client-side components
  public/          static files, content-addressed at build time
.cataract/         generated sources and processed assets
dist/              the compiled binary
```

Only `cataract.toml` and `app/routes` are required. A project with no pages needs
no `app/layouts`.

Every file under `app/` must declare its module explicitly:

```chapel
module PagePosts {
  // ...
}
```

Chapel would otherwise derive the module name from the file name, and two
`index.chpl` files in different directories would collide. The scanner reads the
declared name back and generates code that calls it, so it must be unique across
the project.

`.cataract/generated` holds three modules, rewritten on every build and safe to
delete: `CataractAssets.chpl` (the `asset` lookup), `GeneratedRoutes.chpl` (one
handler class per route) and `CataractMain.chpl` (`main` and the middleware
stack). Files no longer emitted are pruned, so a stale module cannot survive a
rebuild.

## Commands

```
cataract build      scan routes, generate sources, compile a binary
cataract dev        rebuild and restart on change
cataract routes     print the route table in match order
cataract new NAME   scaffold an application
```

```
--root <dir>       project root (default: .)
--config <file>    config file relative to root (default: cataract.toml)
--port <n>         override server.port for this invocation
--watch-ms <n>     dev poll interval in milliseconds (default: 400)
--notes            include notes in diagnostic output
```

`dev` rebuilds without `--fast`, because an optimising compile costs more than it
saves on a binary replaced seconds later, and stops on Ctrl-C. Errors, warnings
and a successful build are coloured when the output is a terminal; `NO_COLOR`
turns that off.

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
log_level = "info"           # debug, info, warn, error

[build]
optimize = true              # passes --fast to chpl; `dev` never does
chpl_flags = ""

[security]
csp = "default-src 'self'; object-src 'none'; frame-ancestors 'none'"
hsts_seconds = 0
allowed_origins = ""         # comma-separated
```

`header_timeout_ms` bounds a single read; `request_timeout_ms` bounds the whole
request, which is what a dripping client cannot restart.

### paths

`app`, `routes`, `layouts`, `islands`, `lib`, `public`, `out`, `dist` all default
to the tree above and can be moved. `runtime` must point at the framework's
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
| `--staticRoot` | the built asset directory |
| `--devMode` | disables the static file cache |
| `--serverToken` | the `Server` response header |

`--staticRoot` matters in deployment: the built-in value is the path the asset
directory had at build time, so a binary moved to another machine needs it set,
or needs to be run from the build root.
