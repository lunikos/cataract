module Text {
  private use CTypes;

  proc sub(s: string, lo: int, hi: int): string throws {
    if hi <= lo || lo < 0 then return "";
    const stop = min(hi, s.numBytes);
    if stop <= lo then return "";
    const src = (s.c_str(): c_ptrConst(uint(8)) + lo): c_ptrConst(c_char);
    return string.createCopyingBuffer(src, stop - lo, decodePolicy.replace);
  }

  proc idx(s: string, needle: string, from: int = 0): int throws {
    const n = s.numBytes;
    const m = needle.numBytes;
    if m == 0 || m > n then return -1;
    var i = max(0, from);
    while i + m <= n {
      var j = 0;
      while j < m && s.byte(i + j) == needle.byte(j) do j += 1;
      if j == m then return i;
      i += 1;
    }
    return -1;
  }

  proc chplLiteral(s: string): string throws {
    var sb = "\"";
    var runStart = 0;
    const n = s.numBytes;
    for i in 0..<n {
      const c = s.byte(i);
      var rep = "";
      select c {
        when 34 do rep = "\\\"";
        when 92 do rep = "\\\\";
        when 10 do rep = "\\n";
        when 13 do rep = "\\r";
        when 9  do rep = "\\t";
        otherwise {
          if c >= 32 && c != 127 then continue;
          rep = "\\x" + hexByte(c);
        }
      }
      if i > runStart then sb += sub(s, runStart, i);
      sb += rep;
      runStart = i + 1;
    }
    if runStart < n then sb += sub(s, runStart, n);
    return sb + "\"";
  }

  private proc hexByte(c: uint(8)): string {
    const digits = "0123456789abcdef";
    return digits[((c >> 4) & 0xf): int] + digits[(c & 0xf): int];
  }
}
