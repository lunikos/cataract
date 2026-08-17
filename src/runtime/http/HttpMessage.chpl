module HttpMessage {
  public use HttpMethod;
  public use HttpHeaders;
  public use UrlCodec;

  private use ByteBuffer;
  private use HttpStatus;
  private use MimeTypes;
  private use Map;
  private use Html only escape;

  record Request {
    var method: Method = Method.get;
    var target: string = "/";
    var path: string = "/";
    var queryString: string = "";
    var query: Query;
    var httpMinor: int = 1;
    var headers: Headers;
    var body: Bytes;
    var peerIp: string = "";
    var peerPort: int = 0;
    var keepAlive: bool = true;

    proc header(name: string, fallback: string = ""): string do
      return headers.get(name, fallback);

    proc contentType(): string do return headers.get("Content-Type");

    proc bodyText(): string do return body.toString();

    proc isSecureContext(): bool do
      return headers.get("X-Forwarded-Proto").toLower() == "https";

    proc accepts(mime: string): bool {
      const a = headers.get("Accept", "*/*");
      return a.find(mime) != -1 || a.find("*/*") != -1;
    }

    /* Spoofable unless a proxy overwrites it; never use for authorization. */
    proc clientIp(): string {
      const fwd = headers.get("X-Forwarded-For");
      if fwd.isEmpty() then return peerIp;
      const comma = fwd.find(",");
      if comma == -1 then return fwd.strip();
      return (try! fwd[..<comma]).strip();
    }
  }

  record Response {
    var status: int = 200;
    var headers: Headers;
    var body: Bytes;
    var closeConnection: bool = false;

    proc ref setHeader(name: string, value: string) {
      headers.set(name, value);
    }

    proc ref addHeader(name: string, value: string) {
      headers.add(name, value);
    }

    proc ref setBody(s: string) {
      body.clear();
      body.append(s);
    }

    proc ref setCookie(name: string, value: string, path: string = "/",
                       maxAge: int = -1, httpOnly: bool = true,
                       secure: bool = true, sameSite: string = "Lax") {
      var v = name + "=" + percentEncode(value) + "; Path=" + path;
      if maxAge >= 0 then v += "; Max-Age=" + maxAge:string;
      if httpOnly then v += "; HttpOnly";
      if secure then v += "; Secure";
      v += "; SameSite=" + sameSite;
      headers.add("Set-Cookie", v);
    }
  }

  proc htmlResponse(markup: string, status: int = 200): Response {
    var r = new Response(status = status);
    r.setHeader("Content-Type", "text/html; charset=utf-8");
    r.setBody(markup);
    return r;
  }

  proc textResponse(text: string, status: int = 200): Response {
    var r = new Response(status = status);
    r.setHeader("Content-Type", "text/plain; charset=utf-8");
    r.setBody(text);
    return r;
  }

  proc jsonResponse(payload: string, status: int = 200): Response {
    var r = new Response(status = status);
    r.setHeader("Content-Type", "application/json; charset=utf-8");
    r.setBody(payload);
    return r;
  }

  proc bytesResponse(in payload: Bytes, mime: string, status: int = 200): Response {
    var r = new Response(status = status);
    r.setHeader("Content-Type", mime);
    r.body = payload;
    return r;
  }

  proc redirect(location: string, status: int = 303): Response {
    var r = new Response(status = status);
    r.setHeader("Location", location);
    r.setHeader("Content-Type", "text/plain; charset=utf-8");
    r.setBody("Redirecting to " + location);
    return r;
  }

  proc noContent(): Response {
    return new Response(status = 204);
  }

  /* `detail` is escaped: it is a public parameter, so a handler could pass
     request-derived text into it. */
  proc errorResponse(status: int, detail: string = ""): Response {
    const title = reason(status);
    const body = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" +
                 "<title>" + status:string + " " + title + "</title></head><body>" +
                 "<h1>" + status:string + " &middot; " + title + "</h1>" +
                 (if detail.isEmpty() then "" else "<p>" + escape(detail) + "</p>") +
                 "</body></html>";
    var r = htmlResponse(body, status);
    if status >= 500 then r.closeConnection = true;
    return r;
  }

  /* What a handler sees: no file descriptors, no buffers, no C pointers. */
  record Context {
    var request: Request;
    var params: map(string, string);
    var locals: map(string, string);
    var startedAtMillis: int(64) = 0;
    var requestId: string = "";

    proc pathParam(name: string, fallback: string = ""): string {
      if params.contains(name) then return try! params[name];
      return fallback;
    }

    proc paramInt(name: string, fallback: int): int {
      const raw = pathParam(name);
      if raw.isEmpty() then return fallback;
      try {
        return raw: int;
      } catch {
        return fallback;
      }
    }

    proc queryParam(name: string, fallback: string = ""): string do
      return request.query.get(name, fallback);

    proc ref setLocal(name: string, value: string) {
      locals[name] = value;
    }

    proc getLocal(name: string, fallback: string = ""): string {
      if locals.contains(name) then return try! locals[name];
      return fallback;
    }

    proc method(): Method do return request.method;
    proc path(): string do return request.path;
  }
}
