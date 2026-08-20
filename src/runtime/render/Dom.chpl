module Dom {
  private use Html only stringify;
  private use List;
  private use Markup only MarkupBuilder, isName, isVoidTag;
  private use Mutations;
  private use Set;
  private use Logging only warn;

  param pathAttr = "data-path";
  param MAX_PROBES = 8;

  enum NodeKind { root, element, text }

  record DomNode {
    var kind: NodeKind = NodeKind.element;
    var tag: string;
    var text: string;
    var path: uint(16);
    var names: list(string);
    var values: list(string);
    var kids: list(int);
  }

  record DomTree {
    var nodes: list(DomNode);

    proc size(): int do return nodes.size;

    proc isEmpty(): bool do return nodes.isEmpty();

    proc rootPath(): uint(16) do
      return if nodes.isEmpty() then 0: uint(16) else nodes[0].path;
  }

  record DomBuilder {
    var tree: DomTree;
    var paths: list(string);
    var stack: list(int);
    var used: set(uint(16));
    var ambiguous: bool = false;

    proc init() {
      init this;
      var root = new DomNode(NodeKind.root);
      root.path = claim("r");
      tree.nodes.pushBack(root);
      paths.pushBack("r");
      stack.pushBack(0);
    }

    proc ref open(tag: string) {
      if !push(NodeKind.element, tag, "") then return;
      if isVoidTag(tag) then close();
    }

    proc ref open(tag: string, attrs...?n) {
      if n % 2 != 0 then
        compilerError("attributes are name/value pairs, so the count must be even");
      if !push(NodeKind.element, tag, "") then return;
      for param i in 0..n-2 by 2 do attr(attrs(i), stringify(attrs(i + 1)));
      if isVoidTag(tag) then close();
    }

    proc ref close() {
      if stack.size <= 1 {
        warn("Dom.close with no open element");
        return;
      }
      stack.popBack();
    }

    proc ref el(tag: string, const ref content, attrs...) {
      open(tag, (...attrs));
      text(content);
      close();
    }

    proc ref el(tag: string, const ref content) {
      open(tag);
      text(content);
      close();
    }

    proc ref text(const ref v) {
      if push(NodeKind.text, "", stringify(v)) then stack.popBack();
    }

    proc ref attr(name: string, const ref value) {
      if stack.size <= 1 then return;
      if !isName(name) {
        warn("Dom: refusing attribute name \"" + name + "\"");
        return;
      }
      ref node = tree.nodes[stack.last];
      node.names.pushBack(name);
      node.values.pushBack(stringify(value));
    }

    proc depth(): int do return stack.size - 1;

    proc ref done(): DomTree {
      while stack.size > 1 do stack.popBack();
      return tree;
    }

    proc ref push(kind: NodeKind, tag: string, content: string): bool {
      if kind == NodeKind.element && !isName(tag) {
        warn("Dom: refusing tag name \"" + tag + "\"");
        return false;
      }

      const parent = stack.last;
      const slot = tree.nodes[parent].kids.size;
      const pathText = paths[parent] + "." + slot: string;

      var node = new DomNode(kind, if kind == NodeKind.element then tag.toLower() else "",
                             content);
      if kind != NodeKind.text then node.path = claim(pathText);

      const at = tree.nodes.size;
      tree.nodes.pushBack(node);
      paths.pushBack(pathText);
      tree.nodes[parent].kids.pushBack(at);
      stack.pushBack(at);
      return true;
    }

    proc ref claim(pathText: string): uint(16) {
      var h = fold(pathText);
      var probe = 0;
      while used.contains(h) && probe < MAX_PROBES {
        h = fold(pathText + "#" + probe: string);
        probe += 1;
      }
      if used.contains(h) then ambiguous = true;
      else used.add(h);
      return h;
    }
  }

  proc fold(s: string): uint(16) {
    var h: uint(32) = 0x811c9dc5;
    for i in 0..<s.numBytes {
      h = h ^ s.byte(i): uint(32);
      h = h * 0x01000193;
    }
    const folded = ((h >> 16) ^ h): uint(16);
    return if folded == 0 then 1: uint(16) else folded;
  }

  proc renderInner(const ref t: DomTree): string {
    if t.nodes.isEmpty() then return "";
    var b = new MarkupBuilder();
    for k in t.nodes[0].kids do write(b, t, k);
    return b.done();
  }

  proc renderNode(const ref t: DomTree, at: int): string {
    if at < 0 || at >= t.nodes.size then return "";
    var b = new MarkupBuilder();
    write(b, t, at);
    return b.done();
  }

  private proc write(ref b: MarkupBuilder, const ref t: DomTree, at: int) {
    const ref n = t.nodes[at];
    select n.kind {
      when NodeKind.text do b.text(n.text);
      when NodeKind.root do for k in n.kids do write(b, t, k);
      otherwise {
        if !b.beginTag(n.tag) then return;
        for i in 0..<n.names.size do b.writeAttr(n.names[i], n.values[i]);
        b.writeAttr(pathAttr, n.path: string);
        const before = b.depth();
        b.endTag(n.tag);
        for k in n.kids do write(b, t, k);
        if b.depth() > before then b.close();
      }
    }
  }

  proc diff(const ref before: DomTree, const ref after: DomTree,
            ref sink: MutationBuffer) {
    if before.nodes.isEmpty() || after.nodes.isEmpty() ||
       before.nodes[0].path != after.nodes[0].path {
      sink.fullRender(before.rootPath(), renderInner(after));
      return;
    }
    diffNode(before, 0, after, 0, sink);
  }

  private proc diffNode(const ref a: DomTree, ai: int, const ref b: DomTree, bi: int,
                        ref sink: MutationBuffer) {
    diffAttrs(a.nodes[ai], b.nodes[bi], sink);

    if textOnly(a, ai) && textOnly(b, bi) {
      const wanted = flatText(b, bi);
      if flatText(a, ai) != wanted then sink.setText(a.nodes[ai].path, wanted);
      return;
    }

    const inCommon = min(a.nodes[ai].kids.size, b.nodes[bi].kids.size);
    for i in 0..<inCommon {
      const ak = a.nodes[ai].kids[i];
      const bk = b.nodes[bi].kids[i];
      const ref an = a.nodes[ak];
      const ref bn = b.nodes[bk];

      if an.kind != bn.kind || an.kind == NodeKind.text {
        if an.kind != bn.kind || an.text != bn.text {
          rewrite(a, ai, b, bi, sink);
          return;
        }
        continue;
      }
      if an.tag != bn.tag || an.path != bn.path then
        sink.replaceNode(an.path, renderNode(b, bk));
      else
        diffNode(a, ak, b, bk, sink);
    }

    var elements = 0;
    for i in 0..<inCommon do
      if b.nodes[b.nodes[bi].kids[i]].kind == NodeKind.element then elements += 1;

    for i in inCommon..<b.nodes[bi].kids.size {
      const bk = b.nodes[bi].kids[i];
      if b.nodes[bk].kind != NodeKind.element {
        rewrite(a, ai, b, bi, sink);
        return;
      }
      sink.insertNode(a.nodes[ai].path, elements, renderNode(b, bk));
      elements += 1;
    }

    for i in inCommon..<a.nodes[ai].kids.size {
      const ak = a.nodes[ai].kids[i];
      if a.nodes[ak].kind != NodeKind.element {
        rewrite(a, ai, b, bi, sink);
        return;
      }
      sink.removeNode(a.nodes[ak].path);
    }
  }

  private proc rewrite(const ref a: DomTree, ai: int, const ref b: DomTree, bi: int,
                       ref sink: MutationBuffer) {
    if a.nodes[ai].kind == NodeKind.root then
      sink.fullRender(a.nodes[ai].path, renderInner(b));
    else
      sink.replaceNode(a.nodes[ai].path, renderNode(b, bi));
  }

  private proc diffAttrs(const ref an: DomNode, const ref bn: DomNode,
                         ref sink: MutationBuffer) {
    for i in 0..<bn.names.size {
      var seen = false;
      for j in 0..<an.names.size {
        if an.names[j] != bn.names[i] then continue;
        seen = true;
        if an.values[j] != bn.values[i] then
          sink.setAttr(an.path, bn.names[i], bn.values[i]);
        break;
      }
      if !seen then sink.setAttr(an.path, bn.names[i], bn.values[i]);
    }

    for i in 0..<an.names.size {
      var kept = false;
      for j in 0..<bn.names.size do
        if bn.names[j] == an.names[i] then kept = true;
      if !kept then sink.removeAttr(an.path, an.names[i]);
    }
  }

  private proc textOnly(const ref t: DomTree, at: int): bool {
    for k in t.nodes[at].kids do
      if t.nodes[k].kind != NodeKind.text then return false;
    return true;
  }

  private proc flatText(const ref t: DomTree, at: int): string {
    var sb = "";
    for k in t.nodes[at].kids do sb += t.nodes[k].text;
    return sb;
  }
}
