#define _POSIX_C_SOURCE 200809L
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif
#include "file_watch.h"
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/event.h>
#else
#include <sys/inotify.h>
#endif

#define PATH_BYTES 4096
#define MAX_SYMLINKS 40
#define MAX_WATCHES (KIWI_FILE_WATCH_PATHS * (MAX_SYMLINKS + 2))
typedef struct {
  uint64_t device, inode, bytes;
  int64_t modified_seconds, modified_nanoseconds, changed_seconds, changed_nanoseconds;
  int error;
} FileStamp;

struct KiwiFileWatch {
  int fd, watches[MAX_WATCHES];
  size_t watch_count, count;
#ifdef __APPLE__
  uint64_t devices[MAX_WATCHES], inodes[MAX_WATCHES];
#endif
  char paths[KIWI_FILE_WATCH_PATHS][PATH_BYTES + 1];
  FileStamp stamps[KIWI_FILE_WATCH_PATHS];
  int pending;
};

static FileStamp stamp(const char *path) {
  FileStamp result = {0};
  struct stat info;
  if (stat(path, &info) != 0) { result.error = errno; return result; }
  result.device = info.st_dev;
  result.inode = info.st_ino;
  result.bytes = info.st_size;
#ifdef __APPLE__
  result.modified_seconds = info.st_mtimespec.tv_sec;
  result.modified_nanoseconds = info.st_mtimespec.tv_nsec;
  result.changed_seconds = info.st_ctimespec.tv_sec;
  result.changed_nanoseconds = info.st_ctimespec.tv_nsec;
#else
  result.modified_seconds = info.st_mtim.tv_sec;
  result.modified_nanoseconds = info.st_mtim.tv_nsec;
  result.changed_seconds = info.st_ctim.tv_sec;
  result.changed_nanoseconds = info.st_ctim.tv_nsec;
#endif
  return result;
}

static int same_stamp(const FileStamp *a, const FileStamp *b) {
  return a->device == b->device && a->inode == b->inode && a->bytes == b->bytes
    && a->modified_seconds == b->modified_seconds && a->modified_nanoseconds == b->modified_nanoseconds
    && a->changed_seconds == b->changed_seconds && a->changed_nanoseconds == b->changed_nanoseconds
    && a->error == b->error;
}

static void clear_watches(KiwiFileWatch *watch) {
  for (size_t i = 0; i < watch->watch_count; ++i) {
#ifdef __APPLE__
    close(watch->watches[i]);
#else
    inotify_rm_watch(watch->fd, watch->watches[i]);
#endif
  }
  watch->watch_count = 0;
}

static int add_watch(KiwiFileWatch *watch, const char *path) {
#ifdef __APPLE__
  int fd = open(path, O_EVTONLY | O_CLOEXEC);
  if (fd < 0) return 0;
  struct stat info;
  if (fstat(fd, &info) != 0) { close(fd); return 0; }
  for (size_t i = 0; i < watch->watch_count; ++i) {
    if (watch->devices[i] == (uint64_t)info.st_dev && watch->inodes[i] == (uint64_t)info.st_ino) { close(fd); return 1; }
  }
  if (watch->watch_count == MAX_WATCHES) { close(fd); return 0; }
  struct kevent event;
  EV_SET(&event, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR,
    NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB | NOTE_DELETE | NOTE_RENAME | NOTE_REVOKE, 0, NULL);
  if (kevent(watch->fd, &event, 1, NULL, 0, NULL) < 0) { close(fd); return 0; }
  watch->devices[watch->watch_count] = info.st_dev;
  watch->inodes[watch->watch_count] = info.st_ino;
  watch->watches[watch->watch_count++] = fd;
#else
  int id = inotify_add_watch(watch->fd, path,
    IN_MODIFY | IN_CLOSE_WRITE | IN_ATTRIB | IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO |
    IN_DELETE_SELF | IN_MOVE_SELF | IN_UNMOUNT);
  if (id < 0) return 0;
  for (size_t i = 0; i < watch->watch_count; ++i) if (watch->watches[i] == id) return 1;
  if (watch->watch_count == MAX_WATCHES) { inotify_rm_watch(watch->fd, id); return 0; }
  watch->watches[watch->watch_count++] = id;
#endif
  return 1;
}

static int add_parent(KiwiFileWatch *watch, const char *path) {
  char parent[PATH_BYTES + 1];
  strcpy(parent, path);
  for (;;) {
    char *slash = strrchr(parent, '/');
    if (!slash) strcpy(parent, ".");
    else if (slash == parent) parent[1] = '\0';
    else *slash = '\0';
    struct stat info;
    if (stat(parent, &info) == 0 && S_ISDIR(info.st_mode) && add_watch(watch, parent)) return 1;
    if (!slash || strcmp(parent, "/") == 0) return 0;
  }
}

