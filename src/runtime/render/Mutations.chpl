module Mutations {
  private use ByteBuffer;

  param DELTA_PROTOCOL = "cataract.delta.v1";

  param OP_SET_TEXT = 0x01;
  param OP_SET_ATTR = 0x02;
  param OP_REMOVE_ATTR = 0x03;
  param OP_INSERT_NODE = 0x04;
  param OP_REMOVE_NODE = 0x05;
  param OP_REPLACE_NODE = 0x06;
  param OP_FULL_RENDER = 0xff;

  param HEADER_BYTES = 5;
  param MAX_DATA_BYTES = 65535;
  param MAX_NAME_BYTES = 255;

  record MutationBuffer {
    var wire: Bytes;
    var count: int = 0;
    var overflowed: bool = false;

    proc size(): int do return wire.len;

    proc isEmpty(): bool do return count == 0;

    proc ref reset() {
      wire.clear();
      count = 0;
      overflowed = false;
    }

    proc ref setText(path: uint(16), text: string) {
      emitText(OP_SET_TEXT, path, text);
    }

    proc ref setAttr(path: uint(16), name: string, value: string) {
      if name.isEmpty() || name.numBytes > MAX_NAME_BYTES {
        overflowed = true;
        return;
      }
      var data: Bytes;
      data.push(name.numBytes: uint(8));
      data.append(name);
      data.append(value);
      emit(OP_SET_ATTR, path, data);
    }

    proc ref removeAttr(path: uint(16), name: string) {
      emitText(OP_REMOVE_ATTR, path, name);
    }

    proc ref insertNode(parent: uint(16), at: int, html: string) {
      var data: Bytes;
      data.push((at >> 8): uint(8));
      data.push(at: uint(8));
      data.append(html);
      emit(OP_INSERT_NODE, parent, data);
    }

    proc ref removeNode(path: uint(16)) {
      var data: Bytes;
      emit(OP_REMOVE_NODE, path, data);
    }

    proc ref replaceNode(path: uint(16), html: string) {
      emitText(OP_REPLACE_NODE, path, html);
    }

    proc ref fullRender(path: uint(16), html: string) {
      reset();
      emitText(OP_FULL_RENDER, path, html);
    }

    proc ref emitText(op: int, path: uint(16), text: string) {
      var data: Bytes;
      data.append(text);
      emit(op, path, data);
    }

    proc ref emit(op: int, path: uint(16), const ref data: Bytes) {
      if data.len > MAX_DATA_BYTES {
        overflowed = true;
        return;
      }
      wire.reserve(wire.len + HEADER_BYTES + data.len);
      wire.push(op: uint(8));
      wire.push((path >> 8): uint(8));
      wire.push(path: uint(8));
      wire.push((data.len >> 8): uint(8));
      wire.push(data.len: uint(8));
      wire.append(data);
      count += 1;
    }
  }

  proc opName(op: int): string {
    select op {
      when OP_SET_TEXT do return "set-text";
      when OP_SET_ATTR do return "set-attr";
      when OP_REMOVE_ATTR do return "remove-attr";
      when OP_INSERT_NODE do return "insert-node";
      when OP_REMOVE_NODE do return "remove-node";
      when OP_REPLACE_NODE do return "replace-node";
      when OP_FULL_RENDER do return "full-render";
      otherwise do return "unknown";
    }
  }
}
