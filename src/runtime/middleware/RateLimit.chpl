module RateLimit {
  private use Map;
  private use List;
  private use Pipeline;
  private use HttpMessage;
  private use HttpClock only monoMillis;
  private use JsonWrite only jsonString;

  record Bucket {
    var tokens: real = 0.0;
    var stampMillis: int(64) = 0;
  }

  class RateLimiter: Middleware {
    var requestsPerWindow: int = 60;
    var windowMillis: int = 60000;
    var burst: int = 0;
    var keyHeader: string = "";
    var maxTrackedClients: int = 10000;

    var gate: sync bool;
    var buckets: map(string, Bucket);

    proc init(requestsPerWindow: int = 60, windowMillis: int = 60000,
              burst: int = 0, keyHeader: string = "") {
      this.requestsPerWindow = requestsPerWindow;
      this.windowMillis = windowMillis;
      this.burst = burst;
      this.keyHeader = keyHeader;
      init this;
      gate.writeEF(true);
    }

    override proc name(): string do return "rate-limit";

    proc ceiling(): real {
      return (if burst > 0 then requestsPerWindow + burst else requestsPerWindow): real;
    }

    proc keyFor(const ref ctx: Context): string {
      if keyHeader.isEmpty() then return ctx.request.clientIp();
      const supplied = ctx.request.header(keyHeader);
      return if supplied.isEmpty() then ctx.request.clientIp() else supplied;
    }

    override proc before(ref ctx: Context, ref res: Response): bool {
      if requestsPerWindow <= 0 || windowMillis <= 0 then return false;

      const key = keyFor(ctx);
      const now = monoMillis();
      const perMilli = requestsPerWindow: real / windowMillis: real;

      gate.readFE();

      if buckets.size >= maxTrackedClients && !buckets.contains(key) then evict(now);

      var bucket = if buckets.contains(key) then (try! buckets[key])
                   else new Bucket(ceiling(), now);
      bucket.tokens = min(ceiling(),
                          bucket.tokens + (now - bucket.stampMillis): real * perMilli);
      bucket.stampMillis = now;

      const allowed = bucket.tokens >= 1.0;
      if allowed then bucket.tokens -= 1.0;
      try! buckets.addOrReplace(key, bucket);

      const remaining = bucket.tokens: int;
      gate.writeEF(true);

      ctx.setLocal("cataract.ratelimit.limit", ceiling(): int: string);
      ctx.setLocal("cataract.ratelimit.remaining", remaining: string);

      if allowed then return false;

      const waitSeconds = max(1, ((1.0 - bucket.tokens) / perMilli / 1000.0): int + 1);
      res = tooManyRequests(ctx, waitSeconds);
      return true;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      const limit = ctx.getLocal("cataract.ratelimit.limit");
      if limit.isEmpty() then return;
      res.headers.setIfAbsent("RateLimit-Limit", limit);
      res.headers.setIfAbsent("RateLimit-Remaining",
                              ctx.getLocal("cataract.ratelimit.remaining", "0"));
      res.headers.setIfAbsent("RateLimit-Policy",
                              requestsPerWindow: string + ";w=" +
                              (windowMillis / 1000): string);
    }

    proc evict(now: int(64)) {
      var stale: list(string);
      for key in buckets.keys() do
        if now - (try! buckets[key]).stampMillis > windowMillis then stale.pushBack(key);
      for key in stale do buckets.remove(key);
      if buckets.size >= maxTrackedClients then buckets.clear();
    }

    proc tooManyRequests(const ref ctx: Context, waitSeconds: int): Response {
      var res = if ctx.request.accepts("text/html") && !ctx.request.accepts("application/json")
                then errorResponse(429, "slow down and retry in " +
                                        waitSeconds: string + "s")
                else jsonResponse("{\"error\":\"rate_limited\",\"retryAfter\":" +
                                  waitSeconds: string + ",\"path\":" +
                                  jsonString(ctx.request.path) + "}", 429);
      res.setHeader("Retry-After", waitSeconds: string);
      return res;
    }
  }
}
