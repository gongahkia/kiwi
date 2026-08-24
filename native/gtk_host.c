#include <gtk/gtk.h>
#include <adwaita.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/wayland/gdkwayland.h>
#include <viewporter-client-protocol.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/x11/gdkx.h>
#endif
#include <webgpu/webgpu.h>
#include "gtk_gl_renderer.h"
#include "kiwi_render_model.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct KiwiGtkHost KiwiGtkHost;
typedef struct KiwiGtkTerminalPresentation KiwiGtkTerminalPresentation;
typedef int (*KiwiGtkNativeTabCloseCallback)(void *userdata,
                                              KiwiGtkTerminalPresentation *presentation);

/* A GtkGLArea is a terminal presentation, not a property of the toplevel
 * window. Keeping this state independent is the ownership boundary needed for
 * a future native tab page to carry its own terminal, input, and renderer. */
typedef struct KiwiGtkGlPresentation {
  GtkGLArea *area;
  KiwiGtkGlRenderer *renderer;
  uint64_t context_generation;
  uint64_t rendered_frames;
  int realized;
} KiwiGtkGlPresentation;

enum {
  KIWI_GTK_HOST_ABI_VERSION = 4,
};

typedef struct KiwiGtkKeyEvent {
  uint32_t struct_size;
  uint32_t keyval;
  uint32_t unicode_key;
  uint32_t keycode;
  uint32_t modifiers;
  uint32_t layout_key;
  uint32_t shifted_key;
  uint32_t base_key;
  int action;
} KiwiGtkKeyEvent;

typedef uint32_t (*KiwiGtkKeyCallback)(void *userdata, const KiwiGtkKeyEvent *event);
typedef void (*KiwiGtkTextCallback)(void *userdata, const char *text, size_t text_bytes);
typedef void (*KiwiGtkPreeditCallback)(void *userdata, const char *text, size_t text_bytes,
                                       uint32_t cursor_begin, uint32_t cursor_end);
typedef void (*KiwiGtkPointerCallback)(void *userdata, int kind, double x, double y, double dx, double dy, uint32_t button, int action, uint32_t modifiers);
typedef void (*KiwiGtkFocusCallback)(void *userdata, int focused);
typedef void (*KiwiGtkResizeCallback)(void *userdata, int width, int height, double scale);
typedef void (*KiwiGtkProductActionCallback)(void *userdata, uint32_t action);

typedef struct KiwiGtkCommandPaletteEntry {
  uint32_t action;
  const char *title;
  const char *description;
} KiwiGtkCommandPaletteEntry;

typedef struct KiwiGtkCommandPalette KiwiGtkCommandPalette;

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
  GtkWidget parent_instance;
  char *text;
  guint character_count;
  guint caret_offset;
  guint selection_start;
  guint selection_end;
} KiwiGtkTerminal;

typedef struct _KiwiGtkTerminalClass {
  GtkWidgetClass parent_class;
} KiwiGtkTerminalClass;

#define KIWI_TYPE_GTK_TERMINAL (kiwi_gtk_terminal_get_type())
#define KIWI_GTK_TERMINAL(value) ((KiwiGtkTerminal *)(value))

static GType kiwi_gtk_terminal_get_type(void);

struct KiwiGtkHost {
  GtkApplication *application;
  GtkWidget *window;
  GdkSurface *surface;
  char notification_id[64];
  KiwiGtkTerminalPresentation *primary_presentation;
  GtkWidget *tab_root;
  AdwTabView *tab_view;
  AdwTabBar *tab_bar;
  GPtrArray *presentations;
  GPtrArray *retired_presentations;
  KiwiGtkNativeTabCloseCallback native_tab_close;
  void *native_tab_close_userdata;
  KiwiGtkTerminalPresentation *native_tab_close_request;
  KiwiGtkTerminalPresentation *native_tab_programmatic_close;
  KiwiGtkProductActionCallback product_action;
  void *product_action_userdata;
  KiwiGtkCommandPalette *command_palette;
#ifdef GDK_WINDOWING_WAYLAND
  struct wl_surface *presentation_surface;
  struct wl_subsurface *presentation_subsurface;
  struct wp_viewport *presentation_viewport;
#endif
  int should_close;
};

/* A presentation owns exactly one accessible terminal node, IM context, input
 * controller set, and GtkGL renderer. The toplevel host owns only shared
 * window policy and will later compose one or more presentations as tab pages. */
struct KiwiGtkTerminalPresentation {
  KiwiGtkHost *host;
  GtkWidget *content;
  GtkProgressBar *progress;
  guint progress_pulse_source;
  KiwiGtkTerminal *terminal;
  KiwiGtkCallbacks callbacks;
  GtkIMContext *im_context;
  KiwiGtkGlPresentation *gl_presentation;
  AdwTabPage *tab_page;
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
static guint64 kiwi_gtk_next_notification_id;

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
  KIWI_GTK_PRODUCT_ACTION_COMMAND_PALETTE = 12,
  KIWI_GTK_PRODUCT_ACTION_OPEN_CONFIGURATION = 13,
};

enum {
  KIWI_GTK_ACCESSIBILITY_MAXIMUM_BYTES = 64 * 1024,
  KIWI_GTK_NOTIFICATION_BODY_MAXIMUM_BYTES = 1024,
  KIWI_GTK_NOTIFICATION_TITLE_MAXIMUM_BYTES = 128,
  KIWI_GTK_TEXT_INPUT_MAXIMUM_BYTES = 1024,
};

static int kiwi_gtk_pointer_shape_supported(const char *shape) {
  static const char *const shapes[] = {
      "auto", "cell", "col-resize", "crosshair", "default", "e-resize",
      "ew-resize", "move", "n-resize", "ne-resize", "nesw-resize", "no-drop",
      "not-allowed", "ns-resize", "nw-resize", "nwse-resize", "pointer",
      "row-resize", "s-resize", "se-resize", "sw-resize", "text", "vertical-text",
      "w-resize",
  };
  if (shape == NULL || !g_utf8_validate(shape, -1, NULL) || strlen(shape) > 32) return 0;
  for (size_t index = 0; index < G_N_ELEMENTS(shapes); index += 1) {
    if (g_str_equal(shape, shapes[index])) return 1;
  }
  return 0;
}

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
  { KIWI_GTK_PRODUCT_ACTION_COMMAND_PALETTE, "command-palette" },
  { KIWI_GTK_PRODUCT_ACTION_OPEN_CONFIGURATION, "open-configuration" },
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

G_DEFINE_TYPE_WITH_CODE(KiwiGtkTerminal, kiwi_gtk_terminal, GTK_TYPE_WIDGET,
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

#if GTK_CHECK_VERSION(4, 16, 0)
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
#endif

static void kiwi_gtk_terminal_accessible_text_init(GtkAccessibleTextInterface *interface) {
  interface->get_contents = kiwi_gtk_terminal_contents;
  interface->get_contents_at = kiwi_gtk_terminal_contents_at;
  interface->get_caret_position = kiwi_gtk_terminal_caret_position;
  interface->get_selection = kiwi_gtk_terminal_selection;
  interface->get_attributes = kiwi_gtk_terminal_attributes;
  interface->get_default_attributes = kiwi_gtk_terminal_default_attributes;
#if GTK_CHECK_VERSION(4, 16, 0)
  interface->get_extents = kiwi_gtk_terminal_extents;
  interface->get_offset = kiwi_gtk_terminal_offset;
#endif
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

#ifdef GDK_WINDOWING_WAYLAND
typedef struct KiwiGtkWaylandRegistry {
  struct wl_subcompositor *subcompositor;
  struct wp_viewporter *viewporter;
} KiwiGtkWaylandRegistry;
#endif

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

struct KiwiGtkCommandPalette {
  KiwiGtkHost *host;
  GtkWidget *dialog;
  GtkSearchEntry *search;
  GtkListBox *list;
  KiwiGtkProductActionCallback callback;
  void *userdata;
};

static GtkListBoxRow *kiwi_gtk_command_palette_first_visible(KiwiGtkCommandPalette *palette) {
  for (GtkWidget *child = gtk_widget_get_first_child(GTK_WIDGET(palette->list)); child != NULL;
       child = gtk_widget_get_next_sibling(child)) {
    if (gtk_widget_get_visible(child)) return GTK_LIST_BOX_ROW(child);
  }
  return NULL;
}

static void kiwi_gtk_command_palette_refresh(KiwiGtkCommandPalette *palette) {
  const char *query = gtk_editable_get_text(GTK_EDITABLE(palette->search));
  char *needle = g_utf8_strdown(query == NULL ? "" : query, -1);
  for (GtkWidget *child = gtk_widget_get_first_child(GTK_WIDGET(palette->list)); child != NULL;
       child = gtk_widget_get_next_sibling(child)) {
    const char *title = g_object_get_data(G_OBJECT(child), "kiwi-command-palette-title");
    const char *description = g_object_get_data(G_OBJECT(child), "kiwi-command-palette-description");
    char *combined = g_strconcat(title == NULL ? "" : title, "\n",
                                 description == NULL ? "" : description, NULL);
    char *haystack = g_utf8_strdown(combined, -1);
    gboolean visible = needle == NULL || needle[0] == '\0' || g_strstr_len(haystack, -1, needle) != NULL;
    gtk_widget_set_visible(child, visible);
    g_free(combined);
    g_free(haystack);
  }
  g_free(needle);
  GtkListBoxRow *first = kiwi_gtk_command_palette_first_visible(palette);
  gtk_list_box_select_row(palette->list, first);
}

static void kiwi_gtk_command_palette_destroyed(GtkWidget *widget, gpointer userdata) {
  (void)widget;
  KiwiGtkCommandPalette *palette = userdata;
  if (palette->host != NULL && palette->host->command_palette == palette) {
    palette->host->command_palette = NULL;
  }
  palette->dialog = NULL;
  g_free(palette);
}

void kiwi_gtk_host_command_palette_remove(KiwiGtkHost *host) {
  if (host == NULL || host->command_palette == NULL) return;
  KiwiGtkCommandPalette *palette = host->command_palette;
  host->command_palette = NULL;
  if (palette->dialog != NULL) {
    gtk_window_destroy(GTK_WINDOW(palette->dialog));
  } else {
    g_free(palette);
  }
}

static void kiwi_gtk_command_palette_invoke(KiwiGtkCommandPalette *palette, GtkListBoxRow *row) {
  if (palette == NULL || row == NULL) return;
  uint32_t action = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(row), "kiwi-command-palette-action"));
  KiwiGtkProductActionCallback callback = palette->callback;
  void *userdata = palette->userdata;
  KiwiGtkHost *host = palette->host;
  kiwi_gtk_host_command_palette_remove(host);
  if (callback != NULL) callback(userdata, action);
}

