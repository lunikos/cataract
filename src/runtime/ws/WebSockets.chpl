module WebSockets {
  public use Frames;

  private use CSocket;
  private use Connections;
  private use ByteBuffer;
  private use HttpClock only monoMillis;
  private use Mutations only DELTA_PROTOCOL;
  private use Logging;
  private use Time only sleep;

  private config const sendPollSeconds = 0.0002;
  private config const sendPollCeilingSeconds = 0.004;

  private var socketCounter: atomic int;

  record Message {
    var kind: Opcode = Opcode.text;
    var payload: Bytes;

    proc text(): string do return payload.toString();
    proc size(): int do return payload.len;
    proc isText(): bool do return kind == Opcode.text;
    proc isBinary(): bool do return kind == Opcode.binary;
  }

  class WebSocket {
    var id: string;
    var path: string;
    var peer: string;
    var subprotocol: string;
    var fd: c_int;
    var conn: borrowed Connection;
    var maxMessageBytes: int = 1048576;
    var sendTimeoutMillis: int = 10000;
    var idleTimeoutMillis: int = 300000;
    var liveFlag: atomic bool;
    var sendGate: sync bool;
    var closeSent: atomic bool;

    proc init(conn: borrowed Connection, path: string, maxMessageBytes: int = 1048576,
              sendTimeoutMillis: int = 10000, idleTimeoutMillis: int = 300000,
              subprotocol: string = "") {
      this.id = conn.peerIp() + ":" + conn.peerPort():string + "/" +
                socketCounter.fetchAdd(1):string;
      this.path = path;
      this.peer = conn.peerIp();
      this.subprotocol = subprotocol;
      this.fd = conn.descriptor();
      this.conn = conn;
      this.maxMessageBytes = maxMessageBytes;
      this.sendTimeoutMillis = sendTimeoutMillis;
      this.idleTimeoutMillis = idleTimeoutMillis;
      init this;
      liveFlag.write(true);
      sendGate.writeEF(true);
    }

    proc isOpen(): bool do return liveFlag.read();

    proc wantsDelta(): bool do return subprotocol == DELTA_PROTOCOL;

    proc markClosed() do liveFlag.write(false);

    proc receive(ref message: Message): bool {
      var assembled = new Message();
      var started = false;
      conn.setTimeouts(idleTimeoutMillis, sendTimeoutMillis);

      while liveFlag.read() {
        var frame = new Frame();
        const state = readFrame(conn, maxMessageBytes, frame);

        select state {
          when FrameState.closed {
            markClosed();
            return false;
          }
          when FrameState.protocolError {
            shutdownWith(CLOSE_PROTOCOL_ERROR, "protocol error");
            return false;
          }
          when FrameState.oversized {
            shutdownWith(CLOSE_TOO_LARGE, "message too large");
            return false;
          }
          otherwise do ;
        }

        select frame.opcode {
          when Opcode.close {
            const code = closeCodeOf(frame.payload);
            shutdownWith(code, "");
            return false;
          }
          when Opcode.ping {
            sendFrame(Opcode.pong, frame.payload);
            continue;
          }
          when Opcode.pong do continue;
          when Opcode.continuation {
            if !started {
              shutdownWith(CLOSE_PROTOCOL_ERROR, "continuation without a start frame");
              return false;
            }
            if assembled.payload.len + frame.payload.len > maxMessageBytes {
              shutdownWith(CLOSE_TOO_LARGE, "message too large");
              return false;
            }
            assembled.payload.append(frame.payload);
          }
          otherwise {
            if started {
              shutdownWith(CLOSE_PROTOCOL_ERROR, "interleaved data frames");
              return false;
            }
            started = true;
            assembled.kind = frame.opcode;
            assembled.payload = frame.payload;
          }
        }

        if frame.fin && started {
          message = assembled;
          return true;
        }
      }
      return false;
    }

    proc sendText(payload: string): bool {
      var body: Bytes;
      body.append(payload);
      return sendFrame(Opcode.text, body);
    }

    proc sendBinary(const ref payload: Bytes): bool {
      return sendFrame(Opcode.binary, payload);
    }

    proc ping(payload: string = ""): bool {
      var body: Bytes;
      if !payload.isEmpty() then body.append(payload);
      return sendFrame(Opcode.ping, body);
    }

    proc sendFrame(opcode: Opcode, const ref payload: Bytes): bool {
      if !liveFlag.read() then return false;

      var wire: Bytes;
      encodeFrame(opcode, payload, wire);

      sendGate.readFE();
      defer sendGate.writeEF(true);
      if !liveFlag.read() then return false;

      if !flushTo(fd, wire, sendTimeoutMillis) {
        liveFlag.write(false);
        return false;
      }
      return true;
    }

    proc closeWith(code: int = CLOSE_NORMAL, why: string = "") {
      shutdownWith(code, why);
    }

    proc shutdownWith(code: int, why: string) {
      if closeSent.testAndSet() {
        liveFlag.write(false);
        return;
      }
      var body: Bytes;
      closePayload(code, why, body);
      sendFrame(Opcode.close, body);
      liveFlag.write(false);
    }
  }

  proc flushTo(fd: c_int, const ref payload: Bytes, timeoutMillis: int): bool {
    const total = payload.len;
    if total == 0 then return true;

    const deadline = monoMillis() + timeoutMillis;
    var wait = sendPollSeconds;
    var sent = 0;

    while sent < total {
      const n = cat_send(fd, (payload.ptrConst() + sent): c_ptrConst(void),
                         (total - sent): c_size_t);
      if n > 0 {
        sent += n: int;
        wait = sendPollSeconds;
        continue;
      }
      if n != WOULD_BLOCK {
        Logging.debug("websocket send failed: " + errnoMessage());
        return false;
      }
      if monoMillis() >= deadline {
        Logging.debug("websocket send timed out");
        return false;
      }
      sleep(wait);
      wait = min(wait * 2, sendPollCeilingSeconds);
    }
    return true;
  }
}
