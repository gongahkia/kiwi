#define _POSIX_C_SOURCE 200809L
#include "primary_selection.h"
#include <stdlib.h>
#include <string.h>
#if defined(__linux__)
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <time.h>

struct KiwiPrimaryRead {
  Display *display;
  Window window;
  Atom utf8, incr, property, target;
  char *text;
  size_t maximum, length;
  long offset;
  double deadline;
  int status, incremental, reading;
};
static double now_seconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}
void kiwi_primary_read_destroy(KiwiPrimaryRead *read) {
  if (read == NULL) return;
  if (read->display != NULL) {
    if (read->window != None) XDestroyWindow(read->display, read->window);
    XCloseDisplay(read->display);
  }
  free(read->text);
  free(read);
}
KiwiPrimaryRead *kiwi_primary_read_new(const char *display_name, size_t maximum_bytes, unsigned timeout_ms) {
  if (maximum_bytes == 0 || maximum_bytes > 1024 * 1024 || timeout_ms == 0 || timeout_ms > 5000) return NULL;
  KiwiPrimaryRead *read = calloc(1, sizeof(*read));
  if (read == NULL) return NULL;
  read->maximum = maximum_bytes;
  read->text = malloc(maximum_bytes + 1);
  read->display = XOpenDisplay(display_name);
  if (read->text == NULL || read->display == NULL) { kiwi_primary_read_destroy(read); return NULL; }
  read->window = XCreateSimpleWindow(read->display, DefaultRootWindow(read->display), 0, 0, 1, 1, 0, 0, 0);
  XSelectInput(read->display, read->window, PropertyChangeMask);
  read->utf8 = XInternAtom(read->display, "UTF8_STRING", False);
  read->incr = XInternAtom(read->display, "INCR", False);
  read->property = XInternAtom(read->display, "KIWI_PRIMARY_READ", False);
  read->target = read->utf8;
  read->deadline = now_seconds() + (double)timeout_ms / 1000.0;
  XConvertSelection(read->display, XA_PRIMARY, read->target, read->property, read->window, CurrentTime);
  XFlush(read->display);
  return read;
}
static int read_property(KiwiPrimaryRead *read) {
  Atom type;
  int format;
  unsigned long count, after;
  unsigned char *data = NULL;
  /* The extra byte detects overflow without accepting a truncated prefix. */
  size_t remaining = read->maximum - read->length;
  long words = (long)((remaining + 4) / 4);
  if (words > 16384) words = 16384;
  int result = XGetWindowProperty(read->display, read->window, read->property,
    read->offset, words, True, AnyPropertyType, &type, &format, &count, &after, &data);
  if (result != Success || type == None) { read->status = KIWI_PRIMARY_INVALID; goto done; }
  if (type == read->incr && !read->incremental && read->offset == 0 && read->length == 0) {
    if (format != 32 || count != 1 || after != 0) read->status = KIWI_PRIMARY_INVALID;
    else if (*(unsigned long *)data > read->maximum) read->status = KIWI_PRIMARY_OVER_LIMIT;
    else { read->incremental = 1; read->reading = 0; }
    goto done;
  }
  if (type != read->target || format != 8) { read->status = KIWI_PRIMARY_INVALID; goto done; }
  for (unsigned long index = 0; index < count; ++index) {
    unsigned char byte = data[index];
    size_t needed = read->target == XA_STRING && byte >= 128 ? 2 : 1;
    if (byte == 0) { read->status = KIWI_PRIMARY_INVALID; goto done; }
    if (needed > read->maximum - read->length) { read->status = KIWI_PRIMARY_OVER_LIMIT; goto done; }
    if (needed == 2) {
      read->text[read->length++] = (char)(0xc0 | (byte >> 6));
      read->text[read->length++] = (char)(0x80 | (byte & 0x3f));
    } else read->text[read->length++] = (char)byte;
  }
  if (after != 0) {
    if (read->length == read->maximum) read->status = KIWI_PRIMARY_OVER_LIMIT;
    else if (count == 0 || count % 4 != 0) read->status = KIWI_PRIMARY_INVALID;
    else read->offset += (long)(count / 4);
  } else {
    read->reading = 0;
    if (!read->incremental || (count == 0 && read->offset == 0)) {
      read->text[read->length] = '\0';
      read->status = KIWI_PRIMARY_READY;
    }
    read->offset = 0;
  }
done:
  if (data != NULL) XFree(data);
  XFlush(read->display);
  return read->status;
}
int kiwi_primary_read_poll(KiwiPrimaryRead *read) {
  if (read == NULL) return KIWI_PRIMARY_UNAVAILABLE;
  if (read->status != KIWI_PRIMARY_PENDING) return read->status;
  if (now_seconds() >= read->deadline) return read->status = KIWI_PRIMARY_TIMEOUT;
  if (read->reading) return read_property(read);
  for (int count = 0; count < 32 && XPending(read->display); ++count) {
    XEvent event;
    XNextEvent(read->display, &event);
    if (event.type == SelectionNotify && event.xselection.requestor == read->window &&
        event.xselection.selection == XA_PRIMARY && event.xselection.target == read->target && !read->incremental) {
      if (event.xselection.property == None) {
        if (read->target == read->utf8) {
          read->target = XA_STRING;
          XConvertSelection(read->display, XA_PRIMARY, read->target, read->property, read->window, CurrentTime);
          XFlush(read->display);
        } else return read->status = KIWI_PRIMARY_UNAVAILABLE;
      } else if (event.xselection.property == read->property) {
        read->reading = 1;
        return read_property(read);
      }
    } else if (event.type == PropertyNotify && event.xproperty.window == read->window &&
               event.xproperty.atom == read->property && event.xproperty.state == PropertyNewValue && read->incremental) {
      read->reading = 1;
      return read_property(read);
    }
  }
  return read->status;
}
const char *kiwi_primary_read_text(const KiwiPrimaryRead *read, size_t *bytes) {
  if (read == NULL || bytes == NULL || read->status != KIWI_PRIMARY_READY) return NULL;
  *bytes = read->length;
  return read->text;
}
#else
struct KiwiPrimaryRead { int unused; };
KiwiPrimaryRead *kiwi_primary_read_new(const char *name, size_t maximum, unsigned timeout) {
  (void)name; (void)maximum; (void)timeout; return NULL;
}
int kiwi_primary_read_poll(KiwiPrimaryRead *read) { (void)read; return KIWI_PRIMARY_UNAVAILABLE; }
const char *kiwi_primary_read_text(const KiwiPrimaryRead *read, size_t *bytes) { (void)read; (void)bytes; return NULL; }
void kiwi_primary_read_destroy(KiwiPrimaryRead *read) { (void)read; }
#endif
