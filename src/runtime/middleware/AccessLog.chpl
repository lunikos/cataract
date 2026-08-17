module AccessLog {
  private use Pipeline;
  private use HttpMessage;
  private use HttpMethod;
  private use HttpClock;
  private use Logging;

  class AccessLogger: Middleware {
    var slowRequestMillis: int = 500;

    override proc name(): string do return "access-log";

    override proc before(ref ctx: Context, ref res: Response): bool {
      ctx.startedAtMillis = monoMillis();
      return false;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      const elapsed = monoMillis() - ctx.startedAtMillis;
      const line = methodName(ctx.request.method) + " " + ctx.request.target +
                   " -> " + res.status:string +
                   " " + res.body.len:string + "b " + elapsed:string + "ms " +
                   ctx.request.clientIp();

      if res.status >= 500 then Logging.error(line);
      else if res.status >= 400 || elapsed >= slowRequestMillis then Logging.warn(line);
      else Logging.info(line);
    }
  }
}
