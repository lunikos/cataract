module JsonWrite {
  private use ByteBuffer;
  private use CTypes;
  private use Math only isFinite;

  record JsonBuilder {
    var buf: Bytes;
    var needsComma: bool = false;

    proc ref beginObject() {
      separate();
      buf.append("{");
      needsComma = false;
    }

    proc ref endObject() {
      buf.append("}");
      needsComma = true;
    }

    proc ref beginArray() {
      separate();
      buf.append("[");
      needsComma = false;
    }

    proc ref endArray() {
      buf.append("]");
      needsComma = true;
    }

    proc ref key(name: string) {
      separate();
      writeString(name);
      buf.append(":");
      needsComma = false;
    }

    proc ref value(v: string) {
      separate();
      writeString(v);
      needsComma = true;
    }

    proc ref value(v: int) {
      separate();
      buf.append(v: string);
      needsComma = true;
    }

    proc ref value(v: real) {
      separate();
      if isNonFinite(v) {
        buf.append("null");
      } else {
        buf.append(v: string);
      }
      needsComma = true;
    }

    proc ref value(v: bool) {
      separate();
      buf.append(if v then "true" else "false");
      needsComma = true;
    }

    proc ref nullValue() {
      separate();
      buf.append("null");
      needsComma = true;
    }

    proc ref rawValue(json: string) {
      separate();
      buf.append(json);
      needsComma = true;
    }

    proc ref field(name: string, v: string) {
      key(name);
      value(v);
    }

    proc ref field(name: string, v: int) {
      key(name);
      value(v);
    }

    proc ref field(name: string, v: bool) {
      key(name);
      value(v);
    }

    proc ref field(name: string, v: real) {
      key(name);
      value(v);
    }

    proc done(): string do return buf.toString();

    proc ref clear() {
      buf.clear();
      needsComma = false;
    }

    proc ref separate() {
      if needsComma then buf.append(",");
    }

    proc ref writeString(s: string) {
      buf.append("\"");
      buf.append(escapeJson(s));
      buf.append("\"");
    }
  }

  private proc isNonFinite(v: real): bool {
    return !isFinite(v);
  }

  proc escapeJson(s: string): string {
    const hex = "0123456789abcdef";
    const src = s.c_str(): c_ptrConst(uint(8));
    var sb = new Bytes();
    sb.reserve(s.numBytes + 8);
    var runStart = 0;

    proc flushRun(upTo: int) {
      if upTo > runStart then sb.appendPtr(src + runStart, upTo - runStart);
    }

    var i = 0;
    while i < s.numBytes {
      const c = s.byte(i);
      var rep = "";
      select c {
        when 34 do rep = "\\\"";
        when 92 do rep = "\\\\";
        when 8  do rep = "\\b";
        when 12 do rep = "\\f";
        when 10 do rep = "\\n";
        when 13 do rep = "\\r";
        when 9  do rep = "\\t";
        when 60 do rep = "\\u003c";
        when 62 do rep = "\\u003e";
        when 38 do rep = "\\u0026";
        otherwise {
          if c < 32 {
            rep = "\\u00" + hex[(c / 16): int] + hex[(c % 16): int];
          } else if c == 0xE2 && i + 2 < s.numBytes && s.byte(i + 1) == 0x80 &&
                    (s.byte(i + 2) == 0xA8 || s.byte(i + 2) == 0xA9) {
            flushRun(i);
            sb.append(if s.byte(i + 2) == 0xA8 then "\\u2028" else "\\u2029");
            i += 3;
            runStart = i;
            continue;
          }
        }
      }
      if !rep.isEmpty() {
        flushRun(i);
        sb.append(rep);
        runStart = i + 1;
      }
      i += 1;
    }
    flushRun(s.numBytes);
    return sb.toString();
  }

  proc jsonString(s: string): string {
    return "\"" + escapeJson(s) + "\"";
  }
}
