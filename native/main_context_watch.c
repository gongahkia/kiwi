#include "main_context_watch.h"
#include "pty_watch.h"

#define KIWI_CONTEXT_MAX_FDS 65
#define KIWI_CONTEXT_FALLBACK_SECONDS 0.050

struct KiwiMainContextWatch {
  GMainContext *context;
  KiwiPtyWatch *readiness;
  gboolean acquired;
};

KiwiMainContextWatch *kiwi_main_context_watch_new(GMainContext *context,
                                                void (*notify)(void *), void *userdata) {
  if (context == NULL || notify == NULL) return NULL;
  KiwiMainContextWatch *watch = g_try_new0(KiwiMainContextWatch, 1);
  if (watch == NULL) return NULL;
  watch->readiness = kiwi_pty_watch_create(notify, userdata);
  if (watch->readiness == NULL) { g_free(watch); return NULL; }
  watch->context = g_main_context_ref(context);
  return watch;
}

static double fallback(KiwiMainContextWatch *watch, double timeout) {
  if (watch != NULL) kiwi_pty_watch_update(watch->readiness, NULL, 0);
  return MIN(timeout, KIWI_CONTEXT_FALLBACK_SECONDS);
}

double kiwi_main_context_watch_prepare(KiwiMainContextWatch *watch, double timeout) {
  if (watch == NULL) return fallback(watch, timeout);
  if (!watch->acquired) {
    if (!g_main_context_acquire(watch->context)) return fallback(watch, timeout);
    watch->acquired = TRUE;
  }
  gint priority = G_MAXINT, milliseconds = -1;
  gboolean ready = g_main_context_prepare(watch->context, &priority);
  GPollFD records[KIWI_CONTEXT_MAX_FDS];
  gint count = g_main_context_query(watch->context, priority, &milliseconds,
                                    records, KIWI_CONTEXT_MAX_FDS);
  /* Keep ownership across the host wait. GLib uses the context owner to
   * decide whether a source attached by another thread must signal wakeup. */
  if (count < 0 || count > KIWI_CONTEXT_MAX_FDS) return fallback(watch, timeout);
  int fds[KIWI_CONTEXT_MAX_FDS];
  uint8_t interests[KIWI_CONTEXT_MAX_FDS];
  size_t used = 0;
  for (gint index = 0; index < count; ++index) {
    if (records[index].fd < 0) continue;
    /* Exceptional/hangup readiness is always reported by poll. Unusual
     * priority-only sources retain the bounded fallback instead of spinning. */
    if ((records[index].events & ~(G_IO_IN | G_IO_OUT | G_IO_ERR | G_IO_HUP | G_IO_NVAL)) != 0)
      return fallback(watch, timeout);
    uint8_t interest = ((records[index].events & G_IO_IN) ? KIWI_WATCH_READ : 0) |
                        ((records[index].events & G_IO_OUT) ? KIWI_WATCH_WRITE : 0);
    if (interest == 0) return fallback(watch, timeout);
    fds[used] = records[index].fd;
    interests[used++] = interest;
  }
  if (!kiwi_pty_watch_update_events(watch->readiness, fds, interests, used)) return fallback(watch, timeout);
  if (ready) return 0;
  if (milliseconds >= 0) timeout = MIN(timeout, milliseconds / 1000.0);
  return timeout;
}

void kiwi_main_context_watch_dispatch(KiwiMainContextWatch *watch) {
  GMainContext *context = watch != NULL ? watch->context : g_main_context_default();
  /* Readiness is a hint. GLib re-queries and checks its own records, including
   * source changes since prepare(), before dispatching on this thread. */
  for (int iteration = 0; iteration < 32 && g_main_context_pending(context); ++iteration)
    g_main_context_iteration(context, FALSE);
  if (watch != NULL && watch->acquired) {
    watch->acquired = FALSE;
    g_main_context_release(context);
  }
}

void kiwi_main_context_watch_destroy(KiwiMainContextWatch *watch) {
  if (watch == NULL) return;
  kiwi_pty_watch_destroy(watch->readiness);
  if (watch->acquired) g_main_context_release(watch->context);
  g_main_context_unref(watch->context);
  g_free(watch);
}
