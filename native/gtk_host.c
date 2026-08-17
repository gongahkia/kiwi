#include <gtk/gtk.h>
#include <gdk/wayland/gdkwayland.h>
#include <gdk/x11/gdkx.h>
#include <webgpu/webgpu.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct KiwiGtkHost KiwiGtkHost;

typedef uint32_t (*KiwiGtkKeyCallback)(void *userdata, uint32_t keyval, uint32_t modifiers, int action);
typedef void (*KiwiGtkTextCallback)(void *userdata, uint32_t codepoint);
typedef void (*KiwiGtkPointerCallback)(void *userdata, int kind, double x, double y, double dx, double dy, uint32_t button, int action, uint32_t modifiers);
typedef void (*KiwiGtkFocusCallback)(void *userdata, int focused);
typedef void (*KiwiGtkResizeCallback)(void *userdata, int width, int height, double scale);

typedef struct KiwiGtkCallbacks {
  KiwiGtkFocusCallback focus;
  KiwiGtkKeyCallback key;
  KiwiGtkPointerCallback pointer;
  KiwiGtkResizeCallback resize;
  KiwiGtkTextCallback text;
  void *userdata;
} KiwiGtkCallbacks;

struct KiwiGtkHost {
  GtkApplication *application;
  GtkWidget *window;
  GtkWidget *content;
  KiwiGtkCallbacks callbacks;
  GdkSurface *surface;
  int should_close;
};

typedef struct KiwiGtkClipboardRead {
  GCancellable *cancellable;
  GError *error;
  GMainLoop *loop;
  char *text;
  guint timeout_id;
} KiwiGtkClipboardRead;

static char kiwi_gtk_error[1024];

enum {
  KIWI_GTK_ACTION_PRESS = 1,
  KIWI_GTK_ACTION_RELEASE = 0,
  KIWI_GTK_INPUT_HANDLED = 1,
  KIWI_GTK_INPUT_SUPPRESS_TEXT = 2,
  KIWI_GTK_POINTER_MOTION = 1,
  KIWI_GTK_POINTER_BUTTON = 2,
  KIWI_GTK_POINTER_SCROLL = 3,
};

static void kiwi_gtk_set_error(const char *message) {
  snprintf(kiwi_gtk_error, sizeof(kiwi_gtk_error), "%s", message == NULL ? "unknown GTK host error" : message);
}

static uint32_t kiwi_gtk_modifiers(GdkModifierType state) {
  uint32_t result = 0;
  if ((state & GDK_SHIFT_MASK) != 0) result |= 1;
  if ((state & GDK_CONTROL_MASK) != 0) result |= 2;
  if ((state & GDK_ALT_MASK) != 0) result |= 4;
  if ((state & GDK_SUPER_MASK) != 0) result |= 8;
  return result;
}

static gboolean kiwi_gtk_close(GtkWindow *window, gpointer userdata) {
  (void)window;
  KiwiGtkHost *host = userdata;
  host->should_close = 1;
  return TRUE;
}

static void kiwi_gtk_resize(GtkWidget *widget, int width, int height, gpointer userdata) {
  KiwiGtkHost *host = userdata;
  host->surface = gtk_native_get_surface(GTK_NATIVE(host->window));
  if (host->callbacks.resize != NULL) {
    double scale = host->surface == NULL ? 1.0 : gdk_surface_get_scale(host->surface);
    host->callbacks.resize(host->callbacks.userdata, width, height, scale > 0.0 ? scale : 1.0);
  }
  (void)widget;
}

static gboolean kiwi_gtk_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer userdata) {
  (void)controller;
  (void)keycode;
  KiwiGtkHost *host = userdata;
  uint32_t result = host->callbacks.key == NULL ? 0 : host->callbacks.key(host->callbacks.userdata, keyval, kiwi_gtk_modifiers(state), KIWI_GTK_ACTION_PRESS);
  gunichar character = gdk_keyval_to_unicode(keyval);
  if (character != 0 && host->callbacks.text != NULL && (result & KIWI_GTK_INPUT_SUPPRESS_TEXT) == 0 && (state & (GDK_CONTROL_MASK | GDK_ALT_MASK | GDK_SUPER_MASK)) == 0) {
    host->callbacks.text(host->callbacks.userdata, character);
  }
  return (result & KIWI_GTK_INPUT_HANDLED) != 0;
}

