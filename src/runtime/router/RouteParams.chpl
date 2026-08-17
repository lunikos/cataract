module RouteParams {
  private use List;
  private use HttpMethod;

  enum SegmentKind { literal, dynamic, catchAll }

  record Segment {
    var kind: SegmentKind = SegmentKind.literal;
    var text: string = "";
  }

  /* [id] is one segment; [...rest] is the remainder and must come last. */
  proc compilePattern(pattern: string): list(Segment) throws {
    var segs: list(Segment);
    if pattern == "/" then return segs;

    const raw = pattern.split("/");
    var idx = 0;
    for part in raw {
      if part.isEmpty() then continue;
      idx += 1;
      if part.startsWith("[") && part.endsWith("]") {
        var inner = part[1..<(part.size - 1)];
        if inner.startsWith("...") {
          const name = inner[3..];
          if name.isEmpty() then
            throw new owned IllegalArgumentError("empty catch-all name in " + pattern);
          segs.pushBack(new Segment(SegmentKind.catchAll, name));
        } else {
          if inner.isEmpty() then
            throw new owned IllegalArgumentError("empty parameter name in " + pattern);
          segs.pushBack(new Segment(SegmentKind.dynamic, inner));
        }
      } else {
        segs.pushBack(new Segment(SegmentKind.literal, part));
      }
    }

    for i in 0..<segs.size do
      if segs[i].kind == SegmentKind.catchAll && i != segs.size - 1 then
        throw new owned IllegalArgumentError("catch-all must be the last segment in " + pattern);

    return segs;
  }

  /* Static beats dynamic at equal depth; deeper beats shallower; catch-all sinks. */
  proc specificityOf(const ref segs: list(Segment)): int {
    var score = segs.size * 100;
    for s in segs {
      select s.kind {
        when SegmentKind.literal do score += 10;
        when SegmentKind.dynamic do score += 3;
        when SegmentKind.catchAll do score -= 50;
      }
    }
    return score;
  }

  proc isStatic(const ref segs: list(Segment)): bool {
    for s in segs do
      if s.kind != SegmentKind.literal then return false;
    return true;
  }

  proc splitPath(path: string): list(string) {
    var sb: list(string);
    for part in path.split("/") do
      if !part.isEmpty() then sb.pushBack(part);
    return sb;
  }

  proc methodBit(m: Method): int do return 1 << (m: int);

  proc maskAllows(mask: int, m: Method): bool {
    return (mask & methodBit(m)) != 0;
  }

  proc allowedMethodList(mask: int): string {
    var sb = "";
    for m in Method {
      if m == Method.unknown || m == Method.head then continue;
      if maskAllows(mask, m) {
        if !sb.isEmpty() then sb += ", ";
        sb += methodName(m);
      }
    }
    if maskAllows(mask, Method.get) then sb += ", HEAD";
    return sb;
  }
}
