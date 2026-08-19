# Middleware

Middleware is two-phase rather than nested continuations. `before` may
short-circuit by filling the response and returning `true`; `after` always runs
for the stages actually entered, in reverse order. A stage that stops a request
therefore cannot strand logging or header hardening.

```chapel
class Middleware {
  proc name(): string;
  proc before(ref ctx: Context, ref res: Response): bool;
  proc after(const ref ctx: Context, ref res: Response);
}
```

Every application gets the access log, the security guard and the static file
server, in that order. Anything declared below is inserted after the guard and
before static files, so it covers routes and assets alike.

## Groups

A group is one stage in the outer chain holding a chain of its own, active only
for paths under its prefix.

```toml
[middleware]
groups = "api, admin"

[middleware.api]
match = "/api"
use = "cors, rate-limit"
cors_origins = "https://app.example"
rate_limit_requests = 120
rate_limit_window_ms = 60000

[middleware.admin]
match = "/admin"
use = "csrf"
csrf_same_site = "Strict"
```

`groups` names the groups; each gets a `[middleware.<name>]` section with a
`match` prefix and a `use` list. Stages run in the order they are named. A
`use` line directly under `[middleware]` applies to everything:

```toml
[middleware]
use = "rate-limit"
rate_limit_requests = 600
rate_limit_window_ms = 60000
```

`match` is a path prefix: `/api` covers `/api` and `/api/anything`, and `/`
covers the whole site. Naming a stage that does not exist is a build error
listing the ones that do.

A group records how many of its own stages it entered in the request's locals,
so a short-circuit inside a group unwinds exactly those and no others.

The same shape is available in Chapel, which is where a stage you wrote
yourself goes:

```chapel
var api = app.group("api", "/api");
api.add(new shared RateLimiter(requestsPerWindow = 120, windowMillis = 60000));
api.add(new shared AuditTrail());
```

## RateLimiter

A token bucket per client. Tokens refill continuously at
`requestsPerWindow / windowMillis`, so there is no edge at which a window resets
and a burst gets through twice.

```toml
[middleware.api]
use = "rate-limit"
rate_limit_requests = 120        # tokens restored per window
rate_limit_window_ms = 60000     # the window, in milliseconds
rate_limit_burst = 30            # extra tokens a quiet client may bank
rate_limit_key_header = ""       # count per header value; empty means per client IP
```

Over the limit is `429` with `Retry-After`, as JSON or as an HTML error document
depending on what the request accepts. Every response the limiter covers carries
`RateLimit-Limit`, `RateLimit-Remaining` and `RateLimit-Policy`.

Clients are tracked in a map bounded by `maxTrackedClients`; when it fills,
entries idle for longer than the window are dropped first.

The default key is `clientIp()`, which reads `X-Forwarded-For` and is spoofable
unless a proxy overwrites it. Behind an untrusted network, set
`rate_limit_key_header` to something the client cannot choose freely, such as an
API key.

## CorsPolicy

```toml
[middleware.api]
use = "cors"
cors_origins = "https://app.example, https://admin.example"   # or "*"
cors_methods = "GET, POST, PUT, DELETE"
cors_headers = "Content-Type, Authorization"                  # or "*" to echo
cors_expose = "X-Request-Id"
cors_credentials = false
cors_max_age = 600
```

A preflight — `OPTIONS` carrying `Access-Control-Request-Method` — is answered
by the policy itself with `204` and the `Access-Control-*` headers, or `403` if
the origin is not on the list. Other requests carrying an allowed `Origin` get
`Access-Control-Allow-Origin` and `Vary: Origin` on the way out.

With `cors_credentials = true`, `*` is echoed back as the requesting origin,
because a browser refuses `*` on a credentialed response.

The origins named here are merged into the security guard's allow-list, so
declaring CORS also lets those origins make mutating requests. The two cannot
drift apart.

## CsrfGuard

A double-submit cookie. The first request that arrives without the cookie mints
a token from `/dev/urandom` and sets it; a `POST`, `PUT`, `PATCH` or `DELETE`
must then present the same token, either in a header or as a form field.

```toml
[middleware.admin]
use = "csrf"
csrf_cookie = "cataract_csrf"    # cookie name
csrf_header = "X-CSRF-Token"     # header the client echoes it in
csrf_field = "_csrf"             # form field, for urlencoded bodies
csrf_secure = true               # Secure on the cookie; false for plain http
csrf_same_site = "Lax"
```

The cookie is deliberately readable by scripts — the client has to be able to
echo it — and the comparison runs over the whole token without an early exit.

In a page, the token for this request is `csrfToken(ctx)`:

```chapel
h.open("form", "method", "post", "action", url(Route.postsId, post.id));
h.open("input", "type", "hidden", "name", "_csrf", "value", csrfToken(ctx));
h.el("button", "Publish", "type", "submit");
h.close();
```

From JavaScript, read the cookie and send it back:

```js
const token = document.cookie.match(/cataract_csrf=([^;]+)/)?.[1];
await fetch("/api/posts", {
  method: "POST",
  headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
  body: JSON.stringify({ title }),
});
```

A missing or mismatched token is `403` before any handler runs.

## Writing your own

Subclass `Middleware` in `app/lib` and add it to a group:

```chapel
module AuditTrail {
  use Cataract;

  class Auditor: Middleware {
    override proc name(): string do return "audit";

    override proc before(ref ctx: Context, ref res: Response): bool {
      ctx.setLocal("audit.actor", ctx.request.header("X-Actor", "anonymous"));
      return false;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      logInfo(ctx.getLocal("audit.actor") + " " + ctx.request.path + " -> " +
              res.status:string);
    }
  }
}
```

Middleware objects are shared across concurrent requests, so anything that
varies per request belongs in `ctx.locals` — as above — and any mutable field
belongs behind a `sync` variable. `ctx.setLocal` is available in `before`;
`after` receives the context by `const ref` and can read it.