static void kiwi_gtk_key_released(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer userdata) {
  (void)controller;
  (void)keycode;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.key != NULL) host->callbacks.key(host->callbacks.userdata, keyval, kiwi_gtk_modifiers(state), KIWI_GTK_ACTION_RELEASE);
}

static void kiwi_gtk_focus_enter(GtkEventControllerFocus *controller, gpointer userdata) {
  (void)controller;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.focus != NULL) host->callbacks.focus(host->callbacks.userdata, 1);
}

static void kiwi_gtk_focus_leave(GtkEventControllerFocus *controller, gpointer userdata) {
  (void)controller;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.focus != NULL) host->callbacks.focus(host->callbacks.userdata, 0);
}

static void kiwi_gtk_motion(GtkEventControllerMotion *controller, double x, double y, gpointer userdata) {
  (void)controller;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.pointer != NULL) host->callbacks.pointer(host->callbacks.userdata, KIWI_GTK_POINTER_MOTION, x, y, 0.0, 0.0, 0, 0, 0);
}

static void kiwi_gtk_click_pressed(GtkGestureClick *gesture, int presses, double x, double y, gpointer userdata) {
  (void)presses;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.pointer != NULL) host->callbacks.pointer(host->callbacks.userdata, KIWI_GTK_POINTER_BUTTON, x, y, 0.0, 0.0, gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture)), KIWI_GTK_ACTION_PRESS, 0);
}

static void kiwi_gtk_click_released(GtkGestureClick *gesture, int presses, double x, double y, gpointer userdata) {
  (void)presses;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.pointer != NULL) host->callbacks.pointer(host->callbacks.userdata, KIWI_GTK_POINTER_BUTTON, x, y, 0.0, 0.0, gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture)), KIWI_GTK_ACTION_RELEASE, 0);
}

static gboolean kiwi_gtk_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer userdata) {
  (void)controller;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.pointer != NULL) host->callbacks.pointer(host->callbacks.userdata, KIWI_GTK_POINTER_SCROLL, 0.0, 0.0, dx, dy, 0, 0, 0);
  return TRUE;
}

KiwiGtkHost *kiwi_gtk_host_new(const char *application_id, int width, int height, const char *title, const KiwiGtkCallbacks *callbacks) {
  if (application_id == NULL || title == NULL || callbacks == NULL || width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK host received invalid construction arguments");
    return NULL;
  }
  KiwiGtkHost *host = g_new0(KiwiGtkHost, 1);
  host->callbacks = *callbacks;
  GError *error = NULL;
  host->application = gtk_application_new(application_id, G_APPLICATION_NON_UNIQUE);
  if (!g_application_register(G_APPLICATION(host->application), NULL, &error)) {
    kiwi_gtk_set_error(error == NULL ? "GTK application registration failed" : error->message);
    if (error != NULL) g_error_free(error);
    g_object_unref(host->application);
    g_free(host);
    return NULL;
  }
  host->window = gtk_application_window_new(host->application);
  gtk_window_set_default_size(GTK_WINDOW(host->window), width, height);
  gtk_window_set_title(GTK_WINDOW(host->window), title);
  host->content = gtk_drawing_area_new();
  gtk_widget_set_hexpand(host->content, TRUE);
  gtk_widget_set_vexpand(host->content, TRUE);
  gtk_window_set_child(GTK_WINDOW(host->window), host->content);
  g_signal_connect(host->window, "close-request", G_CALLBACK(kiwi_gtk_close), host);
  g_signal_connect(host->content, "resize", G_CALLBACK(kiwi_gtk_resize), host);
  GtkEventController *key = gtk_event_controller_key_new();
  g_signal_connect(key, "key-pressed", G_CALLBACK(kiwi_gtk_key_pressed), host);
  g_signal_connect(key, "key-released", G_CALLBACK(kiwi_gtk_key_released), host);
  gtk_widget_add_controller(host->content, key);
  GtkEventController *focus = gtk_event_controller_focus_new();
  g_signal_connect(focus, "enter", G_CALLBACK(kiwi_gtk_focus_enter), host);
  g_signal_connect(focus, "leave", G_CALLBACK(kiwi_gtk_focus_leave), host);
  gtk_widget_add_controller(host->content, focus);
  GtkEventController *motion = gtk_event_controller_motion_new();
  g_signal_connect(motion, "motion", G_CALLBACK(kiwi_gtk_motion), host);
  gtk_widget_add_controller(host->content, motion);
  GtkGesture *click = gtk_gesture_click_new();
  g_signal_connect(click, "pressed", G_CALLBACK(kiwi_gtk_click_pressed), host);
  g_signal_connect(click, "released", G_CALLBACK(kiwi_gtk_click_released), host);
  gtk_widget_add_controller(host->content, GTK_EVENT_CONTROLLER(click));
  GtkEventController *scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
  g_signal_connect(scroll, "scroll", G_CALLBACK(kiwi_gtk_scroll), host);
  gtk_widget_add_controller(host->content, scroll);
  gtk_window_present(GTK_WINDOW(host->window));
  while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);
  host->surface = gtk_native_get_surface(GTK_NATIVE(host->window));
  if (host->surface == NULL) {
    kiwi_gtk_set_error("GTK window did not realize a GDK surface");
    gtk_window_destroy(GTK_WINDOW(host->window));
    g_object_unref(host->application);
    g_free(host);
    return NULL;
  }
  gtk_widget_grab_focus(host->content);
  return host;
}

