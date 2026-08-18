module Logging {
  private use IO;
  private use CSocket only cat_use_colour;

  enum LogLevel { trace = 0, debug = 1, info = 2, warn = 3, error = 4, silent = 5 }

  proc parseLevel(s: string): LogLevel {
    select s.toLower() {
      when "trace" do return LogLevel.trace;
      when "debug" do return LogLevel.debug;
      when "info"  do return LogLevel.info;
      when "warn"  do return LogLevel.warn;
      when "error" do return LogLevel.error;
      when "silent" do return LogLevel.silent;
      otherwise do return LogLevel.info;
    }
  }

  private var levelOrd: atomic int = LogLevel.info: int;

  private var writeGate: sync bool = true;

  proc setLevel(l: LogLevel) {
    levelOrd.write(l: int);
  }

  proc enabled(l: LogLevel): bool {
    return (l: int) >= levelOrd.read();
  }

  private const colour = cat_use_colour() != 0;

  private proc paint(code: string, text: string): string do
    return if colour then "\x1b[" + code + "m" + text + "\x1b[0m" else text;

  private proc tag(l: LogLevel): string {
    select l {
      when LogLevel.trace do return "trace";
      when LogLevel.debug do return "debug";
      when LogLevel.info  do return paint("32", "info ");
      when LogLevel.warn  do return paint("33", "warn ");
      when LogLevel.error do return paint("31", "error");
      otherwise do return "     ";
    }
  }

  proc emit(l: LogLevel, msg: string) {
    if !enabled(l) then return;
    const line = tag(l) + "  " + msg;
    writeGate.readFE();
    defer writeGate.writeEF(true);
    writeln(line);
    try! stdout.flush();
  }

  inline proc trace(msg: string) do emit(LogLevel.trace, msg);
  inline proc debug(msg: string) do emit(LogLevel.debug, msg);
  inline proc info(msg: string)  do emit(LogLevel.info, msg);
  inline proc warn(msg: string)  do emit(LogLevel.warn, msg);
  inline proc error(msg: string) do emit(LogLevel.error, msg);
}
