module StaticFiles {
  private use Pipeline;
  private use HttpMessage;
  private use HttpMethod;
  private use MimeTypes;
  private use ByteBuffer;
  private use Logging;
  private use Map;
  private use IO;
  private use FileSystem;
  private use Path;
  private use CTypes;

  record CachedFile {
    var payload: Bytes;
    var etag: string;
    var mime: string;
  }

  /* Second guard: the parser collapsed ".." already, `resolve` re-rejects it. */
  class StaticFileServer: Middleware {
    var root: string;
    var mount: string = "/";
    var cacheSeconds: int = 3600;
    var cacheEnabled: bool = true;
    var maxCacheBytes: int = 33554432;

    /* Files are read whole, so without a cap the client picks the allocation size. */
    var maxFileBytes: int = 8388608;

    var entries: map(string, CachedFile);
    var cachedBytes: int = 0;
    var gate: sync bool;

    proc init(root: string, cacheEnabled: bool = true, cacheSeconds: int = 3600,
              mount: string = "/", maxCacheBytes: int = 33554432,
              maxFileBytes: int = 8388608) {
      this.root = root;
      this.mount = mount;
      this.cacheSeconds = cacheSeconds;
      this.cacheEnabled = cacheEnabled;
      this.maxCacheBytes = maxCacheBytes;
      this.maxFileBytes = maxFileBytes;
      init this;
      gate.writeEF(true);
    }

    override proc name(): string do return "static";

    override proc before(ref ctx: Context, ref res: Response): bool {
      const m = ctx.request.method;
      if m != Method.get && m != Method.head then return false;

      const rel = resolve(ctx.request.path);
      if rel.isEmpty() then return false;

      const full = joinPath(root, rel);
      if !readable(full) then return false;

      var entry: CachedFile;
      if !load(full, rel, entry) then return false;

      const versioned = ctx.request.query.contains("v");

      const inm = ctx.request.header("If-None-Match");
      if inm == entry.etag {
        res = new Response(status = 304);
        applyCacheHeaders(res, versioned, entry);
        return true;
      }

      res = bytesResponse(entry.payload, entry.mime);
      applyCacheHeaders(res, versioned, entry);
      return true;
    }

    proc applyCacheHeaders(ref res: Response, versioned: bool, const ref entry: CachedFile) {
      res.setHeader("ETag", entry.etag);
      res.setHeader("Accept-Ranges", "none");
      if versioned && cacheSeconds > 0 then
        res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
      else
        res.setHeader("Cache-Control", "public, max-age=" + cacheSeconds:string);
    }

    proc resolve(path: string): string {
      var p = path;
      if mount != "/" {
        if !p.startsWith(mount) then return "";
        p = p[mount.size..];
        if !p.startsWith("/") then p = "/" + p;
      }
      if p == "/" || p.endsWith("/") then return "";
      if p.find("..") != -1 || p.find("\\") != -1 || p.find("\x00") != -1 then return "";

      var rel = "";
      for seg in p.split("/") {
        if seg.isEmpty() then continue;
        if seg.startsWith(".") then return "";
        if !rel.isEmpty() then rel += "/";
        rel += seg;
      }
      return rel;
    }

    proc load(full: string, rel: string, ref outEntry: CachedFile): bool {
      if cacheEnabled {
        gate.readFE();
        const hit = entries.contains(rel);
        if hit then outEntry = try! entries[rel];
        gate.writeEF(true);
        if hit then return true;
      }

      var payload: Bytes;
      if !readWholeFile(full, maxFileBytes, payload) then return false;

      var entry = new CachedFile(payload, "", forPath(rel));
      entry.etag = "\"" + fnv1a(entry.payload):string + "-" + entry.payload.len:string + "\"";

      if cacheEnabled {
        gate.readFE();
        if cachedBytes + entry.payload.len <= maxCacheBytes {
          entries[rel] = entry;
          cachedBytes += entry.payload.len;
        }
        gate.writeEF(true);
      }

      outEntry = entry;
      return true;
    }
  }

  proc readable(path: string): bool {
    try {
      return isFile(path);
    } catch {
      return false;
    }
  }

  proc readWholeFile(path: string, maxBytes: int, ref outBuf: Bytes): bool {
    try {
      const f = open(path, ioMode.r);
      defer try! f.close();
      const size = f.size;
      if size > maxBytes {
        Logging.warn("static file over the size cap, not served: " + path);
        return false;
      }
      if size <= 0 {
        outBuf.clear();
        return true;
      }
      var raw: [0..<size] uint(8);
      var r = f.reader();
      const n = r.readBinary(raw);
      try! r.close();
      outBuf.clear();
      if n > 0 then outBuf.appendPtr(c_ptrToConst(raw[0]), n);
      return true;
    } catch e {
      Logging.debug("static read failed for " + path + ": " + e.message());
      return false;
    }
  }

  /* Content-derived: an ETag must be stable across restarts and replicas. */
  proc fnv1a(const ref b: Bytes): uint(64) {
    var h: uint(64) = 0xcbf29ce484222325;
    for i in 0..<b.len {
      h = h ^ b.data[i]: uint(64);
      h = h * 0x100000001b3;
    }
    return h;
  }
}
