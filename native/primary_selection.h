#ifndef KIWI_PRIMARY_SELECTION_H
#define KIWI_PRIMARY_SELECTION_H
#include <stddef.h>
typedef struct KiwiPrimaryRead KiwiPrimaryRead;
enum {
  KIWI_PRIMARY_PENDING = 0,
  KIWI_PRIMARY_READY = 1,
  KIWI_PRIMARY_UNAVAILABLE = -1,
  KIWI_PRIMARY_TIMEOUT = -2,
  KIWI_PRIMARY_OVER_LIMIT = -3,
  KIWI_PRIMARY_INVALID = -4
};
/* Main-thread, private X connection. No wait for the selection owner. A poll
 * consumes at most 32 events and one 64 KiB property slice. Live X server
 * round trips (connection, atom/property requests) still use synchronous Xlib. */
KiwiPrimaryRead *kiwi_primary_read_new(const char *display_name, size_t maximum_bytes, unsigned timeout_ms);
int kiwi_primary_read_poll(KiwiPrimaryRead *read);
const char *kiwi_primary_read_text(const KiwiPrimaryRead *read, size_t *bytes);
void kiwi_primary_read_destroy(KiwiPrimaryRead *read);
#endif
