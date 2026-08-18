#include "cataract_cli.h"

#include <errno.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <sys/stat.h>
#include <unistd.h>

void cat_cli_sleep_millis(int millis) {
  struct timespec req;

  if (millis <= 0) return;

  req.tv_sec = millis / 1000;
  req.tv_nsec = (long)(millis % 1000) * 1000000L;

  /* Not resumed after EINTR: the caller re-checks the stop flag instead. */
  nanosleep(&req, NULL);
}

static volatile sig_atomic_t cat_cli_stop_flag = 0;

static void cat_cli_on_stop(int sig) {
  (void)sig;
  cat_cli_stop_flag = 1;
}

int cat_cli_install_shutdown_handlers(void) {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = cat_cli_on_stop;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;
  if (sigaction(SIGINT, &sa, NULL) != 0) return -1;
  if (sigaction(SIGTERM, &sa, NULL) != 0) return -1;
  return 0;
}

int cat_cli_shutdown_requested(void) {
  return cat_cli_stop_flag != 0;
}

int cat_cli_use_colour(void) {
  const char *no = getenv("NO_COLOR");
  if (no != NULL && no[0] != '\0') return 0;
  return isatty(STDERR_FILENO) && isatty(STDOUT_FILENO);
}

long long cat_cli_mtime_nanos(const char *path) {
  struct stat st;
  if (path == NULL || stat(path, &st) != 0) return 0;
#if defined(__APPLE__)
  return (long long)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
#else
  return (long long)st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec;
#endif
}