static void kiwi_gtk_command_palette_query_changed(GtkEditable *editable, gpointer userdata) {
  (void)editable;
  kiwi_gtk_command_palette_refresh(userdata);
}

static void kiwi_gtk_command_palette_activate(GtkSearchEntry *search, gpointer userdata) {
  (void)search;
  KiwiGtkCommandPalette *palette = userdata;
  GtkListBoxRow *row = gtk_list_box_get_selected_row(palette->list);
  if (row == NULL) row = kiwi_gtk_command_palette_first_visible(palette);
  kiwi_gtk_command_palette_invoke(palette, row);
}

static void kiwi_gtk_command_palette_row_activated(GtkListBox *list, GtkListBoxRow *row,
                                                    gpointer userdata) {
  (void)list;
  kiwi_gtk_command_palette_invoke(userdata, row);
}

static void kiwi_gtk_command_palette_run(GtkButton *button, gpointer userdata) {
  (void)button;
  KiwiGtkCommandPalette *palette = userdata;
  GtkListBoxRow *row = gtk_list_box_get_selected_row(palette->list);
  if (row == NULL) row = kiwi_gtk_command_palette_first_visible(palette);
  kiwi_gtk_command_palette_invoke(palette, row);
}

static void kiwi_gtk_command_palette_cancel(GtkButton *button, gpointer userdata) {
  (void)button;
  KiwiGtkCommandPalette *palette = userdata;
  kiwi_gtk_host_command_palette_remove(palette->host);
}

static gboolean kiwi_gtk_command_palette_close(GtkWindow *window, gpointer userdata) {
  (void)window;
  KiwiGtkCommandPalette *palette = userdata;
  kiwi_gtk_host_command_palette_remove(palette->host);
  return TRUE;
}

static gboolean kiwi_gtk_command_palette_key_pressed(GtkEventControllerKey *controller,
                                                      guint keyval, guint keycode,
                                                      GdkModifierType state,
                                                      gpointer userdata) {
  (void)controller;
  (void)keycode;
  (void)state;
  if (keyval != GDK_KEY_Escape) return FALSE;
  KiwiGtkCommandPalette *palette = userdata;
  kiwi_gtk_host_command_palette_remove(palette->host);
  return TRUE;
}

int kiwi_gtk_host_command_palette_show(KiwiGtkHost *host,
                                       const KiwiGtkCommandPaletteEntry *entries,
                                       size_t count, KiwiGtkProductActionCallback callback,
                                       void *userdata) {
  if (host == NULL || host->window == NULL || entries == NULL || callback == NULL ||
      count == 0 || count > 32) {
    kiwi_gtk_set_error("GTK command palette needs a host, callback, and one through 32 entries");
    return 0;
  }
  for (size_t index = 0; index < count; index += 1) {
    if (kiwi_gtk_product_action(entries[index].action) == NULL ||
        entries[index].action == KIWI_GTK_PRODUCT_ACTION_COMMAND_PALETTE ||
        entries[index].title == NULL || entries[index].description == NULL ||
        entries[index].title[0] == '\0' || strlen(entries[index].title) > 128 ||
        strlen(entries[index].description) > 256 ||
        !g_utf8_validate(entries[index].title, -1, NULL) ||
        !g_utf8_validate(entries[index].description, -1, NULL)) {
      kiwi_gtk_set_error("GTK command palette received an invalid bounded UTF-8 entry");
      return 0;
    }
  }
  kiwi_gtk_host_command_palette_remove(host);
  KiwiGtkCommandPalette *palette = g_new0(KiwiGtkCommandPalette, 1);
  palette->host = host;
  palette->callback = callback;
  palette->userdata = userdata;
  palette->dialog = gtk_window_new();
  gtk_window_set_title(GTK_WINDOW(palette->dialog), "Command Palette");
  gtk_window_set_modal(GTK_WINDOW(palette->dialog), TRUE);
  gtk_window_set_transient_for(GTK_WINDOW(palette->dialog), GTK_WINDOW(host->window));
  gtk_window_set_default_size(GTK_WINDOW(palette->dialog), 520, 340);
  GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_margin_top(content, 12);
  gtk_widget_set_margin_bottom(content, 12);
  gtk_widget_set_margin_start(content, 12);
  gtk_widget_set_margin_end(content, 12);
  palette->search = GTK_SEARCH_ENTRY(gtk_search_entry_new());
  gtk_editable_set_text(GTK_EDITABLE(palette->search), "");
  gtk_search_entry_set_placeholder_text(palette->search, "Type to filter actions");
  gtk_box_append(GTK_BOX(content), GTK_WIDGET(palette->search));
  GtkWidget *scroll = gtk_scrolled_window_new();
  gtk_widget_set_vexpand(scroll, TRUE);
  gtk_widget_set_margin_top(scroll, 8);
  palette->list = GTK_LIST_BOX(gtk_list_box_new());
  gtk_list_box_set_selection_mode(palette->list, GTK_SELECTION_SINGLE);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), GTK_WIDGET(palette->list));
  gtk_box_append(GTK_BOX(content), scroll);
  for (size_t index = 0; index < count; index += 1) {
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_margin_top(box, 6);
    gtk_widget_set_margin_bottom(box, 6);
    gtk_widget_set_margin_start(box, 8);
    gtk_widget_set_margin_end(box, 8);
    GtkWidget *title = gtk_label_new(entries[index].title);
    gtk_label_set_xalign(GTK_LABEL(title), 0.0f);
    gtk_widget_add_css_class(title, "heading");
    GtkWidget *description = gtk_label_new(entries[index].description);
    gtk_label_set_xalign(GTK_LABEL(description), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(description), TRUE);
    gtk_widget_add_css_class(description, "dim-label");
    gtk_box_append(GTK_BOX(box), title);
    gtk_box_append(GTK_BOX(box), description);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
    g_object_set_data(G_OBJECT(row), "kiwi-command-palette-action",
                      GUINT_TO_POINTER(entries[index].action));
    g_object_set_data_full(G_OBJECT(row), "kiwi-command-palette-title",
                           g_strdup(entries[index].title), g_free);
    g_object_set_data_full(G_OBJECT(row), "kiwi-command-palette-description",
                           g_strdup(entries[index].description), g_free);
    gtk_list_box_append(palette->list, row);
  }
  GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_set_halign(actions, GTK_ALIGN_END);
  gtk_widget_set_margin_top(actions, 12);
  GtkWidget *cancel = gtk_button_new_with_label("Cancel");
  GtkWidget *run = gtk_button_new_with_label("Run");
  gtk_widget_add_css_class(run, "suggested-action");
  gtk_box_append(GTK_BOX(actions), cancel);
  gtk_box_append(GTK_BOX(actions), run);
  gtk_box_append(GTK_BOX(content), actions);
  gtk_window_set_child(GTK_WINDOW(palette->dialog), content);
  gtk_window_set_default_widget(GTK_WINDOW(palette->dialog), run);
  GtkEventController *key = gtk_event_controller_key_new();
  g_signal_connect(key, "key-pressed", G_CALLBACK(kiwi_gtk_command_palette_key_pressed), palette);
  gtk_widget_add_controller(palette->dialog, key);
  g_signal_connect(palette->search, "changed", G_CALLBACK(kiwi_gtk_command_palette_query_changed), palette);
  g_signal_connect(palette->search, "activate", G_CALLBACK(kiwi_gtk_command_palette_activate), palette);
  g_signal_connect(palette->list, "row-activated", G_CALLBACK(kiwi_gtk_command_palette_row_activated), palette);
  g_signal_connect(cancel, "clicked", G_CALLBACK(kiwi_gtk_command_palette_cancel), palette);
  g_signal_connect(run, "clicked", G_CALLBACK(kiwi_gtk_command_palette_run), palette);
  g_signal_connect(palette->dialog, "close-request", G_CALLBACK(kiwi_gtk_command_palette_close), palette);
  g_signal_connect(palette->dialog, "destroy", G_CALLBACK(kiwi_gtk_command_palette_destroyed), palette);
  host->command_palette = palette;
  kiwi_gtk_command_palette_refresh(palette);
  gtk_window_present(GTK_WINDOW(palette->dialog));
  gtk_widget_grab_focus(GTK_WIDGET(palette->search));
  return 1;
}

int kiwi_gtk_host_command_palette_invoke_smoke(KiwiGtkHost *host) {
  if (host == NULL || host->command_palette == NULL || host->command_palette->dialog == NULL) {
    kiwi_gtk_set_error("GTK command palette smoke needs an active palette");
    return 0;
  }
  GtkListBoxRow *row = gtk_list_box_get_selected_row(host->command_palette->list);
  if (row == NULL) row = kiwi_gtk_command_palette_first_visible(host->command_palette);
  if (row == NULL) {
    kiwi_gtk_set_error("GTK command palette smoke needs a visible palette entry");
    return 0;
  }
  kiwi_gtk_command_palette_invoke(host->command_palette, row);
  return 1;
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
  g_menu_append(file, "Command Palette", "win.command-palette");
  g_menu_append(file, "Settings", "win.open-configuration");
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

#ifdef GDK_WINDOWING_WAYLAND
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
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  int width = terminal == NULL ? 0 : gtk_widget_get_width(terminal->content);
  int height = terminal == NULL ? 0 : gtk_widget_get_height(terminal->content);
  if (host->presentation_surface == NULL || host->presentation_viewport == NULL ||
      width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK Wayland host has no nonzero presentation viewport");
    return 0;
  }
  wl_surface_set_buffer_scale(host->presentation_surface, 1);
  wp_viewport_set_destination(host->presentation_viewport, width, height);
  return 1;
}
#endif

