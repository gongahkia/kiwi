#define _POSIX_C_SOURCE 200809L
#include "pty_watch.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

#define KIWI_WATCH_MAX_FDS 129 /* PTY + child exit for 64 panes, plus configuration */
struct KiwiPtyWatch {
  pthread_t thread;
  pthread_mutex_t mutex;
  int signal[2];
  int fds[KIWI_WATCH_MAX_FDS];
  short events[KIWI_WATCH_MAX_FDS];
  size_t count;
  uint64_t generation;
  int armed;
  int stopping;
  void (*notify)(void *);
  void *userdata;
};

static void signal_worker(KiwiPtyWatch *watch) {
  char byte = 0;
  /* A full nonblocking pipe already guarantees a wake. */
  while (write(watch->signal[1], &byte, 1) < 0 && errno == EINTR) {}
}

static void *watch_main(void *argument) {
  KiwiPtyWatch *watch = argument;
  for (;;) {
    struct pollfd fds[KIWI_WATCH_MAX_FDS + 1];
    pthread_mutex_lock(&watch->mutex);
    if (watch->stopping) { pthread_mutex_unlock(&watch->mutex); return NULL; }
    size_t count = watch->armed ? watch->count : 0;
    uint64_t generation = watch->generation;
    fds[0] = (struct pollfd){ .fd = watch->signal[0], .events = POLLIN };
    for (size_t i = 0; i < count; ++i) fds[i + 1] = (struct pollfd){ .fd = watch->fds[i], .events = watch->events[i] };
    pthread_mutex_unlock(&watch->mutex);

    int result = poll(fds, (nfds_t)count + 1, -1);
    if (result < 0) { if (errno == EINTR) continue; return NULL; }
    if (fds[0].revents) {
      char bytes[128];
      while (read(watch->signal[0], bytes, sizeof(bytes)) > 0) {}
      continue;
    }
    int ready = 0;
    for (size_t i = 1; i <= count; ++i) if (fds[i].revents) { ready = 1; break; }
    pthread_mutex_lock(&watch->mutex);
    int notify = ready && watch->armed && !watch->stopping && watch->generation == generation;
    if (notify) watch->armed = 0;
    pthread_mutex_unlock(&watch->mutex);
    if (notify) watch->notify(watch->userdata);
  }
}

KiwiPtyWatch *kiwi_pty_watch_create(void (*notify)(void *), void *userdata) {
  if (!notify) return NULL;
  KiwiPtyWatch *watch = calloc(1, sizeof(*watch));
  if (!watch) return NULL;
  if (pipe(watch->signal) != 0) { free(watch); return NULL; }
  for (size_t i = 0; i < 2; ++i) {
    int flags = fcntl(watch->signal[i], F_GETFL);
    if (flags < 0 || fcntl(watch->signal[i], F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(watch->signal[i], F_SETFD, FD_CLOEXEC) < 0) goto fail_pipe;
  }
  if (pthread_mutex_init(&watch->mutex, NULL) != 0) goto fail_pipe;
  watch->notify = notify;
  watch->userdata = userdata;
  if (pthread_create(&watch->thread, NULL, watch_main, watch) != 0) {
    pthread_mutex_destroy(&watch->mutex);
    goto fail_pipe;
  }
  return watch;
fail_pipe:
  close(watch->signal[0]); close(watch->signal[1]); free(watch);
  return NULL;
}

int kiwi_pty_watch_update(KiwiPtyWatch *watch, const int *fds, size_t count) {
  if (count > KIWI_WATCH_MAX_FDS) return 0;
  uint8_t interests[KIWI_WATCH_MAX_FDS];
  for (size_t i = 0; i < count; ++i) interests[i] = KIWI_WATCH_READ;
  return kiwi_pty_watch_update_events(watch, fds, interests, count);
}

int kiwi_pty_watch_update_events(KiwiPtyWatch *watch, const int *fds,
                                  const uint8_t *interests, size_t count) {
  if (!watch || count > KIWI_WATCH_MAX_FDS || (count && (!fds || !interests))) return 0;
  for (size_t i = 0; i < count; ++i) {
    if (fds[i] < 0 || interests[i] == 0 || (interests[i] & ~(KIWI_WATCH_READ | KIWI_WATCH_WRITE))) return 0;
  }
  pthread_mutex_lock(&watch->mutex);
  for (size_t i = 0; i < count; ++i) {
    watch->fds[i] = fds[i];
    watch->events[i] = ((interests[i] & KIWI_WATCH_READ) ? POLLIN : 0) |
                       ((interests[i] & KIWI_WATCH_WRITE) ? POLLOUT : 0);
  }
  watch->count = count;
  watch->generation++;
  watch->armed = count > 0;
  pthread_mutex_unlock(&watch->mutex);
  signal_worker(watch);
  return 1;
}

void kiwi_pty_watch_destroy(KiwiPtyWatch *watch) {
  if (!watch) return;
  pthread_mutex_lock(&watch->mutex);
  watch->stopping = 1;
  pthread_mutex_unlock(&watch->mutex);
  signal_worker(watch);
  pthread_join(watch->thread, NULL);
  pthread_mutex_destroy(&watch->mutex);
  close(watch->signal[0]); close(watch->signal[1]); free(watch);
}
