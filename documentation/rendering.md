# Pages, layouts, islands and assets

A page is a Chapel module that exports `page`. It receives the request context
and the page's metadata, and returns the body of the document.

```chapel
module PagePosts {
  use Cataract;
  use PostStore;

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Posts";

    var h = new MarkupBuilder();
    h.el("h1", "Posts");
    h.open("ul");
    for p in PostStore.all() {
      h.open("li");
      h.el("a", p.title, "href", "/posts/" + p.id);
      h.close();
    }
    return h.done();
  }
}
```

The return value goes into a layout, and the result into the document shell.
There is no template language: markup is written in Chapel, and the framework's
job is to make that safe rather than to add a second syntax.

## MarkupBuilder

`MarkupBuilder` keeps a stack of open elements, escapes every value, validates
every name and closes what is left open.

| method | effect |
| --- | --- |
| `open(tag)` / `open(tag, name, value, ...)` | writes the tag, pushes it |
| `close()` | closes the innermost open element |
| `el(tag, content)` / `el(tag, content, name, value, ...)` | open, escaped text, close |
| `text(value)` | escaped; any type with a `: string` cast |
| `raw(html)` | unescaped; the caller owns safety |
| `comment(text)` | an HTML comment |
| `depth()` | number of elements currently open |
| `done()` | closes anything still open, returns the string |

`close()` takes no argument because the stack already holds the tag name, which
makes a mismatched close impossible to write. Void elements (`img`, `input`,
`br`, `meta`, `link` and the rest) are never pushed, so they need no close.

An odd number of attribute arguments is a compile-time error. A tag or attribute
name outside `[A-Za-z][A-Za-z0-9_:-]*` is dropped and logged rather than emitted.

`text` and `el` escape `& < > " '`. `raw` does not, and exists for composing
already-safe fragments — the output of another `MarkupBuilder`, or the return
value of `island`. Passing request data to `raw` is a cross-site scripting bug.

`defer` scopes an element to a Chapel block, and `classList` builds a conditional
class attribute:

```chapel
{
  h.open("tr", "class", classList("warn", n.degraded, "down", n.offline));
  defer h.close();
  // ...
}
```

## PageMeta

| field | type | effect |
| --- | --- | --- |
| `title` | `string` | `<title>` |
| `description` | `string` | `<meta name="description">` |
| `lang` | `string` | `<html lang>`, default `"en"` |
| `canonical` | `string` | `<link rel="canonical">` when set |
| `icon` | `string` | `<link rel="icon">` when set |
| `bodyClass` | `string` | `class` on `<body>` |
| `stylesheets` | `list(string)` | one `<link rel="stylesheet">` each |
| `scripts` | `list(string)` | one `<script type="module">` each |
| `needsClientRuntime` | `bool` | set by `island` |
| `status` | `int` | the response status, default `200` |

`status` is what makes an error page honest — a page that renders "not found"
should say so in the status line:

```chapel
if !PostStore.find(id, post) {
  meta.status = 404;
  meta.title = "Post not found";
  h.el("h1", "Post not found");
  return h.done();
}
```

Stylesheets at the top level of `public/` are added to every page automatically.

## Layouts

A layout is a module in `app/layouts` that exports `layout`. It receives the
rendered page as `slot`.

```chapel
module RootLayout {
  use Cataract;

  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {
    var h = new MarkupBuilder();

    h.open("header");
    h.el("a", "Home", "href", "/");
    h.close();

    h.open("main");
    h.raw(slot);
    h.close();

    return h.done();
  }
}
```

A layout is named by its file: `app/layouts/root.chpl` is `root`. A page selects
one with a module-level `param layout = "focus";` and defaults to `root`.

Layouts run after the page and before the document shell, so a layout can still
set fields on `meta`.

A `page` or `layout` declared `throws` is wrapped by the generated handler: an
escaped error is logged and becomes a `500` rather than unwinding the connection
task.

## Islands

A page ships no JavaScript until it declares an island. The server renders the
region in full, attaches its props as JSON, and the client mounts only that
region.

```chapel
var props = new JsonBuilder();
props.beginObject();
props.field("start", PostStore.count());
props.endObject();

var fallback = new MarkupBuilder();
fallback.el("button", PostStore.count():string + " posts", "class", "counter");

h.raw(island(meta, "counter", props.done(), fallback.done()));
```

`island` sets `meta.needsClientRuntime`, which is what adds the
`/_cataract/client.js` tag. A page that declares none ships no script tag at all.
A layout may declare one, in which case every page using that layout gets the
runtime.

Island modules live in `app/islands/`, named by their file:

```js
// app/islands/counter.js
import { defineIsland } from "cataract/client";

defineIsland("counter", (el, props) => {
  const button = el.querySelector("button") ?? el;
  let value = props.start ?? 0;
  button.addEventListener("click", () => {
    button.textContent = `${++value} posts`;
  });
});
```

The factory receives the island element and the parsed props, and runs once per
element. A factory that throws is logged and the element left as rendered, so a
failed mount degrades to a static region rather than a blank one.

`app/islands/*.js` are concatenated with the client runtime into
`/_cataract/client.js`. The `import` naming `cataract/client` is stripped during
concatenation — the bundle has no module graph, and `defineIsland` is already in
scope. Keeping the import means the file stays a valid ES module that an editor
and a real bundler both understand.

The runtime mounts on `DOMContentLoaded`, then watches the document with a
`MutationObserver`, so islands introduced later by another island's DOM writes
are picked up. An element is mounted at most once.

Props are attribute text in the document and visible to the client. Do not put
anything in them the requester should not see.

## Static assets

Everything under `app/public` is copied to `.cataract/public` at build time and
served from the root. Each file is hashed and given a version marker:

```
/styles.css?v=be6a02a3da64
```

The URL stays readable and the file keeps its name, so source maps and relative
references inside a stylesheet keep working. Resolve one with `asset`:

```chapel
use CataractAssets;

meta.icon = asset("/img/logo.svg");
```

`asset` is generated from the build's digest table and compiles to a jump table,
not a runtime map. An unknown path is returned unchanged. CSS files at the top
level of `public/` are linked into every page automatically; nested stylesheets
are not, so a page can opt into one through `meta.stylesheets`.

A request carrying `?v=` is answered `Cache-Control: public, max-age=31536000,
immutable`, because a versioned URL names one exact byte sequence. The same path
without the marker gets `max-age=<cache_seconds>`. Every response carries a
content-derived `ETag`, stable across restarts and replicas; a matching
`If-None-Match` is answered `304`. Range requests are not supported.

Files are read whole into memory, so one larger than 8 MB is not served and a
warning is logged. Served files are cached up to 32 MB; past that they are still
served but re-read per request. `cataract dev` disables the cache.
