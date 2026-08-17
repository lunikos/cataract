module Chrome {
  use Cataract;
  use Pages;

  proc header(logo: string): string {
    var h = new MarkupBuilder();
    h.el("a", "Skip to content", "class", "skip", "href", "#content");

    h.open("header", "class", "site");
    h.open("a", "class", "brand", "href", "/");
    h.open("img", "src", logo, "alt", "", "width", "20", "height", "20");
    h.text("Cataract");
    h.close();

    h.open("nav");
    h.el("a", "Docs", "href", "/docs");
    h.el("a", "Pricing", "href", "/pricing");
    h.el("a", "Changelog", "href", "/changelog");
    h.close();
    h.close();

    return h.done();
  }

  proc footer(): string {
    var h = new MarkupBuilder();
    h.open("footer");
    h.el("span", "Server-rendered by Chapel. " + Pages.count():string +
                 " pages in the tree.");
    h.close();
    return h.done();
  }
}
