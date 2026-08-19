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
| `id` | `ip:port/n`, unique for the life of the process |
| `path` | the path the socket was opened on |

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

## Configuration

```toml
[server]
socket_max_message_bytes = 1048576   # a larger message closes with 1009
socket_idle_timeout_ms = 300000      # silence before the socket is dropped
socket_send_timeout_ms = 10000       # how long one frame may take to write
socket_subprotocols = ""             # comma-separated, negotiated if the client asks
```

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

`examples/dashboard` serves `/ws/fleet`. It joins the `fleet` room, sends a
snapshot of the node table on connect, answers `snapshot` and `presence`
commands, and broadcasts anything else to the other watchers. Build and run it,
then open two browser tabs against the page to watch presence change.
