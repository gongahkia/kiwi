#include <gtk/gtk.h>
#include <gdk/wayland/gdkwayland.h>
#include <gdk/x11/gdkx.h>
#include <webgpu/webgpu.h>
#include <viewporter-client-protocol.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct KiwiGtkHost KiwiGtkHost;

typedef uint32_t (*KiwiGtkKeyCallback)(void *userdata, uint32_t keyval, uint32_t modifiers, int action);
typedef void (*KiwiGtkTextCallback)(void *userdata, const char *text, size_t text_bytes);
typedef void (*KiwiGtkPreeditCallback)(void *userdata, const char *text, size_t text_bytes,
                                       uint32_t cursor_begin, uint32_t cursor_end);
typedef void (*KiwiGtkPointerCallback)(void *userdata, int kind, double x, double y, double dx, double dy, uint32_t button, int action, uint32_t modifiers);
typedef void (*KiwiGtkFocusCallback)(void *userdata, int focused);
typedef void (*KiwiGtkResizeCallback)(void *userdata, int width, int height, double scale);
typedef void (*KiwiGtkProductActionCallback)(void *userdata, uint32_t action);

typedef struct KiwiGtkCallbacks {
  KiwiGtkFocusCallback focus;
  KiwiGtkKeyCallback key;
  KiwiGtkPointerCallback pointer;
  KiwiGtkResizeCallback resize;
  KiwiGtkTextCallback text;
  KiwiGtkPreeditCallback preedit;
  void *userdata;
} KiwiGtkCallbacks;

typedef struct _KiwiGtkTerminal {
  GtkDrawingArea parent_instance;
  char *text;
  guint character_count;
  guint caret_offset;
  guint selection_start;
  guint selection_end;
} KiwiGtkTerminal;

typedef struct _KiwiGtkTerminalClass {
  GtkDrawingAreaClass parent_class;
} KiwiGtkTerminalClass;

#define KIWI_TYPE_GTK_TERMINAL (kiwi_gtk_terminal_get_type())
#define KIWI_GTK_TERMINAL(value) ((KiwiGtkTerminal *)(value))

static GType kiwi_gtk_terminal_get_type(void);

