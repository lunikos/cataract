# Routing and handlers

The directory tree under `app/routes` is the route table. A file's location
determines its path; the procedures it declares determine its kind.

Only `.chpl` files are routes. Nothing else is scanned — there is no template
format and no second file type.

## Paths

| file | route |
| --- | --- |
| `routes/index.chpl` | `/` |
| `routes/about.chpl` | `/about` |
| `routes/posts/index.chpl` | `/posts` |
| `routes/posts/[id].chpl` | `/posts/[id]` |
| `routes/docs/[...path].chpl` | `/docs/[...path]` |
| `routes/api/health.chpl` | `/api/health` |

`index` contributes no segment. There is no distinction between page and API
directories: `/api` above is a choice, not a convention.

**`[name]`** matches exactly one non-empty segment, read with
`ctx.pathParam("name")` or `ctx.paramInt("name", fallback)`.

**`[...name]`** matches one or more segments and captures them as a single string
with the separators intact. It must be the last segment.

```chapel
// routes/docs/[...path].chpl  matching /docs/guide/routing
const slug = ctx.pathParam("path");   // "guide/routing"
```

A catch-all does not match the parent path: `/docs/[...path]` does not answer
`/docs`. Add `routes/docs/index.chpl` for that.

**`(group)`** — a directory wrapped in parentheses organises files without
contributing a path segment:

```
routes/(marketing)/pricing.chpl   ->  /pricing
```

**`_` and `.`** — any name beginning with either is skipped, directories
included, and is never scanned or compiled. Such files can be partial work.

## Pages and API routes

A module exporting `proc page` is a page. A module exporting procedures named for
HTTP methods is an API route. Declaring both is an error.

```chapel
proc page(ctx: Context, ref meta: PageMeta): string      // a page
proc get(ctx: Context): Response                         // an API route
```

Handler names are `get`, `post`, `put`, `patch`, `del` and `options`. `del`
serves `DELETE`; `delete` is a Chapel keyword and cannot name a procedure, and
writing `proc delete` is reported by the scanner rather than left to `chpl`.

`HEAD` is served by the `GET` handler with the body elided at write time.

Pages are covered in [Rendering](rendering.md). An API route looks like this:

```chapel
module ApiTasks {
  use Cataract;
  use TaskStore;

  proc get(ctx: Context): Response {
    var b = new JsonBuilder();
    b.beginObject();
    b.field("count", TaskStore.count());
    b.endObject();
    return jsonResponse(b.done());
  }

  proc post(ctx: Context): Response throws {
    const title = JsonField.text(ctx.request.bodyText(), "title");
    if title.isEmpty() then return errorResponse(422, "title is required");

    var res = jsonResponse(TaskStore.add(title), 201);
    res.setHeader("Location", "/tasks/" + TaskStore.count():string);
    return res;
  }
}
```

A handler declared `throws` is wrapped by the generated dispatcher: an escaped
error is logged and becomes a `500` rather than unwinding the connection task.

## Match order

Matching happens in two tiers. Patterns with no dynamic segments resolve through
a hash lookup. Everything else walks a list pre-sorted by specificity:

1. more segments beats fewer
2. a literal segment beats a parameter
3. a catch-all sorts last

The first structural match is therefore the most specific one, with no
backtracking. Given `/posts/new`, `/posts/[id]` and `/posts/[...rest]`, a request
for `/posts/new` matches the literal route. `cataract routes` prints the compiled
table in this order.

Two files resolving to the same path and the same method set are a build error.
The same path with disjoint methods is allowed; the masks merge for `Allow`.

When a path matches but no handler accepts the method, the response is `405` with
an `Allow` header. When nothing matches, `404`.

## Context

| member | returns |
| --- | --- |
| `pathParam(name, fallback = "")` | a captured route segment |
| `paramInt(name, fallback)` | the same, parsed as an integer |
| `queryParam(name, fallback = "")` | a query-string value |
| `setLocal(name, value)` / `getLocal(name, fallback)` | per-request scratch state |
| `method()` / `path()` | the request method and normalised path |
| `requestId` | `ip:port#n`, also used by the access log |
| `request` | the parsed request |

`ctx.request` carries `header(name)`, `contentType()`, `bodyText()`,
`accepts(mime)`, `clientIp()`, `query`, `headers`, `peerIp` and `peerPort`.

`clientIp()` reads `X-Forwarded-For` and is spoofable unless a trusted proxy
overwrites it. Never use it for authorization.

Query parameters are decoded with `+` as a space; repeated keys keep the first
value.

## Response

```chapel
jsonResponse(payload, status = 200)
htmlResponse(markup, status = 200)
textResponse(text, status = 200)
bytesResponse(payload, mime, status = 200)
redirect(location, status = 303)
noContent()                          // 204
errorResponse(status, detail = "")   // a minimal HTML error document
```

| method | effect |
| --- | --- |
| `setHeader(name, value)` | replaces any existing value |
| `addHeader(name, value)` | appends, for multi-value fields |
| `setBody(text)` | replaces the body |
| `setCookie(name, value, ...)` | appends a `Set-Cookie` |

`setCookie` defaults to `HttpOnly`, `Secure`, `SameSite=Lax` and `Path=/`, and
percent-encodes the value.

`Content-Length`, `Date`, `Server` and `Connection` are written by the server and
cannot be overridden. Header names and values are validated at write time, so a
handler cannot inject a header or split the response.

## JsonBuilder

A streaming writer. It tracks enough structure to place commas; balancing
begin/end pairs is the caller's job.

```chapel
var b = new JsonBuilder();
b.beginObject();
b.field("status", "ok");          // string, int, bool and real overloads
b.key("items");
b.beginArray();
b.value("first");
b.endArray();
b.rawValue(alreadySerialised);    // the caller owns validity
b.endObject();
return jsonResponse(b.done());
```

Strings are escaped, including `U+2028` and `U+2029`, which are literal line
terminators when JSON is inlined into a `<script>` block. `NaN` and the
infinities serialise as `null`.

## Request bodies

Available as `ctx.request.bodyText()` or as bytes through `ctx.request.body`, and
bounded by `server.max_body_bytes`; a larger body is rejected with `413` before a
handler runs.

A `POST`, `PUT` or `PATCH` with neither `Content-Length` nor `Transfer-Encoding`
is rejected with `411`, before routing. Chunked bodies are decoded; trailers are
consumed and discarded rather than merged into the headers.

## Headless projects

A project with no pages needs no `app/layouts`, and its `404` and `405` responses
are JSON rather than HTML — an application with no HTML surface should not answer
with markup. `examples/api` is a worked version.
