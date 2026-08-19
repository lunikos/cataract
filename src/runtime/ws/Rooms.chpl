module Rooms {
  private use WebSockets;
  private use List;
  private use Map;
  private use Logging;

  private var gate: sync bool = true;
  private var members: map(string, map(string, shared WebSocket));

  proc join(room: string, socket: shared WebSocket) {
    gate.readFE();
    defer gate.writeEF(true);
    if !members.contains(room) then
      try! members.addOrReplace(room, new map(string, shared WebSocket));
    ref seats = try! members[room];
    try! seats.addOrReplace(socket.id, socket);
  }

  proc leave(room: string, socket: shared WebSocket) {
    leaveById(room, socket.id);
  }

  proc leaveById(room: string, socketId: string) {
    gate.readFE();
    defer gate.writeEF(true);
    if !members.contains(room) then return;
    ref seats = try! members[room];
    if seats.contains(socketId) then seats.remove(socketId);
    if seats.size == 0 then members.remove(room);
  }

  proc leaveAll(socket: shared WebSocket) {
    var occupied: list(string);
    gate.readFE();
    for room in members.keys() do
      if (try! members[room]).contains(socket.id) then occupied.pushBack(room);
    gate.writeEF(true);

    for room in occupied do leaveById(room, socket.id);
  }

  proc occupancy(room: string): int {
    gate.readFE();
    defer gate.writeEF(true);
    if !members.contains(room) then return 0;
    return (try! members[room]).size;
  }

  proc names(): list(string) {
    var found: list(string);
    gate.readFE();
    defer gate.writeEF(true);
    for room in members.keys() do found.pushBack(room);
    return found;
  }

  proc broadcast(room: string, payload: string, exceptId: string = ""): int {
    var audience = snapshot(room);
    var delivered = 0;
    var stale: list(string);

    for socket in audience {
      if socket.id == exceptId then continue;
      if !socket.isOpen() {
        stale.pushBack(socket.id);
        continue;
      }
      if socket.sendText(payload) then delivered += 1;
      else stale.pushBack(socket.id);
    }

    for id in stale do leaveById(room, id);
    return delivered;
  }

  proc broadcastAll(payload: string): int {
    var total = 0;
    for room in names() do total += broadcast(room, payload);
    return total;
  }

  private proc snapshot(room: string): list(shared WebSocket) {
    var audience: list(shared WebSocket);
    gate.readFE();
    defer gate.writeEF(true);
    if !members.contains(room) then return audience;
    for socket in (try! members[room]).values() do audience.pushBack(socket);
    return audience;
  }
}
