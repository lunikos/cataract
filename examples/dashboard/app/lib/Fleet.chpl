module Fleet {
  use List;

  record Node {
    var id: string;
    var region: string;
    var status: string;
    var cpu: int;
    var memory: int;
    var uptimeHours: int;
  }

  /* Read-only, so every task reads it unsynchronised; see examples/api for the
     mutable case. */
  private const nodes: list(Node) = seeded();

  private proc seeded(): list(Node) {
    var l: list(Node);
    l.pushBack(new Node("ash-01", "us-east", "healthy", 34, 61, 812));
    l.pushBack(new Node("ash-02", "us-east", "healthy", 27, 44, 812));
    l.pushBack(new Node("fra-01", "eu-central", "degraded", 88, 92, 130));
    l.pushBack(new Node("fra-02", "eu-central", "healthy", 41, 55, 604));
    l.pushBack(new Node("sin-01", "ap-south", "offline", 0, 0, 0));
    l.pushBack(new Node("sin-02", "ap-south", "healthy", 19, 38, 2201));
    return l;
  }

  iter all() ref: Node {
    for n in nodes do yield n;
  }

  proc count(): int do return nodes.size;

  proc countByStatus(status: string): int {
    var n = 0;
    for node in nodes do if node.status == status then n += 1;
    return n;
  }

  proc find(id: string, ref result: Node): bool {
    for node in nodes {
      if node.id == id {
        result = node;
        return true;
      }
    }
    return false;
  }

  /* An empty filter matches everything. */
  iter matching(status: string, region: string) ref: Node {
    for n in nodes {
      if !status.isEmpty() && n.status != status then continue;
      if !region.isEmpty() && n.region != region then continue;
      yield n;
    }
  }

  proc isKnownStatus(status: string): bool {
    select status {
      when "healthy", "degraded", "offline" do return true;
      otherwise do return false;
    }
  }

  proc regions(): list(string) {
    var seen: list(string);
    for n in nodes {
      var have = false;
      for r in seen do if r == n.region then have = true;
      if !have then seen.pushBack(n.region);
    }
    return seen;
  }

  proc overall(): string {
    if countByStatus("offline") > 0 then return "offline";
    if countByStatus("degraded") > 0 then return "degraded";
    return "healthy";
  }
}
