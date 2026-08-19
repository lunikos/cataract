module Distribution {
  private use HttpMessage;

  enum Affinity { pinned, roundRobin, path, client, sticky }

  enum ListenerMode { single, perLocale }

  proc parseAffinity(name: string): Affinity {
    select name.toLower() {
      when "pinned" do return Affinity.pinned;
      when "round-robin" do return Affinity.roundRobin;
      when "roundrobin" do return Affinity.roundRobin;
      when "path" do return Affinity.path;
      when "client" do return Affinity.client;
      when "sticky" do return Affinity.sticky;
      otherwise do return Affinity.pinned;
    }
  }

  proc affinityName(mode: Affinity): string {
    select mode {
      when Affinity.roundRobin do return "round-robin";
      when Affinity.path do return "path";
      when Affinity.client do return "client";
      when Affinity.sticky do return "sticky";
      otherwise do return "pinned";
    }
  }

  proc parseListenerMode(name: string): ListenerMode {
    return if name.toLower() == "per-locale" then ListenerMode.perLocale
           else ListenerMode.single;
  }

  class Placement {
    var mode: Affinity = Affinity.pinned;
    var stickyKey: string = "sid";
    var cursor: atomic int;

    proc init(mode: Affinity = Affinity.pinned, stickyKey: string = "sid") {
      this.mode = mode;
      this.stickyKey = stickyKey;
    }

    proc distributes(): bool do return mode != Affinity.pinned && numLocales > 1;

    proc localeFor(const ref ctx: Context): int {
      if !distributes() then return here.id;

      select mode {
        when Affinity.roundRobin do
          return cursor.fetchAdd(1) % numLocales;
        when Affinity.path do
          return spread(ctx.request.path);
        when Affinity.client do
          return spread(ctx.request.clientIp());
        when Affinity.sticky do
          return spread(stickyValue(ctx));
        otherwise do return here.id;
      }
    }

    proc stickyValue(const ref ctx: Context): string {
      const fromQuery = ctx.request.query.get(stickyKey);
      if !fromQuery.isEmpty() then return fromQuery;

      const needle = stickyKey + "=";
      for crumb in ctx.request.header("Cookie").split(";") {
        const item = crumb.strip();
        if item.startsWith(needle) then return (try! item[needle.size..]).strip();
      }
      return ctx.request.clientIp();
    }
  }

  proc spread(key: string): int {
    if numLocales <= 1 then return 0;
    var h: uint(64) = 0xcbf29ce484222325;
    for i in 0..<key.numBytes {
      h = h ^ key.byte(i): uint(64);
      h = h * 0x100000001b3;
    }
    return ((h >> 8) % numLocales: uint(64)): int;
  }
}
