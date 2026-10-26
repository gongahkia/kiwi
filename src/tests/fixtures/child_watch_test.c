#define _POSIX_C_SOURCE 200809L
#include "child_watch.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

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
    /* Darwin may reject attaching a process filter to an already-exited
     * child. The timed-reaping fallback must be able to reap it immediately. */
    assert(errno == ESRCH);
    assert(waitpid(pid, &status, WNOHANG) == pid);
  }
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 9);
}

int main(void) {
  assert(kiwi_child_watch_open(0) == -1 && errno == EINVAL);
  assert(kiwi_child_watch_open(-1) == -1 && errno == EINVAL);
  int baseline = open_count();
  gated_exit();
  for (int i = 0; i < 100; ++i) immediate_exit();
  assert(open_count() == baseline);
  puts("Child readiness tests passed: closed streams, exit status, rapid exits, close-on-exec and descriptor cleanup.");
  return 0;
}
