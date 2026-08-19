module UrlCodec {
  private use Map;
  private use List;
  private use CTypes;
  private use HttpHeaders only asciiChar;

  private proc hexVal(c: uint(8)): int {
    if c >= 48 && c <= 57 then return (c - 48): int;
    if c >= 97 && c <= 102 then return (c - 87): int;
    if c >= 65 && c <= 70 then return (c - 55): int;
    return -1;
  }

  proc percentDecode(s: string, plusAsSpace: bool = false): string {
    var sb: [0..<(s.numBytes + 1)] uint(8);
    var n = 0;
    var i = 0;
    while i < s.numBytes {
      const c = s.byte(i);
      if c == 37 && i + 2 < s.numBytes {
        const hi = hexVal(s.byte(i + 1));
        const lo = hexVal(s.byte(i + 2));
        if hi >= 0 && lo >= 0 {
          sb[n] = (hi * 16 + lo): uint(8);
          n += 1;
          i += 3;
          continue;
        }
      }
      sb[n] = if plusAsSpace && c == 43 then 32: uint(8) else c;
      n += 1;
      i += 1;
    }
    if n == 0 then return "";
    return try! string.createCopyingBuffer(c_ptrToConst(sb[0]): c_ptrConst(c_char), n,
                                           decodePolicy.replace);
  }

  proc percentEncode(s: string): string {
    const hex = "0123456789ABCDEF";
    var sb = "";
    for i in 0..<s.numBytes {
      const c = s.byte(i);
      const unreserved = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) ||
                         (c >= 97 && c <= 122) || c == 45 || c == 46 || c == 95 || c == 126;
      if unreserved {
        sb += asciiChar(c);
      } else {
        sb += "%";
        sb += hex[(c / 16): int];
        sb += hex[(c % 16): int];
      }
    }
    return sb;
  }

  record Query {
    var pairs: map(string, string);

    proc get(name: string, fallback: string = ""): string {
      if pairs.contains(name) then return try! pairs[name];
      return fallback;
    }

    proc getInt(name: string, fallback: int): int {
      const raw = get(name);
      if raw.isEmpty() then return fallback;
      try {
        return raw: int;
      } catch {
        return fallback;
      }
    }

    proc contains(name: string): bool do return pairs.contains(name);
    proc size(): int do return pairs.size;
  }

  proc parseQuery(raw: string): Query {
    var q = new Query();
    if raw.isEmpty() then return q;
    for part in raw.split("&") {
      if part.isEmpty() then continue;
      const eq = part.find("=");
      var k: string, v: string;
      if eq == -1 {
        k = part;
        v = "";
      } else {
        k = try! part[..<eq];
        v = try! part[(eq + 1)..];
      }
      const key = percentDecode(k, plusAsSpace = true);
      if key.isEmpty() then continue;
      if !q.pairs.contains(key) then
        q.pairs[key] = percentDecode(v, plusAsSpace = true);
    }
    return q;
  }

  proc hasControlBytes(s: string): bool {
    for i in 0..<s.numBytes {
      const c = s.byte(i);
      if c <= 32 || c == 127 then return true;
    }
    return false;
  }

  record TargetParts {
    var path: string;
    var queryString: string;
  }

  proc splitTarget(target: string): TargetParts {
    const q = target.find("?");
    if q == -1 then return new TargetParts(target, "");
    return new TargetParts(try! target[..<q], try! target[(q + 1)..]);
  }

  proc normalizePath(path: string): string {
    if path.isEmpty() || path.byte(0) != 47 then return "";
    var stack: list(string);
    for seg in path.split("/") {
      if seg.isEmpty() || seg == "." then continue;
      if seg == ".." {
        if stack.isEmpty() then return "";
        stack.popBack();
        continue;
      }
      if hasControlBytes(seg) then return "";
      stack.pushBack(seg);
    }
    if stack.isEmpty() then return "/";
    var sb = "";
    for seg in stack do sb += "/" + seg;
    if path.endsWith("/") then sb += "/";
    return sb;
  }
}
