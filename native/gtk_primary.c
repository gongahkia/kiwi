#include "gtk_primary.h"
#include <string.h>

struct KiwiGtkPrimaryRead {
  unsigned references;
  int status;
  guint timeout;
  gint64 deadline;
  size_t maximum, length;
  char *text;
  GCancellable *cancellable;
  GInputStream *stream;
};

static unsigned live_requests;
static const char *mime_types[] = { "text/plain;charset=utf-8", "text/plain", NULL };

static void release(KiwiGtkPrimaryRead *read) {
  if (--read->references != 0) return;
  g_assert(read->timeout == 0);
  g_clear_object(&read->stream);
  g_clear_object(&read->cancellable);
  g_free(read->text);
  g_free(read);
  --live_requests;
}

static void finish(KiwiGtkPrimaryRead *read, int status) {
  if (read->status != KIWI_PRIMARY_PENDING) return;
  read->status = status;
  if (read->timeout != 0) { g_source_remove(read->timeout); read->timeout = 0; }
  if (status != KIWI_PRIMARY_READY) g_cancellable_cancel(read->cancellable);
}

static gboolean timeout_read(gpointer userdata) {
  KiwiGtkPrimaryRead *read = userdata;
  read->timeout = 0;
  finish(read, KIWI_PRIMARY_TIMEOUT);
  return G_SOURCE_REMOVE;
}

static void next_chunk(KiwiGtkPrimaryRead *read);

static void chunk_done(GObject *source, GAsyncResult *result, gpointer userdata) {
  KiwiGtkPrimaryRead *read = userdata;
  GError *error = NULL;
  gssize count = g_input_stream_read_finish(G_INPUT_STREAM(source), result, &error);
  if (kiwi_gtk_primary_read_poll(read) == KIWI_PRIMARY_PENDING) {
    if (count < 0) finish(read, KIWI_PRIMARY_UNAVAILABLE);
    else if (count == 0) {
      finish(read, g_utf8_validate(read->text, read->length, NULL) ? KIWI_PRIMARY_READY : KIWI_PRIMARY_INVALID);
    } else {
      size_t previous = read->length;
      read->length += (size_t)count;
      if (read->length > read->maximum) finish(read, KIWI_PRIMARY_OVER_LIMIT);
      else if (memchr(read->text + previous, '\0', (size_t)count) != NULL) finish(read, KIWI_PRIMARY_INVALID);
      else next_chunk(read);
    }
  }
  g_clear_error(&error);
  release(read);
}

static void next_chunk(KiwiGtkPrimaryRead *read) {
  /* One extra byte distinguishes exact-limit EOF from a truncated paste. */
  size_t count = MIN((size_t)8192, read->maximum + 1 - read->length);
  ++read->references;
  g_input_stream_read_async(read->stream, read->text + read->length, count,
    G_PRIORITY_DEFAULT, read->cancellable, chunk_done, read);
}

static void opened(GObject *source, GAsyncResult *result, gpointer userdata) {
  KiwiGtkPrimaryRead *read = userdata;
  GError *error = NULL;
  read->stream = gdk_clipboard_read_finish(GDK_CLIPBOARD(source), result, NULL, &error);
  if (kiwi_gtk_primary_read_poll(read) == KIWI_PRIMARY_PENDING) {
    if (read->stream != NULL) next_chunk(read);
    else finish(read, KIWI_PRIMARY_UNAVAILABLE);
  }
  g_clear_error(&error);
  release(read);
}

KiwiGtkPrimaryRead *kiwi_gtk_primary_read_new(GdkClipboard *clipboard, size_t maximum_bytes, unsigned timeout_ms) {
  if (clipboard == NULL || maximum_bytes == 0 || maximum_bytes > 1024 * 1024 ||
      timeout_ms == 0 || timeout_ms > 1000 || live_requests >= 16) return NULL;
  KiwiGtkPrimaryRead *read = g_new0(KiwiGtkPrimaryRead, 1);
  ++live_requests;
  read->references = 2; /* Caller and asynchronous open. */
  read->maximum = maximum_bytes;
  read->text = g_malloc(maximum_bytes + 1);
  read->cancellable = g_cancellable_new();
  read->deadline = g_get_monotonic_time() + (gint64)timeout_ms * 1000;
  read->timeout = g_timeout_add(timeout_ms, timeout_read, read);
  gdk_clipboard_read_async(clipboard, mime_types, G_PRIORITY_DEFAULT, read->cancellable, opened, read);
  return read;
}

int kiwi_gtk_primary_read_poll(KiwiGtkPrimaryRead *read) {
  if (read == NULL) return KIWI_PRIMARY_UNAVAILABLE;
  if (read->status == KIWI_PRIMARY_PENDING && g_get_monotonic_time() >= read->deadline)
    finish(read, KIWI_PRIMARY_TIMEOUT);
  return read->status;
}

const char *kiwi_gtk_primary_read_text(const KiwiGtkPrimaryRead *read, size_t *bytes) {
  if (read == NULL || bytes == NULL || read->status != KIWI_PRIMARY_READY) return NULL;
  *bytes = read->length;
  return read->text;
}

void kiwi_gtk_primary_read_destroy(KiwiGtkPrimaryRead *read) {
  if (read == NULL) return;
  finish(read, KIWI_PRIMARY_UNAVAILABLE);
  release(read);
}