static uint32_t kiwi_gtk_modifiers(GdkModifierType state) {
  uint32_t result = 0;
  if ((state & GDK_SHIFT_MASK) != 0) result |= 1;
  if ((state & GDK_CONTROL_MASK) != 0) result |= 2;
  if ((state & GDK_ALT_MASK) != 0) result |= 4;
  if ((state & GDK_SUPER_MASK) != 0) result |= 8;
  return result;
}

static uint32_t kiwi_gtk_unicode_scalar(guint keyval) {
  uint32_t value = gdk_keyval_to_unicode(keyval);
  if (value < 0x20 || value > 0x10ffff || (value >= 0x7f && value <= 0x9f) ||
      (value >= 0xd800 && value <= 0xdfff)) {
    return 0;
  }
  return value;
}

uint32_t kiwi_gtk_host_pc101_base_key(uint32_t keycode) {
  /* GTK normalizes Wayland evdev input to the standard XKB keycode space. */
  switch (keycode) {
    case 10: return '1'; case 11: return '2'; case 12: return '3';
    case 13: return '4'; case 14: return '5'; case 15: return '6';
    case 16: return '7'; case 17: return '8'; case 18: return '9';
    case 19: return '0'; case 20: return '-'; case 21: return '=';
    case 24: return 'q'; case 25: return 'w'; case 26: return 'e';
    case 27: return 'r'; case 28: return 't'; case 29: return 'y';
    case 30: return 'u'; case 31: return 'i'; case 32: return 'o';
    case 33: return 'p'; case 34: return '['; case 35: return ']';
    case 38: return 'a'; case 39: return 's'; case 40: return 'd';
    case 41: return 'f'; case 42: return 'g'; case 43: return 'h';
    case 44: return 'j'; case 45: return 'k'; case 46: return 'l';
    case 47: return ';'; case 48: return '\''; case 49: return '`';
    case 51: return '\\';
    case 52: return 'z'; case 53: return 'x'; case 54: return 'c';
    case 55: return 'v'; case 56: return 'b'; case 57: return 'n';
    case 58: return 'm'; case 59: return ','; case 60: return '.';
    case 61: return '/'; case 65: return ' ';
    default: return 0;
  }
}

static void kiwi_gtk_key_variants(KiwiGtkTerminalPresentation *presentation,
                                  int group, uint32_t keycode,
                                  KiwiGtkKeyEvent *event) {
  event->base_key = kiwi_gtk_host_pc101_base_key(keycode);
  if (presentation == NULL || presentation->content == NULL || keycode == 0) return;

  GdkDisplay *display = gtk_widget_get_display(presentation->content);
  GdkKeymapKey *keys = NULL;
  guint *keyvals = NULL;
  int entries = 0;
  if (display == NULL || group < 0) return;
  if (!gdk_display_map_keycode(display, keycode, &keys, &keyvals, &entries)) {
    g_free(keys);
    g_free(keyvals);
    return;
  }

  for (int index = 0; index < entries; index += 1) {
    if (keys[index].group != group) continue;
    uint32_t scalar = kiwi_gtk_unicode_scalar(keyvals[index]);
    if (scalar == 0) continue;
    if (keys[index].level == 0 && event->layout_key == 0) {
      event->layout_key = scalar;
    } else if (keys[index].level == 1 && event->shifted_key == 0) {
      event->shifted_key = scalar;
    }
  }
  g_free(keys);
  g_free(keyvals);
}

static uint32_t kiwi_gtk_dispatch_key(KiwiGtkTerminalPresentation *presentation,
                                      GtkEventControllerKey *controller,
                                      guint keyval, guint keycode,
                                      GdkModifierType state, int action) {
  if (presentation == NULL || presentation->callbacks.key == NULL) return 0;
  KiwiGtkKeyEvent event = {
    .struct_size = sizeof(event),
    .keyval = keyval,
    .unicode_key = kiwi_gtk_unicode_scalar(keyval),
    .keycode = keycode,
    .modifiers = kiwi_gtk_modifiers(state),
    .action = action,
  };
  int group = controller == NULL ? 0 : gtk_event_controller_key_get_group(controller);
  kiwi_gtk_key_variants(presentation, group, keycode, &event);
  return presentation->callbacks.key(presentation->callbacks.userdata, &event);
}

static gboolean kiwi_gtk_close(GtkWindow *window, gpointer userdata) {
  (void)window;
  KiwiGtkHost *host = userdata;
  host->should_close = 1;
  return TRUE;
}

static void kiwi_gtk_resize(GtkWidget *widget, int width, int height, gpointer userdata) {
  KiwiGtkTerminalPresentation *presentation = userdata;
  KiwiGtkHost *host = presentation->host;
  host->surface = gtk_native_get_surface(GTK_NATIVE(host->window));
  if (presentation->callbacks.resize != NULL) {
    double scale = host->surface == NULL ? 1.0 : gdk_surface_get_scale(host->surface);
    presentation->callbacks.resize(presentation->callbacks.userdata, width, height,
                                   scale > 0.0 ? scale : 1.0);
  }
  (void)widget;
}

static void kiwi_gtk_resize_property(GObject *object, GParamSpec *parameter,
                                     gpointer userdata) {
  (void)parameter;
  GtkWidget *widget = GTK_WIDGET(object);
  kiwi_gtk_resize(widget, gtk_widget_get_width(widget), gtk_widget_get_height(widget),
                  userdata);
}

static gboolean kiwi_gtk_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer userdata) {
  KiwiGtkTerminalPresentation *presentation = userdata;
  uint32_t result = kiwi_gtk_dispatch_key(presentation, controller, keyval, keycode, state,
                                          KIWI_GTK_ACTION_PRESS);
  return (result & KIWI_GTK_INPUT_HANDLED) != 0 &&
         (result & KIWI_GTK_INPUT_DEFER_TEXT) == 0;
}

static void kiwi_gtk_key_released(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer userdata) {
  KiwiGtkTerminalPresentation *presentation = userdata;
  kiwi_gtk_dispatch_key(presentation, controller, keyval, keycode, state,
                        KIWI_GTK_ACTION_RELEASE);
}

static void kiwi_gtk_im_commit(GtkIMContext *context, const char *text, gpointer userdata) {
  (void)context;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (text == NULL || presentation->callbacks.text == NULL) return;
  size_t text_bytes = strlen(text);
  if (text_bytes == 0) return;
  if (text_bytes > KIWI_GTK_TEXT_INPUT_MAXIMUM_BYTES ||
      !g_utf8_validate(text, (gssize)text_bytes, NULL)) {
    kiwi_gtk_set_error("GTK input method committed invalid or oversized UTF-8");
    return;
  }
  presentation->callbacks.text(presentation->callbacks.userdata, text, text_bytes);
}

static void kiwi_gtk_im_preedit_changed(GtkIMContext *context, gpointer userdata) {
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->callbacks.preedit == NULL) return;
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
    presentation->callbacks.preedit(presentation->callbacks.userdata, text, text_bytes,
                                    cursor_offset, cursor_offset);
  }
  if (attributes != NULL) pango_attr_list_unref(attributes);
  g_free(text);
}

static void kiwi_gtk_focus_enter(GtkEventControllerFocus *controller, gpointer userdata) {
  (void)controller;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->callbacks.focus != NULL) {
    presentation->callbacks.focus(presentation->callbacks.userdata, 1);
  }
}

static void kiwi_gtk_focus_leave(GtkEventControllerFocus *controller, gpointer userdata) {
  (void)controller;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->im_context != NULL) gtk_im_context_reset(presentation->im_context);
  if (presentation->callbacks.focus != NULL) {
    presentation->callbacks.focus(presentation->callbacks.userdata, 0);
  }
}

static void kiwi_gtk_motion(GtkEventControllerMotion *controller, double x, double y, gpointer userdata) {
  (void)controller;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->callbacks.pointer != NULL) {
    presentation->callbacks.pointer(presentation->callbacks.userdata,
                                    KIWI_GTK_POINTER_MOTION, x, y, 0.0, 0.0, 0, 0, 0);
  }
}

static void kiwi_gtk_click_pressed(GtkGestureClick *gesture, int presses, double x, double y, gpointer userdata) {
  (void)presses;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->callbacks.pointer != NULL) {
    presentation->callbacks.pointer(presentation->callbacks.userdata,
                                    KIWI_GTK_POINTER_BUTTON, x, y, 0.0, 0.0,
                                    gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture)),
                                    KIWI_GTK_ACTION_PRESS, 0);
  }
}

static void kiwi_gtk_click_released(GtkGestureClick *gesture, int presses, double x, double y, gpointer userdata) {
  (void)presses;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->callbacks.pointer != NULL) {
    presentation->callbacks.pointer(presentation->callbacks.userdata,
                                    KIWI_GTK_POINTER_BUTTON, x, y, 0.0, 0.0,
                                    gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture)),
                                    KIWI_GTK_ACTION_RELEASE, 0);
  }
}

static gboolean kiwi_gtk_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer userdata) {
  (void)controller;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation->callbacks.pointer != NULL) {
    presentation->callbacks.pointer(presentation->callbacks.userdata,
                                    KIWI_GTK_POINTER_SCROLL, 0.0, 0.0, dx, dy, 0, 0, 0);
  }
  return TRUE;
}

