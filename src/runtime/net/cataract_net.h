#ifndef CATARACT_NET_H
#define CATARACT_NET_H

#include <stddef.h>
#include <stdint.h>

/* Chapel sees descriptors and flat byte buffers; never a struct layout. */

int cat_net_init(void);

int cat_install_shutdown_handlers(void);
int cat_shutdown_requested(void);

int cat_listen(const char *host, uint16_t port, int backlog);

int cat_accept(int listen_fd, char *peer_ip, size_t peer_ip_cap, uint16_t *peer_port);

int cat_set_nonblocking(int fd);
int cat_set_nodelay(int fd, int on);

int cat_wait_readable(int fd, int timeout_ms);

long cat_recv(int fd, void *buf, size_t len);

long cat_send(int fd, const void *buf, size_t len);

int cat_shutdown(int fd);
int cat_close(int fd);

int cat_use_colour(void);

int cat_errno(void);
const char *cat_strerror(int err);

int64_t cat_unix_time(void);
int64_t cat_mono_millis(void);

#endif /* CATARACT_NET_H */
