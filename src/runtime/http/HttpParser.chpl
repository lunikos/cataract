module HttpParser {
  private use Connections;
  private use ByteBuffer;
  private use CTypes;
  private use HttpMessage;
  private use HttpHeaders;
  private use HttpMethod;
  private use UrlCodec;

  record Limits {
    var maxRequestLine: int = 8192;
    var maxHeaderBytes: int = 32768;
    var maxHeaderCount: int = 100;
    var maxBodyBytes: int = 1048576;
    var maxBufferBytes: int = 262144;

    var requestTimeoutMillis: int = 20000;
  }

  enum Outcome { ok, closed, timedOut, malformed }

  record ParseResult {
    var outcome: Outcome = Outcome.malformed;
    var status: int = 400;
    var detail: string = "";
    var request: Request;
  }

  private proc findHeaderEnd(const ref b: [] uint(8), from: int, to: int): int {
    var i = from;
    while i + 3 < to {
      if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 then
        return i + 4;
      i += 1;
    }
    return -1;
  }

  private proc findLineEnd(const ref b: [] uint(8), from: int, to: int): int {
    var i = from;
    while i + 1 < to {
      if b[i] == 13 && b[i + 1] == 10 then return i;
      i += 1;
    }
    return -1;
  }

  private proc fail(status: int, detail: string): ParseResult {
    var r = new ParseResult();
    r.outcome = Outcome.malformed;
    r.status = status;
    r.detail = detail;
    return r;
  }

  proc readRequest(conn: borrowed Connection, const ref limits: Limits): ParseResult {
    var scanned = 0;
    var headerEnd = -1;
    var armed = false;
    defer conn.clearReadDeadline();

    while true {
      if conn.buffered() > 0 {
        if !armed {
          conn.startReadDeadline(limits.requestTimeoutMillis);
          armed = true;
        }
        const base = conn.start;
        const resumeAt = base + max(0, scanned - 3);
        headerEnd = findHeaderEnd(conn.inBuf, resumeAt, conn.stop);
        if headerEnd != -1 then break;
        scanned = conn.buffered();
      }

      if conn.buffered() >= limits.maxHeaderBytes then
        return fail(431, "header block exceeds " + limits.maxHeaderBytes:string + " bytes");

      if conn.buffered() >= conn.inDom.size {
        if !conn.growTo(conn.inDom.size * 2, limits.maxBufferBytes) then
          return fail(431, "header block exceeds connection buffer");
      }

      const st = conn.fill();
      select st {
        when ReadState.eof {
          var r = new ParseResult();
          r.outcome = if conn.buffered() == 0 then Outcome.closed else Outcome.malformed;
          r.status = 400;
          r.detail = "connection closed mid-request";
          return r;
        }
        when ReadState.timeout {
          var r = new ParseResult();
          r.outcome = Outcome.timedOut;
          r.status = 408;
          return r;
        }
        when ReadState.failed {
          var r = new ParseResult();
          r.outcome = Outcome.closed;
          r.status = 400;
          return r;
        }
        otherwise do ;
      }
    }

    var req = new Request();
    req.peerIp = conn.peerIp();
    req.peerPort = conn.peerPort();

    const lineEnd = findLineEnd(conn.inBuf, conn.start, headerEnd);
    if lineEnd == -1 then return fail(400, "missing request line");
    if lineEnd - conn.start > limits.maxRequestLine then
      return fail(414, "request line too long");

    const lineErr = parseRequestLine(conn.inBuf, conn.start, lineEnd, req);
    if lineErr != 0 then
      return fail(lineErr, "malformed request line");

    var cursor = lineEnd + 2;
    var count = 0;
    while cursor < headerEnd - 2 {
      const fieldEnd = findLineEnd(conn.inBuf, cursor, headerEnd);
      if fieldEnd == -1 then break;
      if fieldEnd == cursor then break;

      count += 1;
      if count > limits.maxHeaderCount then
        return fail(431, "too many header fields");

      const first = conn.inBuf[cursor];
      if first == 32 || first == 9 then
        return fail(400, "obsolete line folding rejected");

      const colon = findColon(conn.inBuf, cursor, fieldEnd);
      if colon == -1 then return fail(400, "header field without colon");

      const name = sliceToString(conn.inBuf, cursor, colon);
      if !isSafeFieldName(name) then return fail(400, "invalid header name");

      var vs = colon + 1;
      while vs < fieldEnd && (conn.inBuf[vs] == 32 || conn.inBuf[vs] == 9) do vs += 1;
      var ve = fieldEnd;
      while ve > vs && (conn.inBuf[ve - 1] == 32 || conn.inBuf[ve - 1] == 9) do ve -= 1;

      req.headers.add(name, sliceToString(conn.inBuf, vs, ve));
      cursor = fieldEnd + 2;
    }

    conn.consume(headerEnd - conn.start);

    if req.httpMinor >= 1 && !req.headers.contains("Host") then
      return fail(400, "HTTP/1.1 requires Host");
    if req.headers.count("Host") > 1 then
      return fail(400, "duplicate Host header");
    if req.headers.count("Content-Length") > 1 then
      return fail(400, "duplicate Content-Length header");
    if req.headers.count("Transfer-Encoding") > 1 then
      return fail(400, "duplicate Transfer-Encoding header");

    const connHeader = req.headers.get("Connection").toLower();
    req.keepAlive = if req.httpMinor == 0
                    then connHeader.find("keep-alive") != -1
                    else connHeader.find("close") == -1;

    const bodyResult = readBody(conn, limits, req);
    if bodyResult != 0 then
      return fail(bodyResult, "invalid message body");

    var ok = new ParseResult();
    ok.outcome = Outcome.ok;
    ok.status = 200;
    ok.request = req;
    return ok;
  }

  private proc findColon(const ref b: [] uint(8), from: int, to: int): int {
    var i = from;
    while i < to {
      if b[i] == 58 then return i;
      i += 1;
    }
    return -1;
  }

  private proc parseRequestLine(const ref b: [] uint(8), from: int, to: int,
                                ref req: Request): int {
    var sp1 = -1, sp2 = -1;
    var i = from;
    while i < to {
      if b[i] == 32 {
        if sp1 == -1 then sp1 = i;
        else if sp2 == -1 then sp2 = i;
        else return 400;
      }
      i += 1;
    }
    if sp1 == -1 || sp2 == -1 then return 400;

    req.method = parseMethod(sliceToString(b, from, sp1));
    if req.method == Method.unknown then return 501;

    const target = sliceToString(b, sp1 + 1, sp2);
    if target.isEmpty() || target.byte(0) != 47 then return 400;

    const version = sliceToString(b, sp2 + 1, to);
    if version == "HTTP/1.1" then req.httpMinor = 1;
    else if version == "HTTP/1.0" then req.httpMinor = 0;
    else return 505;

    req.target = target;
    const parts = splitTarget(target);
    req.queryString = parts.queryString;
    req.query = parseQuery(parts.queryString);

    const decoded = percentDecode(parts.path);
    const normalized = normalizePath(decoded);
    if normalized.isEmpty() then return 400;
    req.path = normalized;

    return 0;
  }

  private proc readBody(conn: borrowed Connection, const ref limits: Limits,
                        ref req: Request): int {
    const te = req.headers.get("Transfer-Encoding").toLower();
    const hasLength = req.headers.contains("Content-Length");

    if !te.isEmpty() && hasLength then return 400;

    if !te.isEmpty() {
      if te != "chunked" then return 501;
      return readChunkedBody(conn, limits, req);
    }

    if !hasLength {
      if req.method == Method.post || req.method == Method.put ||
         req.method == Method.patch then return 411;
      return 0;
    }

    const length = req.headers.getInt("Content-Length", -1);
    if length < 0 then return 400;
    if length > limits.maxBodyBytes then return 413;
    if length == 0 then return 0;

    req.body.reserve(length);
    var remaining = length;
    while remaining > 0 {
      if conn.buffered() == 0 {
        const st = conn.fill();
        if st != ReadState.ok then return 400;
      }
      const take = min(remaining, conn.buffered());
      req.body.appendPtr(c_ptrToConst(conn.inBuf[conn.start]), take);
      conn.consume(take);
      remaining -= take;
    }
    return 0;
  }

  private proc readChunkedBody(conn: borrowed Connection, const ref limits: Limits,
                               ref req: Request): int {
    var total = 0;

    while true {
      var lineEnd = findLineEnd(conn.inBuf, conn.start, conn.stop);
      while lineEnd == -1 {
        if conn.buffered() >= limits.maxRequestLine then return 400;
        if conn.buffered() >= conn.inDom.size &&
           !conn.growTo(conn.inDom.size * 2, limits.maxBufferBytes) then return 400;
        if conn.fill() != ReadState.ok then return 400;
        lineEnd = findLineEnd(conn.inBuf, conn.start, conn.stop);
      }

      const sizeLine = sliceToString(conn.inBuf, conn.start, lineEnd);
      conn.consume(lineEnd + 2 - conn.start);

      const size = parseChunkSize(sizeLine);
      if size < 0 then return 400;

      total += size;
      if total > limits.maxBodyBytes then return 413;

      if size == 0 {

        while true {
          var te = findLineEnd(conn.inBuf, conn.start, conn.stop);
          while te == -1 {
            if conn.buffered() >= limits.maxRequestLine then return 400;
            if conn.fill() != ReadState.ok then return 400;
            te = findLineEnd(conn.inBuf, conn.start, conn.stop);
          }
          const empty = (te == conn.start);
          conn.consume(te + 2 - conn.start);
          if empty then break;
        }
        return 0;
      }

      var remaining = size;
      while remaining > 0 {
        if conn.buffered() == 0 && conn.fill() != ReadState.ok then return 400;
        const take = min(remaining, conn.buffered());
        req.body.appendPtr(c_ptrToConst(conn.inBuf[conn.start]), take);
        conn.consume(take);
        remaining -= take;
      }

      while conn.buffered() < 2 do
        if conn.fill() != ReadState.ok then return 400;
      if !(conn.inBuf[conn.start] == 13 && conn.inBuf[conn.start + 1] == 10) then return 400;
      conn.consume(2);
    }
    return 0;
  }

  private proc parseChunkSize(line: string): int {
    var acc = 0;
    var seen = 0;
    for i in 0..<line.numBytes {
      const c = line.byte(i);
      if c == 59 then break;
      var v = -1;
      if c >= 48 && c <= 57 then v = (c - 48): int;
      else if c >= 97 && c <= 102 then v = (c - 87): int;
      else if c >= 65 && c <= 70 then v = (c - 55): int;
      else if c == 32 || c == 9 then break;
      else return -1;
      acc = acc * 16 + v;
      seen += 1;
      if seen > 8 then return -1;
    }
    if seen == 0 then return -1;
    return acc;
  }
}
