module Scanner {
  private use List;
  private use Map;
  private use Sort;
  private use IO;
  private use FileSystem;
  private use Path;
  private use Diagnostics;
  private use Manifest;
  private use Text;
  private use AppConfig;

  /* [id] is one segment, [...name] the rest, (group) none, _ and . skipped. */
  proc scanRoutes(const ref cfg: ProjectConfig, root: string, ref diags: Bag): Bundle throws {
    var bundle = new Bundle();

    const routesRoot = resolveIn(root, cfg.routesDir);
    if !isDir(routesRoot) {
      diags.error(routesRoot, 0, "routes directory not found",
                  "create it, or set paths.routes in cataract.toml");
      return bundle;
    }

    var files: list(string);
    collectFiles(routesRoot, files);

    var sorted = files.toArray();
    sort(sorted);

    var seen: map(string, string);
    var symbols: map(string, int);
    var urlNames: map(string, int);

    for path in sorted {
      const rel = relativeTo(routesRoot, path);
      if !rel.endsWith(".chpl") {
        diags.note(path, "not a Chapel module; skipping");
        continue;
      }

      var entry = new RouteEntry();
      entry.sourcePath = path;
      entry.pattern = patternFor(rel, path, diags);
      if entry.pattern.isEmpty() then continue;
      entry.specificity = specificityOf(entry.pattern);
      collectParams(entry.pattern, entry.params);

      readRouteModule(path, entry, diags);
      if entry.moduleName.isEmpty() then continue;

      const prefix = if entry.kind == EntryKind.page then "page_"
                     else if entry.kind == EntryKind.socket then "socket_"
                     else "api_";
      entry.symbol = unique(symbols, symbolFor(prefix, entry.pattern));
      entry.urlName = unique(urlNames, urlNameFor(entry.pattern));

      if entry.kind == EntryKind.page {
        if !contains(bundle.pageModules, entry.moduleName) then
          bundle.pageModules.pushBack(entry.moduleName);
      } else if !contains(bundle.apiModules, entry.moduleName) {
        bundle.apiModules.pushBack(entry.moduleName);
      }

      const dupKey = entry.pattern + " " + methodKey(entry.methods);
      if seen.contains(dupKey) {
        diags.error(path, 0,
                    "route " + entry.pattern + " already handled by " + seen[dupKey],
                    "give the routes distinct paths or distinct methods");
        continue;
      }
      seen[dupKey] = path;

      bundle.routes.pushBack(entry);
    }

    scanLayouts(cfg, root, bundle, bundle.pageCount() > 0, diags);
    scanIslands(cfg, root, bundle, diags);
    scanLib(cfg, root, diags);

    for r in bundle.routes do
      if r.kind == EntryKind.page && !bundle.layouts.contains(r.layout) then
        diags.error(r.sourcePath, 0, "unknown layout \"" + r.layout + "\"",
                    "add " + cfg.layoutsDir + "/" + r.layout + ".chpl");

    return bundle;
  }

  private proc unique(ref taken: map(string, int), candidate: string): string throws {
    if !taken.contains(candidate) {
      taken[candidate] = 1;
      return candidate;
    }
    taken[candidate] += 1;
    return candidate + "_" + taken[candidate]:string;
  }

  private proc collectFiles(dir: string, ref acc: list(string)) throws {
    for entry in listDir(dir, hidden = false) {
      if entry.startsWith("_") || entry.startsWith(".") then continue;
      const full = joinPath(dir, entry);
      if isDir(full) then collectFiles(full, acc);
      else if isFile(full) then acc.pushBack(full);
    }
  }

  private proc relativeTo(root: string, path: string): string throws {
    if !path.startsWith(root) then return path;
    var at = root.numBytes;
    while at < path.numBytes && path.byte(at) == 47 do at += 1;
    return sub(path, at, path.numBytes);
  }

  private proc stripExtension(name: string): string throws {
    const dot = name.rfind(".");
    if dot == -1 then return name;
    return name[..<dot];
  }

  private proc patternFor(rel: string, path: string, ref diags: Bag): string throws {
    var segments: list(string);
    const parts = rel.split("/");
    var seenSegments = 0;

    for part in parts {
      seenSegments += 1;
      const isLast = (seenSegments == parts.size);
      var name = if isLast then stripExtension(part) else part;

      if name.isEmpty() then continue;
      if name.startsWith("(") && name.endsWith(")") then continue;
      if isLast && name == "index" then continue;

      if name.startsWith("[") {
        if !name.endsWith("]") {
          diags.error(path, 0, "malformed dynamic segment \"" + name + "\"",
                      "use [name] or [...name]");
          return "";
        }
        const inner = name[1..<(name.size - 1)];
        const bare = if inner.startsWith("...") then inner[3..] else inner;
        if bare.isEmpty() || !isIdentifier(bare) {
          diags.error(path, 0, "\"" + bare + "\" is not a usable parameter name",
                      "parameter names must be Chapel identifiers");
          return "";
        }
        if inner.startsWith("...") && !isLast {
          diags.error(path, 0, "catch-all segment must be the last part of the path");
          return "";
        }
      }

      segments.pushBack(name);
    }

    if segments.isEmpty() then return "/";
    var sb = "";
    for s in segments do sb += "/" + s;
    return sb;
  }

