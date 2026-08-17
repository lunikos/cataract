module Assets {
  private use List;
  private use Map;
  private use Sort;
  private use IO;
  private use FileSystem;
  private use Path;
  private use Diagnostics;
  private use Manifest;
  private use AppConfig;
  private use Text only sub;

  record AssetTable {
    var digests: map(string, string);
    var clientBundleBytes: int = 0;
    var copied: int = 0;
  }

  /* Addressed by query string, so a versioned URL stays distinguishable. */
  proc build(const ref cfg: ProjectConfig, root: string, const ref bundle: Bundle,
             ref diags: Bag): AssetTable throws {
    var table = new AssetTable();

    const publicSrc = resolveIn(root, cfg.publicDir);
    const publicOut = joinPath(resolveIn(root, cfg.outDir), "public");

    ensureDir(publicOut, diags);

    if isDir(publicSrc) {
      var files: list(string);
      collect(publicSrc, files);
      var sorted = files.toArray();
      sort(sorted);

      for src in sorted {
        const rel = relativeTo(publicSrc, src);
        const dst = joinPath(publicOut, rel);
        ensureDir(dirname(dst), diags);
        if !copyIfChanged(src, dst, diags) then continue;
        table.digests["/" + rel] = digestOf(src, diags);
        table.copied += 1;
      }
    } else {
      diags.note(publicSrc, "no public directory; skipping asset copy");
    }

    buildClientBundle(cfg, root, bundle, publicOut, table, diags);
    return table;
  }

  private proc buildClientBundle(const ref cfg: ProjectConfig, root: string,
                                 const ref bundle: Bundle, publicOut: string,
                                 ref table: AssetTable, ref diags: Bag) throws {
    if bundle.islands.isEmpty() then return;

    const runtimeJs = joinPath(resolveRuntime(cfg, root), "client/hydrate.js");
    if !isFile(runtimeJs) {
      diags.error(runtimeJs, 0, "client runtime not found",
                  "check paths.runtime in cataract.toml");
      return;
    }

    const outDir = joinPath(publicOut, "_cataract");
    ensureDir(outDir, diags);
    const outFile = joinPath(outDir, "client.js");

    var payload = "";
    payload += readText(runtimeJs, diags);
    payload += "\n";

    for island in bundle.islands {
      payload += "\n// island: " + island.name + "\n";
      payload += rewriteImports(readText(island.sourcePath, diags));
      payload += "\n";
    }

    if !writeText(outFile, payload, diags) then return;
    table.clientBundleBytes = payload.numBytes;
    table.digests["/_cataract/client.js"] = fnvHex(payload);
  }

  private proc rewriteImports(source: string): string throws {
    var sb = "";
    for line in source.split("\n") {
      const t = line.strip();
      if t.startsWith("import ") && t.find("cataract") != -1 then continue;
      sb += line + "\n";
    }
    return sb;
  }

  private proc collect(dir: string, ref acc: list(string)) throws {
    for entry in listDir(dir, hidden = false) {
      if entry.startsWith(".") then continue;
      const full = joinPath(dir, entry);
      if isDir(full) then collect(full, acc);
      else if isFile(full) then acc.pushBack(full);
    }
  }

  private proc relativeTo(root: string, path: string): string throws {
    if !path.startsWith(root) then return path;
    var at = root.numBytes;
    while at < path.numBytes && path.byte(at) == 47 do at += 1;
    return sub(path, at, path.numBytes);
  }

  proc ensureDir(path: string, ref diags: Bag) throws {
    if path.isEmpty() || isDir(path) then return;
    try {
      mkdir(path, parents = true);
    } catch e {
      diags.error(path, 0, "cannot create directory: " + e.message());
    }
  }

  private proc copyIfChanged(src: string, dst: string, ref diags: Bag): bool throws {
    try {
      if isFile(dst) && getFileSize(src) == getFileSize(dst) &&
         digestOf(src, diags) == digestOf(dst, diags) then return true;
      copy(src, dst);
      return true;
    } catch e {
      diags.error(src, 0, "cannot copy asset: " + e.message());
      return false;
    }
  }

  proc digestOf(path: string, ref diags: Bag): string throws {
    try {
      const f = open(path, ioMode.r);
      defer try! f.close();
      const size = f.size;
      if size <= 0 then return "0";
      var raw: [0..<size] uint(8);
      var r = f.reader();
      const n = r.readBinary(raw);
      try! r.close();

      var h: uint(64) = 0xcbf29ce484222325;
      for i in 0..<n {
        h = h ^ raw[i]: uint(64);
        h = h * 0x100000001b3;
      }
      return hex12(h);
    } catch e {
      diags.error(path, 0, "cannot hash asset: " + e.message());
      return "0";
    }
  }

  proc fnvHex(s: string): string throws {
    var h: uint(64) = 0xcbf29ce484222325;
    for i in 0..<s.numBytes {
      h = h ^ s.byte(i): uint(64);
      h = h * 0x100000001b3;
    }
    return hex12(h);
  }

  private proc hex12(h: uint(64)): string throws {
    const digits = "0123456789abcdef";
    var sb = "";
    var shift = 44;
    while shift >= 0 {
      sb += digits[((h >> shift) & 0xf): int];
      shift -= 4;
    }
    return sb;
  }

  proc readText(path: string, ref diags: Bag): string throws {
    try {
      var r = openReader(path);
      defer try! r.close();
      return r.readAll(string);
    } catch e {
      diags.error(path, 0, "cannot read file: " + e.message());
      return "";
    }
  }

  proc writeText(path: string, content: string, ref diags: Bag): bool throws {
    try {
      var w = openWriter(path);
      defer try! w.close();
      w.write(content);
      return true;
    } catch e {
      diags.error(path, 0, "cannot write file: " + e.message());
      return false;
    }
  }

  proc writeIfChanged(path: string, content: string, ref diags: Bag): bool throws {
    if isFile(path) {
      const existing = readText(path, diags);
      if existing == content then return false;
    }
    writeText(path, content, diags);
    return true;
  }
}