static void kiwi_gtk_gl_area_realize(GtkGLArea *area, gpointer userdata) {
  KiwiGtkGlPresentation *presentation = userdata;
  gtk_gl_area_make_current(area);
  if (gtk_gl_area_get_error(area) != NULL) {
    presentation->realized = 0;
    kiwi_gtk_set_error(gtk_gl_area_get_error(area)->message);
    return;
  }
  presentation->context_generation += 1;
  presentation->realized = 1;
}

static void kiwi_gtk_gl_area_unrealize(GtkGLArea *area, gpointer userdata) {
  (void)area;
  KiwiGtkGlPresentation *presentation = userdata;
  presentation->realized = 0;
}

static gboolean kiwi_gtk_gl_area_render(GtkGLArea *area, GdkGLContext *context,
                                        gpointer userdata) {
  (void)context;
  KiwiGtkGlPresentation *presentation = userdata;
  gtk_gl_area_make_current(area);
  if (gtk_gl_area_get_error(area) != NULL) {
    presentation->realized = 0;
    kiwi_gtk_set_error(gtk_gl_area_get_error(area)->message);
    return FALSE;
  }
  presentation->rendered_frames += 1;
  /* The renderer owns the GtkGLArea render result. This lifecycle observer
   * must not stop signal emission before it has uploaded and drawn a frame. */
  return FALSE;
}

static void kiwi_gtk_gl_presentation_prepare_destroy(
    KiwiGtkGlPresentation *presentation) {
  if (presentation == NULL) return;
  /* Disconnect the renderer while GtkGLArea is still a live GObject. GTK may
   * emit unmap/unrealize while removing the widget, but the presentation
   * observer remains valid until the owning widget tree is gone. */
  if (presentation->renderer != NULL) {
    kiwi_gtk_gl_renderer_destroy(presentation->renderer);
    presentation->renderer = NULL;
  }
}

static void kiwi_gtk_gl_presentation_destroy(KiwiGtkGlPresentation *presentation) {
  if (presentation == NULL) return;
  kiwi_gtk_gl_presentation_prepare_destroy(presentation);
  /* GtkOverlay/AdwTabView owns the widget tree. Do not unparent a live area
   * during terminal or host teardown: GTK may defer property/focus emission
   * until after removal. The disconnected area is instead released with its
   * owning page/window, while this small presentation record remains valid. */
  presentation->area = NULL;
  g_free(presentation);
}

static int kiwi_gtk_terminal_presentation_enable_gl_renderer(
    KiwiGtkTerminalPresentation *terminal) {
  if (terminal == NULL || terminal->content == NULL) {
    kiwi_gtk_set_error("GTK GL area probe needs a live terminal root");
    return 0;
  }
  if (terminal->gl_presentation != NULL) return 1;
  KiwiGtkGlPresentation *gl_presentation = g_new0(KiwiGtkGlPresentation, 1);
  GtkWidget *area = gtk_gl_area_new();
  gtk_widget_set_hexpand(area, TRUE);
  gtk_widget_set_vexpand(area, TRUE);
  /* Terminal input and accessibility stay on the semantic widget below this
   * visual layer; GtkGLArea is not a competing focus or pointer target. */
  gtk_widget_set_can_target(area, FALSE);
  gl_presentation->area = GTK_GL_AREA(area);
  if (!kiwi_gtk_gl_renderer_configure_area(gl_presentation->area)) {
    kiwi_gtk_set_error("GTK GL area must be configured before realization");
    kiwi_gtk_gl_presentation_destroy(gl_presentation);
    return 0;
  }
  g_signal_connect(area, "realize", G_CALLBACK(kiwi_gtk_gl_area_realize), gl_presentation);
  g_signal_connect(area, "unrealize", G_CALLBACK(kiwi_gtk_gl_area_unrealize), gl_presentation);
  g_signal_connect(area, "render", G_CALLBACK(kiwi_gtk_gl_area_render), gl_presentation);
  gl_presentation->renderer = kiwi_gtk_gl_renderer_new(gl_presentation->area);
  if (gl_presentation->renderer == NULL) {
    kiwi_gtk_set_error("GTK GL renderer could not be constructed");
    kiwi_gtk_gl_presentation_destroy(gl_presentation);
    return 0;
  }
  gtk_overlay_add_overlay(GTK_OVERLAY(terminal->content), area);
  /* GTK4 overlays paint in insertion order. Keep host-owned progress above
   * the optional GL terminal surface without allowing it to take input. */
  if (terminal->progress != NULL) {
    g_object_ref(terminal->progress);
    gtk_overlay_remove_overlay(GTK_OVERLAY(terminal->content),
                               GTK_WIDGET(terminal->progress));
    gtk_overlay_add_overlay(GTK_OVERLAY(terminal->content),
                            GTK_WIDGET(terminal->progress));
    g_object_unref(terminal->progress);
  }
  KiwiGlyphInstance cell = {0};
  cell.bg = UINT32_C(0xff12ab34);
  KiwiGtkGlCellUpdate cell_update = {
      .cells = &cell,
      .first_cell = 0,
      .cell_count = 1,
  };
  KiwiFrameUniform frame = {0};
  frame.columns = 1;
  frame.rows = 1;
  KiwiGtkGlFrame snapshot = {
      .render_model_version = KIWI_RENDER_MODEL_VERSION,
      .revision = 1,
      .cell_updates = &cell_update,
      .cell_update_count = 1,
      .cell_count = 1,
      .frame = &frame,
      .resource_flags = KIWI_GTK_GL_FRAME_CELLS_FULL,
  };
  if (!kiwi_gtk_gl_renderer_submit(gl_presentation->renderer, &snapshot)) {
    kiwi_gtk_set_error(kiwi_gtk_gl_renderer_last_error(gl_presentation->renderer));
    kiwi_gtk_gl_presentation_destroy(gl_presentation);
    return 0;
  }
  terminal->gl_presentation = gl_presentation;
  return 1;
}

int kiwi_gtk_host_enable_gl_area_probe(KiwiGtkHost *host) {
  return kiwi_gtk_terminal_presentation_enable_gl_renderer(
      host == NULL ? NULL : host->primary_presentation);
}

int kiwi_gtk_host_request_gl_area_render(KiwiGtkHost *host) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->gl_presentation == NULL) {
    kiwi_gtk_set_error("GTK GL area render needs an enabled probe");
    return 0;
  }
  gtk_gl_area_queue_render(terminal->gl_presentation->area);
  return 1;
}

int kiwi_gtk_host_gl_area_state(const KiwiGtkHost *host,
                                uint64_t *context_generation,
                                uint64_t *rendered_frames,
                                int *realized) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->gl_presentation == NULL || context_generation == NULL ||
      rendered_frames == NULL || realized == NULL) {
    kiwi_gtk_set_error("GTK GL area state needs an enabled probe and destinations");
    return 0;
  }
  *context_generation = terminal->gl_presentation->context_generation;
  *rendered_frames = terminal->gl_presentation->rendered_frames;
  *realized = terminal->gl_presentation->realized;
  return 1;
}

uint64_t kiwi_gtk_host_gl_area_rendered_revision(const KiwiGtkHost *host) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  return terminal == NULL || terminal->gl_presentation == NULL ? 0 :
      kiwi_gtk_gl_renderer_rendered_revision(terminal->gl_presentation->renderer);
}

int kiwi_gtk_host_gl_area_upload_metrics(const KiwiGtkHost *host,
                                         uint64_t *cell_full_uploads,
                                         uint64_t *cell_subrange_uploads,
                                         uint64_t *cell_subrange_bytes,
                                         uint64_t *glyph_uploads,
                                         uint64_t *glyph_upload_bytes) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->gl_presentation == NULL || cell_full_uploads == NULL ||
      cell_subrange_uploads == NULL || cell_subrange_bytes == NULL ||
      glyph_uploads == NULL || glyph_upload_bytes == NULL) {
    kiwi_gtk_set_error("GTK GL upload metrics need an enabled renderer and destinations");
    return 0;
  }
  kiwi_gtk_gl_renderer_upload_metrics(terminal->gl_presentation->renderer, cell_full_uploads,
                                      cell_subrange_uploads, cell_subrange_bytes,
                                      glyph_uploads, glyph_upload_bytes);
  return 1;
}

int kiwi_gtk_host_gl_area_submit_snapshot(KiwiGtkHost *host,
                                           const KiwiGtkGlFrame *snapshot) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->gl_presentation == NULL) {
    kiwi_gtk_set_error("GTK GL snapshot needs an enabled renderer");
    return 0;
  }
  if (kiwi_gtk_gl_renderer_submit(terminal->gl_presentation->renderer, snapshot)) return 1;
  kiwi_gtk_set_error(kiwi_gtk_gl_renderer_last_error(terminal->gl_presentation->renderer));
  return 0;
}

static void kiwi_gtk_terminal_progress_stop(
    KiwiGtkTerminalPresentation *presentation) {
  if (presentation != NULL && presentation->progress_pulse_source != 0) {
    g_source_remove(presentation->progress_pulse_source);
    presentation->progress_pulse_source = 0;
  }
}

static gboolean kiwi_gtk_terminal_progress_pulse(gpointer userdata) {
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation == NULL || presentation->progress == NULL ||
      !gtk_widget_get_visible(GTK_WIDGET(presentation->progress))) {
    if (presentation != NULL) presentation->progress_pulse_source = 0;
    return G_SOURCE_REMOVE;
  }
  gtk_progress_bar_pulse(presentation->progress);
  return G_SOURCE_CONTINUE;
}

