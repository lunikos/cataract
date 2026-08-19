module StaticExport {
  private use List;
  private use IO;
  private use FileSystem;
  private use Path;
  private use HttpMessage;
  private use HttpMethod;
  private use Server only App;
  private use Logging;

  param MISSING_PROBE = "/__cataract_not_found__";

  record ExportReport {
    var written: int = 0;
    var copied: int = 0;
    var skipped: int = 0;
    var failed: int = 0;
  }

  proc exportSite(app: borrowed App, outDir: string, const ref paths: list(string),
                  assetRoot: string, host: string): ExportReport {
    var report = new ExportReport();
    app.seal();

    if !ensureDir(outDir) {
      report.failed += 1;
      return report;
    }

    for path in paths {
      var res = render(app, path, host);
      if res.status < 200 || res.status >= 300 {
        Logging.warn("skipped " + path + ": the handler answered " + res.status:string);
        report.skipped += 1;
        continue;
      }
      if writeBody(outDir, destinationFor(path, res), res) then report.written += 1;
      else report.failed += 1;
    }

    var missing = render(app, MISSING_PROBE, host);
    if writeBody(outDir, "404.html", missing) then report.written += 1;

    report.copied = copyTree(assetRoot, outDir);
    return report;
  }

  private proc render(app: borrowed App, path: string, host: string): Response {
    var request = new Request();
    request.method = Method.get;
    request.path = path;
    request.target = path;
    request.peerIp = "127.0.0.1";
    request.keepAlive = false;
    request.headers.set("Host", host);
    request.headers.set("Accept", "text/html,application/json");
    request.headers.set("User-Agent", "cataract-static");

    var ctx = new Context(request = request);
    ctx.requestId = "static:" + path;
    return app.handle(ctx);
  }

  /* A page becomes a directory index so its URL keeps working without a
     rewrite rule; anything else keeps the exact path it was requested at. */
  private proc destinationFor(path: string, const ref res: Response): string {
    var relative = path;
    while relative.startsWith("/") do relative = relative[1..];

    const html = res.headers.get("Content-Type").startsWith("text/html");
    if !html then return if relative.isEmpty() then "index" else relative;
    if relative.isEmpty() then return "index.html";
    if relative.endsWith("/") then return relative + "index.html";
    return relative + "/index.html";
  }

  private proc writeBody(outDir: string, relative: string,
                         const ref res: Response): bool {
    const full = joinPath(outDir, relative);
    if !ensureDir(dirname(full)) then return false;
    try {
      var writer = openWriter(full);
      defer try! writer.close();
      writer.write(res.body.toString());
      return true;
    } catch e {
      Logging.error("cannot write " + full + ": " + e.message());
      return false;
    }
  }

  private proc ensureDir(path: string): bool {
    try {
      if path.isEmpty() || isDir(path) then return true;
      mkdir(path, parents = true);
      return true;
    } catch e {
      Logging.error("cannot create " + path + ": " + e.message());
      return false;
    }
  }

  private proc copyTree(from: string, to: string): int {
    var count = 0;
    try {
      if from.isEmpty() || !isDir(from) then return 0;
      for entry in listDir(from, hidden = false) {
        const source = joinPath(from, entry);
        const target = joinPath(to, entry);
        if isDir(source) {
          if !ensureDir(target) then continue;
          count += copyTree(source, target);
        } else if isFile(source) {
          copy(source, target, metadata = true);
          count += 1;
        }
      }
    } catch e {
      Logging.error("cannot copy assets: " + e.message());
    }
    return count;
  }
}
