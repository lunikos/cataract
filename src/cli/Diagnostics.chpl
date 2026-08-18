module Diagnostics {
  private use List;
  private use IO;
  private use CliHost only red, yellow;

  enum Severity { note, warning, error }

  record Diagnostic {
    var severity: Severity = Severity.error;
    var file: string = "";
    var line: int = 0;
    var column: int = 0;
    var message: string = "";
    var hint: string = "";
  }

  private proc colourise(s: Severity, text: string): string {
    select s {
      when Severity.error do return red(text);
      when Severity.warning do return yellow(text);
      otherwise do return text;
    }
  }

  proc severityLabel(s: Severity): string throws {
    select s {
      when Severity.error do return "error";
      when Severity.warning do return "warning";
      otherwise do return "note";
    }
  }

  class BuildError: Error {
    var detail: string;
    proc init(detail: string) {
      this.detail = detail;
    }
    override proc message(): string do return detail;
  }

  /* Collected rather than thrown, so one build reports every problem at once. */
  record Bag {
    var items: list(Diagnostic);
    var errorCount: int = 0;
    var reported: int = 0;
    var showNotes: bool = false;

    proc ref error(file: string, line: int, message: string, hint: string = "") throws {
      items.pushBack(new Diagnostic(Severity.error, file, line, 0, message, hint));
      errorCount += 1;
    }

    proc ref warn(file: string, line: int, message: string, hint: string = "") throws {
      items.pushBack(new Diagnostic(Severity.warning, file, line, 0, message, hint));
    }

    proc ref note(file: string, message: string) throws {
      items.pushBack(new Diagnostic(Severity.note, file, 0, 0, message, ""));
    }

    proc hasErrors(): bool throws do return errorCount > 0;

    proc render(from: int = 0): string throws {
      var sb = "";
      for i in from..<items.size {
        const d = items[i];
        if d.severity == Severity.note && !showNotes then continue;
        sb += colourise(d.severity, severityLabel(d.severity)) + ": ";
        if !d.file.isEmpty() {
          sb += d.file;
          if d.line > 0 then sb += ":" + d.line:string;
          sb += ": ";
        }
        sb += d.message + "\n";
        if !d.hint.isEmpty() then sb += "       hint: " + d.hint + "\n";
      }
      return sb;
    }

    proc ref report() throws {
      if reported >= items.size then return;
      try! stderr.write(render(reported));
      reported = items.size;
    }

    proc ref raiseIfFailed(stage: string) throws {
      report();
      if hasErrors() then
        throw new owned BuildError(stage + " failed with " + errorCount:string +
                                   " error(s)");
    }
  }
}