int kiwi_gtk_terminal_presentation_set_progress(
    KiwiGtkTerminalPresentation *presentation, uint32_t progress, uint32_t state) {
  if (presentation == NULL || presentation->progress == NULL || progress > 100 || state > 4) {
    kiwi_gtk_set_error("GTK terminal progress needs a live presentation, state 0 through 4, and progress 0 through 100");
    return 0;
  }
  GtkWidget *widget = GTK_WIDGET(presentation->progress);
  kiwi_gtk_terminal_progress_stop(presentation);
  gtk_widget_remove_css_class(widget, "error");
  gtk_widget_remove_css_class(widget, "warning");
  if (state == 0) {
    gtk_widget_set_visible(widget, FALSE);
    gtk_progress_bar_set_fraction(presentation->progress, 0.0);
    gtk_progress_bar_set_text(presentation->progress, NULL);
    gtk_widget_set_tooltip_text(widget, NULL);
    return 1;
  }

  gtk_widget_set_visible(widget, TRUE);
  gtk_progress_bar_set_show_text(presentation->progress, TRUE);
  if (state == 3) {
    gtk_progress_bar_set_text(presentation->progress, "Terminal task is running");
    gtk_widget_set_tooltip_text(widget, "Terminal task is running");
    gtk_progress_bar_pulse(presentation->progress);
    presentation->progress_pulse_source = g_timeout_add(100,
        kiwi_gtk_terminal_progress_pulse, presentation);
    return 1;
  }

  gtk_progress_bar_set_fraction(presentation->progress, (double)progress / 100.0);
  if (state == 1) {
    char text[32];
    g_snprintf(text, sizeof(text), "%u%%", progress);
    gtk_progress_bar_set_text(presentation->progress, text);
    gtk_widget_set_tooltip_text(widget, "Terminal task progress");
  } else if (state == 2) {
    char text[64];
    g_snprintf(text, sizeof(text), "Terminal task failed (%u%%)", progress);
    gtk_widget_add_css_class(widget, "error");
    gtk_progress_bar_set_text(presentation->progress, text);
    gtk_widget_set_tooltip_text(widget, "Terminal task failed");
  } else {
    char text[64];
    g_snprintf(text, sizeof(text), "Terminal task paused (%u%%)", progress);
    gtk_widget_add_css_class(widget, "warning");
    gtk_progress_bar_set_text(presentation->progress, text);
    gtk_widget_set_tooltip_text(widget, "Terminal task paused");
  }
  return 1;
}

int kiwi_gtk_terminal_presentation_progress_round_trip(
    KiwiGtkTerminalPresentation *presentation) {
  if (!kiwi_gtk_terminal_presentation_set_progress(presentation, 73, 1) ||
      !gtk_widget_get_visible(GTK_WIDGET(presentation->progress)) ||
      gtk_progress_bar_get_fraction(presentation->progress) != 0.73 ||
      g_strcmp0(gtk_progress_bar_get_text(presentation->progress), "73%") != 0) {
    kiwi_gtk_set_error("GTK terminal progress did not retain a determinate value");
    return 0;
  }
  if (!kiwi_gtk_terminal_presentation_set_progress(presentation, 73, 2) ||
      !gtk_widget_has_css_class(GTK_WIDGET(presentation->progress), "error") ||
      g_strcmp0(gtk_progress_bar_get_text(presentation->progress),
                 "Terminal task failed (73%)") != 0) {
    kiwi_gtk_set_error("GTK terminal progress did not retain an error state");
    return 0;
  }
  if (!kiwi_gtk_terminal_presentation_set_progress(presentation, 0, 3) ||
      presentation->progress_pulse_source == 0) {
    kiwi_gtk_set_error("GTK terminal progress did not retain an indeterminate state");
    return 0;
  }
  if (!kiwi_gtk_terminal_presentation_set_progress(presentation, 73, 4) ||
      presentation->progress_pulse_source != 0 ||
      !gtk_widget_has_css_class(GTK_WIDGET(presentation->progress), "warning") ||
      g_strcmp0(gtk_progress_bar_get_text(presentation->progress),
                 "Terminal task paused (73%)") != 0) {
    kiwi_gtk_set_error("GTK terminal progress did not retain a paused state");
    return 0;
  }
  if (!kiwi_gtk_terminal_presentation_set_progress(presentation, 0, 0) ||
      gtk_widget_get_visible(GTK_WIDGET(presentation->progress)) ||
      presentation->progress_pulse_source != 0) {
    kiwi_gtk_set_error("GTK terminal progress did not clear");
    return 0;
  }
  return 1;
}

static void kiwi_gtk_terminal_presentation_dispose(
    KiwiGtkTerminalPresentation *presentation) {
  if (presentation == NULL) return;
  kiwi_gtk_terminal_progress_stop(presentation);
  kiwi_gtk_gl_presentation_prepare_destroy(presentation->gl_presentation);
}

static void kiwi_gtk_terminal_presentation_destroy(
    KiwiGtkTerminalPresentation *presentation) {
  if (presentation == NULL) return;
  kiwi_gtk_gl_presentation_destroy(presentation->gl_presentation);
  presentation->gl_presentation = NULL;
  g_free(presentation);
}

static KiwiGtkTerminalPresentation *kiwi_gtk_terminal_presentation_new(
    KiwiGtkHost *host, const KiwiGtkCallbacks *callbacks) {
  if (host == NULL || callbacks == NULL) return NULL;
  KiwiGtkTerminalPresentation *presentation = g_new0(KiwiGtkTerminalPresentation, 1);
  presentation->host = host;
  presentation->callbacks = *callbacks;
  presentation->content = gtk_overlay_new();
  presentation->progress = GTK_PROGRESS_BAR(gtk_progress_bar_new());
  presentation->terminal = KIWI_GTK_TERMINAL(
      g_object_new(KIWI_TYPE_GTK_TERMINAL, NULL));
  gtk_widget_set_hexpand(presentation->content, TRUE);
  gtk_widget_set_vexpand(presentation->content, TRUE);
  gtk_widget_set_hexpand(GTK_WIDGET(presentation->terminal), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(presentation->terminal), TRUE);
  gtk_overlay_set_child(GTK_OVERLAY(presentation->content),
                        GTK_WIDGET(presentation->terminal));
  gtk_widget_set_halign(GTK_WIDGET(presentation->progress), GTK_ALIGN_FILL);
  gtk_widget_set_valign(GTK_WIDGET(presentation->progress), GTK_ALIGN_START);
  gtk_widget_set_margin_start(GTK_WIDGET(presentation->progress), 12);
  gtk_widget_set_margin_end(GTK_WIDGET(presentation->progress), 12);
  gtk_widget_set_margin_top(GTK_WIDGET(presentation->progress), 8);
  gtk_widget_set_can_target(GTK_WIDGET(presentation->progress), FALSE);
  gtk_widget_set_focusable(GTK_WIDGET(presentation->progress), FALSE);
  gtk_widget_add_css_class(GTK_WIDGET(presentation->progress), "osd");
  gtk_widget_set_visible(GTK_WIDGET(presentation->progress), FALSE);
  gtk_overlay_add_overlay(GTK_OVERLAY(presentation->content),
                          GTK_WIDGET(presentation->progress));
  g_signal_connect(presentation->terminal, "notify::width",
                   G_CALLBACK(kiwi_gtk_resize_property), presentation);
  g_signal_connect(presentation->terminal, "notify::height",
                   G_CALLBACK(kiwi_gtk_resize_property), presentation);

  GtkEventControllerKey *key = GTK_EVENT_CONTROLLER_KEY(gtk_event_controller_key_new());
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(key), GTK_PHASE_CAPTURE);
  g_signal_connect(key, "key-pressed", G_CALLBACK(kiwi_gtk_key_pressed), presentation);
  g_signal_connect(key, "key-released", G_CALLBACK(kiwi_gtk_key_released), presentation);
  gtk_widget_add_controller(GTK_WIDGET(presentation->terminal),
                            GTK_EVENT_CONTROLLER(key));

  GtkEventControllerKey *im_key = GTK_EVENT_CONTROLLER_KEY(gtk_event_controller_key_new());
  GtkIMContext *im_context = gtk_im_multicontext_new();
  gtk_im_context_set_client_widget(im_context, GTK_WIDGET(presentation->terminal));
  g_signal_connect(im_context, "commit", G_CALLBACK(kiwi_gtk_im_commit), presentation);
  g_signal_connect(im_context, "preedit-changed", G_CALLBACK(kiwi_gtk_im_preedit_changed),
                   presentation);
  gtk_event_controller_key_set_im_context(im_key, im_context);
  presentation->im_context = gtk_event_controller_key_get_im_context(im_key);
  g_object_unref(im_context);
  gtk_widget_add_controller(GTK_WIDGET(presentation->terminal),
                            GTK_EVENT_CONTROLLER(im_key));

  GtkEventController *focus = gtk_event_controller_focus_new();
  g_signal_connect(focus, "enter", G_CALLBACK(kiwi_gtk_focus_enter), presentation);
  g_signal_connect(focus, "leave", G_CALLBACK(kiwi_gtk_focus_leave), presentation);
  gtk_widget_add_controller(GTK_WIDGET(presentation->terminal), focus);
  GtkEventController *motion = gtk_event_controller_motion_new();
  g_signal_connect(motion, "motion", G_CALLBACK(kiwi_gtk_motion), presentation);
  gtk_widget_add_controller(GTK_WIDGET(presentation->terminal), motion);
  GtkGesture *click = gtk_gesture_click_new();
  g_signal_connect(click, "pressed", G_CALLBACK(kiwi_gtk_click_pressed), presentation);
  g_signal_connect(click, "released", G_CALLBACK(kiwi_gtk_click_released), presentation);
  gtk_widget_add_controller(GTK_WIDGET(presentation->terminal), GTK_EVENT_CONTROLLER(click));
  GtkEventController *scroll = gtk_event_controller_scroll_new(
      GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
  g_signal_connect(scroll, "scroll", G_CALLBACK(kiwi_gtk_scroll), presentation);
  gtk_widget_add_controller(GTK_WIDGET(presentation->terminal), scroll);
  return presentation;
}

