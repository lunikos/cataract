module CliHost {
  private use CTypes;

  require "cataract_cli.h", "cataract_cli.c";

  private extern proc cat_cli_sleep_millis(millis: c_int): void;
  private extern proc cat_cli_install_shutdown_handlers(): c_int;
  private extern proc cat_cli_shutdown_requested(): c_int;
  private extern proc cat_cli_use_colour(): c_int;
  private extern proc cat_cli_mtime_nanos(path: c_ptrConst(c_char)): int(64);

  proc sleepMillis(millis: int) do cat_cli_sleep_millis(millis: c_int);

  proc mtimeNanos(path: string): int(64) do return cat_cli_mtime_nanos(path.c_str());

  proc installShutdownHandlers(): bool do
    return cat_cli_install_shutdown_handlers() == 0;

  proc shutdownRequested(): bool do return cat_cli_shutdown_requested() != 0;

  const colour = cat_cli_use_colour() != 0;

  proc red(s: string): string do return if colour then "\x1b[31m" + s + "\x1b[0m" else s;
  proc yellow(s: string): string do return if colour then "\x1b[33m" + s + "\x1b[0m" else s;
  proc green(s: string): string do return if colour then "\x1b[32m" + s + "\x1b[0m" else s;
}
