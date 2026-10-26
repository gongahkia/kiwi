#ifndef KIWI_CHILD_WATCH_H
#define KIWI_CHILD_WATCH_H

/* A pollable, close-on-exec exit notification for an unreaped direct child.
 * The caller owns the returned descriptor and must still reap with waitpid.
 * No data should be read from this descriptor. -1 means use timed reaping;
 * this can occur on older kernels, resource exhaustion or an exit race. */
int kiwi_child_watch_open(int pid);

#endif