static void kiwi_gtk_native_tab_selected(GObject *object, GParamSpec *parameter,
                                         gpointer userdata) {
  (void)object;
  (void)parameter;
  KiwiGtkTerminalPresentation *presentation = userdata;
  if (presentation != NULL && presentation->tab_page != NULL &&
      adw_tab_page_get_selected(presentation->tab_page)) {
    const char *title = adw_tab_page_get_title(presentation->tab_page);
    if (presentation->host != NULL && presentation->host->window != NULL &&
        title != NULL) {
      gtk_window_set_title(GTK_WINDOW(presentation->host->window), title);
    }
    gtk_widget_grab_focus(GTK_WIDGET(presentation->terminal));
  }
}

static KiwiGtkTerminalPresentation *kiwi_gtk_native_tab_presentation(
    KiwiGtkHost *host, AdwTabPage *page) {
  if (host == NULL || host->presentations == NULL || page == NULL) return NULL;
  for (guint index = 0; index < host->presentations->len; index += 1) {
    KiwiGtkTerminalPresentation *presentation =
        g_ptr_array_index(host->presentations, index);
    if (presentation->tab_page == page) return presentation;
  }
  return NULL;
}

static gboolean kiwi_gtk_native_tab_close_requested(
    AdwTabView *view, AdwTabPage *page, gpointer userdata) {
  KiwiGtkHost *host = userdata;
  KiwiGtkTerminalPresentation *presentation =
      kiwi_gtk_native_tab_presentation(host, page);
  if (presentation == NULL) return TRUE;
  if (host->native_tab_programmatic_close == presentation) return FALSE;
  if (host->native_tab_close == NULL) {
    kiwi_gtk_set_error("GTK native tab close needs an application lifecycle handler");
    return TRUE;
  }
  host->native_tab_close_request = presentation;
  (void)host->native_tab_close(host->native_tab_close_userdata, presentation);
  if (host->native_tab_close_request == presentation) {
    host->native_tab_close_request = NULL;
  }
  (void)view;
  return TRUE;
}

static int kiwi_gtk_native_tab_attach(KiwiGtkHost *host,
                                      KiwiGtkTerminalPresentation *presentation,
                                      const char *title) {
  if (host == NULL || host->tab_view == NULL || presentation == NULL ||
      presentation->content == NULL || title == NULL || title[0] == '\0' ||
      !g_utf8_validate(title, -1, NULL)) {
    kiwi_gtk_set_error("GTK native tab needs a terminal presentation and valid title");
    return 0;
  }
  presentation->tab_page = adw_tab_view_append(host->tab_view, presentation->content);
  if (presentation->tab_page == NULL) {
    kiwi_gtk_set_error("GTK native tab could not attach a terminal presentation");
    return 0;
  }
  adw_tab_page_set_title(presentation->tab_page, title);
  g_signal_connect(presentation->tab_page, "notify::selected",
                   G_CALLBACK(kiwi_gtk_native_tab_selected), presentation);
  if (host->presentations == NULL) host->presentations = g_ptr_array_new();
  g_ptr_array_add(host->presentations, presentation);
  return 1;
}

static int kiwi_gtk_host_enable_native_tab_container(KiwiGtkHost *host,
                                                       const char *title) {
  if (host == NULL || host->primary_presentation == NULL || host->window == NULL) {
    kiwi_gtk_set_error("GTK native tabs need a live application window");
    return 0;
  }
  if (host->tab_view != NULL) return 1;
  if (title == NULL || title[0] == '\0' || !g_utf8_validate(title, -1, NULL)) {
    kiwi_gtk_set_error("GTK native tabs need a valid initial title");
    return 0;
  }

  host->tab_view = ADW_TAB_VIEW(adw_tab_view_new());
  host->tab_bar = ADW_TAB_BAR(adw_tab_bar_new());
  host->tab_root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_hexpand(GTK_WIDGET(host->tab_view), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(host->tab_view), TRUE);
  adw_tab_bar_set_view(host->tab_bar, host->tab_view);
  adw_tab_bar_set_autohide(host->tab_bar, FALSE);
  g_signal_connect(host->tab_view, "close-page",
                   G_CALLBACK(kiwi_gtk_native_tab_close_requested), host);
  gtk_box_append(GTK_BOX(host->tab_root), GTK_WIDGET(host->tab_bar));
  gtk_box_append(GTK_BOX(host->tab_root), GTK_WIDGET(host->tab_view));

  /* GtkWindow owns the existing presentation. Retain it over the reparent so
   * its PTY/input/GL state is never reconstructed merely to add tab chrome. */
  g_object_ref(host->primary_presentation->content);
  gtk_window_set_child(GTK_WINDOW(host->window), NULL);
  if (!kiwi_gtk_native_tab_attach(host, host->primary_presentation, title)) {
    gtk_window_set_child(GTK_WINDOW(host->window), host->primary_presentation->content);
    g_object_unref(host->primary_presentation->content);
    g_object_unref(host->tab_root);
    host->tab_root = NULL;
    host->tab_view = NULL;
    host->tab_bar = NULL;
    return 0;
  }
  gtk_window_set_child(GTK_WINDOW(host->window), host->tab_root);
  g_object_unref(host->primary_presentation->content);
  return 1;
}

int kiwi_gtk_host_native_tab_probe(KiwiGtkHost *host) {
  if (!kiwi_gtk_host_enable_native_tab_container(host, "Kiwi terminal 1")) return 0;
  if (host->presentations == NULL || host->presentations->len != 1) {
    kiwi_gtk_set_error("GTK native tab probe has an invalid initial page");
    return 0;
  }
  KiwiGtkTerminalPresentation *second = kiwi_gtk_terminal_presentation_new(
      host, &host->primary_presentation->callbacks);
  if (second == NULL || !kiwi_gtk_terminal_presentation_enable_gl_renderer(second) ||
      !kiwi_gtk_native_tab_attach(host, second, "Kiwi terminal 2")) {
    kiwi_gtk_terminal_presentation_destroy(second);
    if (second != NULL && host->presentations != NULL) {
      g_ptr_array_remove(host->presentations, second);
    }
    kiwi_gtk_set_error("GTK native tab probe could not create a second terminal presentation");
    return 0;
  }
  adw_tab_view_set_selected_page(host->tab_view, second->tab_page);
  return host->presentations->len == 2 &&
      adw_tab_view_get_selected_page(host->tab_view) == second->tab_page;
}

uint32_t kiwi_gtk_host_native_tab_count(const KiwiGtkHost *host) {
  return host == NULL || host->presentations == NULL ? 0 : host->presentations->len;
}

int kiwi_gtk_host_enable_native_tabs(KiwiGtkHost *host, const char *title) {
  return kiwi_gtk_host_enable_native_tab_container(host, title);
}

KiwiGtkTerminalPresentation *kiwi_gtk_host_primary_presentation(
    KiwiGtkHost *host) {
  return host == NULL ? NULL : host->primary_presentation;
}

KiwiGtkTerminalPresentation *kiwi_gtk_host_native_tab_new(
    KiwiGtkHost *host, const char *title, const KiwiGtkCallbacks *callbacks) {
  if (host == NULL || host->tab_view == NULL || callbacks == NULL) {
    kiwi_gtk_set_error("GTK native tab needs an enabled tab container and callbacks");
    return NULL;
  }
  KiwiGtkTerminalPresentation *presentation =
      kiwi_gtk_terminal_presentation_new(host, callbacks);
  if (presentation == NULL || !kiwi_gtk_terminal_presentation_enable_gl_renderer(presentation) ||
      !kiwi_gtk_native_tab_attach(host, presentation, title)) {
    if (presentation != NULL && host->presentations != NULL) {
      g_ptr_array_remove(host->presentations, presentation);
    }
    kiwi_gtk_terminal_presentation_destroy(presentation);
    kiwi_gtk_set_error("GTK native tab could not create a terminal presentation");
    return NULL;
  }
  adw_tab_view_set_selected_page(host->tab_view, presentation->tab_page);
  return presentation;
}

int kiwi_gtk_host_native_tab_select(KiwiGtkHost *host,
                                    KiwiGtkTerminalPresentation *presentation) {
  if (host == NULL || host->tab_view == NULL || presentation == NULL ||
      presentation->host != host || presentation->tab_page == NULL) {
    kiwi_gtk_set_error("GTK native tab selection needs a live page in this host");
    return 0;
  }
  adw_tab_view_set_selected_page(host->tab_view, presentation->tab_page);
  return 1;
}

int kiwi_gtk_host_native_tab_select_next(KiwiGtkHost *host) {
  if (host == NULL || host->tab_view == NULL || host->presentations == NULL ||
      host->presentations->len < 2) {
    kiwi_gtk_set_error("GTK native next-tab needs at least two live pages");
    return 0;
  }
  AdwTabPage *selected = adw_tab_view_get_selected_page(host->tab_view);
  for (guint index = 0; index < host->presentations->len; index += 1) {
    KiwiGtkTerminalPresentation *current =
        g_ptr_array_index(host->presentations, index);
    if (current->tab_page == selected) {
      KiwiGtkTerminalPresentation *next = g_ptr_array_index(
          host->presentations, (index + 1) % host->presentations->len);
      adw_tab_view_set_selected_page(host->tab_view, next->tab_page);
      return 1;
    }
  }
  kiwi_gtk_set_error("GTK native tab selection has no matching presentation");
  return 0;
}

KiwiGtkTerminalPresentation *kiwi_gtk_host_native_tab_selected(
    KiwiGtkHost *host) {
  if (host == NULL || host->tab_view == NULL) return NULL;
  return kiwi_gtk_native_tab_presentation(host,
                                          adw_tab_view_get_selected_page(host->tab_view));
}

static int kiwi_gtk_host_contains_presentation(const KiwiGtkHost *host,
                                                const KiwiGtkTerminalPresentation *needle) {
  if (host == NULL || host->presentations == NULL || needle == NULL) return 0;
  for (guint index = 0; index < host->presentations->len; index += 1) {
    if (g_ptr_array_index(host->presentations, index) == needle) return 1;
  }
  return 0;
}

