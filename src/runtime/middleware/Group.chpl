module Group {
  private use List;
  private use Pipeline;
  private use HttpMessage;

  class MiddlewareGroup: Middleware {
    var title: string;
    var prefixes: list(string);
    var inner: Chain;

    proc init(title: string, prefix: string = "/") {
      this.title = title;
      init this;
      addPrefix(prefix);
    }

    override proc name(): string do return "group:" + title;

    proc addPrefix(prefix: string) {
      var normalized = prefix.strip();
      if normalized.isEmpty() then normalized = "/";
      if normalized.size > 1 && normalized.endsWith("/") then
        normalized = normalized[..<(normalized.size - 1)];
      prefixes.pushBack(normalized);
    }

    proc add(in stage: shared Middleware) {
      inner.add(stage);
    }

    proc size(): int do return inner.size();

    proc covers(path: string): bool {
      for prefix in prefixes {
        if prefix == "/" then return true;
        if path == prefix then return true;
        if path.startsWith(prefix + "/") then return true;
      }
      return false;
    }

    override proc before(ref ctx: Context, ref res: Response): bool {
      if !covers(ctx.request.path) then return false;
      const (handled, entered) = inner.runBefore(ctx, res);
      ctx.setLocal(stateKey(), entered: string);
      return handled;
    }

    override proc after(const ref ctx: Context, ref res: Response) {
      if !covers(ctx.request.path) then return;
      const entered = ctx.getLocal(stateKey(), "0");
      var depth = 0;
      try {
        depth = entered: int;
      } catch {
        depth = inner.size();
      }
      inner.runAfter(ctx, res, depth);
    }

    proc stateKey(): string do return "cataract.group." + title;
  }
}
