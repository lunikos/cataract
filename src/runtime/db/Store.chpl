module Store {
  private use CTypes;
  private use List;
  private use IO;
  private use FileSystem;
  private use Path;
  private use Logging;

  class StoreError: Error {
    var detail: string;
    proc init(detail: string) {
      this.detail = detail;
    }
    override proc message(): string do return detail;
  }

  proc conflict(table: string, column: string, value: string) throws {
    throw new owned StoreError(table + "." + column + " already holds " + value);
  }

  proc encodeCell(value: string): string {
    var sb = "";
    for i in 0..<value.numBytes {
      const c = value.byte(i);
      select c {
        when 92 do sb += "\\\\";
        when 9 do sb += "\\t";
        when 10 do sb += "\\n";
        when 13 do sb += "\\r";
        otherwise do sb += asciiOf(c);
      }
    }
    return sb;
  }

  proc decodeCell(value: string): string {
    var sb = "";
    var i = 0;
    while i < value.numBytes {
      const c = value.byte(i);
      if c == 92 && i + 1 < value.numBytes {
        const next = value.byte(i + 1);
        select next {
          when 92 do sb += "\\";
          when 116 do sb += "\t";
          when 110 do sb += "\n";
          when 114 do sb += "\r";
          otherwise do sb += asciiOf(next);
        }
        i += 2;
        continue;
      }
      sb += asciiOf(c);
      i += 1;
    }
    return sb;
  }

  private proc asciiOf(c: uint(8)): string {
    var one: [0..0] uint(8) = c;
    return try! string.createCopyingBuffer(c_ptrToConst(one[0]): c_ptrConst(c_char), 1,
                                           decodePolicy.replace);
  }

  proc cellsOf(line: string): list(string) {
    var cells: list(string);
    for raw in line.split("\t") do cells.pushBack(decodeCell(raw));
    return cells;
  }

  proc toInt(cell: string, fallback: int = 0): int {
    try {
      return cell: int;
    } catch {
      return fallback;
    }
  }

  proc toReal(cell: string, fallback: real = 0.0): real {
    try {
      return cell: real;
    } catch {
      return fallback;
    }
  }

  proc toBool(cell: string): bool {
    const t = cell.toLower();
    return t == "true" || t == "1";
  }

  proc likeMatch(value: string, pattern: string): bool {
    return globMatch(value, pattern, 0, 0);
  }

  private proc globMatch(value: string, pattern: string, vi: int, pi: int): bool {
    var v = vi;
    var p = pi;
    while p < pattern.numBytes {
      const pc = pattern.byte(p);
      if pc == 37 {
        if p + 1 == pattern.numBytes then return true;
        var probe = v;
        while probe <= value.numBytes {
          if globMatch(value, pattern, probe, p + 1) then return true;
          probe += 1;
        }
        return false;
      }
      if v >= value.numBytes then return false;
      if pc != 95 && pc != value.byte(v) then return false;
      v += 1;
      p += 1;
    }
    return v == value.numBytes;
  }

  class Journal {
    var path: string;
    var live: bool = false;

    proc init(directory: string, table: string) {
      this.path = if directory.isEmpty() then "" else joinPath(directory, table + ".rows");
      this.live = !directory.isEmpty();
    }

    proc ready(): bool do return live;

    proc prepare() {
      if !live then return;
      const dir = dirname(path);
      try {
        if !dir.isEmpty() && !isDir(dir) then mkdir(dir, parents = true);
      } catch e {
        Logging.error("cannot create " + dir + ": " + e.message());
        live = false;
      }
    }

    proc storedLines(): list(string) {
      var lines: list(string);
      if !live then return lines;
      try {
        if !isFile(path) then return lines;
        var reader = openReader(path);
        defer try! reader.close();
        var line: string;
        while reader.readLine(line, stripNewline = true) do
          if !line.isEmpty() then lines.pushBack(line);
      } catch e {
        Logging.error("cannot read " + path + ": " + e.message());
      }
      return lines;
    }

    proc persist(const ref lines: list(string)) {
      if !live then return;
      try {
        var writer = openWriter(path);
        for line in lines do writer.writeln(line);
        writer.close();
      } catch e {
        Logging.error("cannot write " + path + ": " + e.message());
      }
    }
  }
}
