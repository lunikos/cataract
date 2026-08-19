module Urls {
  private use UrlCodec only percentEncode;
  private use List;

  proc segment(value: string): string do return percentEncode(value);

  proc segment(value: int): string do return value: string;

  proc segment(value: bool): string do return if value then "true" else "false";

  proc rest(value: string): string {
    var sb = "";
    for part in value.split("/") {
      if part.isEmpty() then continue;
      if !sb.isEmpty() then sb += "/";
      sb += percentEncode(part);
    }
    return sb;
  }

  proc query(pairs...?n): string {
    if n % 2 != 0 then
      compilerError("query takes name/value pairs, so the count must be even");
    var sb = "";
    for param i in 0..n-2 by 2 {
      if sb.isEmpty() then sb = "?"; else sb += "&";
      sb += percentEncode(pairs(i)) + "=" + segment(pairs(i + 1));
    }
    return sb;
  }
}
