#include "gtk_primary.h"
#include <gtk/gtk.h>
#include <string.h>

/* Offer a stream immediately, write a partial UTF-8 sequence, then stall. */
typedef struct { GdkContentProvider parent; } SlowProvider;
typedef struct { GdkContentProviderClass parent; } SlowProviderClass;
G_DEFINE_TYPE(SlowProvider, slow_provider, GDK_TYPE_CONTENT_PROVIDER)
static unsigned partial_writes, completed_writes;

static gboolean slow_complete(gpointer userdata) {
  GTask *task = userdata;
  if (!g_task_return_error_if_cancelled(task)) g_task_return_boolean(task, TRUE);
  ++completed_writes;
  g_object_unref(task);
  return G_SOURCE_REMOVE;
}
static void partial_done(GObject *source, GAsyncResult *result, gpointer userdata) {
  GTask *task = userdata;
  GError *error = NULL;
  gssize count = g_output_stream_write_finish(G_OUTPUT_STREAM(source), result, &error);
  if (count < 0) {
    g_task_return_error(task, error);
    g_object_unref(task);
    ++completed_writes;
  } else {
    ++partial_writes;
    g_timeout_add(100, slow_complete, task);
  }
}
static void slow_write(GdkContentProvider *provider, const char *mime_type, GOutputStream *stream,
                       int priority, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer userdata) {
  (void)mime_type;
  GTask *task = g_task_new(provider, cancellable, callback, userdata);
  g_output_stream_write_async(stream, "\xc3", 1, priority, cancellable, partial_done, task);
}
static gboolean slow_finish(GdkContentProvider *provider, GAsyncResult *result, GError **error) {
  (void)provider;
  return g_task_propagate_boolean(G_TASK(result), error);
}
static GdkContentFormats *slow_formats(GdkContentProvider *provider) {
  (void)provider;
  const char *types[] = { "text/plain;charset=utf-8" };
  return gdk_content_formats_new(types, 1);
}
static void slow_provider_class_init(SlowProviderClass *klass) {
  GdkContentProviderClass *provider = GDK_CONTENT_PROVIDER_CLASS(klass);
  provider->ref_formats = slow_formats;
  provider->write_mime_type_async = slow_write;
  provider->write_mime_type_finish = slow_finish;
}
static void slow_provider_init(SlowProvider *self) { (void)self; }

static int wait_read(KiwiGtkPrimaryRead *read) {
  gint64 deadline = g_get_monotonic_time() + 2000000;
  while (kiwi_gtk_primary_read_poll(read) == KIWI_PRIMARY_PENDING) {
    g_assert_cmpint(g_get_monotonic_time(), <, deadline);
    g_main_context_iteration(NULL, TRUE);
  }
  return kiwi_gtk_primary_read_poll(read);
}

static void offer(GdkClipboard *clipboard, const char *text, size_t bytes) {
  GBytes *data = g_bytes_new(text, bytes);
  GdkContentProvider *provider = gdk_content_provider_new_for_bytes("text/plain;charset=utf-8", data);
  g_assert_true(gdk_clipboard_set_content(clipboard, provider));
  g_object_unref(provider);
  g_bytes_unref(data);
}

static void expect(GdkClipboard *clipboard, const char *text, size_t bytes, size_t maximum, int status) {
  offer(clipboard, text, bytes);
  KiwiGtkPrimaryRead *read = kiwi_gtk_primary_read_new(clipboard, maximum, 1000);
  g_assert_nonnull(read);
  g_assert_cmpint(wait_read(read), ==, status);
  size_t count = 999;
  const char *received = kiwi_gtk_primary_read_text(read, &count);
  if (status == KIWI_PRIMARY_READY) {
    g_assert_nonnull(received);
    g_assert_cmpuint(count, ==, bytes);
    g_assert_cmpmem(received, count, text, bytes);
  } else g_assert_null(received);
  kiwi_gtk_primary_read_destroy(read);
}

