module Cors {
  private use Pipeline;
  private use HttpMessage;
  private use HttpMethod;

  private param preflightLocal = "cataract.cors.preflight";

  class CorsPolicy: Middleware {
    var allowedOrigins: string = "";
    var allowedMethods: string = "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS";
    var allowedHeaders: string = "Content-Type, Accept, Authorization, X-CSRF-Token";
    var exposedHeaders: string = "";
    var allowCredentials: bool = false;
    var maxAgeSeconds: int = 600;

    proc init(allowedOrigins: string = "", allowCredentials: bool = false) {
      this.allowedOrigins = allowedOrigins;
      this.allowCredentials = allowCredentials;
    }

    override proc name(): string do return "cors";

    proc wildcard(): bool do return allowedOrigins.strip() == "*";

    proc permits(origin: string): bool {
      if origin.isEmpty() then return false;
      if wildcard() then return true;
      for allowed in allowedOrigins.split(",") do
        if allowed.strip() == origin then return true;
      return false;
    }

    proc echoedOrigin(origin: string): string {
      return if wildcard() && !allowCredentials then "*" else origin;
    }

    override proc before(ref ctx: Context, ref res: Response): bool {
      const origin = ctx.request.header("Origin");
      if origin.isEmpty() then return false;

      const preflight = ctx.request.method == Method.options &&
                        !ctx.request.header("Access-Control-Request-Method").isEmpty();
      if !preflight then return false;

      if !permits(origin) {
        res = errorResponse(403, "origin is not allowed");
        return true;
      }

      res = new Response(status = 204);
      res.setHeader("Access-Control-Allow-Origin", echoedOrigin(origin));
      res.setHeader("Access-Control-Allow-Methods", allowedMethods);
      res.setHeader("Access-Control-Allow-Headers", requestedHeaders(ctx));
      res.setHeader("Access-Control-Max-Age", maxAgeSeconds: string);
      if allowCredentials then res.setHeader("Access-Control-Allow-Credentials", "true");
      res.addHeader("Vary", "Origin");
      res.addHeader("Vary", "Access-Control-Request-Headers");
      ctx.setLocal(preflightLocal, "1");
      return true;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      if !ctx.getLocal(preflightLocal).isEmpty() then return;
      const origin = ctx.request.header("Origin");
      if origin.isEmpty() || !permits(origin) then return;

      res.headers.setIfAbsent("Access-Control-Allow-Origin", echoedOrigin(origin));
      if allowCredentials then
        res.headers.setIfAbsent("Access-Control-Allow-Credentials", "true");
      if !exposedHeaders.isEmpty() then
        res.headers.setIfAbsent("Access-Control-Expose-Headers", exposedHeaders);
      res.addHeader("Vary", "Origin");
    }

    proc requestedHeaders(const ref ctx: Context): string {
      const asked = ctx.request.header("Access-Control-Request-Headers");
      return if allowedHeaders.strip() == "*" && !asked.isEmpty() then asked
             else allowedHeaders;
    }
  }
}
