module Html {
  private use ByteBuffer;
  private use CTypes;
  private use Types only isStringType;

  proc escape(s: string): string {
    var needs = false;
    for i in 0..<s.numBytes {
      const c = s.byte(i);
      if c == 38 || c == 60 || c == 62 || c == 34 || c == 39 {
        needs = true;
        break;
      }
    }
    if !needs then return s;

    const src = s.c_str(): c_ptrConst(uint(8));
    var sb = new Bytes();
    sb.reserve(s.numBytes + 16);
    var runStart = 0;
    for i in 0..<s.numBytes {
      const c = s.byte(i);
      var rep = "";
      select c {
        when 38 do rep = "&amp;";
        when 60 do rep = "&lt;";
        when 62 do rep = "&gt;";
        when 34 do rep = "&quot;";
        when 39 do rep = "&#39;";
        otherwise do continue;
      }
      if i > runStart then sb.appendPtr(src + runStart, i - runStart);
      sb.append(rep);
      runStart = i + 1;
    }
    if runStart < s.numBytes then sb.appendPtr(src + runStart, s.numBytes - runStart);
    return sb.toString();
  }

  proc stringify(const ref v): string {
    param isStr = isStringType(v.type);
    if isStr then return v;
    else return v: string;
  }
}