int main(void) {
  gtk_init();
  GdkClipboard *clipboard = gdk_display_get_primary_clipboard(gdk_display_get_default());
  expect(clipboard, "", 0, 1, KIWI_PRIMARY_READY);
  expect(clipboard, "hello", 5, 5, KIWI_PRIMARY_READY);
  expect(clipboard, "hello!", 6, 5, KIWI_PRIMARY_OVER_LIMIT);
  expect(clipboard, "a\0b", 3, 4, KIWI_PRIMARY_INVALID);
  expect(clipboard, "\xc3", 1, 4, KIWI_PRIMARY_INVALID);
  expect(clipboard, "\xc0\xaf", 2, 4, KIWI_PRIMARY_INVALID);
  char *large = g_malloc0(1024 * 1024 + 1);
  memset(large, 'x', 1024 * 1024 + 1);
  /* A UTF-8 code point crosses the 8 KiB chunk boundary. */
  large[8191] = '\xc3'; large[8192] = '\xa9';
  expect(clipboard, large, 1024 * 1024, 1024 * 1024, KIWI_PRIMARY_READY);
  expect(clipboard, large, 1024 * 1024 + 1, 1024 * 1024, KIWI_PRIMARY_OVER_LIMIT);
  g_free(large);
  g_assert_null(kiwi_gtk_primary_read_new(clipboard, 0, 1000));
  g_assert_null(kiwi_gtk_primary_read_new(clipboard, 1024 * 1024 + 1, 1000));
  g_assert_null(kiwi_gtk_primary_read_new(clipboard, 1, 0));
  g_assert_null(kiwi_gtk_primary_read_new(clipboard, 1, 1001));

  offer(clipboard, "ready", 5);
  KiwiGtkPrimaryRead *reads[16];
  for (unsigned i = 0; i < 16; ++i) {
    reads[i] = kiwi_gtk_primary_read_new(clipboard, 1024, 1000);
    g_assert_nonnull(reads[i]);
  }
  g_assert_null(kiwi_gtk_primary_read_new(clipboard, 1024, 1000));
  for (unsigned i = 0; i < 16; ++i) kiwi_gtk_primary_read_destroy(reads[i]);
  /* Detached callbacks retain their slots until they have actually finished. */
  g_assert_null(kiwi_gtk_primary_read_new(clipboard, 1024, 1000));
  for (unsigned i = 0; i < 100; ++i) {
    while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);
    g_usleep(1000);
  }
  expect(clipboard, "recovered", 9, 9, KIWI_PRIMARY_READY);

  KiwiGtkPrimaryRead *timed = kiwi_gtk_primary_read_new(clipboard, 16, 1);
  g_assert_nonnull(timed);
  g_usleep(5000); /* Also enforce deadlines when dispatch has been delayed. */
  g_assert_cmpint(kiwi_gtk_primary_read_poll(timed), ==, KIWI_PRIMARY_TIMEOUT);
  kiwi_gtk_primary_read_destroy(timed);
  while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);

  GdkContentProvider *slow = g_object_new(slow_provider_get_type(), NULL);
  g_assert_true(gdk_clipboard_set_content(clipboard, slow));
  g_object_unref(slow);
  timed = kiwi_gtk_primary_read_new(clipboard, 1024, 30);
  g_assert_cmpint(wait_read(timed), ==, KIWI_PRIMARY_TIMEOUT);
  g_assert_cmpuint(partial_writes, ==, 1);
  kiwi_gtk_primary_read_destroy(timed);
  KiwiGtkPrimaryRead *cancelled = kiwi_gtk_primary_read_new(clipboard, 1024, 1000);
  gint64 deadline = g_get_monotonic_time() + 1000000;
  while (partial_writes < 2) {
    g_assert_cmpint(g_get_monotonic_time(), <, deadline);
    g_main_context_iteration(NULL, TRUE);
  }
  kiwi_gtk_primary_read_destroy(cancelled);
  while (completed_writes < 2) {
    g_assert_cmpint(g_get_monotonic_time(), <, deadline);
    g_main_context_iteration(NULL, TRUE);
  }
  expect(clipboard, "after-stall", 11, 11, KIWI_PRIMARY_READY);
  g_print("GTK PRIMARY passed: exact limits, multichunk UTF-8, invalid data, cancellation before/after stream open, stalled-owner deadlines and request capacity.\n");
  return 0;
}
