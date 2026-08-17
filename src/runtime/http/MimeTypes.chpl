module MimeTypes {
  private use Map;

  private var table: map(string, string);
  private var ready: atomic bool;
  private var initGate: sync bool = true;

  private proc load() {
    initGate.readFE();
    defer initGate.writeEF(true);
    if !ready.read() {
      table["html"] = "text/html; charset=utf-8";
      table["htm"]  = "text/html; charset=utf-8";
      table["css"]  = "text/css; charset=utf-8";
      table["js"]   = "text/javascript; charset=utf-8";
      table["mjs"]  = "text/javascript; charset=utf-8";
      table["json"] = "application/json; charset=utf-8";
      table["map"]  = "application/json; charset=utf-8";
      table["txt"]  = "text/plain; charset=utf-8";
      table["md"]   = "text/markdown; charset=utf-8";
      table["xml"]  = "application/xml; charset=utf-8";
      table["svg"]  = "image/svg+xml";
      table["png"]  = "image/png";
      table["jpg"]  = "image/jpeg";
      table["jpeg"] = "image/jpeg";
      table["gif"]  = "image/gif";
      table["webp"] = "image/webp";
      table["avif"] = "image/avif";
      table["ico"]  = "image/x-icon";
      table["woff"] = "font/woff";
      table["woff2"] = "font/woff2";
      table["ttf"]  = "font/ttf";
      table["otf"]  = "font/otf";
      table["wasm"] = "application/wasm";
      table["pdf"]  = "application/pdf";
      table["zip"]  = "application/zip";
      table["webm"] = "video/webm";
      table["mp4"]  = "video/mp4";
      table["mp3"]  = "audio/mpeg";
      ready.write(true);
    }
  }

  proc forExtension(ext: string): string {
    if !ready.read() then load();
    const key = ext.toLower();
    if table.contains(key) then return try! table[key];
    return "application/octet-stream";
  }

  proc forPath(path: string): string {
    const dot = path.rfind(".");
    if dot == -1 then return "application/octet-stream";
    const slash = path.rfind("/");
    if slash != -1 && slash > dot then return "application/octet-stream";
    return forExtension(try! path[(dot + 1)..]);
  }

  proc isCompressible(mime: string): bool {
    return mime.startsWith("text/") || mime.startsWith("application/json") ||
           mime.startsWith("application/xml") || mime.startsWith("image/svg");
  }
}
