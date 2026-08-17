module HttpClock {
  private use CSocket;

  private const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  private const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

  /* The value changes once a second, so it is memoised behind a lock. */
  private var cacheGate: sync bool = true;
  private var cachedSecond: int(64) = -1;
  private var cachedDate: string = "";

  proc unixNow(): int(64) do return cat_unix_time();
  proc monoMillis(): int(64) do return cat_mono_millis();

  proc httpDate(): string {
    const now = cat_unix_time();
    cacheGate.readFE();
    defer cacheGate.writeEF(true);
    if now != cachedSecond {
      cachedSecond = now;
      cachedDate = formatHttpDate(now);
    }
    return cachedDate;
  }

  proc formatHttpDate(epoch: int(64)): string {
    const days = floorDiv(epoch, 86400);
    var rem = epoch - days * 86400;

    const hour = (rem / 3600): int;
    const minute = ((rem % 3600) / 60): int;
    const second = (rem % 60): int;
    const dow = (((days % 7) + 11) % 7): int;

    const z = days + 719468;
    const era = floorDiv(z, 146097);
    const doe = z - era * 146097;
    const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const y0 = yoe + era * 400;
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    const day = (doy - (153 * mp + 2) / 5 + 1): int;
    const month = (if mp < 10 then mp + 3 else mp - 9): int;
    const year = (if month <= 2 then y0 + 1 else y0): int;

    return DAYS[dow] + ", " + pad2(day) + " " + MONTHS[month - 1] + " " + year:string +
           " " + pad2(hour) + ":" + pad2(minute) + ":" + pad2(second) + " GMT";
  }

  private proc floorDiv(a: int(64), b: int(64)): int(64) {
    var q = a / b;
    if (a % b != 0) && ((a < 0) != (b < 0)) then q -= 1;
    return q;
  }

  private proc pad2(v: int): string {
    return if v < 10 then "0" + v:string else v:string;
  }
}
