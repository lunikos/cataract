module AppConfig {
  private use Map;
  private use IO;
  private use FileSystem;
  private use Path;
  private use Diagnostics;
  private use OS.POSIX only getenv;
  private use CTypes;

  record ProjectConfig {
    var name: string = "cataract-app";
    var version: string = "0.1.0";

    var appDir: string = "app";
    var routesDir: string = "app/routes";
    var layoutsDir: string = "app/layouts";
    var islandsDir: string = "app/islands";
    var libDir: string = "app/lib";
    var publicDir: string = "app/public";
    var dbDir: string = "app/db";

    var outDir: string = ".cataract";
    var distDir: string = "dist";
    var runtimeDir: string = "src/runtime";

    var host: string = "127.0.0.1";
    var port: int = 3000;
    var maxConcurrency: int = 512;
    var maxBodyBytes: int = 1048576;
    var keepAliveTimeoutMillis: int = 5000;
    var headerTimeoutMillis: int = 10000;
    var requestTimeoutMillis: int = 20000;
    var logLevel: string = "info";

    var socketMaxMessageBytes: int = 1048576;
    var socketIdleTimeoutMillis: int = 300000;
    var socketSendTimeoutMillis: int = 10000;
    var socketSubprotocols: string = "";

    var databaseDir: string = "";

    var affinity: string = "pinned";
    var stickyKey: string = "sid";
    var listeners: string = "single";
    var exposeLocale: bool = false;

    var optimize: bool = true;
    var chplFlags: string = "";
    var contentSecurityPolicy: string = "";
    var hstsSeconds: int = 0;
    var allowedOrigins: string = "";
  }

  proc load(path: string, ref diags: Bag): ProjectConfig throws {
    var cfg = new ProjectConfig();
    if !exists(path) {
      diags.note(path, "no config found; using defaults");
      return cfg;
    }

    var section = "";
    var lineNo = 0;

    try {
      var r = openReader(path);
      defer try! r.close();
      var line: string;
      while r.readLine(line, stripNewline = true) {
        lineNo += 1;
        var s = stripComment(line).strip();
        if s.isEmpty() then continue;

        if s.startsWith("[") {
          if !s.endsWith("]") {
            diags.error(path, lineNo, "malformed section header: " + s);
            continue;
          }
          section = s[1..<(s.size - 1)].strip();
          continue;
        }

        const eq = s.find("=");
        if eq == -1 {
          diags.error(path, lineNo, "expected key = value");
          continue;
        }

        const key = s[..<eq].strip();
        const raw = s[(eq + 1)..].strip();
        const value = unquote(raw);
        const full = if section.isEmpty() then key else section + "." + key;

        apply(cfg, full, value, path, lineNo, diags);
      }
    } catch e {
      diags.error(path, 0, "could not read config: " + e.message());
    }

    return cfg;
  }

  private proc stripComment(line: string): string throws {
    var inQuotes = false;
    var at = 0;
    for ch in line {
      if ch == "\"" then inQuotes = !inQuotes;
      else if ch == "#" && !inQuotes then return line[..<at];
      at += 1;
    }
    return line;
  }

  private proc unquote(v: string): string throws {
    if v.size >= 2 && v.startsWith("\"") && v.endsWith("\"") then
      return v[1..<(v.size - 1)];
    return v;
  }

  private proc toInt(v: string, fallback: int, path: string, line: int,
                     ref diags: Bag): int throws {
    try {
      return v: int;
    } catch {
      diags.error(path, line, "expected an integer, got \"" + v + "\"");
      return fallback;
    }
  }

  private proc toBool(v: string): bool throws {
    const t = v.toLower();
    return t == "true" || t == "1" || t == "yes";
  }

  private proc apply(ref cfg: ProjectConfig, key: string, value: string,
                     path: string, line: int, ref diags: Bag) throws {
    select key {
      when "project.name" do cfg.name = value;
      when "project.version" do cfg.version = value;

      when "paths.app" do cfg.appDir = value;
      when "paths.routes" do cfg.routesDir = value;
      when "paths.layouts" do cfg.layoutsDir = value;
      when "paths.islands" do cfg.islandsDir = value;
      when "paths.lib" do cfg.libDir = value;
      when "paths.public" do cfg.publicDir = value;
      when "paths.db" do cfg.dbDir = value;
      when "paths.out" do cfg.outDir = value;
      when "paths.dist" do cfg.distDir = value;
      when "paths.runtime" do cfg.runtimeDir = value;

      when "server.host" do cfg.host = value;
      when "server.port" do cfg.port = toInt(value, cfg.port, path, line, diags);
      when "server.max_concurrency" do
        cfg.maxConcurrency = toInt(value, cfg.maxConcurrency, path, line, diags);
      when "server.max_body_bytes" do
        cfg.maxBodyBytes = toInt(value, cfg.maxBodyBytes, path, line, diags);
      when "server.keep_alive_ms" do
        cfg.keepAliveTimeoutMillis = toInt(value, cfg.keepAliveTimeoutMillis, path, line, diags);
      when "server.header_timeout_ms" do
        cfg.headerTimeoutMillis = toInt(value, cfg.headerTimeoutMillis, path, line, diags);
      when "server.request_timeout_ms" do
        cfg.requestTimeoutMillis = toInt(value, cfg.requestTimeoutMillis, path, line, diags);
      when "server.log_level" do cfg.logLevel = value;
      when "server.socket_max_message_bytes" do
        cfg.socketMaxMessageBytes = toInt(value, cfg.socketMaxMessageBytes, path, line, diags);
      when "server.socket_idle_timeout_ms" do
        cfg.socketIdleTimeoutMillis = toInt(value, cfg.socketIdleTimeoutMillis, path, line,
                                            diags);
      when "server.socket_send_timeout_ms" do
        cfg.socketSendTimeoutMillis = toInt(value, cfg.socketSendTimeoutMillis, path, line,
                                            diags);
      when "server.socket_subprotocols" do cfg.socketSubprotocols = value;

      when "database.path" do cfg.databaseDir = value;

      when "distribution.affinity" do cfg.affinity = value;
      when "distribution.sticky_key" do cfg.stickyKey = value;
      when "distribution.listeners" do cfg.listeners = value;
      when "distribution.expose_locale" do cfg.exposeLocale = toBool(value);

      when "build.optimize" do cfg.optimize = toBool(value);
      when "build.chpl_flags" do cfg.chplFlags = value;

      when "security.csp" do cfg.contentSecurityPolicy = value;
      when "security.hsts_seconds" do
        cfg.hstsSeconds = toInt(value, cfg.hstsSeconds, path, line, diags);
      when "security.allowed_origins" do cfg.allowedOrigins = value;

      otherwise do diags.warn(path, line, "unknown key \"" + key + "\"");
    }
  }

  proc resolveIn(root: string, relative: string): string throws {
    if relative.startsWith("/") then return relative;
    return joinPath(root, relative);
  }

  /* A configured path that exists wins, so a vendored runtime is never bypassed. */
  proc resolveRuntime(const ref cfg: ProjectConfig, root: string): string throws {
    const configured = resolveIn(root, cfg.runtimeDir);
    if isDir(configured) then return configured;

    const raw = getenv("CATARACT_RUNTIME".c_str());
    if raw == nil then return configured;

    const fromEnv = try! string.createCopyingBuffer(raw);
    if fromEnv.isEmpty() || !isDir(fromEnv) then return configured;
    return fromEnv;
  }
}
