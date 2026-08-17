module Pipeline {
  private use List;
  private use HttpMessage;

  /* `before` may short-circuit; `after` always runs, in reverse entry order. */
  class Middleware {
    proc name(): string do return "middleware";

    proc before(ref ctx: Context, ref res: Response): bool do return false;

    proc after(const ref ctx: Context, ref res: Response) { }
  }

  record Chain {
    var stages: list(shared Middleware);

    proc ref add(in m: shared Middleware) {
      stages.pushBack(m);
    }

    proc size(): int do return stages.size;

    proc runBefore(ref ctx: Context, ref res: Response): (bool, int) {
      for i in 0..<stages.size {
        if stages[i].before(ctx, res) then return (true, i + 1);
      }
      return (false, stages.size);
    }

    proc runAfter(const ref ctx: Context, ref res: Response, entered: int) {
      var i = entered - 1;
      while i >= 0 {
        stages[i].after(ctx, res);
        i -= 1;
      }
    }
  }
}