int kiwi_gtk_host_native_tab_close(KiwiGtkHost *host,
                                   KiwiGtkTerminalPresentation *presentation) {
  if (!kiwi_gtk_host_contains_presentation(host, presentation) ||
      host->tab_view == NULL || presentation->tab_page == NULL) {
    kiwi_gtk_set_error("GTK native tab close needs a live page in this host");
    return 0;
  }
  if (host->presentations->len < 2 && host->native_tab_close_request != presentation) {
    kiwi_gtk_set_error("GTK native tab close refuses to remove the final page");
    return 0;
  }
  kiwi_gtk_terminal_presentation_dispose(presentation);
  if (host->native_tab_close_request == presentation) {
    host->native_tab_close_request = NULL;
    adw_tab_view_close_page_finish(host->tab_view, presentation->tab_page, TRUE);
  } else {
    host->native_tab_programmatic_close = presentation;
    adw_tab_view_close_page(host->tab_view, presentation->tab_page);
    host->native_tab_programmatic_close = NULL;
  }
  g_ptr_array_remove(host->presentations, presentation);
  presentation->tab_page = NULL;
  /* AdwTabView removes a page synchronously, but GTK may still emit focus and
   * unmap signals from the terminal widget during the enclosing turn. Those
   * controllers retain this presentation as their callback userdata. Keep the
   * small retired owner alive until GtkWindow teardown completes. */
  if (host->retired_presentations == NULL) host->retired_presentations = g_ptr_array_new();
  g_ptr_array_add(host->retired_presentations, presentation);
  /* Let GTK settle the page removal while callback userdata and the detached
   * presentation are both still retained. Bounded nonblocking iterations avoid
   * entering a nested main loop from a close-page signal. */
  for (unsigned int iteration = 0; iteration < 32 && g_main_context_pending(NULL);
       iteration += 1) {
    g_main_context_iteration(NULL, FALSE);
  }
  return 1;
}

int kiwi_gtk_host_set_native_tab_close_handler(
    KiwiGtkHost *host, KiwiGtkNativeTabCloseCallback callback, void *userdata) {
  if (host == NULL || callback == NULL) {
    kiwi_gtk_set_error("GTK native tab close handler needs a host and callback");
    return 0;
  }
  host->native_tab_close = callback;
  host->native_tab_close_userdata = userdata;
  return 1;
}

int kiwi_gtk_terminal_presentation_enable_gl(
    KiwiGtkTerminalPresentation *presentation) {
  return kiwi_gtk_terminal_presentation_enable_gl_renderer(presentation);
}

int kiwi_gtk_terminal_presentation_request_gl_area_render(
    KiwiGtkTerminalPresentation *presentation) {
  if (presentation == NULL || presentation->gl_presentation == NULL) {
    kiwi_gtk_set_error("GTK GL area render needs an enabled presentation");
    return 0;
  }
  gtk_gl_area_queue_render(presentation->gl_presentation->area);
  return 1;
}

int kiwi_gtk_terminal_presentation_gl_area_state(
    const KiwiGtkTerminalPresentation *presentation, uint64_t *context_generation,
    uint64_t *rendered_frames, int *realized) {
  if (presentation == NULL || presentation->gl_presentation == NULL ||
      context_generation == NULL || rendered_frames == NULL || realized == NULL) {
    kiwi_gtk_set_error("GTK GL area state needs an enabled presentation and destinations");
    return 0;
  }
  *context_generation = presentation->gl_presentation->context_generation;
  *rendered_frames = presentation->gl_presentation->rendered_frames;
  *realized = presentation->gl_presentation->realized;
  return 1;
}

uint64_t kiwi_gtk_terminal_presentation_gl_area_rendered_revision(
    const KiwiGtkTerminalPresentation *presentation) {
  return presentation == NULL || presentation->gl_presentation == NULL ? 0 :
      kiwi_gtk_gl_renderer_rendered_revision(presentation->gl_presentation->renderer);
}

int kiwi_gtk_terminal_presentation_gl_area_upload_metrics(
    const KiwiGtkTerminalPresentation *presentation, uint64_t *cell_full_uploads,
    uint64_t *cell_subrange_uploads, uint64_t *cell_subrange_bytes,
    uint64_t *glyph_uploads, uint64_t *glyph_upload_bytes) {
  if (presentation == NULL || presentation->gl_presentation == NULL ||
      cell_full_uploads == NULL || cell_subrange_uploads == NULL ||
      cell_subrange_bytes == NULL || glyph_uploads == NULL || glyph_upload_bytes == NULL) {
    kiwi_gtk_set_error("GTK GL upload metrics need an enabled presentation and destinations");
    return 0;
  }
  kiwi_gtk_gl_renderer_upload_metrics(presentation->gl_presentation->renderer,
                                      cell_full_uploads, cell_subrange_uploads,
                                      cell_subrange_bytes, glyph_uploads,
                                      glyph_upload_bytes);
  return 1;
}

int kiwi_gtk_terminal_presentation_gl_area_submit_snapshot(
    KiwiGtkTerminalPresentation *presentation, const KiwiGtkGlFrame *snapshot) {
  if (presentation == NULL || presentation->gl_presentation == NULL) {
    kiwi_gtk_set_error("GTK GL snapshot needs an enabled presentation");
    return 0;
  }
  if (kiwi_gtk_gl_renderer_submit(presentation->gl_presentation->renderer, snapshot)) return 1;
  kiwi_gtk_set_error(kiwi_gtk_gl_renderer_last_error(presentation->gl_presentation->renderer));
  return 0;
}

void kiwi_gtk_terminal_presentation_drawable_size(
    const KiwiGtkTerminalPresentation *presentation, int *width, int *height) {
  if (width != NULL) *width = presentation == NULL || presentation->content == NULL ? 0 :
      gtk_widget_get_width(presentation->content);
  if (height != NULL) *height = presentation == NULL || presentation->content == NULL ? 0 :
      gtk_widget_get_height(presentation->content);
}

double kiwi_gtk_terminal_presentation_content_scale(
    const KiwiGtkTerminalPresentation *presentation) {
  return presentation == NULL || presentation->content == NULL ? 1.0 :
      gtk_widget_get_scale_factor(presentation->content);
}

int kiwi_gtk_terminal_presentation_set_text_input_caret(
    KiwiGtkTerminalPresentation *presentation, int x, int y, int width, int height) {
  if (presentation == NULL || presentation->im_context == NULL || x < 0 || y < 0 ||
      width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK input method received an invalid caret rectangle");
    return 0;
  }
  GdkRectangle rectangle = { x, y, width, height };
  gtk_im_context_set_cursor_location(presentation->im_context, &rectangle);
  return 1;
}

int kiwi_gtk_terminal_presentation_set_pointer_shape(
    KiwiGtkTerminalPresentation *presentation, const char *shape) {
  if (presentation == NULL || presentation->terminal == NULL ||
      !kiwi_gtk_pointer_shape_supported(shape)) {
    kiwi_gtk_set_error("GTK pointer shape is invalid or unavailable");
    return 0;
  }
  gtk_widget_set_cursor_from_name(GTK_WIDGET(presentation->terminal), shape);
  return 1;
}

int kiwi_gtk_terminal_presentation_accessibility_update(
    KiwiGtkTerminalPresentation *presentation, const char *text, size_t text_bytes,
    uint32_t character_count, int32_t caret_offset, int32_t selection_start,
    int32_t selection_end, int focused, const char *title) {
  if (presentation == NULL || presentation->terminal == NULL) {
    kiwi_gtk_set_error("GTK accessibility update has no terminal widget");
    return 0;
  }
  (void)focused;
  return kiwi_gtk_terminal_update(presentation->terminal, text, text_bytes,
                                  character_count, caret_offset, selection_start,
                                  selection_end, title);
}

void kiwi_gtk_terminal_presentation_set_title(
    KiwiGtkTerminalPresentation *presentation, const char *title) {
  if (presentation == NULL || title == NULL || !g_utf8_validate(title, -1, NULL)) return;
  if (presentation->tab_page != NULL) adw_tab_page_set_title(presentation->tab_page, title);
  if (presentation->host != NULL && presentation->host->window != NULL &&
      (presentation->tab_page == NULL || adw_tab_page_get_selected(presentation->tab_page))) {
    gtk_window_set_title(GTK_WINDOW(presentation->host->window), title);
  }
}

KiwiGtkHost *kiwi_gtk_host_new(const char *application_id, int width, int height, const char *title, const KiwiGtkCallbacks *callbacks) {
  if (application_id == NULL || title == NULL || callbacks == NULL || width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK host received invalid construction arguments");
    return NULL;
  }
  KiwiGtkHost *host = g_new0(KiwiGtkHost, 1);
  adw_init();
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
  g_snprintf(host->notification_id, sizeof(host->notification_id),
             "kiwi-terminal-osc9-%" G_GUINT64_FORMAT,
             ++kiwi_gtk_next_notification_id);
  host->window = gtk_application_window_new(host->application);
  gtk_window_set_default_size(GTK_WINDOW(host->window), width, height);
  gtk_window_set_title(GTK_WINDOW(host->window), title);
  host->primary_presentation = kiwi_gtk_terminal_presentation_new(host, callbacks);
  if (host->primary_presentation == NULL) {
    kiwi_gtk_set_error("GTK host could not create its terminal presentation");
    gtk_window_destroy(GTK_WINDOW(host->window));
    g_object_unref(host->application);
    g_free(host);
    return NULL;
  }
  gtk_window_set_child(GTK_WINDOW(host->window), host->primary_presentation->content);
  g_signal_connect(host->window, "close-request", G_CALLBACK(kiwi_gtk_close), host);
  gtk_window_present(GTK_WINDOW(host->window));
  while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);
  host->surface = gtk_native_get_surface(GTK_NATIVE(host->window));
  if (host->surface == NULL) {
    kiwi_gtk_set_error("GTK window did not realize a GDK surface");
    gtk_window_destroy(GTK_WINDOW(host->window));
    kiwi_gtk_terminal_presentation_destroy(host->primary_presentation);
    g_object_unref(host->application);
    g_free(host);
    return NULL;
  }
  gtk_widget_grab_focus(GTK_WIDGET(host->primary_presentation->terminal));
  return host;
}