  private proc collectParams(pattern: string, ref params: list(string)) throws {
    for seg in pattern.split("/") {
      if !seg.startsWith("[") then continue;
      var inner = seg[1..<(seg.size - 1)];
      if inner.startsWith("...") then inner = inner[3..];
      params.pushBack(inner);
    }
  }

  private proc isIdentifier(s: string): bool throws {
    if s.isEmpty() then return false;
    var first = true;
    for ch in s {
      const alpha = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_";
      const digit = ch >= "0" && ch <= "9";
      if first && !alpha then return false;
      if !alpha && !digit then return false;
      first = false;
    }
    return true;
  }

  private proc methodKey(const ref methods: list(string)): string throws {
    if methods.isEmpty() then return "GET";
    var arr = methods.toArray();
    sort(arr);
    var sb = "";
    for m in arr {
      if !sb.isEmpty() then sb += ",";
      sb += m.toUpper();
    }
    return sb;
  }

  /* What a module declares decides what it is. The module name is explicit
     because two index.chpl files would otherwise collide. */
  private proc readRouteModule(path: string, ref entry: RouteEntry,
                               ref diags: Bag) throws {
    const source = readSource(path, "route", diags);

    entry.moduleName = findModuleName(source);
    if entry.moduleName.isEmpty() {
      if !source.isEmpty() then
        diags.error(path, 0, "route has no module declaration",
                    "wrap the file in `module " + suggestModuleName(entry.pattern) +
                    " { ... }`");
      return;
    }

    const socketAt = findProc(source, "socket");
    if socketAt >= 0 {
      entry.kind = EntryKind.socket;
      entry.throwsRender = lineDeclaresThrows(source, socketAt);
      entry.methods.pushBack("GET");
      return;
    }

    /* `delete` cannot name a Chapel procedure, so DELETE is spelled `del`. */
    const handlers = [("get", "GET"), ("post", "POST"), ("put", "PUT"),
                      ("patch", "PATCH"), ("del", "DELETE"), ("options", "OPTIONS")];

    for (fn, httpName) in handlers {
      const at = findProc(source, fn);
      if at < 0 then continue;
      entry.methods.pushBack(httpName);
      if lineDeclaresThrows(source, at) then entry.throwsMethods.pushBack(httpName);
    }

    if findProc(source, "delete") >= 0 then
      diags.error(path, 0, "`delete` is a Chapel keyword and cannot name a procedure",
                  "spell the DELETE handler `proc del(ctx: Context): Response`");

    const pageAt = findProc(source, "page");
    if pageAt >= 0 {
      if !entry.methods.isEmpty() {
        diags.error(path, 0, "route declares both `proc page` and method handlers",
                    "a page and an API route are separate files");
        entry.moduleName = "";
        return;
      }
      entry.kind = EntryKind.page;
      entry.throwsRender = lineDeclaresThrows(source, pageAt);
      entry.methods.pushBack("GET");
      const declared = findParamString(source, "layout");
      if !declared.isEmpty() then entry.layout = declared;
      return;
    }

    entry.kind = EntryKind.api;
    if entry.methods.isEmpty() {
      diags.error(path, 0, "route exports no handlers",
                  "declare `proc page(ctx: Context, ref meta: PageMeta): string`, " +
                  "or one of proc get/post/put/patch/del/options(ctx: Context): Response");
      entry.moduleName = "";
    }
  }

  private proc readSource(path: string, what: string, ref diags: Bag): string throws {
    try {
      var r = openReader(path);
      defer try! r.close();
      return r.readAll(string);
    } catch e {
      diags.error(path, 0, "cannot read " + what + ": " + e.message());
      return "";
    }
  }

  private proc findParamString(source: string, name: string): string throws {
    const needle = "param " + name;
    var at = idx(source, needle);
    while at != -1 {
      var i = at + needle.numBytes;
      while i < source.numBytes && (source.byte(i) == 32 || source.byte(i) == 61) do i += 1;
      if i < source.numBytes && source.byte(i) == 34 {
        i += 1;
        var j = i;
        while j < source.numBytes && source.byte(j) != 34 && source.byte(j) != 10 do j += 1;
        if j < source.numBytes && source.byte(j) == 34 then return sub(source, i, j);
      }
      at = idx(source, needle, at + 1);
    }
    return "";
  }

