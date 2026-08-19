module SocketFleet {
  use Cataract;
  use Fleet;

  param room = "fleet";

  proc socket(ctx: Context, ws: shared WebSocket) throws {
    Rooms.join(room, ws);
    defer Rooms.leave(room, ws);

    ws.sendText(snapshot("welcome"));
    Rooms.broadcast(room, presence(), ws.id);

    var incoming = new Message();
    while ws.receive(incoming) {
      const command = incoming.text().strip();
      select command {
        when "snapshot" do ws.sendText(snapshot("snapshot"));
        when "presence" do ws.sendText(presence());
        otherwise do Rooms.broadcast(room, chat(ws.id, command));
      }
    }
  }

  private proc snapshot(event: string): string throws {
    var b = new JsonBuilder();
    b.beginObject();
    b.field("event", event);
    b.field("watching", Rooms.occupancy(room));
    b.key("nodes");
    b.beginArray();
    for n in Fleet.all() {
      b.beginObject();
      b.field("id", n.id);
      b.field("status", n.status);
      b.field("cpu", n.cpu);
      b.endObject();
    }
    b.endArray();
    b.endObject();
    return b.done();
  }

  private proc presence(): string throws {
    var b = new JsonBuilder();
    b.beginObject();
    b.field("event", "presence");
    b.field("watching", Rooms.occupancy(room));
    b.endObject();
    return b.done();
  }

  private proc chat(from: string, text: string): string throws {
    var b = new JsonBuilder();
    b.beginObject();
    b.field("event", "message");
    b.field("from", from);
    b.field("text", text);
    b.endObject();
    return b.done();
  }
}
