module Build {
  private use List;
  private use Sort;
  private use Path;
  private use FileSystem;
  private use Subprocess;
  private use IO;
  private use Time;
  private use Diagnostics;
  private use Manifest;
  private use AppConfig;
  private use Assets;
  private use Emit;
  private use Map;
  private use CliHost only mtimeNanos;

  record BuildResult {
    var binary: string;
    var ok: bool = false;
    var seconds: real = 0.0;
    var reused: bool = false;
    var changed: bool = false;
    var pages: int = 0;
    var apiRoutes: int = 0;
    var sockets: int = 0;
    var tables: int = 0;
    var assets: int = 0;
  }

  private const RUNTIME_SUBDIRS = ["", "net", "http", "router", "render",
                                   "middleware", "util", "ws", "cluster", "db", "ssg"];

  proc compile(const ref cfg: ProjectConfig, root: string, const ref bundle: Bundle,
               const ref emitted: Emitted, ref diags: Bag,
               devMode: bool = false): BuildResult throws {
    var result = new BuildResult();

    const distDir = resolveIn(root, cfg.distDir);
    ensureDir(distDir, diags);
    result.binary = joinPath(distDir, cfg.name);

    var args: list(string);
    args.pushBack("chpl");
    args.pushBack("--main-module");
    args.pushBack(emitted.mainModule);

    const runtimeRoot = resolveRuntime(cfg, root);
    if !isDir(runtimeRoot) {
      diags.error(runtimeRoot, 0, "runtime modules not found",
                  "set paths.runtime in cataract.toml, or export CATARACT_RUNTIME " +
                  "to the framework's src/runtime directory");
      return result;
    }
    for sub in RUNTIME_SUBDIRS {
      const dir = if sub.isEmpty() then runtimeRoot else joinPath(runtimeRoot, sub);
      if isDir(dir) {
        args.pushBack("-M");
        args.pushBack(dir);
      }
    }

    for f in emitted.files do args.pushBack(f);

    var extraSources: list(string);
    for r in bundle.routes do
      if !r.moduleName.isEmpty() then extraSources.pushBack(r.sourcePath);
    for l in bundle.layouts.values() do
      if !l.moduleName.isEmpty() then extraSources.pushBack(l.sourcePath);
    collectChapel(resolveIn(root, cfg.libDir), extraSources);

    var sortedExtra = extraSources.toArray();
    sort(sortedExtra);
    for f in sortedExtra do args.pushBack(f);

    if cfg.optimize && !devMode then args.pushBack("--fast");
    for flag in cfg.chplFlags.split(" ") do
      if !flag.strip().isEmpty() then args.pushBack(flag.strip());

    args.pushBack("-o");
    args.pushBack(result.binary);

    var timer: stopwatch;
    timer.start();
    const code = run(args, diags);
    timer.stop();

    result.seconds = timer.elapsed();
    result.ok = (code == 0);
    if !result.ok then
      diags.error("chpl", 0, "compilation failed with exit code " + code:string);
    return result;
  }

  proc run(const ref args: list(string), ref diags: Bag): int throws {
    var argv = args.toArray();
    try {
      var child = spawn(argv);
      child.wait();
      return child.exitCode;
    } catch e {
      diags.error(argv[0], 0, "cannot run: " + e.message(),
                  "is it installed and on PATH?");
      return 127;
    }
  }

  proc toolchainAvailable(): bool throws {
    try {
      var probe = spawn(["chpl", "--version"], stdout = pipeStyle.pipe,
                        stderr = pipeStyle.pipe);
      probe.wait();
      return probe.exitCode == 0;
    } catch {
      return false;
    }
  }

  proc collectChapel(dir: string, ref acc: list(string)) throws {
    if !isDir(dir) then return;
    for entry in listDir(dir, hidden = false) {
      if entry.startsWith("_") || entry.startsWith(".") then continue;
      const full = joinPath(dir, entry);
      if isDir(full) then collectChapel(full, acc);
      else if entry.endsWith(".chpl") then acc.pushBack(full);
    }
  }

  proc compileFingerprint(const ref cfg: ProjectConfig, root: string,
                          const ref emitted: Emitted, devMode: bool): string throws {
    var files: list(string);
    collectCompiled(resolveIn(root, cfg.appDir), files);
    collectCompiled(resolveRuntime(cfg, root), files);
    for f in emitted.files do files.pushBack(f);

    var sorted = files.toArray();
    sort(sorted);

    var h: uint(64) = 0xcbf29ce484222325;
    h = mix(h, cfg.name);
    h = mix(h, cfg.chplFlags);
    h = mix(h, if cfg.optimize && !devMode then "fast" else "plain");
    for path in sorted {
      h = mix(h, path);
      h = mix(h, contentHash(path, sizeOf(path), CliHost.mtimeNanos(path)));
    }
    return hex(h);
  }

  private proc sizeOf(path: string): int throws {
    try {
      return getFileSize(path);
    } catch {
      return -1;
    }
  }

  private proc hex(h: uint(64)): string throws {
    const digits = "0123456789abcdef";
    var sb = "";
    var shift = 60;
    while shift >= 0 {
      sb += digits[((h >> shift) & 0xf): int];
      shift -= 4;
    }
    return sb;
  }

  proc sourceFingerprint(const ref cfg: ProjectConfig, root: string): string throws {
    var files: list(string);
    collectWatched(resolveIn(root, cfg.appDir), files);
    collectWatched(resolveRuntime(cfg, root), files);

    var sorted = files.toArray();
    sort(sorted);

    var h: uint(64) = 0xcbf29ce484222325;
    for path in sorted {
      h = mix(h, path);
      var size = -1;
      try {
        size = getFileSize(path);
      } catch {
      }
      const stamp = CliHost.mtimeNanos(path);
      h = mix(h, size:string);
      h = mix(h, contentHash(path, size, stamp));
    }
    return h:string;
  }

  private var hashes: map(string, (int, int(64), string));

  private proc contentHash(path: string, size: int, stamp: int(64)): string throws {
    if stamp != 0 && hashes.contains(path) {
      const seen = hashes[path];
      if seen(0) == size && seen(1) == stamp then return seen(2);
    }
    var diags = new Bag();
    const digest = fnvHex(readText(path, diags));
    if stamp != 0 then hashes[path] = (size, stamp, digest);
    return digest;
  }

  private proc mix(h: uint(64), s: string): uint(64) throws {
    var acc = h;
    for i in 0..<s.numBytes {
      acc = acc ^ s.byte(i): uint(64);
      acc = acc * 0x100000001b3;
    }
    return acc;
  }

  private proc collectCompiled(dir: string, ref acc: list(string)) throws {
    if !isDir(dir) then return;
    for entry in listDir(dir, hidden = false) {
      if entry.startsWith(".") then continue;
      const full = joinPath(dir, entry);
      if isDir(full) then collectCompiled(full, acc);
      else if entry.endsWith(".chpl") || entry.endsWith(".c") || entry.endsWith(".h") ||
              entry.endsWith(".sql") then
        acc.pushBack(full);
    }
  }

  private proc collectWatched(dir: string, ref acc: list(string)) throws {
    if !isDir(dir) then return;
    for entry in listDir(dir, hidden = false) {
      if entry.startsWith(".") then continue;
      const full = joinPath(dir, entry);
      if isDir(full) then collectWatched(full, acc);
      else if entry.endsWith(".chpl") || entry.endsWith(".js") || entry.endsWith(".css") ||
              entry.endsWith(".c") || entry.endsWith(".h") then
        acc.pushBack(full);
    }
  }
}
