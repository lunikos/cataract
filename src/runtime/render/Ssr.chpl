module Ssr {
  private use Markup;
  private use List;

  param clientRuntimePath = "/_cataract/client.js";
  param islandAttr = "data-cataract-island";
  param propsAttr = "data-cataract-props";
  param sourceAttr = "data-cataract-src";
  param intervalAttr = "data-cataract-every";

  record PageMeta {
    var title: string = "Cataract";
    var description: string = "";
    var lang: string = "en";
    var canonical: string = "";
    var icon: string = "";
    var bodyClass: string = "";
    var stylesheets: list(string);
    var scripts: list(string);
    var needsClientRuntime: bool = false;
    /* A page that renders "not found" must be able to say 404. */
    var status: int = 200;
  }

  /* Declaring an island is what sets `needsClientRuntime`; layouts run before
     `renderDocument`, so the flag is always in time. */
  proc island(ref meta: PageMeta, name: string, propsJson: string,
              serverHtml: string): string {
    meta.needsClientRuntime = true;
    var b = new MarkupBuilder();
    b.open("div", islandAttr, name, propsAttr, propsJson);
    b.raw(serverHtml);
    return b.done();
  }

  proc islandFetch(ref meta: PageMeta, name: string, propsJson: string,
                   serverHtml: string, endpoint: string,
                   refreshMillis: int = 0): string {
    meta.needsClientRuntime = true;
    var b = new MarkupBuilder();
    if refreshMillis > 0 then
      b.open("div", islandAttr, name, propsAttr, propsJson, sourceAttr, endpoint,
             intervalAttr, refreshMillis);
    else
      b.open("div", islandAttr, name, propsAttr, propsJson, sourceAttr, endpoint);
    b.raw(serverHtml);
    return b.done();
  }

  proc renderDocument(const ref meta: PageMeta, bodyHtml: string): string {
    var b = new MarkupBuilder();
    b.raw("<!doctype html>\n");
    b.open("html", "lang", meta.lang);

    b.open("head");
    b.open("meta", "charset", "utf-8");
    b.open("meta", "name", "viewport", "content", "width=device-width, initial-scale=1");
    b.el("title", meta.title);
    if !meta.description.isEmpty() then
      b.open("meta", "name", "description", "content", meta.description);
    if !meta.canonical.isEmpty() then
      b.open("link", "rel", "canonical", "href", meta.canonical);
    if !meta.icon.isEmpty() then b.open("link", "rel", "icon", "href", meta.icon);
    for href in meta.stylesheets do b.open("link", "rel", "stylesheet", "href", href);
    b.close();

    if meta.bodyClass.isEmpty() then b.open("body");
    else b.open("body", "class", meta.bodyClass);
    b.raw(bodyHtml);

    for src in meta.scripts {
      b.open("script", "type", "module", "src", src);
      b.close();
    }
    if meta.needsClientRuntime {
      b.open("script", "type", "module", "src", clientRuntimePath);
      b.close();
    }

    return b.done() + "\n";
  }

  proc errorPage(status: int, title: string, detail: string): string {
    var meta = new PageMeta();
    meta.title = status:string + " " + title;

    var b = new MarkupBuilder();
    b.open("main", "class", "cataract-error");
    b.el("h1", status:string + " " + title);
    if !detail.isEmpty() then b.el("p", detail);

    return renderDocument(meta, b.done());
  }
}