struct KiwiGtkHost {
  GtkApplication *application;
  GtkWidget *window;
  GtkWidget *content;
  KiwiGtkCallbacks callbacks;
  GdkSurface *surface;
  GtkIMContext *im_context;
  KiwiGtkProductActionCallback product_action;
  void *product_action_userdata;
  struct wl_surface *presentation_surface;
  struct wl_subsurface *presentation_subsurface;
  struct wp_viewport *presentation_viewport;
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
static GtkApplication *kiwi_gtk_application;

enum {
  KIWI_GTK_PRODUCT_ACTION_NEW_TAB = 1,
  KIWI_GTK_PRODUCT_ACTION_NEW_WINDOW = 2,
  KIWI_GTK_PRODUCT_ACTION_NEXT_TAB = 3,
  KIWI_GTK_PRODUCT_ACTION_CLOSE_PANE = 4,
  KIWI_GTK_PRODUCT_ACTION_SPLIT_RIGHT = 5,
  KIWI_GTK_PRODUCT_ACTION_SPLIT_DOWN = 6,
  KIWI_GTK_PRODUCT_ACTION_RELOAD_CONFIGURATION = 7,
  KIWI_GTK_PRODUCT_ACTION_MOVE_SESSION_NEW_WINDOW = 8,
  KIWI_GTK_PRODUCT_ACTION_MOVE_SESSION_NEXT_WINDOW = 9,
  KIWI_GTK_PRODUCT_ACTION_DUPLICATE_SESSION_NEW_WINDOW = 10,
  KIWI_GTK_PRODUCT_ACTION_DUPLICATE_SESSION_NEXT_WINDOW = 11,
};

enum {
  KIWI_GTK_ACCESSIBILITY_MAXIMUM_BYTES = 64 * 1024,
  KIWI_GTK_NOTIFICATION_BODY_MAXIMUM_BYTES = 1024,
  KIWI_GTK_NOTIFICATION_TITLE_MAXIMUM_BYTES = 128,
  KIWI_GTK_TEXT_INPUT_MAXIMUM_BYTES = 1024,
};

static void kiwi_gtk_set_error(const char *message);
static void kiwi_gtk_terminal_accessible_text_init(GtkAccessibleTextInterface *interface);

typedef struct KiwiGtkProductAction {
  uint32_t identifier;
  const char *name;
} KiwiGtkProductAction;

static const KiwiGtkProductAction kiwi_gtk_product_actions[] = {
  { KIWI_GTK_PRODUCT_ACTION_NEW_TAB, "new-tab" },
  { KIWI_GTK_PRODUCT_ACTION_NEW_WINDOW, "new-window" },
  { KIWI_GTK_PRODUCT_ACTION_NEXT_TAB, "next-tab" },
  { KIWI_GTK_PRODUCT_ACTION_CLOSE_PANE, "close-pane" },
  { KIWI_GTK_PRODUCT_ACTION_SPLIT_RIGHT, "split-right" },
  { KIWI_GTK_PRODUCT_ACTION_SPLIT_DOWN, "split-down" },
  { KIWI_GTK_PRODUCT_ACTION_RELOAD_CONFIGURATION, "reload-config" },
  { KIWI_GTK_PRODUCT_ACTION_MOVE_SESSION_NEW_WINDOW, "move-session-new-window" },
  { KIWI_GTK_PRODUCT_ACTION_MOVE_SESSION_NEXT_WINDOW, "move-session-next-window" },
  { KIWI_GTK_PRODUCT_ACTION_DUPLICATE_SESSION_NEW_WINDOW, "duplicate-session-new-window" },
  { KIWI_GTK_PRODUCT_ACTION_DUPLICATE_SESSION_NEXT_WINDOW, "duplicate-session-next-window" },
};

static const KiwiGtkProductAction *kiwi_gtk_product_action(uint32_t identifier) {
  for (size_t index = 0; index < G_N_ELEMENTS(kiwi_gtk_product_actions); index += 1) {
    if (kiwi_gtk_product_actions[index].identifier == identifier) return &kiwi_gtk_product_actions[index];
  }
  return NULL;
}

static const KiwiGtkProductAction *kiwi_gtk_product_action_named(const char *name) {
  if (name == NULL) return NULL;
  for (size_t index = 0; index < G_N_ELEMENTS(kiwi_gtk_product_actions); index += 1) {
    if (g_strcmp0(kiwi_gtk_product_actions[index].name, name) == 0) return &kiwi_gtk_product_actions[index];
  }
  return NULL;
}

G_DEFINE_TYPE_WITH_CODE(KiwiGtkTerminal, kiwi_gtk_terminal, GTK_TYPE_DRAWING_AREA,
                        G_IMPLEMENT_INTERFACE(GTK_TYPE_ACCESSIBLE_TEXT,
                                              kiwi_gtk_terminal_accessible_text_init))

static const char *kiwi_gtk_terminal_offset_pointer(const KiwiGtkTerminal *terminal,
                                                     guint offset) {
  return g_utf8_offset_to_pointer(terminal->text,
                                  MIN(offset, terminal->character_count));
}

static guint kiwi_gtk_terminal_pointer_offset(const KiwiGtkTerminal *terminal,
                                              const char *pointer) {
  return (guint)g_utf8_pointer_to_offset(terminal->text, pointer);
}

static GBytes *kiwi_gtk_terminal_contents(GtkAccessibleText *accessible,
                                          unsigned int start, unsigned int end) {
  KiwiGtkTerminal *terminal = KIWI_GTK_TERMINAL(accessible);
  guint first = MIN(start, terminal->character_count);
  guint last = end == G_MAXUINT ? terminal->character_count
                                : MIN(end, terminal->character_count);
  if (last < first) last = first;
  const char *first_pointer = kiwi_gtk_terminal_offset_pointer(terminal, first);
  const char *last_pointer = kiwi_gtk_terminal_offset_pointer(terminal, last);
  return g_bytes_new(first_pointer, (gsize)(last_pointer - first_pointer));
}

static gboolean kiwi_gtk_terminal_word_character(gunichar character) {
  return g_unichar_isalnum(character) || character == '_';
}

static GBytes *kiwi_gtk_terminal_contents_at(GtkAccessibleText *accessible,
                                             unsigned int offset,
                                             GtkAccessibleTextGranularity granularity,
                                             unsigned int *start, unsigned int *end) {
  KiwiGtkTerminal *terminal = KIWI_GTK_TERMINAL(accessible);
  guint clamped_offset = MIN(offset, terminal->character_count);
  const char *first = kiwi_gtk_terminal_offset_pointer(terminal, clamped_offset);
  const char *last = first;
  const char *text_end = kiwi_gtk_terminal_offset_pointer(terminal,
                                                           terminal->character_count);

  if (first < text_end) last = g_utf8_next_char(first);
  if (granularity == GTK_ACCESSIBLE_TEXT_GRANULARITY_LINE ||
      granularity == GTK_ACCESSIBLE_TEXT_GRANULARITY_PARAGRAPH) {
    while (first > terminal->text) {
      const char *previous = g_utf8_find_prev_char(terminal->text, first);
      if (previous == NULL || *previous == '\n') break;
      first = previous;
    }
    last = first;
    while (last < text_end && *last != '\n') last = g_utf8_next_char(last);
    if (last < text_end) last = g_utf8_next_char(last);
  } else if (granularity == GTK_ACCESSIBLE_TEXT_GRANULARITY_WORD && first < text_end) {
    if (kiwi_gtk_terminal_word_character(g_utf8_get_char(first))) {
      while (first > terminal->text) {
        const char *previous = g_utf8_find_prev_char(terminal->text, first);
        if (previous == NULL || !kiwi_gtk_terminal_word_character(g_utf8_get_char(previous))) break;
        first = previous;
      }
      last = first;
      while (last < text_end && kiwi_gtk_terminal_word_character(g_utf8_get_char(last))) {
        last = g_utf8_next_char(last);
      }
    }
  } else if (granularity == GTK_ACCESSIBLE_TEXT_GRANULARITY_SENTENCE && first < text_end) {
    while (first > terminal->text) {
      const char *previous = g_utf8_find_prev_char(terminal->text, first);
      if (previous == NULL || *previous == '\n' || *previous == '.' ||
          *previous == '!' || *previous == '?') {
        break;
      }
      first = previous;
    }
    last = first;
    while (last < text_end) {
      gunichar character = g_utf8_get_char(last);
      last = g_utf8_next_char(last);
      if (character == '\n' || character == '.' || character == '!' || character == '?') {
        break;
      }
    }
  }

  if (start != NULL) *start = kiwi_gtk_terminal_pointer_offset(terminal, first);
  if (end != NULL) *end = kiwi_gtk_terminal_pointer_offset(terminal, last);
  return g_bytes_new(first, (gsize)(last - first));
}

static unsigned int kiwi_gtk_terminal_caret_position(GtkAccessibleText *accessible) {
  return KIWI_GTK_TERMINAL(accessible)->caret_offset;
}

static gboolean kiwi_gtk_terminal_selection(GtkAccessibleText *accessible,
                                            gsize *n_ranges,
                                            GtkAccessibleTextRange **ranges) {
  KiwiGtkTerminal *terminal = KIWI_GTK_TERMINAL(accessible);
  guint start = MIN(terminal->selection_start, terminal->selection_end);
  guint end = MAX(terminal->selection_start, terminal->selection_end);
  if (start == end) {
    if (n_ranges != NULL) *n_ranges = 0;
    if (ranges != NULL) *ranges = NULL;
    return FALSE;
  }
  if (n_ranges != NULL) *n_ranges = 1;
  if (ranges != NULL) {
    *ranges = g_new(GtkAccessibleTextRange, 1);
    (*ranges)[0].start = start;
    (*ranges)[0].length = end - start;
  }
  return TRUE;
}

static gboolean kiwi_gtk_terminal_attributes(GtkAccessibleText *accessible,
                                             unsigned int offset, gsize *n_ranges,
                                             GtkAccessibleTextRange **ranges,
                                             char ***attribute_names,
                                             char ***attribute_values) {
  (void)accessible;
  (void)offset;
  if (n_ranges != NULL) *n_ranges = 0;
  if (ranges != NULL) *ranges = NULL;
  if (attribute_names != NULL) *attribute_names = NULL;
  if (attribute_values != NULL) *attribute_values = NULL;
  return FALSE;
}

static void kiwi_gtk_terminal_default_attributes(GtkAccessibleText *accessible,
                                                 char ***attribute_names,
                                                 char ***attribute_values) {
  (void)accessible;
  if (attribute_names != NULL) *attribute_names = NULL;
  if (attribute_values != NULL) *attribute_values = NULL;
}

static gboolean kiwi_gtk_terminal_extents(GtkAccessibleText *accessible,
                                          unsigned int start, unsigned int end,
                                          graphene_rect_t *extents) {
  (void)accessible;
  (void)start;
  (void)end;
  (void)extents;
  return FALSE;
}

static gboolean kiwi_gtk_terminal_offset(GtkAccessibleText *accessible,
                                         const graphene_point_t *point,
                                         unsigned int *offset) {
  (void)accessible;
  (void)point;
  (void)offset;
  return FALSE;
}

static void kiwi_gtk_terminal_accessible_text_init(GtkAccessibleTextInterface *interface) {
  interface->get_contents = kiwi_gtk_terminal_contents;
  interface->get_contents_at = kiwi_gtk_terminal_contents_at;
  interface->get_caret_position = kiwi_gtk_terminal_caret_position;
  interface->get_selection = kiwi_gtk_terminal_selection;
  interface->get_attributes = kiwi_gtk_terminal_attributes;
  interface->get_default_attributes = kiwi_gtk_terminal_default_attributes;
  interface->get_extents = kiwi_gtk_terminal_extents;
  interface->get_offset = kiwi_gtk_terminal_offset;
}

static void kiwi_gtk_terminal_finalize(GObject *object) {
  KiwiGtkTerminal *terminal = KIWI_GTK_TERMINAL(object);
  g_free(terminal->text);
  G_OBJECT_CLASS(kiwi_gtk_terminal_parent_class)->finalize(object);
}

static void kiwi_gtk_terminal_class_init(KiwiGtkTerminalClass *klass) {
  GObjectClass *object_class = G_OBJECT_CLASS(klass);
  GtkWidgetClass *widget_class = GTK_WIDGET_CLASS(klass);
  object_class->finalize = kiwi_gtk_terminal_finalize;
  gtk_widget_class_set_accessible_role(widget_class, GTK_ACCESSIBLE_ROLE_TEXT_BOX);
}

static void kiwi_gtk_terminal_init(KiwiGtkTerminal *terminal) {
  terminal->text = g_strdup("");
  gtk_widget_set_focusable(GTK_WIDGET(terminal), TRUE);
}

static int kiwi_gtk_terminal_update(KiwiGtkTerminal *terminal, const char *text,
                                    size_t text_bytes, uint32_t character_count,
                                    int32_t caret_offset, int32_t selection_start,
                                    int32_t selection_end, const char *title) {
  if (text == NULL || text_bytes > KIWI_GTK_ACCESSIBILITY_MAXIMUM_BYTES ||
      !g_utf8_validate(text, (gssize)text_bytes, NULL) ||
      g_utf8_strlen(text, (gssize)text_bytes) != character_count) {
    kiwi_gtk_set_error("GTK accessibility update is not bounded valid UTF-8");
    return 0;
  }
  if (caret_offset < -1 || caret_offset > (int32_t)character_count ||
      selection_start < -1 || selection_start > (int32_t)character_count ||
      selection_end < -1 || selection_end > (int32_t)character_count) {
    kiwi_gtk_set_error("GTK accessibility update contains invalid text offsets");
    return 0;
  }

  guint old_count = terminal->character_count;
  guint previous_caret = terminal->caret_offset;
  guint previous_selection_start = terminal->selection_start;
  guint previous_selection_end = terminal->selection_end;
  if (old_count > 0) {
    gtk_accessible_text_update_contents(GTK_ACCESSIBLE_TEXT(terminal),
                                        GTK_ACCESSIBLE_TEXT_CONTENT_CHANGE_REMOVE,
                                        0, old_count);
  }
  g_free(terminal->text);
  terminal->text = g_strndup(text, text_bytes);
  terminal->character_count = character_count;
  terminal->caret_offset = caret_offset < 0 ? character_count : (guint)caret_offset;
  terminal->selection_start = selection_start < 0 ? terminal->caret_offset
                                                   : (guint)selection_start;
  terminal->selection_end = selection_end < 0 ? terminal->caret_offset
                                               : (guint)selection_end;
  gtk_accessible_update_property(GTK_ACCESSIBLE(terminal), GTK_ACCESSIBLE_PROPERTY_LABEL,
                                 title == NULL ? "Kiwi terminal" : title, -1);
  if (character_count > 0) {
    gtk_accessible_text_update_contents(GTK_ACCESSIBLE_TEXT(terminal),
                                        GTK_ACCESSIBLE_TEXT_CONTENT_CHANGE_INSERT,
                                        0, character_count);
  }
  if (previous_caret != terminal->caret_offset) {
    gtk_accessible_text_update_caret_position(GTK_ACCESSIBLE_TEXT(terminal));
  }
  if (previous_selection_start != terminal->selection_start ||
      previous_selection_end != terminal->selection_end) {
    gtk_accessible_text_update_selection_bound(GTK_ACCESSIBLE_TEXT(terminal));
  }
  return 1;
}

typedef struct KiwiGtkWaylandRegistry {
  struct wl_subcompositor *subcompositor;
  struct wp_viewporter *viewporter;
} KiwiGtkWaylandRegistry;

enum {
  KIWI_GTK_ACTION_PRESS = 1,
  KIWI_GTK_ACTION_RELEASE = 0,
  KIWI_GTK_INPUT_HANDLED = 1,
  KIWI_GTK_INPUT_SUPPRESS_TEXT = 2,
  KIWI_GTK_INPUT_DEFER_TEXT = 4,
  KIWI_GTK_POINTER_MOTION = 1,
  KIWI_GTK_POINTER_BUTTON = 2,
  KIWI_GTK_POINTER_SCROLL = 3,
};

static void kiwi_gtk_set_error(const char *message) {
  snprintf(kiwi_gtk_error, sizeof(kiwi_gtk_error), "%s", message == NULL ? "unknown GTK host error" : message);
}

static void kiwi_gtk_product_action_activate(GSimpleAction *action, GVariant *parameter,
                                             gpointer userdata) {
  (void)parameter;
  KiwiGtkHost *host = userdata;
  const KiwiGtkProductAction *product_action =
      kiwi_gtk_product_action_named(g_action_get_name(G_ACTION(action)));
  if (host != NULL && product_action != NULL && host->product_action != NULL) {
    host->product_action(host->product_action_userdata, product_action->identifier);
  }
}

static void kiwi_gtk_install_product_menu(GtkApplication *application) {
  if (gtk_application_get_menubar(application) != NULL) return;
  GMenu *menubar = g_menu_new();
  GMenu *file = g_menu_new();
  GMenu *window = g_menu_new();
  g_menu_append(file, "New Tab", "win.new-tab");
  g_menu_append(file, "New Window", "win.new-window");
  g_menu_append(file, "Reload Configuration", "win.reload-config");
  g_menu_append_submenu(menubar, "File", G_MENU_MODEL(file));
  g_menu_append(window, "Next Tab", "win.next-tab");
  g_menu_append(window, "Close Pane", "win.close-pane");
  g_menu_append(window, "Split Right", "win.split-right");
  g_menu_append(window, "Split Down", "win.split-down");
  g_menu_append(window, "Move Session to New Window", "win.move-session-new-window");
  g_menu_append(window, "Move Session to Next Window", "win.move-session-next-window");
  g_menu_append(window, "Duplicate Session to New Window", "win.duplicate-session-new-window");
  g_menu_append(window, "Duplicate Session to Next Window", "win.duplicate-session-next-window");
  g_menu_append_submenu(menubar, "Window", G_MENU_MODEL(window));
  gtk_application_set_menubar(application, G_MENU_MODEL(menubar));
  g_object_unref(window);
  g_object_unref(file);
  g_object_unref(menubar);
}

static int kiwi_gtk_install_product_actions(KiwiGtkHost *host) {
  if (host == NULL || host->application == NULL || host->window == NULL) {
    kiwi_gtk_set_error("GTK product actions need a realized application window");
    return 0;
  }
  GActionMap *actions = G_ACTION_MAP(host->window);
  for (size_t index = 0; index < G_N_ELEMENTS(kiwi_gtk_product_actions); index += 1) {
    const char *name = kiwi_gtk_product_actions[index].name;
    if (g_action_map_lookup_action(actions, name) != NULL) continue;
    GSimpleAction *action = g_simple_action_new(name, NULL);
    g_signal_connect(action, "activate", G_CALLBACK(kiwi_gtk_product_action_activate), host);
    g_action_map_add_action(actions, G_ACTION(action));
    g_object_unref(action);
  }
  kiwi_gtk_install_product_menu(host->application);
  gtk_application_window_set_show_menubar(GTK_APPLICATION_WINDOW(host->window), TRUE);
  return 1;
}

static void kiwi_gtk_wayland_registry_global(void *userdata, struct wl_registry *registry,
                                             uint32_t name, const char *interface,
                                             uint32_t version) {
  KiwiGtkWaylandRegistry *state = userdata;
  if (state->subcompositor == NULL && strcmp(interface, "wl_subcompositor") == 0) {
    uint32_t supported_version = version < 1 ? version : 1;
    state->subcompositor = wl_registry_bind(registry, name, &wl_subcompositor_interface,
                                            supported_version);
  } else if (state->viewporter == NULL && strcmp(interface, "wp_viewporter") == 0) {
    uint32_t supported_version = version < 1 ? version : 1;
    state->viewporter = wl_registry_bind(registry, name, &wp_viewporter_interface,
                                         supported_version);
  }
}

static void kiwi_gtk_wayland_registry_global_remove(void *userdata, struct wl_registry *registry,
                                                    uint32_t name) {
  (void)userdata;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener kiwi_gtk_wayland_registry_listener = {
  .global = kiwi_gtk_wayland_registry_global,
  .global_remove = kiwi_gtk_wayland_registry_global_remove,
};

static int kiwi_gtk_wayland_create_presentation_surface(KiwiGtkHost *host,
                                                         GdkDisplay *display) {
  if (host->presentation_surface != NULL) return 1;

  struct wl_display *wayland_display = gdk_wayland_display_get_wl_display(display);
  struct wl_compositor *compositor = gdk_wayland_display_get_wl_compositor(display);
  struct wl_surface *parent = gdk_wayland_surface_get_wl_surface(host->surface);
  if (wayland_display == NULL || compositor == NULL || parent == NULL) {
    kiwi_gtk_set_error("GTK Wayland host has no realized parent surface");
    return 0;
  }

  KiwiGtkWaylandRegistry state = {0};
  struct wl_registry *registry = wl_display_get_registry(wayland_display);
  if (registry == NULL || wl_registry_add_listener(registry, &kiwi_gtk_wayland_registry_listener,
                                                   &state) != 0 ||
      wl_display_roundtrip(wayland_display) < 0 || state.subcompositor == NULL ||
      state.viewporter == NULL) {
    if (registry != NULL) wl_registry_destroy(registry);
    if (state.subcompositor != NULL) wl_subcompositor_destroy(state.subcompositor);
    if (state.viewporter != NULL) wp_viewporter_destroy(state.viewporter);
    kiwi_gtk_set_error("Wayland compositor does not expose wl_subcompositor and wp_viewporter");
    return 0;
  }

  host->presentation_surface = wl_compositor_create_surface(compositor);
  if (host->presentation_surface == NULL) {
    wl_subcompositor_destroy(state.subcompositor);
    wp_viewporter_destroy(state.viewporter);
    wl_registry_destroy(registry);
    kiwi_gtk_set_error("could not create Wayland presentation surface");
    return 0;
  }
  host->presentation_subsurface = wl_subcompositor_get_subsurface(
      state.subcompositor, host->presentation_surface, parent);
  host->presentation_viewport = wp_viewporter_get_viewport(state.viewporter,
                                                            host->presentation_surface);
  wl_subcompositor_destroy(state.subcompositor);
  wp_viewporter_destroy(state.viewporter);
  wl_registry_destroy(registry);
  if (host->presentation_subsurface == NULL || host->presentation_viewport == NULL) {
    if (host->presentation_viewport != NULL) {
      wp_viewport_destroy(host->presentation_viewport);
      host->presentation_viewport = NULL;
    }
    if (host->presentation_subsurface != NULL) {
      wl_subsurface_destroy(host->presentation_subsurface);
      host->presentation_subsurface = NULL;
    }
    wl_surface_destroy(host->presentation_surface);
    host->presentation_surface = NULL;
    kiwi_gtk_set_error("could not create Wayland presentation subsurface or viewport");
    return 0;
  }
  wl_subsurface_set_desync(host->presentation_subsurface);
  wl_subsurface_set_position(host->presentation_subsurface, 0, 0);
  wl_subsurface_place_above(host->presentation_subsurface, parent);
  wl_surface_set_buffer_scale(host->presentation_surface, 1);
  return 1;
}

static int kiwi_gtk_wayland_update_viewport(KiwiGtkHost *host) {
  int width = gtk_widget_get_width(host->content);
  int height = gtk_widget_get_height(host->content);
  if (host->presentation_surface == NULL || host->presentation_viewport == NULL ||
      width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK Wayland host has no nonzero presentation viewport");
    return 0;
  }
  wl_surface_set_buffer_scale(host->presentation_surface, 1);
  wp_viewport_set_destination(host->presentation_viewport, width, height);
  return 1;
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
  return (result & KIWI_GTK_INPUT_HANDLED) != 0 &&
         (result & KIWI_GTK_INPUT_DEFER_TEXT) == 0;
}

static void kiwi_gtk_key_released(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer userdata) {
  (void)controller;
  (void)keycode;
  KiwiGtkHost *host = userdata;
  if (host->callbacks.key != NULL) host->callbacks.key(host->callbacks.userdata, keyval, kiwi_gtk_modifiers(state), KIWI_GTK_ACTION_RELEASE);
}

static void kiwi_gtk_im_commit(GtkIMContext *context, const char *text, gpointer userdata) {
  (void)context;
  KiwiGtkHost *host = userdata;
  if (text == NULL || host->callbacks.text == NULL) return;
  size_t text_bytes = strlen(text);
  if (text_bytes == 0) return;
  if (text_bytes > KIWI_GTK_TEXT_INPUT_MAXIMUM_BYTES ||
      !g_utf8_validate(text, (gssize)text_bytes, NULL)) {
    kiwi_gtk_set_error("GTK input method committed invalid or oversized UTF-8");
    return;
  }
  host->callbacks.text(host->callbacks.userdata, text, text_bytes);
}

static void kiwi_gtk_im_preedit_changed(GtkIMContext *context, gpointer userdata) {
  KiwiGtkHost *host = userdata;
  if (host->callbacks.preedit == NULL) return;
  char *text = NULL;
  PangoAttrList *attributes = NULL;
  int cursor = 0;
  gtk_im_context_get_preedit_string(context, &text, &attributes, &cursor);
  size_t text_bytes = text == NULL ? 0 : strlen(text);
  if (text == NULL || text_bytes > KIWI_GTK_TEXT_INPUT_MAXIMUM_BYTES ||
      !g_utf8_validate(text, (gssize)text_bytes, NULL)) {
    kiwi_gtk_set_error("GTK input method preedit is invalid or oversized UTF-8");
  } else {
    glong characters = g_utf8_strlen(text, (gssize)text_bytes);
    glong clamped_cursor = CLAMP((glong)cursor, 0, characters);
    uint32_t cursor_offset = (uint32_t)(g_utf8_offset_to_pointer(text, clamped_cursor) - text);
    host->callbacks.preedit(host->callbacks.userdata, text, text_bytes,
                            cursor_offset, cursor_offset);
  }
  if (attributes != NULL) pango_attr_list_unref(attributes);
  g_free(text);
}

static void kiwi_gtk_focus_enter(GtkEventControllerFocus *controller, gpointer userdata) {
  (void)controller;
  KiwiGtkHost *host = userdata;
  gtk_accessible_update_platform_state(GTK_ACCESSIBLE(host->content),
                                       GTK_ACCESSIBLE_PLATFORM_STATE_FOCUSED);
  if (host->callbacks.focus != NULL) host->callbacks.focus(host->callbacks.userdata, 1);
}

static void kiwi_gtk_focus_leave(GtkEventControllerFocus *controller, gpointer userdata) {
  (void)controller;
  KiwiGtkHost *host = userdata;
  if (host->im_context != NULL) gtk_im_context_reset(host->im_context);
  gtk_accessible_update_platform_state(GTK_ACCESSIBLE(host->content),
                                       GTK_ACCESSIBLE_PLATFORM_STATE_FOCUSED);
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
  if (kiwi_gtk_application == NULL) {
    GError *error = NULL;
    kiwi_gtk_application = gtk_application_new(application_id, G_APPLICATION_NON_UNIQUE);
    if (!g_application_register(G_APPLICATION(kiwi_gtk_application), NULL, &error)) {
      kiwi_gtk_set_error(error == NULL ? "GTK application registration failed" : error->message);
      if (error != NULL) g_error_free(error);
      g_object_unref(kiwi_gtk_application);
      kiwi_gtk_application = NULL;
      g_free(host);
      return NULL;
    }
  } else if (g_strcmp0(g_application_get_application_id(G_APPLICATION(kiwi_gtk_application)), application_id) != 0) {
    kiwi_gtk_set_error("GTK process already owns a different application ID");
    g_free(host);
    return NULL;
  }
  host->application = g_object_ref(kiwi_gtk_application);
  host->window = gtk_application_window_new(host->application);
  gtk_window_set_default_size(GTK_WINDOW(host->window), width, height);
  gtk_window_set_title(GTK_WINDOW(host->window), title);
  host->content = g_object_new(KIWI_TYPE_GTK_TERMINAL, NULL);
  gtk_widget_set_hexpand(host->content, TRUE);
  gtk_widget_set_vexpand(host->content, TRUE);
  gtk_window_set_child(GTK_WINDOW(host->window), host->content);
  g_signal_connect(host->window, "close-request", G_CALLBACK(kiwi_gtk_close), host);
  g_signal_connect(host->content, "resize", G_CALLBACK(kiwi_gtk_resize), host);
  GtkEventControllerKey *key = GTK_EVENT_CONTROLLER_KEY(gtk_event_controller_key_new());
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(key), GTK_PHASE_CAPTURE);
  g_signal_connect(key, "key-pressed", G_CALLBACK(kiwi_gtk_key_pressed), host);
  g_signal_connect(key, "key-released", G_CALLBACK(kiwi_gtk_key_released), host);
  gtk_widget_add_controller(host->content, GTK_EVENT_CONTROLLER(key));

  GtkEventControllerKey *im_key = GTK_EVENT_CONTROLLER_KEY(gtk_event_controller_key_new());
  GtkIMContext *im_context = gtk_im_multicontext_new();
  gtk_im_context_set_client_widget(im_context, host->content);
  g_signal_connect(im_context, "commit", G_CALLBACK(kiwi_gtk_im_commit), host);
  g_signal_connect(im_context, "preedit-changed", G_CALLBACK(kiwi_gtk_im_preedit_changed), host);
  gtk_event_controller_key_set_im_context(im_key, im_context);
  host->im_context = gtk_event_controller_key_get_im_context(im_key);
  g_object_unref(im_context);
  gtk_widget_add_controller(host->content, GTK_EVENT_CONTROLLER(im_key));
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
  host->product_action = NULL;
  host->product_action_userdata = NULL;
  if (host->presentation_viewport != NULL) wp_viewport_destroy(host->presentation_viewport);
  if (host->presentation_subsurface != NULL) wl_subsurface_destroy(host->presentation_subsurface);
  if (host->presentation_surface != NULL) wl_surface_destroy(host->presentation_surface);
  if (host->window != NULL) gtk_window_destroy(GTK_WINDOW(host->window));
  if (host->application != NULL) g_object_unref(host->application);
  g_free(host);
}

int kiwi_gtk_host_set_product_action_handler(KiwiGtkHost *host,
                                             KiwiGtkProductActionCallback callback,
                                             void *userdata) {
  if (host == NULL || callback == NULL) {
    kiwi_gtk_set_error("GTK product actions need a host and callback");
    return 0;
  }
  host->product_action = callback;
  host->product_action_userdata = userdata;
  if (kiwi_gtk_install_product_actions(host)) return 1;
  host->product_action = NULL;
  host->product_action_userdata = NULL;
  return 0;
}

int kiwi_gtk_host_product_action_invoke_smoke(KiwiGtkHost *host, uint32_t identifier) {
  const KiwiGtkProductAction *product_action = kiwi_gtk_product_action(identifier);
  if (host == NULL || product_action == NULL || host->window == NULL ||
      host->product_action == NULL ||
      g_action_map_lookup_action(G_ACTION_MAP(host->window), product_action->name) == NULL) {
    kiwi_gtk_set_error("GTK product-menu smoke needs an installed valid action");
    return 0;
  }
  g_action_group_activate_action(G_ACTION_GROUP(host->window), product_action->name, NULL);
  return 1;
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
  double scale = host == NULL || host->surface == NULL ? 1.0 : gdk_surface_get_scale(host->surface);
  if (scale <= 0.0) scale = 1.0;
  if (width != NULL) *width = host == NULL ? 0 : (int)(gtk_widget_get_width(host->content) * scale + 0.5);
  if (height != NULL) *height = host == NULL ? 0 : (int)(gtk_widget_get_height(host->content) * scale + 0.5);
}

double kiwi_gtk_host_content_scale(const KiwiGtkHost *host) { return host == NULL || host->surface == NULL ? 1.0 : gdk_surface_get_scale(host->surface); }

void kiwi_gtk_host_set_size(KiwiGtkHost *host, int width, int height) { if (host != NULL && width > 0 && height > 0) gtk_window_set_default_size(GTK_WINDOW(host->window), width, height); }

int kiwi_gtk_host_clipboard_write(KiwiGtkHost *host, const char *text) {
  if (host == NULL || host->surface == NULL || text == NULL) return 0;
  gdk_clipboard_set_text(gdk_display_get_clipboard(gdk_surface_get_display(host->surface)), text);
  return 1;
}

int kiwi_gtk_host_notify(KiwiGtkHost *host, const char *title, const char *body) {
  if (host == NULL || host->application == NULL || title == NULL || body == NULL ||
      title[0] == '\0' || strlen(title) > KIWI_GTK_NOTIFICATION_TITLE_MAXIMUM_BYTES ||
      strlen(body) > KIWI_GTK_NOTIFICATION_BODY_MAXIMUM_BYTES ||
      !g_utf8_validate(title, -1, NULL) || !g_utf8_validate(body, -1, NULL)) {
    kiwi_gtk_set_error("GTK notification received invalid bounded UTF-8 text");
    return 0;
  }
  GNotification *notification = g_notification_new(title);
  if (notification == NULL) {
    kiwi_gtk_set_error("GTK could not construct a notification");
    return 0;
  }
  g_notification_set_body(notification, body);
  g_application_send_notification(G_APPLICATION(host->application),
                                  "kiwi-terminal-osc9", notification);
  g_object_unref(notification);
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
    if (!kiwi_gtk_wayland_create_presentation_surface(host, display)) return NULL;
    WGPUSurfaceSourceWaylandSurface source = WGPU_SURFACE_SOURCE_WAYLAND_SURFACE_INIT;
    source.display = gdk_wayland_display_get_wl_display(display);
    source.surface = host->presentation_surface;
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
  GdkDisplay *display = gdk_surface_get_display(host->surface);
  if (GDK_IS_WAYLAND_DISPLAY(display) && host->presentation_surface != NULL) {
    return kiwi_gtk_wayland_update_viewport(host);
  }
  return 1;
}

int kiwi_gtk_host_set_text_input_caret(KiwiGtkHost *host, int x, int y,
                                       int width, int height) {
  if (host == NULL || host->im_context == NULL || x < 0 || y < 0 ||
      width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK input method received an invalid caret rectangle");
    return 0;
  }
  GdkRectangle rectangle = { x, y, width, height };
  gtk_im_context_set_cursor_location(host->im_context, &rectangle);
  return 1;
}

int kiwi_gtk_host_system_appearance(const KiwiGtkHost *host) {
  if (host == NULL || host->content == NULL) return -1;
  GtkSettings *settings = gtk_widget_get_settings(host->content);
  if (settings == NULL) return -1;
  gboolean dark = FALSE;
  g_object_get(settings, "gtk-application-prefer-dark-theme", &dark, NULL);
  return dark ? 1 : 0;
}

int kiwi_gtk_host_text_input_inject_smoke(KiwiGtkHost *host) {
  static const char preedit[] = "e\xCC\x81";
  static const char commit[] = "\xE2\x9C\x93";
  if (host == NULL || host->callbacks.preedit == NULL || host->callbacks.text == NULL) {
    kiwi_gtk_set_error("GTK text-input smoke needs installed preedit and commit callbacks");
    return 0;
  }
  host->callbacks.preedit(host->callbacks.userdata, preedit, sizeof(preedit) - 1,
                          sizeof(preedit) - 1, sizeof(preedit) - 1);
  host->callbacks.text(host->callbacks.userdata, commit, sizeof(commit) - 1);
  return 1;
}

int kiwi_gtk_host_key_text_inject_smoke(KiwiGtkHost *host) {
  static const char text[] = "a";
  if (host == NULL || host->callbacks.key == NULL || host->callbacks.text == NULL) {
    kiwi_gtk_set_error("GTK key/text smoke needs installed key and text callbacks");
    return 0;
  }
  if (kiwi_gtk_key_pressed(NULL, 'a', 0, 0, host)) {
    kiwi_gtk_set_error("GTK key/text smoke expected the deferred key to reach the input method");
    return 0;
  }
  kiwi_gtk_im_commit(NULL, text, host);
  kiwi_gtk_key_released(NULL, 'a', 0, 0, host);
  return 1;
}

int kiwi_gtk_host_accessibility_update(KiwiGtkHost *host, const char *text,
                                       size_t text_bytes, uint32_t character_count,
                                       int32_t caret_offset, int32_t selection_start,
                                       int32_t selection_end, int focused,
                                       const char *title) {
  if (host == NULL || host->content == NULL) {
    kiwi_gtk_set_error("GTK accessibility update has no terminal widget");
    return 0;
  }
  (void)focused;
  return kiwi_gtk_terminal_update(KIWI_GTK_TERMINAL(host->content), text, text_bytes,
                                  character_count, caret_offset, selection_start,
                                  selection_end, title);
}

const char *kiwi_gtk_host_last_error(void) { return kiwi_gtk_error; }
