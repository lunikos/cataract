module JsonField {
  /* A scanner, not a parser: one top-level scalar, no nesting. Offsets come from
     `string.find` and stay in byte space throughout. */
  private proc after(payload: string, name: string): string throws {
    const key = "\"" + name + "\"";
    const at = payload.find(key);
    if at == -1 then return "";

    const rest = payload[(at + key.numBytes)..];
    const colon = rest.find(":");
    if colon == -1 then return "";
    return rest[(colon + 1)..].strip();
  }

  proc present(payload: string, name: string): bool throws {
    return !after(payload, name).isEmpty();
  }

  proc text(payload: string, name: string): string throws {
    const raw = after(payload, name);
    if !raw.startsWith("\"") then return "";
    const body = raw[1..];
    const close = body.find("\"");
    if close == -1 then return "";
    return body[..<close];
  }

  proc flag(payload: string, name: string, fallback: bool): bool throws {
    const raw = after(payload, name);
    if raw.startsWith("true") then return true;
    if raw.startsWith("false") then return false;
    return fallback;
  }
}
