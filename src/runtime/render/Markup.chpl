/* Markup as Chapel: a tag stack, name validation, escaping on every value. */
module Markup {
  private use ByteBuffer;
  private use Html only escape, stringify;
  private use List;
  private use Logging only warn;

  private const voidTags = ["area", "base", "br", "col", "embed", "hr", "img",
                            "input", "link", "meta", "param", "source", "track",
                            "wbr"];

  record MarkupBuilder {
    var buf: Bytes;
    var stack: list(string);

    proc ref open(tag: string, attrs...?n) {
      if n % 2 != 0 then
        compilerError("attributes are name/value pairs, so the count must be even");
      if !beginTag(tag) then return;
      for param i in 0..n-2 by 2 do writeAttr(attrs(i), stringify(attrs(i + 1)));
      endTag(tag);
    }

    proc ref open(tag: string) {
      if !beginTag(tag) then return;
      endTag(tag);
    }

    /* No tag argument: the stack knows it, so a mismatch is unrepresentable. */
    proc ref close() {
      if stack.isEmpty() {
        warn("Markup.close with no open element");
        return;
      }
      buf.append("</");
      buf.append(stack.popBack());
      buf.append(">");
    }

    proc ref el(tag: string, const ref content, attrs...?n) {
      open(tag, (...attrs));
      text(content);
      close();
    }

    proc ref el(tag: string, const ref content) {
      open(tag);
      text(content);
      close();
    }

    proc ref text(const ref v) do buf.append(escape(stringify(v)));

    /* Unescaped; the caller owns the safety of whatever it passes. */
    proc ref raw(s: string) do buf.append(s);

    proc ref comment(s: string) {
      buf.append("<!--");
      buf.append(escape(s).replace("--", "&#45;&#45;"));
      buf.append("-->");
    }

    proc depth(): int do return stack.size;

    /* Closes what is still open, so an early return cannot truncate a document. */
    proc ref done(): string {
      while !stack.isEmpty() do close();
      return buf.toString();
    }

    proc ref beginTag(tag: string): bool {
      const name = tag.toLower();
      if !isName(name) {
        warn("Markup: refusing tag name \"" + tag + "\"");
        return false;
      }
      buf.append("<");
      buf.append(name);
      return true;
    }

    proc ref endTag(tag: string) {
      buf.append(">");
      const name = tag.toLower();
      var isVoid = false;
      for v in voidTags do if v == name then isVoid = true;
      if !isVoid then stack.pushBack(name);
    }

    proc ref writeAttr(name: string, value: string) {
      /* Dropped, not sanitised: such a name came from somewhere it should not. */
      if !isName(name) {
        warn("Markup: refusing attribute name \"" + name + "\"");
        return;
      }
      buf.append(" ");
      buf.append(name);
      buf.append("=\"");
      buf.append(escape(value));
      buf.append("\"");
    }
  }

  private proc isName(s: string): bool {
    if s.isEmpty() then return false;
    for i in 0..<s.numBytes {
      const c = s.byte(i);
      const ok = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) ||
                 (c >= 48 && c <= 57) || c == 45 || c == 95 || c == 58;
      if !ok then return false;
    }
    const first = s.byte(0);
    return (first >= 97 && first <= 122) || (first >= 65 && first <= 90);
  }

  proc classList(pairs...?n): string {
    if n % 2 != 0 then
      compilerError("classList takes name/condition pairs, so the count must be even");
    var sb = "";
    for param i in 0..n-2 by 2 {
      if !pairs(i + 1) then continue;
      if !sb.isEmpty() then sb += " ";
      sb += pairs(i);
    }
    return sb;
  }
}
