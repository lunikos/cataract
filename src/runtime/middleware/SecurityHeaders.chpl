module SecurityHeaders {
  private use Pipeline;
  private use HttpMessage;
  private use HttpMethod;

  /* Hardening, plus the checks that must run before a handler does. */
  class SecurityGuard: Middleware {
    var contentSecurityPolicy: string =
      "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " +
      "object-src 'none'; base-uri 'self'; frame-ancestors 'none'";
    var hstsSeconds: int = 0;
    var allowedOrigins: string = "";
    var enforceOrigin: bool = true;

    override proc name(): string do return "security";

    override proc before(ref ctx: Context, ref res: Response): bool {
      const m = ctx.request.method;
      const mutating = (m == Method.post || m == Method.put ||
                        m == Method.patch || m == Method.del);

      if enforceOrigin && mutating {
        const origin = ctx.request.header("Origin");
        if !origin.isEmpty() && !originAllowed(origin, ctx.request.header("Host")) {
          res = errorResponse(403, "cross-origin request rejected");
          return true;
        }
      }
      return false;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      res.headers.setIfAbsent("X-Content-Type-Options", "nosniff");
      res.headers.setIfAbsent("Referrer-Policy", "strict-origin-when-cross-origin");
      res.headers.setIfAbsent("X-Frame-Options", "DENY");
      res.headers.setIfAbsent("Cross-Origin-Opener-Policy", "same-origin");
      res.headers.setIfAbsent("Cross-Origin-Resource-Policy", "same-origin");

      const mime = res.headers.get("Content-Type");
      if mime.startsWith("text/html") then
        res.headers.setIfAbsent("Content-Security-Policy", contentSecurityPolicy);

      if hstsSeconds > 0 && ctx.request.isSecureContext() then
        res.headers.setIfAbsent("Strict-Transport-Security",
                                "max-age=" + hstsSeconds:string + "; includeSubDomains");
    }

    proc originAllowed(origin: string, host: string): bool {
      if !host.isEmpty() {
        if origin == "https://" + host || origin == "http://" + host then return true;
      }
      if allowedOrigins.isEmpty() then return false;
      for allowed in allowedOrigins.split(",") do
        if allowed.strip() == origin then return true;
      return false;
    }
  }
}
