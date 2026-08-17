module HttpWriter {
  private use Connections;
  private use ByteBuffer;
  private use HttpMessage;
  private use HttpHeaders;
  private use HttpStatus;
  private use HttpMethod;
  private use HttpClock;
  private use Logging;

  config const serverToken = "Cataract";

  proc writeResponse(conn: borrowed Connection, ref res: Response,
                     requestMethod: Method, keepAlive: bool): bool {
    const bodyAllowed = hasBody(res.status) && requestMethod != Method.head;
    const contentLength = if hasBody(res.status) then res.body.len else 0;

    conn.write("HTTP/1.1 " + res.status:string + " " + reason(res.status) + "\r\n");

    res.headers.set("Date", httpDate());
    res.headers.setIfAbsent("Server", serverToken);
    if hasBody(res.status) then
      res.headers.set("Content-Length", contentLength:string);
    else
      res.headers.remove("Content-Length");
    res.headers.set("Connection", if keepAlive then "keep-alive" else "close");

    for f in res.headers {
      if !isSafeFieldName(f.name) || !isSafeFieldValue(f.value) {
        Logging.warn("dropped unsafe response header: " + f.name);
        continue;
      }
      conn.write(f.name);
      conn.write(": ");
      conn.write(f.value);
      conn.write("\r\n");
    }
    conn.write("\r\n");

    if bodyAllowed && res.body.len > 0 then
      conn.writeBytes(res.body);

    return conn.flush();
  }

  proc writeBareError(conn: borrowed Connection, status: int, detail: string = ""): bool {
    const title = reason(status);
    const payload = status:string + " " + title +
                    (if detail.isEmpty() then "" else " - " + detail) + "\n";
    conn.write("HTTP/1.1 " + status:string + " " + title + "\r\n");
    conn.write("Date: " + httpDate() + "\r\n");
    conn.write("Server: " + serverToken + "\r\n");
    conn.write("Content-Type: text/plain; charset=utf-8\r\n");
    conn.write("Content-Length: " + payload.numBytes:string + "\r\n");
    conn.write("Connection: close\r\n\r\n");
    conn.write(payload);
    return conn.flush();
  }
}
