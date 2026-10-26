#ifndef KIWI_MAIN_CONTEXT_WATCH_H
#define KIWI_MAIN_CONTEXT_WATCH_H
#include <glib.h>

typedef struct KiwiMainContextWatch KiwiMainContextWatch;
KiwiMainContextWatch *kiwi_main_context_watch_new(GMainContext *context,
                                                void (*notify)(void *), void *userdata);
/* Arm descriptor readiness and cap the host wait to GLib's next timer. The
 * worker only notifies; dispatch always runs on the calling UI thread.
 * Prepare, dispatch and destroy must run on the same thread. Prepare retains
 * context ownership until dispatch or destroy, including fallback waits. */
double kiwi_main_context_watch_prepare(KiwiMainContextWatch *watch, double timeout);
void kiwi_main_context_watch_dispatch(KiwiMainContextWatch *watch);
void kiwi_main_context_watch_destroy(KiwiMainContextWatch *watch);
#endif
