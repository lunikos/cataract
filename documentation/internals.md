# Architecture and security

Cataract is two layers. `cataract-cli` scans a project and generates Chapel
source; `cataract-runtime` is the server that source is linked against. They
share only the generated code.

## The build

```
scan      walk app/routes, read each module, build a route manifest
assets    copy public/, hash each file, concatenate the island bundle
codegen   emit CataractAssets, GeneratedRoutes and CataractMain
compile   invoke chpl over the runtime, the generated modules and app/
```

Diagnostics are collected rather than thrown, so one build reports every problem
at once. Each stage is a checkpoint that aborts if errors were recorded.

Route and library modules are passed to `chpl` as source files rather than
through `-M`, because their module names deliberately do not have to match their
file names. The runtime is passed as module search paths.

Rebuilds are content-hashed, not timestamped: an editor that rewrites a file with
identical bytes does not trigger a rebuild, and a checkout that rolls timestamps
backwards does. Generated files whose content is unchanged are not rewritten, so
`chpl` does not rebuild the world.

## The request path

```
accept  ->  gate  ->  begin task  ->  parse  ->  middleware  ->  route  ->  handler
```

One task per connection. The accept loop takes a permit from a bounded gate
before spawning a task, so a connection flood becomes backpressure rather than
unbounded task creation — Chapel's `begin` has no limit of its own.

Each connection is an `owned Connection` moved into its task, which makes the
descriptor's lifetime exactly the task's lifetime, including on an error unwind.
The accept loop runs inside a `sync` block, so no connection task can outlive the
scope holding the gate it borrows.

Middleware is two-phase rather than nested continuations. `before` may
short-circuit by filling the response and returning true; `after` always runs for
the stages actually entered, in reverse order. A short-circuiting stage therefore
cannot strand logging or header hardening.

Route patterns compile to segment lists at start-up. Handlers are virtual methods
on a generated class rather than first-class procedures, so each route carries
its own compile-time state without instantiating the router generically.

## Why every socket is non-blocking

This constraint shapes the whole I/O design: **a Chapel task blocked inside a
foreign call does not release its scheduler worker.** Under the qthreads tasking
layer, a task spawned by a task sitting in a blocking `accept()` does not run
until that call returns. A server written the obvious way accepts one connection
and then serves nothing.

So every descriptor is `O_NONBLOCK` and every wait happens in Chapel: the accept
loop sleeps when nothing is pending, and `Connection.fill` and `Connection.flush`
retry across `EAGAIN` with exponential backoff against a deadline. `sleep` yields
to the scheduler, so the worker is free while a connection waits. Timeouts are
tracked against a monotonic clock rather than delegated to `SO_RCVTIMEO`.

A connection owns one read buffer used as a sliding window: `[start, stop)` is
unconsumed, and bytes left over after a request are the head of the next
pipelined request, so the window compacts rather than resets. The header scan
resumes where the previous partial read stopped, so a slow drip costs O(n)
overall rather than O(n²).

## The C boundary

All of it is `src/runtime/net/cataract_net.[ch]` plus the `extern` block in
`CSocket.chpl`. Struct layout — `sockaddr_in`, `timeval` — is platform-dependent
and padding-sensitive, so it is never mirrored into Chapel records. Chapel sees
file descriptors and flat byte buffers, and nothing else.

`SIGPIPE` is masked at start-up, so a peer disappearing mid-write surfaces as
`EPIPE` on one task instead of killing the process. `strerror` is called through
a thread-local buffer, because the standard one is shared and two concurrent
failures would overwrite each other.

Nothing above `net/` imports `CTypes` for socket work, and no application route
can reach a descriptor at all.

## Shutdown

`SIGINT` and `SIGTERM` set a flag; the handler does nothing else. The accept loop
polls it, stops accepting, and drains outstanding connections up to
`drainSeconds` before returning. Connections in flight finish their current
request; keep-alive is not renewed once shutdown is requested.

## Concurrency in application code

Route handlers run concurrently on different tasks. Module-level state must be
either immutable after start-up:

```chapel
private const posts = [ /* ... */ ];   // read by every task, no synchronisation
```

or guarded. A `sync` variable is the idiomatic mutex, and blocking on one yields
the task to the scheduler — exactly what blocking inside a foreign call would
not do:

