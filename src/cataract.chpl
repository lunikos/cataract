module CataractCLI {
  use Cli;
  use IO;

  proc main(args: [] string): int throws {
    const inv = parseArgs(args);
    if !inv.valid {
      try! stderr.writeln("error: ", inv.error);
      try! stderr.writeln(usage());
      return 2;
    }
    return dispatch(inv);
  }
}
