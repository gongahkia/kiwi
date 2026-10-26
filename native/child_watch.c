#define _GNU_SOURCE
#include "child_watch.h"
#include <errno.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#elif defined(__APPLE__)
#include <fcntl.h>
#include <sys/event.h>
#endif

int kiwi_child_watch_open(int pid) {
  if (pid <= 0) { errno = EINVAL; return -1; }
#if defined(__linux__) && defined(SYS_pidfd_open)
  return (int)syscall(SYS_pidfd_open, pid, 0);
#elif defined(__APPLE__)
  int fd = kqueue();
  if (fd < 0) return -1;
  struct kevent event;
  EV_SET(&event, (uintptr_t)pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
  if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 || kevent(fd, &event, 1, NULL, 0, NULL) < 0) {
    int saved_errno = errno;
    close(fd);
    errno = saved_errno;
    return -1;
  }
  return fd;
#else
  errno = ENOSYS;
  return -1;
#endif
}