```chapel
private var mutex: sync bool;
private var items: list(Task);

private proc lock()   { mutex.writeEF(true); }
private proc unlock() { mutex.readFE(); }

proc snapshot(): list(Task) {
  lock();
  defer unlock();
  return items;              // a copy, so the lock is not held across serialisation
}
```

`examples/api` is a worked version of this.

---

# Security

What the runtime enforces, and where. Not a claim of completeness — a list of
what has been considered, so gaps are visible.

## Request parsing

The request line, header block, header count and body size are all bounded, and
exceeding one is answered `414`, `431` or `413` rather than allocated for.

| limit | default |
| --- | --- |
| request line | 8 KB |
| header block | 32 KB |
| header count | 100 |
| body | `server.max_body_bytes`, 1 MB |
| connection buffer | 256 KB |

**Request smuggling.** A request carrying both `Content-Length` and
`Transfer-Encoding` is rejected. A duplicate `Content-Length`, `Host` or
`Transfer-Encoding` is rejected, because a front-end proxy may read one and the
origin the other. Obsolete line folding (`obs-fold`) is rejected. Any
`Transfer-Encoding` other than `chunked` is `501`. Chunked trailers are consumed
and discarded, never merged into the request headers.

**Framing.** A `POST`, `PUT` or `PATCH` with no framing header is `411`, before
routing. `HTTP/1.1` without `Host` is `400`.

**Slow clients.** `header_timeout_ms` bounds a single `recv`, which is not enough
on its own because every byte received restarts it. `request_timeout_ms` is an
absolute budget for the whole request, armed when the first byte arrives; a
client dripping one byte per interval is disconnected at that deadline.

**Header syntax.** Field names are restricted to alphanumerics, `-`, `_` and `.`.
Anything else is `400`.

## Paths

The target is percent-decoded, then normalised: `.` and `..` are resolved against
a virtual root and any residual escape yields `400`. Normalisation runs on the
*decoded* path, so `%2e%2e%2f` cannot slip past a check for `../`. Control bytes,
spaces and NUL in a decoded segment are rejected — a NUL would truncate the path
at any later C boundary.

The static file layer re-checks independently before touching disk: any `..`,
backslash, NUL, or segment beginning with `.` is refused, and a directory path is
never served. Two independent guards, either sufficient alone.

## Responses

Header names and values are validated at write time, not on the way in. CR, LF
and NUL in a value are rejected, so a handler cannot inject a header or split a
response; an invalid field is dropped and logged.

`MarkupBuilder` escapes `& < > " '` in text and attribute values, and validates
tag and attribute names. `raw` is the single unescaped path.

`JsonBuilder` escapes the mandatory set plus `U+2028` and `U+2029`.

`setCookie` defaults to `HttpOnly`, `Secure` and `SameSite=Lax`.

Applied to every response unless already set:

```
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
X-Frame-Options: DENY
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
```

`Content-Security-Policy` is applied to HTML responses only, defaulting to a
`'self'` policy with `object-src 'none'` and `frame-ancestors 'none'`. Override
with `security.csp`; a headless JSON service should tighten it to
`default-src 'none'; frame-ancestors 'none'`.

`Strict-Transport-Security` is sent only when `security.hsts_seconds` is above
zero **and** the request arrived over TLS, determined from `X-Forwarded-Proto` —
meaningful only behind a proxy that overwrites it.

## Cross-origin requests

A `POST`, `PUT`, `PATCH` or `DELETE` carrying an `Origin` matching neither the
request `Host` nor `security.allowed_origins` is answered `403` before any
handler runs. A request with no `Origin` is allowed through: this defends against
browser-driven cross-site requests, and is not a substitute for authentication.

## Process

`SIGPIPE` is masked, so a vanished peer is `EPIPE` on one task rather than a dead
process. `strerror` uses a per-thread buffer. The accept gate turns a connection
flood into backpressure. Static files are capped at 8 MB so one request cannot
choose an unbounded allocation.

## Not provided

No TLS termination, authentication, session store, rate limiting or CSRF token
scheme. Cataract expects a reverse proxy for TLS; rate limiting and
authentication belong in middleware you write.

Report security issues privately to the maintainers rather than in a public
issue tracker.
