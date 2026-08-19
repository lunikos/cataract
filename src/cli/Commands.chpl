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
  private use Scaffold;

  record Options {
    var root: string = ".";
    var configPath: string = "cataract.toml";
    var devMode: bool = false;
    var showNotes: bool = false;
    var port: int = -1;
    var watchIntervalMillis: int = 400;
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
    var plan = analyze(opts, diags);
    diags.raiseIfFailed("scan");

    plan.assets = Assets.build(plan.cfg, opts.root, plan.bundle, diags);
    diags.raiseIfFailed("assets");

    plan.emitted = emit(plan.cfg, opts.root, plan.bundle, plan.assets, diags);
    diags.raiseIfFailed("codegen");

    if !toolchainAvailable() {
      diags.error("chpl", 0, "the Chapel compiler is not on PATH",
                  "install Chapel 2.x, or run `cataract routes` to inspect the " +
                  "manifest without compiling");
      diags.raiseIfFailed("toolchain");
    }

    const result = compile(plan.cfg, opts.root, plan.bundle, plan.emitted, diags,
                           opts.devMode);
    diags.raiseIfFailed("compile");

    writeln(CliHost.green("built"), " ", result.binary, "  (", plan.bundle.pageCount(),
            " pages, ", plan.bundle.apiCount(), " api routes, ",
            plan.bundle.socketCount(), " sockets, ", plan.assets.copied,
            " assets) in ", fmt(result.seconds), "s");
    return 0;
  }

  proc dev(const ref opts: Options, ref diags: Bag): int throws {
    var devOpts = opts;
    devOpts.devMode = true;

    if !CliHost.installShutdownHandlers() then
      writeln("warning: Ctrl-C will not stop the server cleanly");

    writeln("cataract dev: watching ", devOpts.root, " (Ctrl-C to stop)");

    while !CliHost.shutdownRequested() {
      writeln("building...");
      stdout.flush();

      var buildBag = new Bag();
      buildBag.showNotes = devOpts.showNotes;
      const built = rebuild(devOpts, buildBag);
      buildBag.report();

      var cfgBag = new Bag();
      cfgBag.showNotes = devOpts.showNotes;
      const cfg = AppConfig.load(joinPath(devOpts.root, devOpts.configPath), cfgBag);
      const baseline = sourceFingerprint(cfg, devOpts.root);

      if CliHost.shutdownRequested() then break;

      if built != 0 {
        writeln(CliHost.red("build failed"), "; waiting for changes");
        waitForChange(cfg, devOpts, baseline);
        continue;
      }

      const binary = joinPath(resolveIn(devOpts.root, cfg.distDir), cfg.name);
      const requestedPort = if devOpts.port > 0 then devOpts.port else cfg.port;

      try {
        var child = spawn([binary,
                           "--port=" + requestedPort:string,
                           "--devMode=true"]);
        const changed = waitForChange(cfg, devOpts, baseline);
        writeln(if changed then "change detected; restarting" else "stopping");
        stdout.flush();
        try child.terminate();
        child.wait();
      } catch e {
        writeln("could not run ", binary, ": ", e.message());
        waitForChange(cfg, devOpts, baseline);
      }
    }
    return 0;
  }

  private proc waitForChange(const ref cfg: ProjectConfig, const ref opts: Options,
                             baseline: string): bool throws {
    while sourceFingerprint(cfg, opts.root) == baseline {
      if CliHost.shutdownRequested() then return false;
      CliHost.sleepMillis(opts.watchIntervalMillis);
    }
    return !CliHost.shutdownRequested();
  }

  private proc rebuild(const ref opts: Options, ref diags: Bag): int throws {
    try {
      return build(opts, diags);
    } catch {
      return 1;
    }
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
