module Csrf {
  private use IO;
  private use Pipeline;
  private use HttpMessage;
  private use HttpMethod;
  private use UrlCodec only parseQuery, percentDecode;
  private use HttpClock only monoMillis;
  private use Logging;

  param tokenLocal = "cataract.csrf.token";
  private param mintedLocal = "cataract.csrf.minted";

  proc csrfToken(const ref ctx: Context): string do return ctx.getLocal(tokenLocal);

  class CsrfGuard: Middleware {
    var cookieName: string = "cataract_csrf";
    var headerName: string = "X-CSRF-Token";
    var fieldName: string = "_csrf";
    var cookiePath: string = "/";
    var secureCookie: bool = true;
    var sameSite: string = "Lax";
    var tokenBytes: int = 16;

    proc init(cookieName: string = "cataract_csrf",
              headerName: string = "X-CSRF-Token") {
      this.cookieName = cookieName;
      this.headerName = headerName;
    }

    override proc name(): string do return "csrf";

    override proc before(ref ctx: Context, ref res: Response): bool {
      const held = cookieValue(ctx, cookieName);

      if isMutating(ctx.request.method) {
        if held.isEmpty() || !sameToken(held, submitted(ctx)) {
          res = errorResponse(403, "CSRF token missing or stale");
          return true;
        }
      }

      if held.isEmpty() {
        const minted = newToken(tokenBytes);
        ctx.setLocal(tokenLocal, minted);
        ctx.setLocal(mintedLocal, "1");
      } else {
        ctx.setLocal(tokenLocal, held);
      }
      return false;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      if ctx.getLocal(mintedLocal).isEmpty() then return;
      res.setCookie(cookieName, ctx.getLocal(tokenLocal), cookiePath, -1,
                    httpOnly = false, secure = secureCookie, sameSite = sameSite);
    }

    proc submitted(const ref ctx: Context): string {
      const fromHeader = ctx.request.header(headerName).strip();
      if !fromHeader.isEmpty() then return fromHeader;
      if !ctx.request.contentType().startsWith("application/x-www-form-urlencoded") then
        return "";
      return parseQuery(ctx.request.bodyText()).get(fieldName);
    }
  }

  proc isMutating(m: Method): bool {
    return m == Method.post || m == Method.put || m == Method.patch || m == Method.del;
  }

  proc cookieValue(const ref ctx: Context, name: string): string {
    const needle = name + "=";
    for crumb in ctx.request.header("Cookie").split(";") {
      const item = crumb.strip();
      if item.startsWith(needle) then
        return percentDecode((try! item[needle.size..]).strip());
    }
    return "";
  }

  proc sameToken(a: string, b: string): bool {
    if a.isEmpty() || b.isEmpty() then return false;
    if a.numBytes != b.numBytes then return false;
    var difference = 0;
    for i in 0..<a.numBytes do difference |= (a.byte(i) ^ b.byte(i)): int;
    return difference == 0;
  }

  private var fallbackCounter: atomic int;

  proc newToken(byteCount: int): string {
    const wanted = max(8, byteCount);
    var raw: [0..<wanted] uint(8);
    if !fillFromUrandom(raw, wanted) then fillFromClock(raw, wanted);
    return hexOf(raw, wanted);
  }

  private proc fillFromUrandom(ref raw: [] uint(8), wanted: int): bool {
    try {
      const source = open("/dev/urandom", ioMode.r);
      defer try! source.close();
      var reader = source.reader(locking = false);
      defer try! reader.close();
      return reader.readBinary(raw) == wanted;
    } catch {
      return false;
    }
  }

  private proc fillFromClock(ref raw: [] uint(8), wanted: int) {
    Logging.warn("csrf: /dev/urandom is unavailable; tokens are weaker than intended");
    var mixed: uint(64) = (monoMillis(): uint(64) << 20) ^
                          fallbackCounter.fetchAdd(1): uint(64);
    for i in 0..<wanted {
      mixed = mixed * 6364136223846793005 + 1442695040888963407;
      raw[i] = (mixed >> 33): uint(8);
    }
  }

  private proc hexOf(const ref raw: [] uint(8), count: int): string {
    const digits = "0123456789abcdef";
    var sb = "";
    for i in 0..<count {
      sb += digits[(raw[i] >> 4): int];
      sb += digits[(raw[i] & 0xf): int];
    }
    return sb;
  }
}