void kiwi_gtk_host_destroy(KiwiGtkHost *host) {
  if (host == NULL) return;
  kiwi_gtk_host_command_palette_remove(host);
  if (host->application != NULL && host->notification_id[0] != '\0') {
    g_application_withdraw_notification(G_APPLICATION(host->application),
                                        host->notification_id);
  }
  host->product_action = NULL;
  host->product_action_userdata = NULL;
  if (host->presentations != NULL) {
    for (guint index = 0; index < host->presentations->len; index += 1) {
      kiwi_gtk_terminal_presentation_dispose(g_ptr_array_index(host->presentations, index));
    }
  } else {
    kiwi_gtk_terminal_presentation_dispose(host->primary_presentation);
  }
#ifdef GDK_WINDOWING_WAYLAND
  if (host->presentation_viewport != NULL) wp_viewport_destroy(host->presentation_viewport);
  if (host->presentation_subsurface != NULL) wl_subsurface_destroy(host->presentation_subsurface);
  if (host->presentation_surface != NULL) wl_surface_destroy(host->presentation_surface);
#endif
  if (host->window != NULL) gtk_window_destroy(GTK_WINDOW(host->window));
  if (host->presentations != NULL) {
    for (guint index = 0; index < host->presentations->len; index += 1) {
      kiwi_gtk_terminal_presentation_destroy(g_ptr_array_index(host->presentations, index));
    }
    g_ptr_array_free(host->presentations, TRUE);
    host->presentations = NULL;
  } else {
    kiwi_gtk_terminal_presentation_destroy(host->primary_presentation);
  }
  if (host->retired_presentations != NULL) {
    for (guint index = 0; index < host->retired_presentations->len; index += 1) {
      kiwi_gtk_terminal_presentation_destroy(
          g_ptr_array_index(host->retired_presentations, index));
    }
    g_ptr_array_free(host->retired_presentations, TRUE);
    host->retired_presentations = NULL;
  }
  host->primary_presentation = NULL;
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
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (width != NULL) *width = terminal == NULL ? 0 : (int)(gtk_widget_get_width(terminal->content) * scale + 0.5);
  if (height != NULL) *height = terminal == NULL ? 0 : (int)(gtk_widget_get_height(terminal->content) * scale + 0.5);
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
                                  host->notification_id, notification);
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

int kiwi_gtk_host_open_text_file(KiwiGtkHost *host, const char *path) {
  if (host == NULL || path == NULL || path[0] == '\0') return 0;
  GFile *file = g_file_new_for_path(path);
  char *uri = g_file_get_uri(file);
  GError *error = NULL;
  gboolean opened = g_app_info_launch_default_for_uri(uri, NULL, &error);
  g_free(uri);
  g_object_unref(file);
  if (!opened) {
    kiwi_gtk_set_error(error == NULL ? "could not open text file" : error->message);
    if (error != NULL) g_error_free(error);
  }
  return opened ? 1 : 0;
}

void *kiwi_gtk_host_create_surface(void *instance_pointer, KiwiGtkHost *host) {
  if (instance_pointer == NULL || host == NULL || host->surface == NULL) {
    kiwi_gtk_set_error("GTK host has no realized surface");
    return NULL;
  }
#if defined(GDK_WINDOWING_WAYLAND) || defined(GDK_WINDOWING_X11)
  WGPUInstance instance = (WGPUInstance)instance_pointer;
  WGPUSurfaceDescriptor descriptor = WGPU_SURFACE_DESCRIPTOR_INIT;
  GdkDisplay *display = gdk_surface_get_display(host->surface);
#endif
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    if (!kiwi_gtk_wayland_create_presentation_surface(host, display)) return NULL;
    WGPUSurfaceSourceWaylandSurface source = WGPU_SURFACE_SOURCE_WAYLAND_SURFACE_INIT;
    source.display = gdk_wayland_display_get_wl_display(display);
    source.surface = host->presentation_surface;
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    return wgpuInstanceCreateSurface(instance, &descriptor);
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    WGPUSurfaceSourceXlibWindow source = WGPU_SURFACE_SOURCE_XLIB_WINDOW_INIT;
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    source.display = gdk_x11_display_get_xdisplay(display);
    source.window = gdk_x11_surface_get_xid(host->surface);
    G_GNUC_END_IGNORE_DEPRECATIONS
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    return wgpuInstanceCreateSurface(instance, &descriptor);
  }
#endif
#if !defined(GDK_WINDOWING_WAYLAND) && !defined(GDK_WINDOWING_X11)
  (void)instance_pointer;
#endif
  kiwi_gtk_set_error("unsupported GDK backend; Kiwi GTK host requires Wayland or X11");
  return NULL;
}

int kiwi_gtk_host_set_drawable_size(KiwiGtkHost *host, uint32_t width, uint32_t height) {
  if (host == NULL || host->surface == NULL || width == 0 || height == 0) {
    kiwi_gtk_set_error("GTK host has no nonzero realized drawable");
    return 0;
  }
  GdkDisplay *display = gdk_surface_get_display(host->surface);
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display) && host->presentation_surface != NULL) {
    return kiwi_gtk_wayland_update_viewport(host);
  }
#else
  (void)display;
#endif
  return 1;
}

int kiwi_gtk_host_set_text_input_caret(KiwiGtkHost *host, int x, int y,
                                       int width, int height) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->im_context == NULL || x < 0 || y < 0 ||
      width < 1 || height < 1) {
    kiwi_gtk_set_error("GTK input method received an invalid caret rectangle");
    return 0;
  }
  GdkRectangle rectangle = { x, y, width, height };
  gtk_im_context_set_cursor_location(terminal->im_context, &rectangle);
  return 1;
}

int kiwi_gtk_host_system_appearance(const KiwiGtkHost *host) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->content == NULL) return -1;
  GtkSettings *settings = gtk_widget_get_settings(terminal->content);
  if (settings == NULL) return -1;
  gboolean dark = FALSE;
  g_object_get(settings, "gtk-application-prefer-dark-theme", &dark, NULL);
  return dark ? 1 : 0;
}

int kiwi_gtk_host_text_input_inject_smoke(KiwiGtkHost *host) {
  static const char preedit[] = "e\xCC\x81";
  static const char commit[] = "\xE2\x9C\x93";
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->callbacks.preedit == NULL ||
      terminal->callbacks.text == NULL) {
    kiwi_gtk_set_error("GTK text-input smoke needs installed preedit and commit callbacks");
    return 0;
  }
  terminal->callbacks.preedit(terminal->callbacks.userdata, preedit, sizeof(preedit) - 1,
                              sizeof(preedit) - 1, sizeof(preedit) - 1);
  terminal->callbacks.text(terminal->callbacks.userdata, commit, sizeof(commit) - 1);
  return 1;
}

int kiwi_gtk_host_key_text_inject_smoke(KiwiGtkHost *host) {
  static const char text[] = "a";
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->callbacks.key == NULL ||
      terminal->callbacks.text == NULL) {
    kiwi_gtk_set_error("GTK key/text smoke needs installed key and text callbacks");
    return 0;
  }
  if (kiwi_gtk_key_pressed(NULL, 'a', 0, 0, terminal)) {
    kiwi_gtk_set_error("GTK key/text smoke expected the deferred key to reach the input method");
    return 0;
  }
  kiwi_gtk_im_commit(NULL, text, terminal);
  kiwi_gtk_key_released(NULL, 'a', 0, 0, terminal);
  return 1;
}

uint32_t kiwi_gtk_host_keyboard_supported_flags(const KiwiGtkHost *host) {
  KiwiGtkKeyEvent event = {0};
  kiwi_gtk_key_variants(host == NULL ? NULL : host->primary_presentation, 0, 38, &event);
  return event.layout_key != 0 && event.shifted_key != 0 && event.base_key == 'a'
    ? 0x1f
    : 0x1b;
}

int kiwi_gtk_host_key_variants_inject_smoke(KiwiGtkHost *host) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->callbacks.key == NULL) {
    kiwi_gtk_set_error("GTK key-variant smoke needs an installed key callback");
    return 0;
  }
  if (kiwi_gtk_host_pc101_base_key(38) != 'a' ||
      kiwi_gtk_host_pc101_base_key(24) != 'q' ||
      kiwi_gtk_host_pc101_base_key(0) != 0 ||
      kiwi_gtk_host_keyboard_supported_flags(host) != 0x1f) {
    kiwi_gtk_set_error("GTK PC-101 keycode table is invalid");
    return 0;
  }
  kiwi_gtk_dispatch_key(terminal, NULL, 'A', 38, GDK_CONTROL_MASK | GDK_SHIFT_MASK,
                        KIWI_GTK_ACTION_PRESS);
  kiwi_gtk_dispatch_key(terminal, NULL, 'A', 38, GDK_CONTROL_MASK | GDK_SHIFT_MASK,
                        KIWI_GTK_ACTION_RELEASE);
  return 1;
}

int kiwi_gtk_host_accessibility_update(KiwiGtkHost *host, const char *text,
                                       size_t text_bytes, uint32_t character_count,
                                       int32_t caret_offset, int32_t selection_start,
                                       int32_t selection_end, int focused,
                                       const char *title) {
  KiwiGtkTerminalPresentation *terminal = host == NULL ? NULL : host->primary_presentation;
  if (terminal == NULL || terminal->terminal == NULL) {
    kiwi_gtk_set_error("GTK accessibility update has no terminal widget");
    return 0;
  }
  (void)focused;
  return kiwi_gtk_terminal_update(terminal->terminal, text, text_bytes,
                                  character_count, caret_offset, selection_start,
                                  selection_end, title);
}

uint32_t kiwi_gtk_host_abi_version(void) { return KIWI_GTK_HOST_ABI_VERSION; }

const char *kiwi_gtk_host_last_error(void) { return kiwi_gtk_error; }
