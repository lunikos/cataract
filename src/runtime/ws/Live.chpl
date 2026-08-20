module Live {
  private use Dom;
  private use Logging;
  private use Map;
  private use Mutations;
  private use Rooms;
  private use WebSockets;

  private config const deltaCeilingBytes = 4096;

  private var gate: sync bool = true;
  private var sessions: map(string, DomTree);

  proc push(socket: shared WebSocket, const ref next: DomTree): int {
    if !socket.isOpen() then return -1;

    if !socket.wantsDelta() {
      const html = renderInner(next);
      remember(socket.id, next);
      if !socket.sendText(html) then return -1;
      return html.numBytes;
    }

    var delta = new MutationBuffer();
    var before: DomTree;
    if recall(socket.id, before) then diff(before, next, delta);
    else delta.fullRender(next.rootPath(), renderInner(next));

    if delta.overflowed || delta.size() > deltaCeilingBytes then
      delta.fullRender(next.rootPath(), renderInner(next));

    remember(socket.id, next);

    if delta.overflowed {
      Logging.error("live region does not fit one mutation frame; nothing sent");
      return -1;
    }
    if delta.isEmpty() then return 0;
    if !socket.sendBinary(delta.wire) then return -1;

    Logging.debug("live delta " + socket.id + " " + delta.count: string + " op(s) " +
                  delta.size(): string + "B");
    return delta.size();
  }

  proc broadcast(room: string, const ref next: DomTree, exceptId: string = ""): int {
    var total = 0;
    for socket in Rooms.occupants(room) {
      if socket.id == exceptId then continue;
      const sent = push(socket, next);
      if sent > 0 then total += sent;
    }
    return total;
  }

  proc forget(socketId: string) {
    gate.readFE();
    defer gate.writeEF(true);
    if sessions.contains(socketId) then sessions.remove(socketId);
  }

  proc tracked(): int {
    gate.readFE();
    defer gate.writeEF(true);
    return sessions.size;
  }

  private proc recall(socketId: string, ref found: DomTree): bool {
    gate.readFE();
    defer gate.writeEF(true);
    if !sessions.contains(socketId) then return false;
    found = try! sessions[socketId];
    return true;
  }

  private proc remember(socketId: string, const ref tree: DomTree) {
    gate.readFE();
    defer gate.writeEF(true);
    try! sessions.addOrReplace(socketId, tree);
  }
}
