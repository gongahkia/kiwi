#define _POSIX_C_SOURCE 200809L
#include "pty_watch.h"
#include <assert.h>
#include <errno.h>
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
  assert(!kiwi_pty_watch_update(watch, terminal, 130));
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

  /* Writable readiness is opt-in: full input buffers must wake after their
   * reader drains, without waiting for terminal output or a fallback timer. */
  int blocked[2];
  assert(pipe(blocked) == 0);
  for (int i = 0; i < 2; ++i) {
    int flags = fcntl(blocked[i], F_GETFL);
    assert(flags >= 0 && fcntl(blocked[i], F_SETFL, flags | O_NONBLOCK) == 0);
  }
  char buffer[4096] = {0};
  size_t filled = 0;
  ssize_t written;
  while ((written = write(blocked[1], buffer, sizeof(buffer))) > 0) {
    filled += (size_t)written;
    assert(filled <= 1024 * 1024);
  }
  assert(errno == EAGAIN && filled > 0);
  uint8_t interest = 0;
  assert(!kiwi_pty_watch_update_events(watch, &blocked[1], &interest, 1));
  interest = 4;
  assert(!kiwi_pty_watch_update_events(watch, &blocked[1], &interest, 1));
  assert(!kiwi_pty_watch_update_events(watch, &blocked[1], NULL, 1));
  interest = KIWI_WATCH_WRITE;
  assert(kiwi_pty_watch_update_events(watch, &blocked[1], &interest, 1));
  assert(!readable(events[0], 30));
  while (read(blocked[0], buffer, sizeof(buffer)) > 0) {}
  assert(errno == EAGAIN);
  receive(events[0]);
  assert(!readable(events[0], 30));
  interest = KIWI_WATCH_READ;
  assert(kiwi_pty_watch_update_events(watch, &blocked[1], &interest, 1));
  assert(!readable(events[0], 30));
  assert(kiwi_pty_watch_update(watch, NULL, 0));
  kiwi_pty_watch_destroy(watch);
  close(blocked[0]); close(blocked[1]);

  /* Exercise repeated creation, arming and teardown while worker polls. */
  for (int i = 0; i < 100; ++i) {
    watch = kiwi_pty_watch_create(notify, &events[1]);
    assert(watch && kiwi_pty_watch_update(watch, terminal, 1));
    kiwi_pty_watch_destroy(watch);
  }
  close(terminal[0]); close(terminal[1]); close(other[0]);
  close(events[0]); close(events[1]);
  puts("PTY readiness tests passed: one-shot read/write wake, backpressure, rearm, replacement, EOF, bounded input, shutdown.");
  return 0;
}
