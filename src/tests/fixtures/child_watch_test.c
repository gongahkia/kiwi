#define _POSIX_C_SOURCE 200809L
#include "child_watch.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double monotonic_seconds(void) {
  struct timespec now;
  assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
  return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}

static void reap_with_deadline(int pid, int *status) {
  double deadline = monotonic_seconds() + 1.5;
  for (;;) {
    int result = waitpid(pid, status, WNOHANG);
    if (result == pid) return;
    assert(result == 0 || (result == -1 && errno == EINTR));
    assert(monotonic_seconds() < deadline);
    /* Like PollSchedule's no-exit-descriptor fallback, retry without assuming
     * that process-filter rejection means waitpid can already reap a zombie. */
    int waited = poll(NULL, 0, 10);
    assert(waited == 0 || (waited == -1 && errno == EINTR));
  }
}

static void delayed_reap(void) {
  int gate[2];
  assert(pipe(gate) == 0);
  int pid = fork();
  assert(pid >= 0);
  if (pid == 0) {
    close(gate[1]);
    char byte;
    if (read(gate[0], &byte, 1) != 1) _exit(8);
    poll(NULL, 0, 30);
    _exit(11);
  }
  close(gate[0]);
  int status;
  assert(waitpid(pid, &status, WNOHANG) == 0);
  assert(write(gate[1], "x", 1) == 1);
  close(gate[1]);
  reap_with_deadline(pid, &status);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 11);
}

static int open_count(void) {
  int count = 0;
  for (int fd = 0; fd < 1024; ++fd) if (fcntl(fd, F_GETFD) >= 0) ++count;
  return count;
}

static void gated_exit(void) {
  int gate[2];
  assert(pipe(gate) == 0);
  int pid = fork();
  assert(pid >= 0);
  if (pid == 0) {
    close(gate[1]);
    close(0); close(1); close(2);
    char byte;
    _exit(read(gate[0], &byte, 1) == 1 ? 7 : 8);
  }
  close(gate[0]);
  int fd = kiwi_child_watch_open(pid);
  assert(fd >= 0);
  assert(fcntl(fd, F_GETFD) & FD_CLOEXEC);
  struct pollfd ready = { .fd = fd, .events = POLLIN };
  assert(poll(&ready, 1, 10) == 0);
  assert(write(gate[1], "x", 1) == 1);
  close(gate[1]);
  assert(poll(&ready, 1, 1500) == 1);
  assert(ready.revents & POLLIN);
  int status;
  assert(waitpid(pid, &status, 0) == pid);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 7);
  close(fd);
}

static void immediate_exit(void) {
  int pid = fork();
  assert(pid >= 0);
  if (pid == 0) _exit(9);
  int fd = kiwi_child_watch_open(pid);
  int status;
  if (fd >= 0) {
    struct pollfd ready = { .fd = fd, .events = POLLIN };
    assert(poll(&ready, 1, 1500) == 1);
    assert(ready.revents & POLLIN);
    assert(waitpid(pid, &status, 0) == pid);
    close(fd);
  } else {
    /* Darwin can reject process-filter attachment while a child is exiting,
     * before waitpid can reap it. Exercise the bounded reaping fallback. */
    assert(errno == ESRCH);
    reap_with_deadline(pid, &status);
  }
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 9);
}

int main(void) {
  assert(kiwi_child_watch_open(0) == -1 && errno == EINVAL);
  assert(kiwi_child_watch_open(-1) == -1 && errno == EINVAL);
  int baseline = open_count();
  gated_exit();
  delayed_reap();
  for (int i = 0; i < 100; ++i) immediate_exit();
  assert(open_count() == baseline);
  puts("Child readiness tests passed: closed streams, exit status, rapid exits, close-on-exec and descriptor cleanup.");
  return 0;
}
