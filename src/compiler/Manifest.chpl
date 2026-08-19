module Manifest {
  private use List;
  private use Map;
  private use Sql only Database;

  enum EntryKind { page, api, socket }

  record RouteEntry {
    var pattern: string;
    var sourcePath: string;
    var kind: EntryKind = EntryKind.page;
    var symbol: string;
    var urlName: string;
    var moduleName: string = "";
    var methods: list(string);
    var throwsMethods: list(string);
    var params: list(string);
    var layout: string = "root";
    var specificity: int = 0;
    var throwsRender: bool = false;
  }

  record LayoutEntry {
    var name: string;
    var sourcePath: string;
    var moduleName: string = "";
    var throwsRender: bool = false;
  }

  record IslandEntry {
    var name: string;
    var sourcePath: string;
  }

  record Bundle {
    var routes: list(RouteEntry);
    var database: Database;
    var layouts: map(string, LayoutEntry);
    var islands: list(IslandEntry);
    var pageModules: list(string);
    var apiModules: list(string);

    proc pageCount(): int throws {
      var n = 0;
      for r in routes do if r.kind == EntryKind.page then n += 1;
      return n;
    }

    proc apiCount(): int throws {
      var n = 0;
      for r in routes do if r.kind == EntryKind.api then n += 1;
      return n;
    }

    proc socketCount(): int throws {
      var n = 0;
      for r in routes do if r.kind == EntryKind.socket then n += 1;
      return n;
    }
  }

  proc specificityOf(pattern: string): int throws {
    var depth = 0;
    var score = 0;
    for seg in pattern.split("/") {
      if seg.isEmpty() then continue;
      depth += 1;
      if seg.startsWith("[...") then score -= 50;
      else if seg.startsWith("[") then score += 3;
      else score += 10;
    }
    return depth * 100 + score;
  }

  proc symbolFor(prefix: string, pattern: string): string throws {
    var sb = prefix;
    var lastUnderscore = true;
    for ch in pattern {
      const ok = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") ||
                 (ch >= "0" && ch <= "9");
      if ok {
        sb += ch;
        lastUnderscore = false;
      } else if !lastUnderscore {
        sb += "_";
        lastUnderscore = true;
      }
    }
    if sb.endsWith("_") then sb = sb[..<(sb.size - 1)];
    if sb == prefix then sb = prefix + "root";
    return sb;
  }

  proc urlNameFor(pattern: string): string throws {
    var sb = "";
    for seg in pattern.split("/") {
      if seg.isEmpty() then continue;
      var word = seg;
      if word.startsWith("[") {
        word = word[1..<(word.size - 1)];
        if word.startsWith("...") then word = word[3..];
      }
      var upper = !sb.isEmpty();
      for ch in word {
        const alpha = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z");
        const digit = ch >= "0" && ch <= "9";
        if !alpha && !digit {
          upper = true;
          continue;
        }
        sb += if upper then ch.toUpper() else ch;
        upper = false;
      }
    }
    if sb.isEmpty() then return "root";
    const first = sb[0];
    if first >= "0" && first <= "9" then return "route" + sb;
    return sb;
  }

  proc methodMaskExpr(const ref methods: list(string)): string throws {
    if methods.isEmpty() then return "methodBit(Method.get)";
    var sb = "";
    for m in methods {
      if !sb.isEmpty() then sb += " | ";
      sb += "methodBit(Method." +
            (if m.toLower() == "delete" then "del" else m.toLower()) + ")";
    }
    return sb;
  }
}
