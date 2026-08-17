module Sockets {
  private use CSocket;
  private use Logging;

  class SocketError: Error {
    var detail: string;
    proc init(detail: string) {
      this.detail = detail;
    }
    override proc message(): string do return detail;
  }

  /* A class, so `owned` closes it exactly once even on an error unwind. */
  class Socket {
    var fd: c_int;
    var peerIp: string;
    var peerPort: int;
    var closed: bool = false;

    proc init(fd: c_int, peerIp: string = "", peerPort: int = 0) {
      this.fd = fd;
      this.peerIp = peerIp;
      this.peerPort = peerPort;
    }

    proc close() {
      if closed then return;
      closed = true;
      cat_shutdown(fd);
      cat_close(fd);
    }

    proc setNonBlocking() {
      if cat_set_nonblocking(fd) != 0 then
        Logging.warn("could not set O_NONBLOCK: " + errnoMessage());
    }

    proc setNoDelay(enable: bool) {
      cat_set_nodelay(fd, (if enable then 1 else 0): c_int);
    }

    proc deinit() {
      if !closed then cat_close(fd);
    }
  }

  record Listener {
    var fd: c_int = -1;
    var host: string;
    var port: int;

    proc ref close() {
      if fd >= 0 {
        cat_close(fd);
        fd = -1;
      }
    }
  }

  proc bindAndListen(host: string, port: int, backlog: int = 1024): Listener throws {
    if cat_net_init() != 0 then
      Logging.warn("could not mask SIGPIPE: " + errnoMessage());

    const fd = cat_listen(host.c_str(), port: uint(16), backlog: c_int);
    if fd < 0 then
      throw new owned SocketError("bind " + host + ":" + port:string + " failed (" +
                                  errnoMessage() + ")");
    if cat_set_nonblocking(fd) != 0 then
      throw new owned SocketError("could not set O_NONBLOCK on the listener (" +
                                  errnoMessage() + ")");
    return new Listener(fd, host, port);
  }

  proc shutdownRequested(): bool do return cat_shutdown_requested() != 0;

  proc installShutdownHandlers() {
    if cat_install_shutdown_handlers() != 0 then
      Logging.warn("could not install shutdown handlers: " + errnoMessage());
  }

  proc accept(const ref l: Listener, ref idle: bool): owned Socket? {
    param IP_CAP = 46;
    var ipBuf: [0..<IP_CAP] c_char;
    var peerPort: uint(16) = 0;

    idle = false;
    const fd = cat_accept(l.fd, c_ptrTo(ipBuf[0]), IP_CAP: c_size_t, c_ptrTo(peerPort));
    if fd == WOULD_BLOCK {
      idle = true;
      return nil;
    }
    if fd < 0 then return nil;

    const ip = try! string.createCopyingBuffer(c_ptrToConst(ipBuf[0]): c_ptrConst(c_char));
    var sock = new owned Socket(fd, ip, peerPort: int);
    sock.setNonBlocking();
    return sock;
  }
}
