# WebSockets and rooms

A route module that exports `socket` is a WebSocket endpoint. It lives in
`app/routes` like every other route, and its file position gives it a path.

```chapel
module SocketChat {
  use Cataract;

  proc socket(ctx: Context, ws: shared WebSocket) throws {
    Rooms.join("lobby", ws);
    defer Rooms.leave("lobby", ws);

    ws.sendText("welcome");

    var incoming = new Message();
    while ws.receive(incoming) do
      Rooms.broadcast("lobby", incoming.text(), ws.id);
  }
}
```

`app/routes/ws/chat.chpl` above answers `/ws/chat`. `cataract routes` prints it
as `sock`.

A module declaring `socket` may declare nothing else: a page, a method handler
and a socket are three different kinds of route and mixing them is a build
error.

## The upgrade

The server checks the request headers before it routes. A `GET` carrying
`Upgrade: websocket` and `Connection: Upgrade` is matched against the route
table; if the match is a socket route, the handshake runs. Everything else takes
the ordinary path, so a normal request pays one header comparison.

The handshake is RFC 6455 version 13. `Sec-WebSocket-Key` is hashed with the
protocol GUID and answered as `Sec-WebSocket-Accept`; SHA-1 and base64 are
implemented in Chapel, so the handshake pulls in no dependency. A request with
no key, or a version other than 13, is answered `426 Upgrade Required` with
`Sec-WebSocket-Version: 13`.

Requesting a socket route with a plain browser `GET` returns `426` as well,
which is what `curl http://localhost:3000/ws/chat` will show.

Middleware runs before the upgrade. A stage that short-circuits — a rate limiter
refusing the connection, a CORS policy rejecting an origin — answers with an
ordinary HTTP response and the upgrade never happens. The access log records the
upgrade as `101`.

## The handler

`socket` runs on the connection's own task and owns the connection for as long
as it runs. Returning closes the socket, so the loop shape above is the usual
one.

| member | effect |
| --- | --- |
| `receive(ref message)` | blocks for the next message; `false` once the peer is gone |
| `sendText(payload)` | one text frame; `false` if the socket is closed or the write failed |
| `sendBinary(payload)` | the same for a `Bytes` payload |
| `ping(payload = "")` | a ping frame |
| `closeWith(code, why)` | sends a close frame and marks the socket closed |
| `isOpen()` | whether the socket is still usable |
| `wantsDelta()` | whether the client negotiated the binary mutation protocol |
| `id` | `ip:port/n`, unique for the life of the process |
| `path` | the path the socket was opened on |
| `subprotocol` | the subprotocol agreed at the handshake, or `""` |

`receive` handles the protocol below the application: a `ping` is answered with
a `pong` and the loop continues, a `close` ends it, and continuation frames are
reassembled into one message before it returns. `Message` carries `text()`,
`size()`, `isText()` and `isBinary()`.

Frames from a client must be masked, as the protocol requires; an unmasked frame
closes the connection with `1002`. A message over the size limit closes it with
`1009`.

A handler declared `throws` is wrapped by the generated dispatcher: an escaped
error is logged and the socket is closed with `1001`, rather than unwinding the
connection task.

## Rooms

`Rooms` is a process-wide registry of named sets of sockets. It is the piece
that makes one socket's message reach the others.

```chapel
Rooms.join("lobby", ws);          // add a socket to a room
Rooms.leave("lobby", ws);         // remove it from one room
Rooms.leaveAll(ws);               // remove it from every room
Rooms.occupancy("lobby");         // how many sockets are in it
Rooms.occupants("lobby");         // the sockets themselves, copied
Rooms.names();                    // every room with at least one member
Rooms.broadcast("lobby", text);   // send to all of them, returns the count
Rooms.broadcast("lobby", text, ws.id);   // ...except one
Rooms.broadcastAll(text);         // every room
```

`broadcast` copies the membership under the registry lock and sends outside it,
so a slow peer delays only itself. A socket that has closed, or whose write
fails, is dropped from the room as part of the same call.