void kiwi_gtk_host_destroy(KiwiGtkHost *host) {
  if (host == NULL) return;
  if (host->window != NULL) gtk_window_destroy(GTK_WINDOW(host->window));
  if (host->application != NULL) g_object_unref(host->application);
  g_free(host);
}

void kiwi_gtk_host_pump(KiwiGtkHost *host, uint32_t timeout_milliseconds) {
  (void)host;
  while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);
  if (timeout_milliseconds > 0) g_usleep((gulong)timeout_milliseconds * 1000U);
  while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);
}

int kiwi_gtk_host_should_close(const KiwiGtkHost *host) { return host != NULL && host->should_close; }

double kiwi_gtk_host_time(void) { return (double)g_get_monotonic_time() / 1000000.0; }

void kiwi_gtk_host_request_close(KiwiGtkHost *host) { if (host != NULL) host->should_close = 1; }

void kiwi_gtk_host_set_title(KiwiGtkHost *host, const char *title) { if (host != NULL && title != NULL) gtk_window_set_title(GTK_WINDOW(host->window), title); }

void kiwi_gtk_host_drawable_size(const KiwiGtkHost *host, int *width, int *height) {
  if (width != NULL) *width = host == NULL ? 0 : gtk_widget_get_width(host->content);
  if (height != NULL) *height = host == NULL ? 0 : gtk_widget_get_height(host->content);
}

double kiwi_gtk_host_content_scale(const KiwiGtkHost *host) { return host == NULL || host->surface == NULL ? 1.0 : gdk_surface_get_scale(host->surface); }

void kiwi_gtk_host_set_size(KiwiGtkHost *host, int width, int height) { if (host != NULL && width > 0 && height > 0) gtk_window_set_default_size(GTK_WINDOW(host->window), width, height); }

int kiwi_gtk_host_clipboard_write(KiwiGtkHost *host, const char *text) {
  if (host == NULL || host->surface == NULL || text == NULL) return 0;
  gdk_clipboard_set_text(gdk_display_get_clipboard(gdk_surface_get_display(host->surface)), text);
  return 1;
}

static void kiwi_gtk_clipboard_read_done(GObject *source, GAsyncResult *result, gpointer userdata) {
  KiwiGtkClipboardRead *read = userdata;
  read->text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(source), result, &read->error);
  if (read->timeout_id != 0) {
    g_source_remove(read->timeout_id);
    read->timeout_id = 0;
  }
  g_main_loop_quit(read->loop);
}