  private proc findModuleName(source: string): string throws {
    var at = idx(source, "module ");
    while at != -1 {
      if at == 0 || source.byte(at - 1) == 10 || source.byte(at - 1) == 32 {
        var i = at + 7;
        while i < source.numBytes && source.byte(i) == 32 do i += 1;
        var j = i;
        while j < source.numBytes {
          const c = source.byte(j);
          const ok = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) ||
                     (c >= 48 && c <= 57) || c == 95;
          if !ok then break;
          j += 1;
        }
        if j > i then return sub(source, i, j);
      }
      at = idx(source, "module ", at + 1);
    }
    return "";
  }

  private proc findProc(source: string, name: string): int throws {
    const needle = "proc " + name;
    var at = idx(source, needle);
    while at != -1 {
      const after = at + needle.numBytes;
      if after < source.numBytes {
        const c = source.byte(after);
        if c == 40 || c == 32 then return at;
      }
      at = idx(source, needle, at + 1);
    }
    return -1;
  }

  private proc lineDeclaresThrows(source: string, at: int): bool throws {
    var i = at;
    const n = source.numBytes;
    while i < n && source.byte(i) != 10 do i += 1;
    return idx(sub(source, at, i), " throws") != -1;
  }

  private proc suggestModuleName(pattern: string): string throws {
    var sb = "";
    var upper = true;
    for ch in pattern {
      const alpha = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z");
      const digit = ch >= "0" && ch <= "9";
      if alpha || digit {
        sb += if upper then ch.toUpper() else ch;
        upper = false;
      } else {
        upper = true;
      }
    }
    return if sb.isEmpty() then "PageRoot" else sb;
  }

  private proc scanLayouts(const ref cfg: ProjectConfig, root: string,
                           ref bundle: Bundle, required: bool, ref diags: Bag) throws {
    const dir = resolveIn(root, cfg.layoutsDir);
    if !isDir(dir) {
      if required then
        diags.error(dir, 0, "layouts directory not found",
                    "every page needs a layout; create " + cfg.layoutsDir + "/root.chpl");
      return;
    }

    for entry in listDir(dir, hidden = false) {
      if !entry.endsWith(".chpl") || entry.startsWith("_") then continue;
      var l = new LayoutEntry(stripExtension(entry), joinPath(dir, entry));
      readLayoutModule(l.sourcePath, l, diags);
      if l.moduleName.isEmpty() then continue;
      bundle.layouts[l.name] = l;
    }

    if required && !bundle.layouts.contains("root") then
      diags.error(dir, 0, "no root layout", "create " + cfg.layoutsDir + "/root.chpl");
  }

  private proc readLayoutModule(path: string, ref entry: LayoutEntry,
                                ref diags: Bag) throws {
    const source = readSource(path, "layout", diags);

    entry.moduleName = findModuleName(source);
    if entry.moduleName.isEmpty() {
      if !source.isEmpty() then
        diags.error(path, 0, "layout has no module declaration",
                    "wrap the file in `module " + suggestModuleName(entry.name) +
                    "Layout { ... }`");
      return;
    }

    const at = findProc(source, "layout");
    if at < 0 {
      diags.error(path, 0, "layout declares no `layout` procedure",
                  "declare `proc layout(ctx: Context, slot: string, " +
                  "ref meta: PageMeta): string`");
      entry.moduleName = "";
      return;
    }
    entry.throwsRender = lineDeclaresThrows(source, at);
  }

  private proc contains(const ref l: list(string), value: string): bool throws {
    for v in l do if v == value then return true;
    return false;
  }

  private proc scanLib(const ref cfg: ProjectConfig, root: string,
                       ref diags: Bag) throws {
    const dir = resolveIn(root, cfg.libDir);
    if !isDir(dir) then return;

    var files: list(string);
    collectFiles(dir, files);
    var sorted = files.toArray();
    sort(sorted);

    for path in sorted {
      if !path.endsWith(".chpl") then continue;
      const source = readSource(path, "library file", diags);
      if source.isEmpty() then continue;
      if findModuleName(source).isEmpty() then
        diags.error(path, 0, "library file has no module declaration",
                    "wrap the file in `module Name { ... }`");
    }
  }

  private proc scanIslands(const ref cfg: ProjectConfig, root: string,
                           ref bundle: Bundle, ref diags: Bag) throws {
    const dir = resolveIn(root, cfg.islandsDir);
    if !isDir(dir) then return;

    var names: list(string);
    for entry in listDir(dir, hidden = false) {
      if !entry.endsWith(".js") || entry.startsWith("_") then continue;
      names.pushBack(entry);
    }
    var sorted = names.toArray();
    sort(sorted);
    for entry in sorted do
      bundle.islands.pushBack(new IslandEntry(stripExtension(entry), joinPath(dir, entry)));
  }
}
