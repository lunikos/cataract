module Frames {
  private use Connections;
  private use ByteBuffer;
  private use CTypes;

  enum Opcode { continuation = 0, text, binary, close = 8, ping, pong, reserved = 15 }

  enum FrameState { ok, closed, oversized, protocolError }

  param CLOSE_NORMAL = 1000;
  param CLOSE_GOING_AWAY = 1001;
  param CLOSE_PROTOCOL_ERROR = 1002;
  param CLOSE_UNSUPPORTED = 1003;
  param CLOSE_TOO_LARGE = 1009;

  record Frame {
    var fin: bool = true;
    var opcode: Opcode = Opcode.text;
    var payload: Bytes;
  }

  proc opcodeOf(bits: int): Opcode {
    select bits {
      when 0 do return Opcode.continuation;
      when 1 do return Opcode.text;
      when 2 do return Opcode.binary;
      when 8 do return Opcode.close;
      when 9 do return Opcode.ping;
      when 10 do return Opcode.pong;
      otherwise do return Opcode.reserved;
    }
  }

  proc isControl(op: Opcode): bool {
    return op == Opcode.close || op == Opcode.ping || op == Opcode.pong;
  }

  private proc ensure(conn: borrowed Connection, wanted: int, hardLimit: int): bool {
    if wanted > hardLimit then return false;
    while conn.buffered() < wanted {
      if conn.inDom.size < wanted && !conn.growTo(wanted, hardLimit) then return false;
      if conn.buffered() >= conn.inDom.size &&
         !conn.growTo(conn.inDom.size * 2, hardLimit) then return false;
      if conn.fill() != ReadState.ok then return false;
    }
    return true;
  }

  proc readFrame(conn: borrowed Connection, maxPayloadBytes: int,
                 ref frame: Frame): FrameState {
    const bufferLimit = maxPayloadBytes + 32;

    if !ensure(conn, 2, bufferLimit) then return FrameState.closed;

    const first = conn.inBuf[conn.start];
    const second = conn.inBuf[conn.start + 1];
    conn.consume(2);

    frame.fin = (first & 0x80) != 0;
    if (first & 0x70) != 0 then return FrameState.protocolError;

    frame.opcode = opcodeOf((first & 0x0f): int);
    if frame.opcode == Opcode.reserved then return FrameState.protocolError;

    const masked = (second & 0x80) != 0;
    if !masked then return FrameState.protocolError;

    var length = (second & 0x7f): int;
    if length == 126 {
      if !ensure(conn, 2, bufferLimit) then return FrameState.closed;
      length = (conn.inBuf[conn.start]: int << 8) | conn.inBuf[conn.start + 1]: int;
      conn.consume(2);
    } else if length == 127 {
      if !ensure(conn, 8, bufferLimit) then return FrameState.closed;
      var wide = 0;
      for i in 0..<8 do wide = (wide << 8) | conn.inBuf[conn.start + i]: int;
      conn.consume(8);
      if wide < 0 then return FrameState.protocolError;
      length = wide;
    }

    if isControl(frame.opcode) && (length > 125 || !frame.fin) then
      return FrameState.protocolError;
    if length > maxPayloadBytes then return FrameState.oversized;

    if !ensure(conn, 4, bufferLimit) then return FrameState.closed;
    var key: [0..<4] uint(8);
    for i in 0..<4 do key[i] = conn.inBuf[conn.start + i];
    conn.consume(4);

    frame.payload.clear();
    frame.payload.reserve(max(1, length));

    var taken = 0;
    while taken < length {
      if conn.buffered() == 0 && conn.fill() != ReadState.ok then
        return FrameState.closed;
      const chunk = min(length - taken, conn.buffered());
      for i in 0..<chunk do
        frame.payload.push(conn.inBuf[conn.start + i] ^ key[(taken + i) % 4]);
      conn.consume(chunk);
      taken += chunk;
    }

    return FrameState.ok;
  }

  proc encodeFrame(opcode: Opcode, const ref payload: Bytes, ref sink: Bytes) {
    sink.clear();
    sink.push((0x80 | (opcode: int)): uint(8));

    const length = payload.len;
    if length < 126 {
      sink.push(length: uint(8));
    } else if length < 65536 {
      sink.push(126: uint(8));
      sink.push((length >> 8): uint(8));
      sink.push(length: uint(8));
    } else {
      sink.push(127: uint(8));
      var i = 56;
      while i >= 0 {
        sink.push((length >> i): uint(8));
        i -= 8;
      }
    }
    if length > 0 then sink.appendPtr(payload.ptrConst(), length);
  }

  proc closePayload(code: int, why: string, ref sink: Bytes) {
    sink.clear();
    sink.push((code >> 8): uint(8));
    sink.push(code: uint(8));
    if !why.isEmpty() then sink.append(why);
  }

  proc closeCodeOf(const ref payload: Bytes): int {
    if payload.len < 2 then return CLOSE_NORMAL;
    return (payload.data[0]: int << 8) | payload.data[1]: int;
  }
}
