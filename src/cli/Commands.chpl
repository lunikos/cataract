module Commands {
  private use List;
  private use IO;
  private use Time;
  private use FileSystem;
  private use Path;
  private use Subprocess;
  private use Diagnostics;
  private use CliHost;
  private use AppConfig;
  private use Manifest;
  private use Scanner;
  private use Assets;
  private use Emit;
  private use Build;
  private use Cache;
  private use Scaffold;

  record Options {
    var root: string = ".";
    var configPath: string = "cataract.toml";
    var devMode: bool = false;
    var showNotes: bool = false;
    var port: int = -1;
    var watchIntervalMillis: int = 400;
    var force: bool = false;
    var staticSite: bool = false;
    var staticOut: string = "";
    var shutdownGraceMillis: int = 5000;
    var cachedBinaries: int = 8;
  }

  record BuildPlan {
    var cfg: ProjectConfig;
    var bundle: Bundle;
    var assets: AssetTable;
    var emitted: Emitted;
  }

  proc analyze(const ref opts: Options, ref diags: Bag): BuildPlan throws {
    var plan = new BuildPlan();
    plan.cfg = AppConfig.load(joinPath(opts.root, opts.configPath), diags);
    if opts.port > 0 then plan.cfg.port = opts.port;
    plan.bundle = scanRoutes(plan.cfg, opts.root, diags);
    return plan;
  }

  proc build(const ref opts: Options, ref diags: Bag): int throws {
    const result = compileProject(opts, diags);
    report(result, opts);
    if !result.ok then return 1;
    if !opts.staticSite then return 0;
    return exportStatic(opts, result, diags);
  }

  private proc exportStatic(const ref opts: Options, const ref result: BuildResult,
                            ref diags: Bag): int throws {
    const cfg = AppConfig.load(joinPath(opts.root, opts.configPath), diags);
    const target = if opts.staticOut.isEmpty()
                   then joinPath(resolveIn(opts.root, cfg.distDir), "static")
                   else resolveIn(opts.root, opts.staticOut);

    writeln("exporting to ", target);
    stdout.flush();

    var argv: list(string);
    argv.pushBack(result.binary);
    argv.pushBack("--staticOut=" + target);
    argv.pushBack("--logLevel=" + cfg.logLevel);

    const code = run(argv, diags);
    if code != 0 {
      diags.error(result.binary, 0,
                  "static export failed with exit code " + code:string);
      diags.raiseIfFailed("export");
    }
    writeln(CliHost.green("exported"), " ", target);
    return 0;
  }

  proc compileProject(const ref opts: Options, ref diags: Bag): BuildResult throws {
    var plan = analyze(opts, diags);
    diags.raiseIfFailed("scan");

    if opts.staticSite then noteDynamicRoutes(plan.bundle, diags);

    plan.assets = Assets.build(plan.cfg, opts.root, plan.bundle, diags);
    diags.raiseIfFailed("assets");

    plan.emitted = emit(plan.cfg, opts.root, plan.bundle, plan.assets, diags,
                        opts.devMode);
    diags.raiseIfFailed("codegen");

    const cacheDir = joinPath(resolveIn(opts.root, plan.cfg.outDir), "cache");
    var stamps = Cache.load(cacheDir);
    const digest = compileFingerprint(plan.cfg, opts.root, plan.emitted, opts.devMode);
    const binary = joinPath(resolveIn(opts.root, plan.cfg.distDir), plan.cfg.name);

    var result = new BuildResult();
    result.binary = binary;
    result.pages = plan.bundle.pageCount();
    result.apiRoutes = plan.bundle.apiCount();
    result.sockets = plan.bundle.socketCount();
    result.tables = plan.bundle.database.tableCount();
    result.assets = plan.assets.copied;

    if !opts.force && stamps.matches("compile", digest) && exists(binary) {
      result.ok = true;
      return result;
    }

    if !opts.force && Cache.restoreBinary(cacheDir, digest, binary) {
      result.ok = true;
      result.reused = true;
      result.changed = true;
      stamps.remember("compile", digest);
      Cache.save(cacheDir, stamps, diags);
      return result;
    }

    if !toolchainAvailable() {
      diags.error("chpl", 0, "the Chapel compiler is not on PATH",
                  "install Chapel 2.x, or run `cataract routes` to inspect the " +
                  "manifest without compiling");
      diags.raiseIfFailed("toolchain");
    }

    const compiled = compile(plan.cfg, opts.root, plan.bundle, plan.emitted, diags,
                             opts.devMode);
    diags.raiseIfFailed("compile");

    result.ok = compiled.ok;
    result.seconds = compiled.seconds;
    result.changed = compiled.ok;

    if compiled.ok {
      Cache.storeBinary(cacheDir, digest, binary, opts.cachedBinaries, diags);
      stamps.remember("compile", digest);
      Cache.save(cacheDir, stamps, diags);
    }
    return result;
  }

  private proc noteDynamicRoutes(const ref bundle: Bundle, ref diags: Bag) throws {
    for r in bundle.routes {
      if r.kind != EntryKind.page || r.params.isEmpty() || r.declaresStaticPaths then
        continue;
      diags.warn(r.sourcePath, 0, r.pattern + " has no static form and was not exported",
                 "declare `proc staticPaths(): list(string)` listing the paths to " +
                 "render");
    }
  }

  private proc report(const ref result: BuildResult, const ref opts: Options) throws {
    if !result.ok then return;
    const counts = "  (" + result.pages:string + " pages, " +
                   result.apiRoutes:string + " api routes, " +
                   result.sockets:string + " sockets, " +
                   result.tables:string + " tables, " +
                   result.assets:string + " assets)";

    if result.reused then
      writeln(CliHost.green("restored"), " ", result.binary, counts, " from the cache");
    else if !result.changed then
      writeln(CliHost.green("current"), "  ", result.binary, counts, " unchanged");
    else
      writeln(CliHost.green("built"), "    ", result.binary, counts, " in ",
              fmt(result.seconds), "s");
  }

  proc dev(const ref opts: Options, ref diags: Bag): int throws {
    var devOpts = opts;
    devOpts.devMode = true;

    if !CliHost.installShutdownHandlers() then
      writeln("warning: Ctrl-C will not stop the server cleanly");

    writeln("cataract dev: watching ", devOpts.root, " (Ctrl-C to stop)");
    stdout.flush();

    while !CliHost.shutdownRequested() {
      var cfgBag = new Bag();
      cfgBag.showNotes = devOpts.showNotes;
      const cfg = AppConfig.load(joinPath(devOpts.root, devOpts.configPath), cfgBag);
      var baseline = sourceFingerprint(cfg, devOpts.root);

      if !rebuild(devOpts).ok {
        writeln(CliHost.red("build failed"), "; waiting for changes");
        waitForChange(cfg, devOpts, baseline);
        continue;
      }
      if CliHost.shutdownRequested() then break;

      const binary = joinPath(resolveIn(devOpts.root, cfg.distDir), cfg.name);
      const requestedPort = if devOpts.port > 0 then devOpts.port else cfg.port;

      try {
        var child = spawn([binary, "--port=" + requestedPort:string, "--devMode=true"]);
        var restart = false;

        while !restart && !CliHost.shutdownRequested() {
          if !waitForChange(cfg, devOpts, baseline) then break;
          baseline = sourceFingerprint(cfg, devOpts.root);

          const rebuilt = rebuild(devOpts);
          if !rebuilt.ok {
            writeln(CliHost.red("build failed"), "; the previous server is still up");
            continue;
          }
          if rebuilt.changed {
            restart = true;
          } else {
            writeln("assets updated; the server keeps running");
            stdout.flush();
          }
        }

        writeln(if restart then "restarting" else "stopping");
        stdout.flush();
        stopChild(child, devOpts.shutdownGraceMillis);
      } catch e {
        writeln("could not run ", binary, ": ", e.message());
        waitForChange(cfg, devOpts, baseline);
      }
    }
    return 0;
  }

  /* SIGTERM first, so the server drains what it is holding; SIGKILL only if the
     grace period passes without it exiting. */
  private proc stopChild(ref child, graceMillis: int) throws {
    try {
      child.terminate();
    } catch {
      return;
    }

    var waited = 0;
    while waited < graceMillis {
      child.poll();
      if !child.running then return;
      CliHost.sleepMillis(25);
      waited += 25;
    }

    writeln("the server did not stop within ", graceMillis, "ms; killing it");
    try {
      child.kill();
      child.wait();
    } catch {
    }
  }

  private proc waitForChange(const ref cfg: ProjectConfig, const ref opts: Options,
                             baseline: string): bool throws {
    while sourceFingerprint(cfg, opts.root) == baseline {
      if CliHost.shutdownRequested() then return false;
      CliHost.sleepMillis(opts.watchIntervalMillis);
    }
    return !CliHost.shutdownRequested();
  }

  private proc rebuild(const ref opts: Options): BuildResult throws {
    var diags = new Bag();
    diags.showNotes = opts.showNotes;
    var result = new BuildResult();
    try {
      result = compileProject(opts, diags);
    } catch {
      result.ok = false;
    }
    diags.report();
    report(result, opts);
    stdout.flush();
    return result;
  }

  proc routes(const ref opts: Options, ref diags: Bag): int throws {
    var plan = analyze(opts, diags);
    diags.raiseIfFailed("scan");

    var ordered = plan.bundle.routes.toArray();
    for i in 0..<ordered.size do
      for j in (i + 1)..<ordered.size do
        if ordered[j].specificity > ordered[i].specificity then
          ordered[i] <=> ordered[j];

    writeln("match order (most specific first)");
    writeln("");
    for r in ordered {
      const kind = if r.kind == EntryKind.page then "page"
                   else if r.kind == EntryKind.socket then "sock"
                   else "api ";
      writeln("  ", kind, "  ", pad(r.pattern, 30), pad(methodList(r), 22),
              pad("Route." + r.urlName, 24), r.sourcePath);
    }
    writeln("");
    writeln("  ", plan.bundle.pageCount(), " pages, ", plan.bundle.apiCount(),
            " api routes, ", plan.bundle.socketCount(), " sockets, ",
            plan.bundle.layouts.size, " layouts, ",
            plan.bundle.islands.size, " islands");
    return 0;
  }

  proc newApp(name: string, const ref opts: Options, ref diags: Bag): int throws {
    if !newProject(name, opts.root, diags) then
      diags.raiseIfFailed("scaffold");
    writeln("created ", joinPath(opts.root, name));
    writeln("  cd ", name, " && cataract build");
    return 0;
  }

  private proc methodList(const ref r: RouteEntry): string throws {
    var sb = "";
    for m in r.methods {
      if !sb.isEmpty() then sb += ",";
      sb += m;
    }
    return if sb.isEmpty() then "GET" else sb;
  }

  private proc pad(s: string, width: int): string throws {
    var sb = s;
    while sb.size < width do sb += " ";
    return sb + " ";
  }

  private proc fmt(v: real): string throws {
    const hundredths = (v * 100 + 0.5): int;
    const whole = hundredths / 100;
    const frac = hundredths % 100;
    return whole:string + "." + (if frac < 10 then "0" else "") + frac:string;
  }
}
