module Handshake {
  private use HttpMessage;
  private use HttpMethod;
  private use Digest only sha1Base64;

  param WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
  param SUPPORTED_VERSION = "13";

  proc isUpgradeRequest(const ref req: Request): bool {
    if req.method != Method.get then return false;
    if req.header("Upgrade").toLower().find("websocket") == -1 then return false;
    return req.header("Connection").toLower().find("upgrade") != -1;
  }

  proc acceptKey(clientKey: string): string {
    return sha1Base64(clientKey + WEBSOCKET_GUID);
  }

  record HandshakeResult {
    var accepted: bool = false;
    var status: int = 400;
    var detail: string = "";
    var responseHead: string = "";
    var subprotocol: string = "";
  }

  proc negotiate(const ref req: Request, offeredProtocols: string = ""): HandshakeResult {
    var result = new HandshakeResult();

    const key = req.header("Sec-WebSocket-Key").strip();
    if key.isEmpty() {
      result.detail = "Sec-WebSocket-Key is missing";
      return result;
    }
    if req.header("Sec-WebSocket-Version").strip() != SUPPORTED_VERSION {
      result.status = 426;
      result.detail = "only WebSocket version 13 is supported";
      return result;
    }

    result.subprotocol = chooseProtocol(req.header("Sec-WebSocket-Protocol"),
                                        offeredProtocols);

    var head = "HTTP/1.1 101 Switching Protocols\r\n";
    head += "Upgrade: websocket\r\n";
    head += "Connection: Upgrade\r\n";
    head += "Sec-WebSocket-Accept: " + acceptKey(key) + "\r\n";
    if !result.subprotocol.isEmpty() then
      head += "Sec-WebSocket-Protocol: " + result.subprotocol + "\r\n";
    head += "\r\n";

    result.responseHead = head;
    result.status = 101;
    result.accepted = true;
    return result;
  }

  private proc chooseProtocol(requested: string, offered: string): string {
    if requested.isEmpty() || offered.isEmpty() then return "";
    for want in requested.split(",") {
      const candidate = want.strip();
      for have in offered.split(",") do
        if have.strip() == candidate then return candidate;
    }
    return "";
  }
}
