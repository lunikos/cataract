module TaskPool {
  private use Time;

  /* `begin` is unbounded, so a flood would be unbounded task creation. */
  record Gate {
    var limit: int;
    var permits: sync int;
    var live: atomic int;

    /* Explicit: a generated initializer would take the sync/atomic fields. */
    proc init(limit: int = 512) {
      this.limit = limit;
    }

    proc ref start() {
      permits.writeEF(limit);
    }

    proc ref acquire() {
      while true {
        var p = permits.readFE();
        if p > 0 {
          permits.writeEF(p - 1);
          live.add(1);
          return;
        }
        permits.writeEF(p);
        sleep(0.0005);
      }
    }

    proc ref release() {
      const p = permits.readFE();
      permits.writeEF(p + 1);
      live.sub(1);
    }

    proc inFlight(): int do return live.read();

    proc drain(timeoutSeconds: real): bool {
      var waited = 0.0;
      while live.read() > 0 && waited < timeoutSeconds {
        sleep(0.01);
        waited += 0.01;
      }
      return live.read() == 0;
    }
  }
}
