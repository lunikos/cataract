module HttpHeaders {
  private use Map;
  private use List;
  private use CTypes;

  record Field {
    var name: string;
    var value: string;
  }

  record Headers {
    var fields: list(Field);
    var lookup: map(string, int);

    proc ref set(name: string, value: string) {
      const key = name.toLower();
      if lookup.contains(key) {
        const at = try! lookup[key];
        fields[at] = new Field(canonical(name), value);
      } else {
        lookup[key] = fields.size;
        fields.pushBack(new Field(canonical(name), value));
      }
    }

    proc ref add(name: string, value: string) {
      const key = name.toLower();
      if !lookup.contains(key) then lookup[key] = fields.size;
      fields.pushBack(new Field(canonical(name), value));
    }

    proc ref setIfAbsent(name: string, value: string) {
      if !contains(name) then set(name, value);
    }

    proc contains(name: string): bool {
      return lookup.contains(name.toLower());
    }

    proc count(name: string): int {
      const key = name.toLower();
      var n = 0;
      for f in fields do if f.name.toLower() == key then n += 1;
      return n;
    }

    proc get(name: string, fallback: string = ""): string {
      const key = name.toLower();
      if !lookup.contains(key) then return fallback;
      return fields[try! lookup[key]].value;
    }

    proc getInt(name: string, fallback: int): int {
      const raw = get(name).strip();
      if raw.isEmpty() then return fallback;
      var acc = 0;
      for i in 0..<raw.numBytes {
        const c = raw.byte(i);
        if c < 48 || c > 57 then return fallback;
        acc = acc * 10 + (c - 48): int;
        if acc > 1 << 40 then return fallback;
      }
      return acc;
    }

    proc ref remove(name: string) {
      const key = name.toLower();
      if !lookup.contains(key) then return;
      var kept: list(Field);
      for f in fields do
        if f.name.toLower() != key then kept.pushBack(f);
      fields = kept;
      reindex();
    }

    proc ref reindex() {
      lookup.clear();
      for (i, f) in zip(0..<fields.size, fields) {
        const key = f.name.toLower();
        if !lookup.contains(key) then lookup[key] = i;
      }
    }

    proc size(): int do return fields.size;

    iter these() {
      for f in fields do yield f;
    }
  }

  proc canonical(name: string): string {
    var sb = "";
    var upper = true;
    for i in 0..<name.numBytes {
      var c = name.byte(i);
      if upper && c >= 97 && c <= 122 then c -= 32;
      else if !upper && c >= 65 && c <= 90 then c += 32;
      sb += asciiChar(c);
      upper = (c == 45);
    }
    return sb;
  }

  proc asciiChar(c: uint(8)): string {
    var b: [0..0] uint(8) = c;
    return try! string.createCopyingBuffer(c_ptrToConst(b[0]): c_ptrConst(c_char), 1,
                                           decodePolicy.replace);
  }

  proc isSafeFieldValue(v: string): bool {
    for i in 0..<v.numBytes {
      const c = v.byte(i);
      if c == 13 || c == 10 || c == 0 then return false;
    }
    return true;
  }

  proc isSafeFieldName(v: string): bool {
    if v.isEmpty() then return false;
    for i in 0..<v.numBytes {
      const c = v.byte(i);
      const ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
                 c == 45 || c == 95 || c == 46;
      if !ok then return false;
    }
    return true;
  }
}
