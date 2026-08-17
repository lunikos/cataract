module Cli {
  private use List;
  private use IO;
  private use Diagnostics;
  private use Commands;

  param VERSION = "0.1.0";

  proc usage(): string throws {
    return "cataract " + VERSION + "\n\n" +
           "usage: cataract <command> [options]\n\n" +
           "commands:\n" +
           "  build              scan routes, generate sources, compile a binary\n" +
           "  dev                rebuild and restart on change\n" +
           "  routes             print the compiled route table in match order\n" +
           "  new <name>         scaffold a new application\n" +
           "  version            print the toolchain version\n\n" +
           "options:\n" +
           "  --root <dir>       project root (default: .)\n" +
           "  --config <file>    config file relative to root " +
           "(default: cataract.toml)\n" +
           "  --port <n>         override server.port\n" +
           "  --watch-ms <n>     dev poll interval in milliseconds (default: 400)\n" +
           "  --notes            include notes in diagnostic output\n";
  }

  record Invocation {
    var command: string = "";
    var target: string = "";
    var opts: Options;
    var valid: bool = true;
    var error: string = "";
  }

  proc parseArgs(const ref argv: [] string): Invocation throws {
    var inv = new Invocation();
    var i = 1;
    const n = argv.size;

    while i < n {
      const arg = argv[i];

      if arg.startsWith("--") {
        select arg {
          when "--root" {
            if !takeValue(argv, i, inv.opts.root, inv) then return inv;
          }
          when "--config" {
            if !takeValue(argv, i, inv.opts.configPath, inv) then return inv;
          }
          when "--port" {
            var raw = "";
            if !takeValue(argv, i, raw, inv) then return inv;
            try {
              inv.opts.port = raw: int;
            } catch {
              return invalid(inv, "--port expects an integer, got \"" + raw + "\"");
            }
          }
          when "--watch-ms" {
            var raw = "";
            if !takeValue(argv, i, raw, inv) then return inv;
            try {
              inv.opts.watchIntervalMillis = raw: int;
            } catch {
              return invalid(inv, "--watch-ms expects an integer, got \"" + raw + "\"");
            }
          }
          when "--notes" do inv.opts.showNotes = true;
          when "--help" do inv.command = "help";
          when "--version" do inv.command = "version";
          otherwise do return invalid(inv, "unknown option " + arg);
        }
      } else if inv.command.isEmpty() {
        inv.command = arg;
      } else if inv.target.isEmpty() {
        inv.target = arg;
      } else {
        return invalid(inv, "unexpected argument " + arg);
      }
      i += 1;
    }

    if inv.command.isEmpty() then inv.command = "help";
    return inv;
  }

  private proc takeValue(const ref argv: [] string, ref i: int, ref dest: string,
                         ref inv: Invocation): bool throws {
    if i + 1 >= argv.size {
      invalid(inv, argv[i] + " expects a value");
      return false;
    }
    i += 1;
    dest = argv[i];
    return true;
  }

  private proc invalid(ref inv: Invocation, message: string): Invocation throws {
    inv.valid = false;
    inv.error = message;
    return inv;
  }

  proc dispatch(const ref inv: Invocation): int throws {
    var diags = new Bag();
    diags.showNotes = inv.opts.showNotes;

    try {
      select inv.command {
        when "build" do return build(inv.opts, diags);
        when "dev" do return dev(inv.opts, diags);
        when "routes" do return routes(inv.opts, diags);
        when "new" {
          if inv.target.isEmpty() {
            try! stderr.writeln("error: `cataract new` needs a project name");
            return 2;
          }
          return newApp(inv.target, inv.opts, diags);
        }
        when "version" {
          writeln("cataract ", VERSION);
          return 0;
        }
        when "help" {
          writeln(usage());
          return 0;
        }
        otherwise {
          try! stderr.writeln("error: unknown command \"", inv.command, "\"");
          try! stderr.writeln(usage());
          return 2;
        }
      }
    } catch e {
      try! stderr.writeln("error: ", e.message());
      return 1;
    }
  }
}
