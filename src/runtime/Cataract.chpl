/* Public surface. Sockets, buffers and the C boundary are absent by design. */
module Cataract {
  public use HttpMessage;
  public use HttpMethod only Method, methodName, effectiveMethod;
  public use HttpStatus only reason;
  public use RouteTable only Handler, Router, RouteKind;
  public use RouteParams only methodBit, maskAllows;
  public use Pipeline only Middleware, Chain;
  public use Server only App, ServerConfig;
  public use Html only escape;
  public use Markup only MarkupBuilder, classList;
  public use JsonWrite only JsonBuilder, jsonString, escapeJson;
  public use Ssr only PageMeta, renderDocument, island, errorPage;
  public use Logging only LogLevel, setLevel, parseLevel,
                          info as logInfo, warn as logWarn, error as logError,
                          debug as logDebug;
  public use HttpParser only Limits;

  param version = "0.2.0";
}
