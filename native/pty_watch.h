#ifndef KIWI_PTY_WATCH_H
#define KIWI_PTY_WATCH_H
#include <stddef.h>
#include <stdint.h>

/* Internal one-shot readiness notification. The worker only polls descriptors
 * and wakes the host; all PTY reads, parsing and Lua callbacks stay on the UI
 * thread. Callers own the descriptors and must destroy before host teardown. */
typedef struct KiwiPtyWatch KiwiPtyWatch;
KiwiPtyWatch *kiwi_pty_watch_create(void (*notify)(void *), void *userdata);
int kiwi_pty_watch_update(KiwiPtyWatch *watch, const int *fds, size_t count);
enum { KIWI_WATCH_READ = 1, KIWI_WATCH_WRITE = 2 };
int kiwi_pty_watch_update_events(KiwiPtyWatch *watch, const int *fds,
                                  const uint8_t *interests, size_t count);
void kiwi_pty_watch_destroy(KiwiPtyWatch *watch);
#endif
