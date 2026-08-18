module CliHost {
  private use CTypes;

  require "cataract_cli.h", "cataract_cli.c";

  private extern proc cat_cli_sleep_millis(millis: c_int): void;
  private extern proc cat_cli_install_shutdown_handlers(): c_int;
  private extern proc cat_cli_shutdown_requested(): c_int;

  proc sleepMillis(millis: int) do cat_cli_sleep_millis(millis: c_int);

  proc installShutdownHandlers(): bool do
    return cat_cli_install_shutdown_handlers() == 0;

  proc shutdownRequested(): bool do return cat_cli_shutdown_requested() != 0;
}