static gboolean kiwi_gtk_clipboard_timeout(gpointer userdata) {
  KiwiGtkClipboardRead *read = userdata;
  read->timeout_id = 0;
  g_cancellable_cancel(read->cancellable);
  return G_SOURCE_REMOVE;
}

int kiwi_gtk_host_clipboard_read(KiwiGtkHost *host, char *destination, size_t capacity, size_t *text_bytes) {
  if (host == NULL || host->surface == NULL || destination == NULL || text_bytes == NULL || capacity == 0) return 0;
  KiwiGtkClipboardRead read = {0};
  read.cancellable = g_cancellable_new();
  read.loop = g_main_loop_new(NULL, FALSE);
  GdkClipboard *clipboard = gdk_display_get_clipboard(gdk_surface_get_display(host->surface));
  read.timeout_id = g_timeout_add(1000, kiwi_gtk_clipboard_timeout, &read);
  gdk_clipboard_read_text_async(clipboard, read.cancellable, kiwi_gtk_clipboard_read_done, &read);
  g_main_loop_run(read.loop);
  g_object_unref(read.cancellable);
  g_main_loop_unref(read.loop);
  if (read.error != NULL) {
    kiwi_gtk_set_error(read.error->message);
    g_error_free(read.error);
    return 0;
  }
  if (read.text == NULL) return 0;
  size_t length = strlen(read.text);
  if (length > capacity) {
    g_free(read.text);
    return -1;
  }
  memcpy(destination, read.text, length);
  destination[length] = '\0';
  *text_bytes = length;
  g_free(read.text);
  return 1;
}

int kiwi_gtk_host_open_uri(KiwiGtkHost *host, const char *uri) {
  if (host == NULL || uri == NULL || uri[0] == '\0') return 0;
  GError *error = NULL;
  gboolean opened = g_app_info_launch_default_for_uri(uri, NULL, &error);
  if (!opened) {
    kiwi_gtk_set_error(error == NULL ? "could not open URI" : error->message);
    if (error != NULL) g_error_free(error);
  }
  return opened ? 1 : 0;
}

void *kiwi_gtk_host_create_surface(void *instance_pointer, KiwiGtkHost *host) {
  if (instance_pointer == NULL || host == NULL || host->surface == NULL) {
    kiwi_gtk_set_error("GTK host has no realized surface");
    return NULL;
  }
  WGPUInstance instance = (WGPUInstance)instance_pointer;
  WGPUSurfaceDescriptor descriptor = WGPU_SURFACE_DESCRIPTOR_INIT;
  GdkDisplay *display = gdk_surface_get_display(host->surface);
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    WGPUSurfaceSourceWaylandSurface source = WGPU_SURFACE_SOURCE_WAYLAND_SURFACE_INIT;
    source.display = gdk_wayland_display_get_wl_display(display);
    source.surface = gdk_wayland_surface_get_wl_surface(host->surface);
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    return wgpuInstanceCreateSurface(instance, &descriptor);
  }
  if (GDK_IS_X11_DISPLAY(display)) {
    WGPUSurfaceSourceXlibWindow source = WGPU_SURFACE_SOURCE_XLIB_WINDOW_INIT;
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    source.display = gdk_x11_display_get_xdisplay(display);
    source.window = gdk_x11_surface_get_xid(host->surface);
    G_GNUC_END_IGNORE_DEPRECATIONS
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    return wgpuInstanceCreateSurface(instance, &descriptor);
  }
  kiwi_gtk_set_error("unsupported GDK backend; Kiwi GTK host requires Wayland or X11");
  return NULL;
}

int kiwi_gtk_host_set_drawable_size(KiwiGtkHost *host, uint32_t width, uint32_t height) {
  if (host == NULL || host->surface == NULL || width == 0 || height == 0) {
    kiwi_gtk_set_error("GTK host has no nonzero realized drawable");
    return 0;
  }
  return 1;
}

const char *kiwi_gtk_host_last_error(void) { return kiwi_gtk_error; }
