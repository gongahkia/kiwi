#define _POSIX_C_SOURCE 200809L
#include "pty_watch.h"
#include <assert.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <unistd.h>

static void notify(void *userdata) {
  int fd = *(int *)userdata;
  assert(write(fd, "!", 1) == 1);
}

static int readable(int fd, int milliseconds) {
  struct pollfd event = { .fd = fd, .events = POLLIN };
  int result = poll(&event, 1, milliseconds);
  assert(result >= 0);
  return result > 0;
}

static void receive(int fd) {
  assert(readable(fd, 1000));
  char byte;
  assert(read(fd, &byte, 1) == 1 && byte == '!');
}

int main(void) {
  int terminal[2], other[2], events[2];
  assert(pipe(terminal) == 0 && pipe(other) == 0 && pipe(events) == 0);
  KiwiPtyWatch *watch = kiwi_pty_watch_create(notify, &events[1]);
  assert(watch);
  assert(!kiwi_pty_watch_update(watch, NULL, 1));
  assert(!kiwi_pty_watch_update(watch, terminal, 66));
  int invalid = -1;
  assert(!kiwi_pty_watch_update(watch, &invalid, 1));
  assert(kiwi_pty_watch_update(watch, terminal, 1));
  assert(!readable(events[0], 20));
  assert(write(terminal[1], "x", 1) == 1);
  receive(events[0]);
  /* It must not consume output or flood events while unread bytes remain. */
  assert(readable(terminal[0], 0));
  assert(!readable(events[0], 30));
  assert(kiwi_pty_watch_update(watch, terminal, 1));
  receive(events[0]);
  assert(!readable(events[0], 30));
  char byte;
  assert(read(terminal[0], &byte, 1) == 1 && byte == 'x');

  /* Replacement is synchronized by the next readiness notification. */
  assert(kiwi_pty_watch_update(watch, other, 1));
  assert(write(other[1], "y", 1) == 1);
  receive(events[0]);
  assert(read(other[0], &byte, 1) == 1 && byte == 'y');
  assert(kiwi_pty_watch_update(watch, other, 1));
  assert(write(terminal[1], "z", 1) == 1);
  assert(!readable(events[0], 30));
  close(other[1]);
  receive(events[0]); /* EOF wakes the host so it can reap the child. */
  assert(!readable(events[0], 30));
  assert(kiwi_pty_watch_update(watch, NULL, 0));
  kiwi_pty_watch_destroy(watch);

  /* Exercise repeated creation, arming and teardown while worker polls. */
  for (int i = 0; i < 100; ++i) {
    watch = kiwi_pty_watch_create(notify, &events[1]);
    assert(watch && kiwi_pty_watch_update(watch, terminal, 1));
    kiwi_pty_watch_destroy(watch);
  }
  close(terminal[0]); close(terminal[1]); close(other[0]);
  close(events[0]); close(events[1]);
  puts("PTY readiness tests passed: one-shot wake, rearm, replacement, EOF, bounded input, shutdown.");
  return 0;
}
