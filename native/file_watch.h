#ifndef KIWI_FILE_WATCH_H
#define KIWI_FILE_WATCH_H
#include <stddef.h>

#define KIWI_FILE_WATCH_PATHS 16
typedef struct KiwiFileWatch KiwiFileWatch;
/* UI-thread owned. The descriptor can be polled by the readiness worker; only
 * the owner drains events. Paths may be absent or replaced by atomic rename.
 * Relative/absolute symlinks and linked directories are followed up to 40 hops;
 * alias and target parents remain watched while the target is absent. */
KiwiFileWatch *kiwi_file_watch_create(const char *const *paths, size_t count);
int kiwi_file_watch_fd(const KiwiFileWatch *watch);
int kiwi_file_watch_update(KiwiFileWatch *watch, const char *const *paths, size_t count);
int kiwi_file_watch_take_changes(KiwiFileWatch *watch);
void kiwi_file_watch_destroy(KiwiFileWatch *watch);
#endif
