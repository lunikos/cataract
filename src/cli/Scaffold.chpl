module Scaffold {
  private use IO;
  private use FileSystem;
  private use Path;
  private use Diagnostics;
  private use Assets only ensureDir, writeText;

  proc newProject(name: string, root: string, ref diags: Bag): bool throws {
    const dir = joinPath(root, name);
    if exists(dir) {
      diags.error(dir, 0, "path already exists");
      return false;
    }

    for sub in ["app/routes/api", "app/layouts", "app/islands", "app/lib", "app/public"] do
      ensureDir(joinPath(dir, sub), diags);

    writeText(joinPath(dir, "cataract.toml"), configTemplate(name), diags);
    writeText(joinPath(dir, ".gitignore"), ".cataract/\ndist/\n", diags);
    writeText(joinPath(dir, "app/layouts/root.chpl"), chapelLayout(name), diags);
    writeText(joinPath(dir, "app/routes/index.chpl"), chapelPage(name), diags);
    writeText(joinPath(dir, "app/routes/api/health.chpl"), healthRoute(), diags);
    writeText(joinPath(dir, "app/public/styles.css"), styles(), diags);

    return !diags.hasErrors();
  }

  private proc configTemplate(name: string): string throws {
    return "[project]\n" +
           "name = \"" + name + "\"\n" +
           "version = \"0.1.0\"\n\n" +
           "# Point this at the framework checkout, or export CATARACT_RUNTIME.\n" +
           "[paths]\n" +
           "# runtime = \"/path/to/cataract/src/runtime\"\n\n" +
           "[server]\n" +
           "host = \"127.0.0.1\"\n" +
           "port = 3000\n" +
           "max_concurrency = 512\n" +
           "log_level = \"info\"\n\n" +
           "# Handler placement across locales; pinned keeps every request here.\n" +
           "[distribution]\n" +
           "affinity = \"pinned\"\n" +
           "listeners = \"single\"\n\n" +
           "[build]\n" +
           "optimize = true\n";
  }

  private proc chapelLayout(name: string): string throws {
    return "module RootLayout {\n" +
           "  use Cataract;\n\n" +
           "  proc layout(ctx: Context, slot: string, ref meta: PageMeta): string {\n" +
           "    var h = new MarkupBuilder();\n\n" +
           "    h.open(\"header\", \"class\", \"site\");\n" +
           "    h.el(\"a\", " + quoted(name) + ", \"href\", \"/\");\n" +
           "    h.close();\n\n" +
           "    h.open(\"main\");\n" +
           "    h.raw(slot);\n" +
           "    h.close();\n\n" +
           "    h.el(\"footer\", \"Served by Cataract\");\n" +
           "    return h.done();\n" +
           "  }\n" +
           "}\n";
  }

  private proc chapelPage(name: string): string throws {
    return "module PageIndex {\n" +
           "  use Cataract;\n\n" +
           "  // A module exporting `page` is a page; one exporting get/post/... is an\n" +
           "  // API route. The file extension decides nothing.\n" +
           "  proc page(ctx: Context, ref meta: PageMeta): string {\n" +
           "    meta.title = " + quoted(name) + ";\n" +
           "    meta.description = \"A Cataract application\";\n\n" +
           "    var h = new MarkupBuilder();\n" +
           "    h.el(\"h1\", \"Hello from Chapel\");\n" +
           "    h.open(\"p\");\n" +
           "    h.text(\"Edit \");\n" +
           "    h.el(\"code\", \"app/routes/index.chpl\");\n" +
           "    h.text(\" and rebuild.\");\n" +
           "    h.close();\n" +
           "    return h.done();\n" +
           "  }\n" +
           "}\n";
  }

  private proc quoted(s: string): string throws {
    return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
  }

  private proc healthRoute(): string throws {
    return "module ApiHealth {\n" +
           "  use Cataract;\n\n" +
           "  proc get(ctx: Context): Response {\n" +
           "    var body = new JsonBuilder();\n" +
           "    body.beginObject();\n" +
           "    body.field(\"status\", \"ok\");\n" +
           "    body.endObject();\n" +
           "    return jsonResponse(body.done());\n" +
           "  }\n" +
           "}\n";
  }

  private proc styles(): string throws {
    return ":root { color-scheme: light dark; }\n" +
           "body { font: 16px/1.6 system-ui, sans-serif; margin: 0 auto; " +
           "max-width: 46rem; padding: 2rem 1rem; }\n" +
           "header.site { font-weight: 600; margin-bottom: 2rem; }\n" +
           "footer { margin-top: 3rem; opacity: 0.6; font-size: 0.875rem; }\n";
  }
}
