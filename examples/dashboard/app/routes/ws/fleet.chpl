module SocketFleet {
  use Cataract;
  use FleetView;

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
}
