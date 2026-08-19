module ByteBuffer {
  private use CSocket;

  record Bytes {
    var dom: domain(1) = {0..<0};
    var data: [dom] uint(8);
    var len: int = 0;

    proc ref reserve(n: int) {
      if n <= dom.size then return;
      var cap = if dom.size == 0 then 1024 else dom.size;
      while cap < n do cap *= 2;
      dom = {0..<cap};
    }

    proc ref clear() {
      len = 0;
    }

    proc ref push(b: uint(8)) {
      reserve(len + 1);
      data[len] = b;
      len += 1;
    }

    proc ref appendPtr(src: c_ptrConst(uint(8)), n: int) {
      if n <= 0 then return;
      reserve(len + n);
      memcpy(c_ptrTo(data[len]): c_ptr(void), src: c_ptrConst(void), n: c_size_t);
      len += n;
    }

    proc ref append(s: string) {
      const n = s.numBytes;
      if n == 0 then return;
      appendPtr(s.c_str(): c_ptrConst(uint(8)), n);
    }

    proc ref append(const ref other: Bytes) {
      if other.len == 0 then return;
      appendPtr(other.ptrConst(), other.len);
    }

    proc ref appendLine(s: string) {
      append(s);
      push(13);
      push(10);
    }

    proc ptr(): c_ptr(uint(8)) {
      if dom.size == 0 then return nil;
      return c_ptrTo(data[0]);
    }

    proc ptrConst(): c_ptrConst(uint(8)) {
      if dom.size == 0 then return nil;
      return c_ptrToConst(data[0]);
    }

    proc isEmpty(): bool do return len == 0;

    proc toString(): string {
      return sliceToString(data, 0, len);
    }
  }

  proc sliceToString(const ref buf: [] uint(8), lo: int, hi: int): string {
    if hi <= lo then return "";
    const n = hi - lo;
    return try! string.createCopyingBuffer(c_ptrToConst(buf[lo]): c_ptrConst(c_char), n,
                                           decodePolicy.replace);
  }
}
