module CSocket {
  public use CTypes;

  require "cataract_net.h", "cataract_net.c";

  extern proc cat_net_init(): c_int;
  extern proc cat_install_shutdown_handlers(): c_int;
  extern proc cat_shutdown_requested(): c_int;
  extern proc cat_listen(host: c_ptrConst(c_char), port: uint(16), backlog: c_int): c_int;
  extern proc cat_accept(listen_fd: c_int, peer_ip: c_ptr(c_char), peer_ip_cap: c_size_t,
                         peer_port: c_ptr(uint(16))): c_int;
  extern proc cat_set_nonblocking(fd: c_int): c_int;
  extern proc cat_set_nodelay(fd: c_int, enable: c_int): c_int;
  extern proc cat_wait_readable(fd: c_int, timeout_ms: c_int): c_int;
  extern proc cat_recv(fd: c_int, buf: c_ptr(void), len: c_size_t): c_long;
  extern proc cat_send(fd: c_int, buf: c_ptrConst(void), len: c_size_t): c_long;
  extern proc cat_shutdown(fd: c_int): c_int;
  extern proc cat_close(fd: c_int): c_int;
  extern proc cat_errno(): c_int;
  extern proc cat_strerror(err: c_int): c_ptrConst(c_char);

  extern proc cat_unix_time(): int(64);
  extern proc cat_mono_millis(): int(64);

  extern proc memcpy(dest: c_ptr(void), src: c_ptrConst(void), n: c_size_t): c_ptr(void);

  param WOULD_BLOCK = -2;

  proc errnoMessage(): string {
    const err = cat_errno();
    const cstr = cat_strerror(err);
    if cstr == nil then return "errno " + err:string;
    return "errno " + err:string + ": " + (try! string.createCopyingBuffer(cstr));
  }
}
