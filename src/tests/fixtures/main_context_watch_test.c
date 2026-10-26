#define _POSIX_C_SOURCE 200809L
#include "main_context_watch.h"
#include <glib-unix.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

typedef struct {
  GMainContext *context;
  pthread_t ui_thread;
  int dispatched;
} Fixture;

static void notify(void *userdata) {
  int descriptor = *(int *)userdata;
  assert(write(descriptor, "!", 1) == 1);
}

static gboolean dispatched(void *userdata) {
  Fixture *fixture = userdata;
  assert(pthread_equal(pthread_self(), fixture->ui_thread));
  fixture->dispatched++;
  return G_SOURCE_REMOVE;
}

static void *attach_after_delay(void *userdata) {
  Fixture *fixture = userdata;
  struct timespec delay = { .tv_nsec = 50000000 };
  nanosleep(&delay, NULL);
  GSource *source = g_idle_source_new();
  g_source_set_callback(source, dispatched, fixture, NULL);
  g_source_attach(source, fixture->context);
  g_source_unref(source);
  return NULL;
}

static void drain(int descriptor) {
  char buffer[128];
  while (read(descriptor, buffer, sizeof(buffer)) > 0) {}
  assert(errno == EAGAIN);
}

static void await_dispatch(KiwiMainContextWatch *watch, Fixture *fixture, int descriptor, int expected) {
  gint64 started = g_get_monotonic_time();
  while (fixture->dispatched < expected) {
    double timeout = kiwi_main_context_watch_prepare(watch, 2.0);
    struct pollfd event = { .fd = descriptor, .events = POLLIN };
    assert(poll(&event, 1, (int)ceil(timeout * 1000)) >= 0);
    drain(descriptor);
    kiwi_main_context_watch_dispatch(watch);
    assert(g_get_monotonic_time() - started < 1500000);
  }
}

int main(void) {
  int events[2];
  assert(pipe(events) == 0);
  int flags = fcntl(events[0], F_GETFL);
  assert(flags >= 0 && fcntl(events[0], F_SETFL, flags | O_NONBLOCK) == 0);
  Fixture fixture = { .context = g_main_context_new(), .ui_thread = pthread_self() };
  KiwiMainContextWatch *watch = kiwi_main_context_watch_new(fixture.context, notify, &events[1]);
  assert(watch);
  kiwi_main_context_watch_dispatch(watch);
  assert(kiwi_main_context_watch_prepare(watch, 2.0) == 2.0);
  pthread_t producer;
  assert(pthread_create(&producer, NULL, attach_after_delay, &fixture) == 0);
  struct pollfd event = { .fd = events[0], .events = POLLIN };
  assert(poll(&event, 1, 1000) == 1);
  assert(fixture.dispatched == 0); /* The worker must never dispatch callbacks. */
  drain(events[0]);
  kiwi_main_context_watch_dispatch(watch);
  assert(fixture.dispatched == 1);
  assert(pthread_join(producer, NULL) == 0);
  assert(poll(&event, 1, 30) == 0); /* One notification per arm. */

  GSource *timer = g_timeout_source_new(50);
  g_source_set_callback(timer, dispatched, &fixture, NULL);
  g_source_attach(timer, fixture.context);
  double timeout = kiwi_main_context_watch_prepare(watch, 2.0);
  assert(timeout >= 0 && timeout <= 0.050);
  await_dispatch(watch, &fixture, events[0], 2);
  g_source_unref(timer);
  kiwi_main_context_watch_dispatch(watch);
  assert(kiwi_main_context_watch_prepare(watch, 2.0) == 2.0);

  /* Installed sources may exceed the fixed descriptor budget. Fall back
   * without truncating the set or leaving an old, constantly-ready watch. */
  int pipes[66][2];
  GSource *sources[66];
  for (int index = 0; index < 66; ++index) {
    assert(pipe(pipes[index]) == 0);
    sources[index] = g_unix_fd_source_new(pipes[index][0], G_IO_IN);
    g_source_attach(sources[index], fixture.context);
  }
  assert(kiwi_main_context_watch_prepare(watch, 2.0) == 0.050);
  assert(kiwi_main_context_watch_prepare(watch, 0.010) == 0.010);
  for (int index = 0; index < 66; ++index) {
    g_source_destroy(sources[index]);
    g_source_unref(sources[index]);
    close(pipes[index][0]); close(pipes[index][1]);
  }
  kiwi_main_context_watch_dispatch(watch);
  assert(kiwi_main_context_watch_prepare(watch, 2.0) == 2.0);
  kiwi_main_context_watch_destroy(watch);
  for (int index = 0; index < 100; ++index) {
    watch = kiwi_main_context_watch_new(fixture.context, notify, &events[1]);
    assert(watch);
    assert(kiwi_main_context_watch_prepare(watch, 2.0) == 2.0);
    kiwi_main_context_watch_destroy(watch);
  }
  g_main_context_unref(fixture.context);
  close(events[0]); close(events[1]);
  puts("GLib readiness tests passed: cross-thread source wake, UI-only dispatch, timers, one-shot notification, bounded fallback and teardown.");
  return 0;
}
