#include "cataract_net.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

int cat_net_init(void) {
  /* A peer vanishing mid-write must be EPIPE on one task, not a process signal. */
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = SIG_IGN;
  return sigaction(SIGPIPE, &sa, NULL);
}

static volatile sig_atomic_t cat_stop_flag = 0;

static void cat_on_stop(int sig) {
  (void)sig;
  cat_stop_flag = 1;
}

int cat_install_shutdown_handlers(void) {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = cat_on_stop;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;
  if (sigaction(SIGINT, &sa, NULL) != 0) return -1;
  if (sigaction(SIGTERM, &sa, NULL) != 0) return -1;
  return 0;
}

int cat_shutdown_requested(void) { return (int)cat_stop_flag; }

int cat_listen(const char *host, uint16_t port, int backlog) {
  struct sockaddr_in addr;
  int fd, on = 1;

  fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (fd < 0) return -1;

  if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0) {
    close(fd);
    return -1;
  }
  /* No SO_REUSEPORT: a second server would share the port and quietly take
     the traffic, so a stale one reads as a change that never took effect. */

  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);

  if (host == NULL || host[0] == '\0' || strcmp(host, "0.0.0.0") == 0) {
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
  } else if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
    close(fd);
    errno = EINVAL;
    return -1;
  }

  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    int saved = errno;
    close(fd);
    errno = saved;
    return -1;
  }

  if (listen(fd, backlog) < 0) {
    int saved = errno;
    close(fd);
    errno = saved;
    return -1;
  }

  return fd;
}

int cat_accept(int listen_fd, char *peer_ip, size_t peer_ip_cap, uint16_t *peer_port) {
  struct sockaddr_in peer;
  socklen_t plen = sizeof(peer);
  int fd;

  memset(&peer, 0, sizeof(peer));

  fd = accept(listen_fd, (struct sockaddr *)&peer, &plen);

  if (fd < 0) {
    if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) return -2;
    return -1;
  }

  if (peer_ip != NULL && peer_ip_cap > 0) {
    peer_ip[0] = '\0';
    inet_ntop(AF_INET, &peer.sin_addr, peer_ip, (socklen_t)peer_ip_cap);
    peer_ip[peer_ip_cap - 1] = '\0';
  }
  if (peer_port != NULL) *peer_port = ntohs(peer.sin_port);

  return fd;
}

int cat_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) return -1;
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int cat_wait_readable(int fd, int timeout_ms) {
  struct pollfd p;
  int rc;

  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;

  /* Not retried on EINTR: that would sleep through the signal ending the run. */
  rc = poll(&p, 1, timeout_ms);

  if (rc > 0) return 1;
  if (rc == 0) return 0;
  if (errno == EINTR) return 0;
  return -1;
}

int cat_set_nodelay(int fd, int on) {
  return setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
}

long cat_recv(int fd, void *buf, size_t len) {
  ssize_t n;

  do {
    n = recv(fd, buf, len, 0);
  } while (n < 0 && errno == EINTR);

  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return -2;
  return (long)n;
}

long cat_send(int fd, const void *buf, size_t len) {
  ssize_t n;

  do {
    n = send(fd, buf, len, 0);
  } while (n < 0 && errno == EINTR);

  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return -2;
  return (long)n;
}

int cat_shutdown(int fd) { return shutdown(fd, SHUT_RDWR); }

int cat_close(int fd) { return close(fd); }

int cat_use_colour(void) {
  const char *no = getenv("NO_COLOR");
  if (no != NULL && no[0] != '\0') return 0;
  return isatty(STDOUT_FILENO);
}

int cat_errno(void) { return errno; }

int cat_eaddrinuse(void) { return EADDRINUSE; }

/* strerror() shares a static buffer across threads; this one is per-thread. */
static _Thread_local char cat_err_buf[128];

const char *cat_strerror(int err) {
  if (strerror_r(err, cat_err_buf, sizeof(cat_err_buf)) != 0)
    snprintf(cat_err_buf, sizeof(cat_err_buf), "errno %d", err);
  return cat_err_buf;
}

int64_t cat_unix_time(void) { return (int64_t)time(NULL); }

int64_t cat_mono_millis(void) {
  struct timespec ts;
#ifdef CLOCK_MONOTONIC
  if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0)
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
  return (int64_t)time(NULL) * 1000;
}
