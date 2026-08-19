module Cache {
  private use List;
  private use Map;
  private use Sort;
  private use IO;
  private use FileSystem;
  private use Path;
  private use Diagnostics;
  private use Assets only ensureDir, readText, writeText;
  private use CliHost only mtimeNanos;

  param STAMP_FILE = "stamps";
  param BINARY_DIR = "binaries";

  record Stamps {
    var entries: map(string, string);

    proc matches(key: string, value: string): bool throws {
      if value.isEmpty() then return false;
      return entries.contains(key) && entries[key] == value;
    }

    proc ref remember(key: string, value: string) throws {
      entries[key] = value;
    }
  }

  proc load(cacheDir: string): Stamps throws {
    var stamps = new Stamps();
    const path = joinPath(cacheDir, STAMP_FILE);
    if !isFile(path) then return stamps;

    try {
      var reader = openReader(path);
      defer try! reader.close();
      var line: string;
      while reader.readLine(line, stripNewline = true) {
        const tab = line.find("\t");
        if tab == -1 then continue;
        stamps.entries[line[..<tab]] = line[(tab + 1)..];
      }
    } catch {
      stamps.entries.clear();
    }
    return stamps;
  }

  proc save(cacheDir: string, const ref stamps: Stamps, ref diags: Bag) throws {
    ensureDir(cacheDir, diags);
    var keys: list(string);
    for key in stamps.entries.keys() do keys.pushBack(key);
    var sorted = keys.toArray();
    sort(sorted);

    var payload = "";
    for key in sorted do payload += key + "\t" + stamps.entries[key] + "\n";
    writeText(joinPath(cacheDir, STAMP_FILE), payload, diags);
  }

  proc storeBinary(cacheDir: string, digest: string, binary: string,
                   keep: int, ref diags: Bag) throws {
    if digest.isEmpty() || !isFile(binary) then return;
    const dir = joinPath(cacheDir, BINARY_DIR);
    ensureDir(dir, diags);
    try {
      copy(binary, joinPath(dir, digest), metadata = true);
    } catch e {
      diags.note(dir, "could not cache the binary: " + e.message());
      return;
    }
    prune(dir, keep, diags);
  }

  proc restoreBinary(cacheDir: string, digest: string, binary: string): bool throws {
    if digest.isEmpty() then return false;
    const stored = joinPath(cacheDir, BINARY_DIR, digest);
    if !isFile(stored) then return false;
    try {
      copy(stored, binary, metadata = true);
      return true;
    } catch {
      return false;
    }
  }

  private proc prune(dir: string, keep: int, ref diags: Bag) throws {
    var stored: list((int(64), string));
    for entry in listDir(dir, hidden = false) {
      const full = joinPath(dir, entry);
      if isFile(full) then stored.pushBack((mtimeNanos(full), full));
    }
    if stored.size <= keep then return;

    var sorted = stored.toArray();
    sort(sorted);
    for i in 0..<(sorted.size - keep) {
      try {
        remove(sorted[i](1));
      } catch e {
        diags.note(sorted[i](1), "could not drop a cached binary: " + e.message());
      }
    }
  }
}
