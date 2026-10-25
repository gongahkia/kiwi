#define _POSIX_C_SOURCE 200809L
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif
#include "file_watch.h"
#include <assert.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void write_file(const char *path, const char *text) {
  FILE *file = fopen(path, "wb");
  assert(file);
  assert(fwrite(text, 1, strlen(text), file) == strlen(text));
  assert(fclose(file) == 0);
}

static void changed(KiwiFileWatch *watch) {
  struct pollfd descriptor = { .fd = kiwi_file_watch_fd(watch), .events = POLLIN };
  assert(poll(&descriptor, 1, 2000) == 1);
  assert(kiwi_file_watch_take_changes(watch) == 1);
  assert(kiwi_file_watch_take_changes(watch) == 0);
}

int main(void) {
  char directory[] = "/tmp/kiwi-file-watch-XXXXXX";
  assert(mkdtemp(directory));
  char path[512], temporary[512], parent[512], future[512], unrelated[512], link_path[512];
  snprintf(path, sizeof(path), "%s/config", directory);
  snprintf(temporary, sizeof(temporary), "%s/replacement", directory);
  snprintf(parent, sizeof(parent), "%s/new", directory);
  snprintf(future, sizeof(future), "%s/new/theme", directory);
  snprintf(unrelated, sizeof(unrelated), "%s/unrelated", directory);
  snprintf(link_path, sizeof(link_path), "%s/link", directory);
  const char *paths[] = {path, future};
  assert(!kiwi_file_watch_create(NULL, 0));
  assert(!kiwi_file_watch_create(paths, KIWI_FILE_WATCH_PATHS + 1));
  assert(!kiwi_file_watch_create((const char *[]) {""}, 1));
  KiwiFileWatch *watch = kiwi_file_watch_create(paths, 2);
  assert(watch);
  assert(fcntl(kiwi_file_watch_fd(watch), F_GETFD) & FD_CLOEXEC);
  assert(kiwi_file_watch_take_changes(watch) == 1); // Initial subscription closes the load/arm race.
  assert(kiwi_file_watch_take_changes(watch) == 0);
  write_file(path, "one"); changed(watch);
  write_file(path, "two"); changed(watch); // Same-size overwrite.
  write_file(temporary, "atomic");
  assert(rename(temporary, path) == 0); changed(watch);
  assert(unlink(path) == 0); changed(watch);
  write_file(path, "recreated"); changed(watch);
  assert(mkdir(parent, 0700) == 0);
  // Reattach to a newly created parent even before the target exists.
  assert(kiwi_file_watch_take_changes(watch) == 0);
  write_file(future, "theme"); changed(watch);
  write_file(unrelated, "ignore");
  assert(kiwi_file_watch_take_changes(watch) == 0);
  assert(kiwi_file_watch_take_changes(watch) == 0);
  assert(symlink(path, link_path) == 0);
  const char *linked[] = {link_path};
  assert(kiwi_file_watch_update(watch, linked, 1));
  assert(kiwi_file_watch_take_changes(watch) == 1);
  write_file(path, "link target"); changed(watch);
  write_file(temporary, "new target");
  assert(rename(temporary, path) == 0); changed(watch);
  assert(!kiwi_file_watch_update(watch, paths, KIWI_FILE_WATCH_PATHS + 1));
  write_file(path, "still armed"); changed(watch);
  for (int round = 0; round < 128; ++round) {
    kiwi_file_watch_destroy(watch);
    watch = kiwi_file_watch_create(paths, 2);
    assert(watch);
    assert(kiwi_file_watch_take_changes(watch) == 1);
    write_file(path, round % 2 ? "a" : "bb"); changed(watch);
  }
  kiwi_file_watch_destroy(watch);
  kiwi_file_watch_destroy(NULL);
  assert(unlink(link_path) == 0);
  assert(unlink(path) == 0);
  assert(unlink(future) == 0);
  assert(unlink(unrelated) == 0);
  assert(rmdir(parent) == 0);
  assert(rmdir(directory) == 0);
  puts("File watcher tests passed: creation, overwrite, atomic rename, delete/recreate, missing parents, symlinks, unrelated events and lifecycle.");
  return 0;
}
