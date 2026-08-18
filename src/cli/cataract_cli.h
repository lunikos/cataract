#ifndef CATARACT_CLI_H
#define CATARACT_CLI_H

/* Blocks the thread. Time.sleep spin-yields, which costs the watcher a core. */
void cat_cli_sleep_millis(int millis);

int cat_cli_install_shutdown_handlers(void);
int cat_cli_shutdown_requested(void);

int cat_cli_use_colour(void);

#endif /* CATARACT_CLI_H */