static int add_path(KiwiFileWatch *watch, const char *path) {
  // The final inode detects writes; directories detect replacement and missing
  // targets. Watch alias parents too, including symlinks in directory components.
  int covered = add_watch(watch, path);
  if (!add_parent(watch, path) && !covered) return 0;
  char current[PATH_BYTES + 1], prefix[PATH_BYTES + 1], target[PATH_BYTES + 1], expanded[PATH_BYTES + 1];
  strcpy(current, path);
  for (unsigned hop = 0; hop <= MAX_SYMLINKS; ++hop) {
    size_t length = strlen(current);
    int found = 0;
    for (size_t end = 1; end <= length; ++end) {
      if ((end < length && current[end] != '/') || current[end - 1] == '/') continue;
      memcpy(prefix, current, end);
      prefix[end] = '\0';
      struct stat info;
      if (lstat(prefix, &info) != 0 || !S_ISLNK(info.st_mode)) continue;
      if (hop == MAX_SYMLINKS || !add_parent(watch, prefix)) return 0;
      ssize_t bytes = readlink(prefix, target, PATH_BYTES);
      if (bytes <= 0 || bytes >= PATH_BYTES) return 0;
      target[bytes] = '\0';
      char *slash = strrchr(prefix, '/');
      size_t base = target[0] == '/' || !slash ? 0 : (size_t)(slash - prefix + 1);
      size_t suffix = length - end;
      if (base + (size_t)bytes + suffix > PATH_BYTES) return 0;
      memcpy(expanded, prefix, base);
      memcpy(expanded + base, target, (size_t)bytes);
      memcpy(expanded + base + bytes, current + end, suffix + 1);
      strcpy(current, expanded);
      found = 1;
      break;
    }
    if (!found) return add_parent(watch, current) || covered;
  }
  return 0;
}

static int rearm(KiwiFileWatch *watch) {
  clear_watches(watch);
  for (size_t i = 0; i < watch->count; ++i) {
    if (!add_path(watch, watch->paths[i])) return 0;
  }
  return 1;
}

int kiwi_file_watch_update(KiwiFileWatch *watch, const char *const *paths, size_t count) {
  if (!watch || !paths || count == 0 || count > KIWI_FILE_WATCH_PATHS) return 0;
  for (size_t i = 0; i < count; ++i) {
    if (!paths[i] || !*paths[i] || strnlen(paths[i], PATH_BYTES + 1) > PATH_BYTES) return 0;
  }
  FileStamp previous[KIWI_FILE_WATCH_PATHS];
  for (size_t i = 0; i < count; ++i) {
    previous[i] = stamp(paths[i]);
    int found = 0;
    for (size_t old = 0; old < watch->count; ++old) {
      if (strcmp(paths[i], watch->paths[old]) == 0) { previous[i] = watch->stamps[old]; found = 1; break; }
    }
    if (!found) watch->pending = 1;
  }
  for (size_t i = 0; i < count; ++i) {
    strcpy(watch->paths[i], paths[i]);
    watch->stamps[i] = previous[i];
  }
  watch->count = count;
  if (!rearm(watch)) return 0;
  // Check after arming too, closing the gap between observing and subscribing.
  for (size_t i = 0; i < count; ++i) {
    FileStamp current = stamp(watch->paths[i]);
    if (!same_stamp(&current, &watch->stamps[i])) watch->pending = 1;
    watch->stamps[i] = current;
  }
  return 1;
}

KiwiFileWatch *kiwi_file_watch_create(const char *const *paths, size_t count) {
  KiwiFileWatch *watch = calloc(1, sizeof(*watch));
  if (!watch) return NULL;
#ifdef __APPLE__
  watch->fd = kqueue();
  if (watch->fd >= 0 && fcntl(watch->fd, F_SETFD, FD_CLOEXEC) < 0) { close(watch->fd); watch->fd = -1; }
#else
  watch->fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
#endif
  if (watch->fd < 0 || !kiwi_file_watch_update(watch, paths, count)) {
    kiwi_file_watch_destroy(watch); return NULL;
  }
  return watch;
}

int kiwi_file_watch_fd(const KiwiFileWatch *watch) { return watch ? watch->fd : -1; }

int kiwi_file_watch_take_changes(KiwiFileWatch *watch) {
  if (!watch) return -1;
  int event_seen = 0;
  // Bounded drain so a busy containing directory cannot monopolize the UI.
  for (int batch = 0; batch < 8; ++batch) {
#ifdef __APPLE__
    struct kevent events[32];
    struct timespec timeout = {0, 0};
    int count = kevent(watch->fd, NULL, 0, events, 32, &timeout);
    if (count < 0) { if (errno == EINTR) continue; return -1; }
    if (!count) break;
    event_seen = 1;
#else
    union { struct inotify_event aligned; char bytes[8192]; } buffer;
    ssize_t count = read(watch->fd, buffer.bytes, sizeof(buffer.bytes));
    if (count < 0) { if (errno == EINTR) continue; if (errno == EAGAIN) break; return -1; }
    if (!count) break;
    size_t offset = 0;
    while (offset + sizeof(struct inotify_event) <= (size_t)count) {
      const struct inotify_event *event = (const struct inotify_event *)(buffer.bytes + offset);
      if (event->mask & ~IN_IGNORED) event_seen = 1;
      offset += sizeof(*event) + event->len;
    }
#endif
  }
  int changed = watch->pending;
  watch->pending = 0;
  if (event_seen) {
    if (!rearm(watch)) return -1;
    for (size_t i = 0; i < watch->count; ++i) {
      FileStamp current = stamp(watch->paths[i]);
      if (!same_stamp(&current, &watch->stamps[i])) changed = 1;
      watch->stamps[i] = current;
    }
  }
  return changed;
}

void kiwi_file_watch_destroy(KiwiFileWatch *watch) {
  if (!watch) return;
  clear_watches(watch);
  if (watch->fd >= 0) close(watch->fd);
  free(watch);
}
