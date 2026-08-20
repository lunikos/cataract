module FleetView {
  use Cataract;
  use Fleet;

  private use HttpClock only monoMillis;

  param room = "fleet";
  param stepMillis = 2000;

  proc statsTree(): DomTree {
    const at = (monoMillis() / stepMillis): int;

    var d = new DomBuilder();

    d.open("dl", "class", "stats");
    cell(d, "watching", Rooms.occupancy(room));
    cell(d, "healthy", Fleet.countByStatus("healthy"));
    cell(d, "degraded", Fleet.countByStatus("degraded"));
    cell(d, "offline", Fleet.countByStatus("offline"));
    d.close();

    d.open("table", "class", "readings");
    d.open("thead");
    d.open("tr");
    for column in ["node", "region", "status", "cpu"] do
      d.el("th", column, "scope", "col");
    d.close();
    d.close();

    d.open("tbody");
    var seat = 0;
    for n in Fleet.all() {
      d.open("tr", "class", classList("warn", n.status == "degraded",
                                      "down", n.status == "offline"));
      d.el("td", n.id);
      d.el("td", n.region);
      d.el("td", n.status);
      d.el("td", reading(n, seat, at):string + "%");
      d.close();
      seat += 1;
    }
    d.close();
    d.close();

    return d.done();
  }

  proc reading(const ref node: Fleet.Node, seat: int, at: int): int {
    if node.status == "offline" then return 0;
    const swing = ((at * 7 + seat * 23) % 11) - 5;
    return max(1, min(99, node.cpu + swing));
  }

  private proc cell(ref d: DomBuilder, title: string, value: int) {
    d.open("div", "class", "stat " + title, "data-stat", title);
    d.el("dt", title);
    d.el("dd", value);
    d.close();
  }
}
