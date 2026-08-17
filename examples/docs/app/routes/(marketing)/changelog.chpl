module PageChangelog {
  use Cataract;
  use List;

  record Release {
    var version: string;
    var date: string;
    var note: string;
  }

  private const releases = [
    new Release("0.1.0", "2026-03-20",
                "Pages, layouts and islands written in Chapel."),
    new Release("0.0.2", "2026-02-11",
                "Non-blocking sockets throughout; graceful shutdown with draining."),
    new Release("0.0.1", "2026-01-08", "Accept loop over raw BSD sockets.")
  ];

  proc page(ctx: Context, ref meta: PageMeta): string {
    meta.title = "Changelog";
    meta.description = "What changed, most recent first.";

    var h = new MarkupBuilder();
    h.el("h1", "Changelog");
    h.open("ul", "class", "releases");
    for r in releases {
      h.open("li");
      h.el("strong", r.version);
      h.el("span", r.date, "class", "date");
      h.el("p", r.note);
      h.close();
    }
    return h.done();
  }
}
