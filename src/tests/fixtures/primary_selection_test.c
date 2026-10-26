#define _POSIX_C_SOURCE 200809L
#include "primary_selection.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(__linux__)
#include <X11/Xlib.h>
#include <X11/Xatom.h>
enum { DIRECT, LATIN1, INCREMENTAL, STALL, BAD_TYPE, NUL_TEXT, BAD_INCR, OVERSIZED_INCR };
typedef struct {
  Display *display;
  Window window, requestor;
  Atom utf8, incr, property, target;
  int mode, requests, chunks, active;
  const char *text;
  size_t length, offset, chunk;
} Owner;
static void tick(void) { const struct timespec delay = {0, 1000000}; nanosleep(&delay, NULL); }
static void serve(Owner *owner) {
  while (XPending(owner->display)) {
    XEvent event;
    XNextEvent(owner->display, &event);
    if (event.type == SelectionRequest) {
      XSelectionRequestEvent *request = &event.xselectionrequest;
      assert(request->selection == XA_PRIMARY);
      owner->requests++;
      if (owner->mode == STALL) continue;
      XEvent reply = {0};
      reply.xselection.type = SelectionNotify;
      reply.xselection.display = request->display;
      reply.xselection.requestor = request->requestor;
      reply.xselection.selection = request->selection;
      reply.xselection.target = request->target;
      reply.xselection.time = request->time;
      if (request->target == (owner->mode == LATIN1 ? XA_STRING : owner->utf8)) {
        reply.xselection.property = request->property;
        if (owner->mode == INCREMENTAL || owner->mode == BAD_INCR || owner->mode == OVERSIZED_INCR) {
          unsigned long hint = owner->mode == OVERSIZED_INCR ? 2 * 1024 * 1024 : 0;
          owner->requestor = request->requestor; owner->property = request->property;
          owner->target = request->target; owner->active = 1;
          XSelectInput(owner->display, request->requestor, PropertyChangeMask);
          XChangeProperty(owner->display, request->requestor, request->property, owner->incr,
            owner->mode == BAD_INCR ? 8 : 32, PropModeReplace, (unsigned char *)&hint, 1);
        } else {
          Atom type = owner->mode == BAD_TYPE ? XA_INTEGER : request->target;
          XChangeProperty(owner->display, request->requestor, request->property, type, 8,
            PropModeReplace, (const unsigned char *)owner->text, (int)owner->length);
        }
      }
      XSendEvent(owner->display, request->requestor, False, 0, &reply);
      XFlush(owner->display);
    } else if (event.type == PropertyNotify && event.xproperty.window == owner->requestor &&
               event.xproperty.atom == owner->property && event.xproperty.state == PropertyDelete && owner->active) {
      size_t remaining = owner->length - owner->offset;
      size_t count = remaining < owner->chunk ? remaining : owner->chunk;
      XChangeProperty(owner->display, owner->requestor, owner->property, owner->target, 8,
        PropModeReplace, (const unsigned char *)owner->text + owner->offset, (int)count);
      owner->offset += count; owner->chunks++;
      if (count == 0) owner->active = 0;
      XFlush(owner->display);
    }
  }
}
static void run_case(int mode, const char *text, size_t length, size_t maximum, int expected,
                     const char *expected_text, size_t expected_length) {
  Owner owner = {0};
  owner.display = XOpenDisplay(NULL); assert(owner.display != NULL);
  owner.window = XCreateSimpleWindow(owner.display, DefaultRootWindow(owner.display), 0, 0, 1, 1, 0, 0, 0);
  owner.utf8 = XInternAtom(owner.display, "UTF8_STRING", False);
  owner.incr = XInternAtom(owner.display, "INCR", False);
  owner.mode = mode; owner.text = text; owner.length = length; owner.chunk = 70000;
  XSetSelectionOwner(owner.display, XA_PRIMARY, owner.window, CurrentTime);
  assert(XGetSelectionOwner(owner.display, XA_PRIMARY) == owner.window);
  Atom clipboard = XInternAtom(owner.display, "CLIPBOARD", False);
  XSetSelectionOwner(owner.display, clipboard, owner.window, CurrentTime);
  XSync(owner.display, False);
  KiwiPrimaryRead *read = kiwi_primary_read_new(DisplayString(owner.display), maximum, mode == STALL ? 30 : 1000);
  assert(read != NULL);
  size_t bytes = 999;
  assert(kiwi_primary_read_text(read, &bytes) == NULL && bytes == 999);
  int status = 0, polls = 0;
  while (status == KIWI_PRIMARY_PENDING && polls++ < 2000) {
    serve(&owner);
    status = kiwi_primary_read_poll(read);
    if (status == KIWI_PRIMARY_PENDING) tick();
  }
  if (status != expected) fprintf(stderr, "mode=%d length=%zu maximum=%zu expected=%d actual=%d polls=%d\n", mode, length, maximum, expected, status, polls);
  assert(status == expected);
  assert(kiwi_primary_read_poll(read) == expected);
  const char *actual = kiwi_primary_read_text(read, &bytes);
  if (expected == KIWI_PRIMARY_READY) {
    assert(actual != NULL && bytes == expected_length && memcmp(actual, expected_text, bytes) == 0 && actual[bytes] == '\0');
    if (mode == INCREMENTAL) assert(owner.chunks >= (length == 0 ? 1 : 2));
    if (length > 65536) assert(polls >= 2);
  } else assert(actual == NULL);
  assert(XGetSelectionOwner(owner.display, clipboard) == owner.window);
  if (mode == LATIN1) assert(owner.requests == 2);
  kiwi_primary_read_destroy(read);
  XDestroyWindow(owner.display, owner.window);
  XCloseDisplay(owner.display);
}
int main(void) {
  /* Keep the isolated server alive between cases; otherwise Xvfb resets when
   * its last client disconnects while the next case is opening its display. */
  Display *keeper = XOpenDisplay(NULL); assert(keeper != NULL);
  assert(kiwi_primary_read_new(NULL, 0, 1) == NULL);
  assert(kiwi_primary_read_new(NULL, 1024 * 1024 + 1, 1) == NULL);
  assert(kiwi_primary_read_new(NULL, 10, 0) == NULL);
  assert(kiwi_primary_read_new(NULL, 10, 5001) == NULL);
  const char unicode[] = "hello \xe4\xb8\xad\xf0\x9f\xa5\x9d";
  run_case(DIRECT, unicode, sizeof(unicode)-1, 1024, KIWI_PRIMARY_READY, unicode, sizeof(unicode)-1);
  run_case(DIRECT, "", 0, 1, KIWI_PRIMARY_READY, "", 0);
  run_case(DIRECT, "abcd", 4, 4, KIWI_PRIMARY_READY, "abcd", 4);
  run_case(DIRECT, "abcde", 5, 4, KIWI_PRIMARY_OVER_LIMIT, NULL, 0);
  run_case(LATIN1, "caf\xe9", 4, 5, KIWI_PRIMARY_READY, "caf\xc3\xa9", 5);
  run_case(LATIN1, "caf\xe9", 4, 4, KIWI_PRIMARY_OVER_LIMIT, NULL, 0);
  run_case(STALL, "", 0, 10, KIWI_PRIMARY_TIMEOUT, NULL, 0);
  run_case(BAD_TYPE, "bad", 3, 10, KIWI_PRIMARY_INVALID, NULL, 0);
  run_case(NUL_TEXT, "a\0b", 3, 10, KIWI_PRIMARY_INVALID, NULL, 0);
  run_case(BAD_INCR, "abc", 3, 10, KIWI_PRIMARY_INVALID, NULL, 0);
  run_case(OVERSIZED_INCR, "abc", 3, 10, KIWI_PRIMARY_OVER_LIMIT, NULL, 0);
  char *large = malloc(1024 * 1024); assert(large != NULL); memset(large, 'x', 1024 * 1024);
  run_case(DIRECT, large, 200000, 200000, KIWI_PRIMARY_READY, large, 200000);
  run_case(INCREMENTAL, large, 1024 * 1024, 1024 * 1024, KIWI_PRIMARY_READY, large, 1024 * 1024);
  run_case(INCREMENTAL, large, 200000, 100000, KIWI_PRIMARY_OVER_LIMIT, NULL, 0);
  run_case(INCREMENTAL, "", 0, 10, KIWI_PRIMARY_READY, "", 0);
  free(large);
  for (int index = 0; index < 50; ++index) {
    KiwiPrimaryRead *read = kiwi_primary_read_new(NULL, 1024, 1000);
    assert(read != NULL); kiwi_primary_read_destroy(read);
  }
  KiwiPrimaryRead *empty = kiwi_primary_read_new(NULL, 1024, 1000);
  int status = 0;
  for (int index = 0; index < 2000 && status == 0; ++index) { status = kiwi_primary_read_poll(empty); tick(); }
  assert(status == KIWI_PRIMARY_UNAVAILABLE);
  kiwi_primary_read_destroy(empty);
  XCloseDisplay(keeper);
  puts("Primary selection native tests passed: UTF-8, Latin-1 fallback, INCR, exact/over limits, stalled owner, malformed data, cancellation and clipboard isolation.");
  return 0;
}
#else
int main(void) {
  assert(kiwi_primary_read_new(NULL, 1024, 1000) == NULL);
  assert(kiwi_primary_read_poll(NULL) == KIWI_PRIMARY_UNAVAILABLE);
  size_t bytes = 0; assert(kiwi_primary_read_text(NULL, &bytes) == NULL);
  kiwi_primary_read_destroy(NULL);
  puts("Primary selection unsupported-platform contract passed.");
  return 0;
}
#endif