The server calls `leaveAll` when a handler returns, so a room cannot retain a
socket whose connection has ended. The `defer Rooms.leave(...)` in the example
is still worth writing: it makes the handler's own membership obvious, and it
runs before the handler's last statements unwind.

Rooms are per-locale state. With `listeners = "per-locale"` each locale keeps
its own registry, so a broadcast reaches the sockets that locale accepted — see
[Distribution](deployment.md#locales-and-affinity).

## Live regions

`Rooms.broadcast` sends text, and a region that changes on the server is
usually sent as re-rendered HTML — a couple of kilobytes to move four numbers.
A live region describes the region instead of serialising it: the server builds
the same tree twice, diffs the two, and sends only what moved, as binary.

### Describing the region

`DomBuilder` takes the calls `MarkupBuilder` takes, and records a tree instead
of appending bytes.

| method | effect |
| --- | --- |
| `open(tag)` / `open(tag, name, value, ...)` | opens an element, pushes it |
| `close()` | closes the innermost open element |
| `el(tag, content)` / `el(tag, content, name, value, ...)` | open, text, close |
| `text(value)` | a text node; any type with a `: string` cast |
| `attr(name, value)` | one attribute on the innermost open element |
| `depth()` | number of elements currently open |
| `done()` | closes anything still open, returns the `DomTree` |

There is no `raw`. A live region is only diffable if the server built every
node in it, so the escape hatch is deliberately absent.

```chapel
proc statsTree(): DomTree {
  var d = new DomBuilder();

  d.open("dl", "class", "stats");
  cell(d, "watching", Rooms.occupancy(room));
  cell(d, "healthy", Fleet.countByStatus("healthy"));
  d.close();

  return d.done();
}
```

### Rendering it

`islandLive` puts the tree in the document and names the socket that will
update it. It is the `island` of live regions: it sets
`meta.needsClientRuntime`, and the page still renders completely without
JavaScript.

```chapel
h.raw(islandLive(meta, statsTree(), "/ws/fleet", 2000));
```

The last argument is how often the client asks for an update, in milliseconds;
leave it out and the client asks for nothing after the first render. An
overload takes an island name and props first, for a region that also wants a
factory of its own:

```chapel
h.raw(islandLive(meta, "fleet", props.done(), statsTree(), "/ws/fleet", 2000));
```

Every element in a live region is rendered with a `data-path` attribute. That
number is the address a mutation names, derived from the element's position in
the tree, so both sides agree on it without exchanging a manifest.

### Updating it

`Live` keeps the last tree it sent to each socket and diffs against that one.

```chapel
proc socket(ctx: Context, ws: shared WebSocket) throws {
  Rooms.join(room, ws);
  defer {
    Rooms.leave(room, ws);
    Live.broadcast(room, statsTree());
  }

  Live.push(ws, statsTree());
  Live.broadcast(room, statsTree(), ws.id);

  var incoming = new Message();
  while ws.receive(incoming) {
    select incoming.text().strip() {
      when "tick" do Live.push(ws, statsTree());
      otherwise do Live.broadcast(room, statsTree());
    }
  }
}
```

| member | effect |
| --- | --- |
| `Live.push(ws, tree)` | diff against that socket's tree and send; returns bytes sent |
| `Live.broadcast(room, tree)` | push one tree to every socket in a room |
| `Live.broadcast(room, tree, exceptId)` | ...except one |
| `Live.forget(id)` | drop a socket's tree; the server calls it when a handler returns |
| `Live.tracked()` | how many sockets have a tree |

`push` returns `0` when nothing changed, and sends no frame — an idle tick
costs nothing. It returns `-1` if the socket is closed or the write failed.

Because each socket has its own tree, `broadcast` is not one frame fanned out:
each watcher is sent what that watcher had not already seen. A socket with no
tree — a first connect, or a reconnect after a drop — is sent a full render, so
resynchronising is the same path as connecting.

`tick` above is the message the client runtime sends on the interval
`islandLive` recorded. A handler is free to ignore it and push on its own
schedule instead.

### The wire

Each mutation is a header and an operand, appended into one binary frame.

| bytes | field |
| --- | --- |
| `0` | opcode |
| `1..2` | path, big-endian `uint16` |
| `3..4` | operand length, big-endian `uint16` |
| `5..` | operand |

| opcode | name | operand | applied as |
| --- | --- | --- | --- |
| `0x01` | set text | the text | `textContent` |
| `0x02` | set attribute | `[nameLen: uint8][name][value]` | `setAttribute` |
| `0x03` | remove attribute | the name | `removeAttribute` |
| `0x04` | insert node | `[index: uint16][html]` | inserted at that child index |
| `0x05` | remove node | empty | `remove()` |
| `0x06` | replace node | the html | inserted before it, then it is removed |
| `0xff` | full render | the region's html | `innerHTML` on the region root |

A five-byte header means a changed count costs six bytes on the wire. On the
dashboard's region a first connect costs about 1.9 KB, a tick that moves five
readings costs 40 bytes, and a watcher joining costs the others six.

A delta larger than `deltaCeilingBytes` — 4 KB by default — is replaced by a
full render, on the grounds that a diff that big is no longer a diff.

### The client

The runtime opens the socket, indexes the region by `data-path`, and applies
what arrives. Operations are queued and applied inside one
`requestAnimationFrame`, so a burst of frames costs one layout pass rather than
one each. The index is kept current as structural operations land, so a
mutation may address a node an earlier one in the same batch created.

A closed socket reconnects with exponential backoff up to thirty seconds. No
state is carried across the gap: the new socket has no tree on the server and
is answered with a full render.

An island on the same element may return `patched()` alongside `destroy()`,
which runs after each batch is applied.

### Falling back

The capability is a WebSocket subprotocol, `cataract.delta.v1`, offered by the
server on every socket route and asked for by the client runtime. A client that
does not ask for it — an older bundle, `curl`, anything hand-written — is sent
the region's HTML as a text frame instead, and `ws.wantsDelta()` says which one
a handler is talking to.

### What it does not do

The diff is positional, not keyed. Changing a value in place, appending to a
list or truncating one produces the minimal set of operations; reordering a
list rewrites the rows that moved rather than moving them. A changed tag, or
text moving inside an element that also holds elements, replaces that subtree.

Node addresses are sixteen bits derived from position. Collisions inside one
tree are probed around, and an address that shifts between renders is answered
with a subtree replace, so a collision costs bytes rather than correctness — but
a region of thousands of elements is not what this is for.

## Configuration

```toml
[server]
socket_max_message_bytes = 1048576   # a larger message closes with 1009
socket_idle_timeout_ms = 300000      # silence before the socket is dropped
socket_send_timeout_ms = 10000       # how long one frame may take to write
socket_subprotocols = ""             # comma-separated, negotiated if the client asks
```

`cataract.delta.v1` is offered in addition to whatever this names, and cannot
be turned off; a client that does not ask for it is unaffected.

Each is a `config const` on the built binary as well:

```
./dist/app --socketMaxMessageBytes=65536 --socketIdleTimeoutMillis=60000
```

## From the browser

```js
const socket = new WebSocket(`ws://${location.host}/ws/chat`);
socket.addEventListener("message", (event) => console.log(event.data));
socket.addEventListener("open", () => socket.send("hello"));
```

Inside an island, open the socket in the factory and close it in the teardown,
so navigating away does not leave it open:

```js
import { defineIsland } from "cataract/client";

defineIsland("chat", (el) => {
  const socket = new WebSocket(`ws://${location.host}/ws/chat`);
  socket.addEventListener("message", (event) => {
    el.querySelector("output").textContent = event.data;
  });
  return () => socket.close();
});
```

## A worked example

`examples/dashboard` serves `/ws/fleet`. The overview page renders the live
region with `islandLive`; the socket joins the `fleet` room, pushes a full
render on connect, answers each `tick` with a delta, and broadcasts when a
watcher joins or leaves. `FleetView.statsTree` is the single description both
the page and the socket render from.

Build and run it, open two browser tabs, and watch the `watching` count move in
both. `--logLevel=debug` prints the size of each delta as it goes out.
