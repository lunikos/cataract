module RouteTable {
  public use RouteParams;

  private use List;
  private use Map;
  private use Sort;
  private use HttpMessage;
  private use HttpMethod;

  enum RouteKind { page, api }

  /* Virtual, so a generated subclass carries per-route state. */
  class Handler {
    proc handle(ctx: Context): Response {
      return errorResponse(501, "handler not implemented");
    }
  }

  record Route {
    var pattern: string;
    var segments: list(Segment);
    var methodMask: int;
    var kind: RouteKind = RouteKind.page;
    var specificity: int = 0;
    var source: string = "";
    var handler: shared Handler?;
  }

  record MatchResult {
    var found: bool = false;
    var methodMismatch: bool = false;
    var allow: string = "";
    var routeIndex: int = -1;
    var params: map(string, string);
  }

  record BySpecificity: relativeComparator {
    proc compare(const ref a: Route, const ref b: Route): int {
      if a.specificity != b.specificity then return b.specificity - a.specificity;
      return if a.pattern < b.pattern then -1 else if a.pattern > b.pattern then 1 else 0;
    }
  }

  /* Literal patterns hash; the rest walk a specificity-sorted list, so the first
     structural match is the most specific one. */
  class Router {
    var routes: list(Route);
    var staticIndex: map(string, int);
    var staticMethodMask: map(string, int);
    var pages: int = 0;
    var sealed: bool = false;

    proc register(pattern: string, methodMask: int, kind: RouteKind,
                      source: string, in handler: shared Handler) throws {
      if sealed then
        throw new owned IllegalArgumentError("router sealed; cannot add " + pattern);

      var segs = compilePattern(pattern);
      var r = new Route(pattern = pattern,
                        segments = segs,
                        methodMask = methodMask,
                        kind = kind,
                        specificity = specificityOf(segs),
                        source = source,
                        handler = handler);
      routes.pushBack(r);
      if kind == RouteKind.page then pages += 1;
    }

    proc seal() {
      var arr = routes.toArray();
      sort(arr, comparator = new BySpecificity());

      routes.clear();
      for r in arr do routes.pushBack(r);

      staticIndex.clear();
      staticMethodMask.clear();
      for i in 0..<routes.size {
        if isStatic(routes[i].segments) {
          const key = routes[i].pattern;
          if !staticIndex.contains(key) {
            staticIndex[key] = i;
            staticMethodMask[key] = routes[i].methodMask;
          } else {
            /* Merge, so 405 is reported only when no registration accepts it. */
            staticMethodMask[key] = (try! staticMethodMask[key]) | routes[i].methodMask;
          }
        }
      }
      sealed = true;
    }

    proc match(path: string, method: Method): MatchResult {
      const m = effectiveMethod(method);
      var result = new MatchResult();

      if staticIndex.contains(path) {
        const combined = try! staticMethodMask[path];
        var i = try! staticIndex[path];
        while i < routes.size {
          if routes[i].pattern == path && maskAllows(routes[i].methodMask, m) {
            result.found = true;
            result.routeIndex = i;
            return result;
          }
          i += 1;
        }
        result.methodMismatch = true;
        result.allow = allowedMethodList(combined);
        return result;
      }

      const parts = splitPath(path);
      var mismatchMask = 0;

      for i in 0..<routes.size {
        var captured: map(string, string);
        if !structuralMatch(routes[i].segments, parts, captured) then continue;
        if !maskAllows(routes[i].methodMask, m) {
          mismatchMask |= routes[i].methodMask;
          continue;
        }
        result.found = true;
        result.routeIndex = i;
        result.params = captured;
        return result;
      }

      if mismatchMask != 0 {
        result.methodMismatch = true;
        result.allow = allowedMethodList(mismatchMask);
      }
      return result;
    }

    proc dispatch(at: int, ctx: Context): Response {
      return routes[at].handler!.handle(ctx);
    }

    proc size(): int do return routes.size;

    proc pageCount(): int do return pages;

    iter patterns() {
      for r in routes do yield (r.pattern, r.kind, r.source, allowedMethodList(r.methodMask));
    }
  }

  private proc structuralMatch(const ref segs: list(Segment), const ref parts: list(string),
                               ref captured: map(string, string)): bool {
    const hasCatchAll = segs.size > 0 && segs[segs.size - 1].kind == SegmentKind.catchAll;

    /* One segment minimum: "/docs/[...path]" must not also answer "/docs". */
    if hasCatchAll {
      if parts.size < segs.size then return false;
    } else if parts.size != segs.size {
      return false;
    }

    for i in 0..<segs.size {
      const s = segs[i];
      select s.kind {
        when SegmentKind.literal {
          if parts[i] != s.text then return false;
        }
        when SegmentKind.dynamic {
          if parts[i].isEmpty() then return false;
          captured[s.text] = parts[i];
        }
        when SegmentKind.catchAll {
          var rest = "";
          for j in i..<parts.size {
            if !rest.isEmpty() then rest += "/";
            rest += parts[j];
          }
          captured[s.text] = rest;
          return true;
        }
      }
    }
    return true;
  }
}
