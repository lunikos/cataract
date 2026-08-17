module RootLayout {
  use Cataract;
  use CataractAssets;
  use Chrome;

  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {
    meta.icon = asset("/img/logo.svg");

    var h = new MarkupBuilder();
    h.raw(Chrome.header(asset("/img/logo.svg")));

    h.open("main", "id", "content");
    h.raw(slot);
    h.close();

    h.raw(Chrome.footer());
    return h.done();
  }
}
