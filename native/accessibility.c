#include <gio/gio.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define KIWI_A11Y_ROOT_PATH "/org/a11y/atspi/accessible/root"
#define KIWI_A11Y_TERMINAL_PATH "/org/a11y/atspi/accessible/terminal"
#define KIWI_A11Y_NULL_PATH "/org/a11y/atspi/null"
#define KIWI_A11Y_MAX_TEXT_BYTES (64 * 1024)
#define KIWI_A11Y_MAX_TITLE_BYTES 1024

typedef struct KiwiAccessibility {
  GDBusConnection *connection;
  GDBusNodeInfo *node;
  gchar *address;
  gchar *text;
  gchar *title;
  gint app_id;
  gint character_count;
  gint caret_offset;
  gint selection_start;
  gint selection_end;
  gboolean terminal_focused;
  guint root_accessible_registration;
  guint root_application_registration;
  guint terminal_accessible_registration;
  guint terminal_text_registration;
  gboolean embedded;
} KiwiAccessibility;

void kiwi_accessibility_destroy(KiwiAccessibility *adapter);

static char kiwi_accessibility_error[512];

static const char kiwi_accessibility_xml[] =
    "<node>"
    "<interface name='org.a11y.atspi.Accessible'>"
    "<method name='GetChildAtIndex'><arg type='i' direction='in'/><arg type='(so)' direction='out'/></method>"
    "<method name='GetChildren'><arg type='a(so)' direction='out'/></method>"
    "<method name='GetIndexInParent'><arg type='i' direction='out'/></method>"
    "<method name='GetRelationSet'><arg type='a(ua(so))' direction='out'/></method>"
    "<method name='GetRole'><arg type='u' direction='out'/></method>"
    "<method name='GetRoleName'><arg type='s' direction='out'/></method>"
    "<method name='GetLocalizedRoleName'><arg type='s' direction='out'/></method>"
    "<method name='GetState'><arg type='au' direction='out'/></method>"
    "<method name='GetAttributes'><arg type='a{ss}' direction='out'/></method>"
    "<method name='GetApplication'><arg type='(so)' direction='out'/></method>"
    "<method name='GetInterfaces'><arg type='as' direction='out'/></method>"
    "<property name='Name' type='s' access='read'/>"
    "<property name='Description' type='s' access='read'/>"
    "<property name='Parent' type='(so)' access='read'/>"
    "<property name='ChildCount' type='i' access='read'/>"
    "<property name='Locale' type='s' access='read'/>"
    "<property name='AccessibleId' type='s' access='read'/>"
    "<property name='HelpText' type='s' access='read'/>"
    "</interface>"
    "<interface name='org.a11y.atspi.Application'>"
    "<method name='GetLocale'><arg type='u' direction='in'/><arg type='s' direction='out'/></method>"
    "<method name='GetApplicationBusAddress'><arg type='s' direction='out'/></method>"
    "<property name='ToolkitName' type='s' access='read'/>"
    "<property name='Version' type='s' access='read'/>"
    "<property name='ToolkitVersion' type='s' access='read'/>"
    "<property name='AtspiVersion' type='s' access='read'/>"
    "<property name='InterfaceVersion' type='u' access='read'/>"
    "<property name='Id' type='i' access='readwrite'/>"
    "</interface>"
    "<interface name='org.a11y.atspi.Text'>"
    "<method name='GetText'><arg type='i' direction='in'/><arg type='i' direction='in'/><arg type='s' direction='out'/></method>"
    "<method name='GetCharacterAtOffset'><arg type='i' direction='in'/><arg type='i' direction='out'/></method>"
    "<method name='GetStringAtOffset'><arg type='i' direction='in'/><arg type='u' direction='in'/><arg type='s' direction='out'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetTextBeforeOffset'><arg type='i' direction='in'/><arg type='u' direction='in'/><arg type='s' direction='out'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetTextAtOffset'><arg type='i' direction='in'/><arg type='u' direction='in'/><arg type='s' direction='out'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetTextAfterOffset'><arg type='i' direction='in'/><arg type='u' direction='in'/><arg type='s' direction='out'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetCaretOffset'><arg type='i' direction='out'/></method>"
    "<method name='SetCaretOffset'><arg type='i' direction='in'/><arg type='b' direction='out'/></method>"
    "<method name='GetNSelections'><arg type='i' direction='out'/></method>"
    "<method name='GetSelection'><arg type='i' direction='in'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetAttributes'><arg type='i' direction='in'/><arg type='a{ss}' direction='out'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetAttributeRun'><arg type='i' direction='in'/><arg type='b' direction='in'/><arg type='a{ss}' direction='out'/><arg type='i' direction='out'/><arg type='i' direction='out'/></method>"
    "<method name='GetDefaultAttributes'><arg type='a{ss}' direction='out'/></method>"
    "<method name='GetAttributeValue'><arg type='i' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='out'/></method>"
    "<property name='CharacterCount' type='i' access='read'/>"
    "<property name='CaretOffset' type='i' access='read'/>"
    "<property name='version' type='u' access='read'/>"
    "</interface>"
    "</node>";

static void kiwi_a11y_set_error(const char *prefix, const GError *error) {
  if (error == NULL || error->message == NULL) {
    snprintf(kiwi_accessibility_error, sizeof(kiwi_accessibility_error), "%s", prefix);
    return;
  }
  snprintf(kiwi_accessibility_error, sizeof(kiwi_accessibility_error), "%s: %s", prefix, error->message);
}

static gboolean kiwi_a11y_terminal_path(const char *path) {
  return g_strcmp0(path, KIWI_A11Y_TERMINAL_PATH) == 0;
}

static gint kiwi_a11y_clamp_offset(const KiwiAccessibility *adapter, gint offset) {
  if (offset < 0) return 0;
  if (offset > adapter->character_count) return adapter->character_count;
  return offset;
}

static GVariant *kiwi_a11y_empty_attributes(void) {
  GVariantBuilder attributes;
  g_variant_builder_init(&attributes, G_VARIANT_TYPE("a{ss}"));
  return g_variant_builder_end(&attributes);
}

static GVariant *kiwi_a11y_empty_properties(void) {
  GVariantBuilder properties;
  g_variant_builder_init(&properties, G_VARIANT_TYPE("a{sv}"));
  return g_variant_builder_end(&properties);
}

static GVariant *kiwi_a11y_empty_relations(void) {
  GVariantBuilder relations;
  g_variant_builder_init(&relations, G_VARIANT_TYPE("a(ua(so))"));
  return g_variant_builder_end(&relations);
}

static GVariant *kiwi_a11y_states(const KiwiAccessibility *adapter, gboolean terminal) {
  GVariantBuilder states;
  g_variant_builder_init(&states, G_VARIANT_TYPE("au"));
  if (terminal) {
    const guint values[] = {8, 11, 17, 24, 25, 30, 40};
    for (gsize index = 0; index < G_N_ELEMENTS(values); ++index) {
      g_variant_builder_add(&states, "u", values[index]);
    }
    if (adapter->terminal_focused) g_variant_builder_add(&states, "u", 12);
  } else {
    const guint values[] = {1, 8, 24, 25, 30};
    for (gsize index = 0; index < G_N_ELEMENTS(values); ++index) {
      g_variant_builder_add(&states, "u", values[index]);
    }
  }
  return g_variant_builder_end(&states);
}

static gchar *kiwi_a11y_text_slice(const KiwiAccessibility *adapter, gint start, gint end) {
  start = kiwi_a11y_clamp_offset(adapter, start);
  end = end < 0 ? adapter->character_count : kiwi_a11y_clamp_offset(adapter, end);
  if (end < start) end = start;
  const gchar *first = g_utf8_offset_to_pointer(adapter->text, start);
  const gchar *last = g_utf8_offset_to_pointer(adapter->text, end);
  return g_strndup(first, (gsize)(last - first));
}

static gchar *kiwi_a11y_range_at_offset(const KiwiAccessibility *adapter, gint offset, guint granularity, gint *start, gint *end) {
  offset = kiwi_a11y_clamp_offset(adapter, offset);
  if (granularity == 0) {
    *start = offset;
    *end = offset < adapter->character_count ? offset + 1 : offset;
    return kiwi_a11y_text_slice(adapter, *start, *end);
  }
  const gchar *pointer = g_utf8_offset_to_pointer(adapter->text, offset);
  const gchar *first = pointer;
  const gchar *last = pointer;
  while (first > adapter->text && first[-1] != '\n') first = g_utf8_prev_char(first);
  while (*last != '\0' && *last != '\n') last = g_utf8_next_char(last);
  *start = (gint)g_utf8_pointer_to_offset(adapter->text, first);
  *end = (gint)g_utf8_pointer_to_offset(adapter->text, last);
  return g_strndup(first, (gsize)(last - first));
}

static void kiwi_a11y_return_range(GDBusMethodInvocation *invocation, gchar *text, gint start, gint end) {
  g_dbus_method_invocation_return_value(invocation, g_variant_new("(sii)", text, start, end));
  g_free(text);
}

static void kiwi_a11y_method_call(GDBusConnection *connection, const gchar *sender, const gchar *object_path,
                                  const gchar *interface_name, const gchar *method_name, GVariant *parameters,
                                  GDBusMethodInvocation *invocation, gpointer user_data) {
  (void)connection;
  (void)sender;
  KiwiAccessibility *adapter = user_data;
  const gboolean terminal = kiwi_a11y_terminal_path(object_path);
  const char *bus = g_dbus_connection_get_unique_name(adapter->connection);

  if (g_strcmp0(interface_name, "org.a11y.atspi.Accessible") == 0) {
    if (g_strcmp0(method_name, "GetChildAtIndex") == 0) {
      gint index = -1;
      g_variant_get(parameters, "(i)", &index);
      if (terminal || index != 0) {
        g_dbus_method_invocation_return_dbus_error(invocation, "org.a11y.atspi.Error.InvalidIndex", "accessible child index is out of bounds");
      } else {
        g_dbus_method_invocation_return_value(invocation, g_variant_new("((so))", bus, KIWI_A11Y_TERMINAL_PATH));
      }
      return;
    }
    if (g_strcmp0(method_name, "GetChildren") == 0) {
      GVariantBuilder children;
      g_variant_builder_init(&children, G_VARIANT_TYPE("a(so)"));
      if (!terminal) g_variant_builder_add(&children, "(so)", bus, KIWI_A11Y_TERMINAL_PATH);
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(@a(so))", g_variant_builder_end(&children)));
      return;
    }
    if (g_strcmp0(method_name, "GetIndexInParent") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(i)", terminal ? 0 : -1));
      return;
    }
    if (g_strcmp0(method_name, "GetRelationSet") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(@a(ua(so)))", kiwi_a11y_empty_relations()));
      return;
    }
    if (g_strcmp0(method_name, "GetRole") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(u)", terminal ? 60 : 75));
      return;
    }
    if (g_strcmp0(method_name, "GetRoleName") == 0 || g_strcmp0(method_name, "GetLocalizedRoleName") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", terminal ? "terminal" : "application"));
      return;
    }
    if (g_strcmp0(method_name, "GetState") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(@au)", kiwi_a11y_states(adapter, terminal)));
      return;
    }
    if (g_strcmp0(method_name, "GetAttributes") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(@a{ss})", kiwi_a11y_empty_attributes()));
      return;
    }
    if (g_strcmp0(method_name, "GetApplication") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("((so))", bus, KIWI_A11Y_ROOT_PATH));
      return;
    }
    if (g_strcmp0(method_name, "GetInterfaces") == 0) {
      const gchar *root_interfaces[] = {"org.a11y.atspi.Accessible", "org.a11y.atspi.Application", NULL};
      const gchar *terminal_interfaces[] = {"org.a11y.atspi.Accessible", "org.a11y.atspi.Text", NULL};
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(^as)", terminal ? terminal_interfaces : root_interfaces));
      return;
    }
  }

  if (g_strcmp0(interface_name, "org.a11y.atspi.Application") == 0) {
    if (g_strcmp0(method_name, "GetLocale") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", "C"));
      return;
    }
    if (g_strcmp0(method_name, "GetApplicationBusAddress") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", adapter->address));
      return;
    }
  }

  if (terminal && g_strcmp0(interface_name, "org.a11y.atspi.Text") == 0) {
    if (g_strcmp0(method_name, "GetText") == 0) {
      gint start = 0;
      gint end = 0;
      g_variant_get(parameters, "(ii)", &start, &end);
      gchar *text = kiwi_a11y_text_slice(adapter, start, end);
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", text));
      g_free(text);
      return;
    }
    if (g_strcmp0(method_name, "GetCharacterAtOffset") == 0) {
      gint offset = 0;
      g_variant_get(parameters, "(i)", &offset);
      gint character = 0;
      if (offset >= 0 && offset < adapter->character_count) character = (gint)g_utf8_get_char(g_utf8_offset_to_pointer(adapter->text, offset));
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(i)", character));
      return;
    }
    if (g_strcmp0(method_name, "GetStringAtOffset") == 0 || g_strcmp0(method_name, "GetTextAtOffset") == 0 ||
        g_strcmp0(method_name, "GetTextBeforeOffset") == 0 || g_strcmp0(method_name, "GetTextAfterOffset") == 0) {
      gint offset = 0;
      guint granularity = 0;
      g_variant_get(parameters, "(iu)", &offset, &granularity);
      if (g_strcmp0(method_name, "GetTextBeforeOffset") == 0) offset -= 1;
      if (g_strcmp0(method_name, "GetTextAfterOffset") == 0) offset += 1;
      gint start = 0;
      gint end = 0;
      gchar *text = kiwi_a11y_range_at_offset(adapter, offset, granularity, &start, &end);
      kiwi_a11y_return_range(invocation, text, start, end);
      return;
    }
    if (g_strcmp0(method_name, "GetCaretOffset") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(i)", adapter->caret_offset));
      return;
    }
    if (g_strcmp0(method_name, "SetCaretOffset") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", FALSE));
      return;
    }
    if (g_strcmp0(method_name, "GetNSelections") == 0) {
      const gboolean active = adapter->selection_start >= 0 && adapter->selection_end > adapter->selection_start;
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(i)", active ? 1 : 0));
      return;
    }
    if (g_strcmp0(method_name, "GetSelection") == 0) {
      gint index = 0;
      g_variant_get(parameters, "(i)", &index);
      const gboolean active = index == 0 && adapter->selection_start >= 0 && adapter->selection_end > adapter->selection_start;
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(ii)", active ? adapter->selection_start : -1, active ? adapter->selection_end : -1));
      return;
    }
    if (g_strcmp0(method_name, "GetAttributes") == 0 || g_strcmp0(method_name, "GetAttributeRun") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(@a{ss}ii)", kiwi_a11y_empty_attributes(), 0, adapter->character_count));
      return;
    }
    if (g_strcmp0(method_name, "GetDefaultAttributes") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(@a{ss})", kiwi_a11y_empty_attributes()));
      return;
    }
    if (g_strcmp0(method_name, "GetAttributeValue") == 0) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", ""));
      return;
    }
  }

  g_dbus_method_invocation_return_dbus_error(invocation, "org.freedesktop.DBus.Error.UnknownMethod", "unsupported Kiwi accessibility method");
}

static GVariant *kiwi_a11y_get_property(GDBusConnection *connection, const gchar *sender, const gchar *object_path,
                                        const gchar *interface_name, const gchar *property_name, GError **error,
                                        gpointer user_data) {
  (void)connection;
  (void)sender;
  KiwiAccessibility *adapter = user_data;
  const gboolean terminal = kiwi_a11y_terminal_path(object_path);
  const char *bus = g_dbus_connection_get_unique_name(adapter->connection);
  if (g_strcmp0(interface_name, "org.a11y.atspi.Accessible") == 0) {
    if (g_strcmp0(property_name, "Name") == 0) return g_variant_new_string(terminal ? adapter->title : "Kiwi");
    if (g_strcmp0(property_name, "Description") == 0) return g_variant_new_string(terminal ? "Kiwi terminal viewport" : "Kiwi terminal application");
    if (g_strcmp0(property_name, "Parent") == 0) return terminal ? g_variant_new("(so)", bus, KIWI_A11Y_ROOT_PATH) : g_variant_new("(so)", "", KIWI_A11Y_NULL_PATH);
    if (g_strcmp0(property_name, "ChildCount") == 0) return g_variant_new_int32(terminal ? 0 : 1);
    if (g_strcmp0(property_name, "Locale") == 0) return g_variant_new_string("C");
    if (g_strcmp0(property_name, "AccessibleId") == 0) return g_variant_new_string(terminal ? "kiwi-terminal" : "kiwi-application");
    if (g_strcmp0(property_name, "HelpText") == 0) return g_variant_new_string(terminal ? "Current bounded Kiwi terminal viewport" : "Kiwi");
  }
  if (g_strcmp0(interface_name, "org.a11y.atspi.Application") == 0) {
    if (g_strcmp0(property_name, "ToolkitName") == 0) return g_variant_new_string("Kiwi");
    if (g_strcmp0(property_name, "Version") == 0 || g_strcmp0(property_name, "ToolkitVersion") == 0) return g_variant_new_string("M2");
    if (g_strcmp0(property_name, "AtspiVersion") == 0) return g_variant_new_string("2.1");
    if (g_strcmp0(property_name, "InterfaceVersion") == 0) return g_variant_new_uint32(1);
    if (g_strcmp0(property_name, "Id") == 0) return g_variant_new_int32(adapter->app_id);
  }
  if (terminal && g_strcmp0(interface_name, "org.a11y.atspi.Text") == 0) {
    if (g_strcmp0(property_name, "CharacterCount") == 0) return g_variant_new_int32(adapter->character_count);
    if (g_strcmp0(property_name, "CaretOffset") == 0) return g_variant_new_int32(adapter->caret_offset);
    if (g_strcmp0(property_name, "version") == 0) return g_variant_new_uint32(1);
  }
  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS, "unknown Kiwi accessibility property");
  return NULL;
}

static gboolean kiwi_a11y_set_property(GDBusConnection *connection, const gchar *sender, const gchar *object_path,
                                       const gchar *interface_name, const gchar *property_name, GVariant *value,
                                       GError **error, gpointer user_data) {
  (void)connection;
  (void)sender;
  (void)object_path;
  KiwiAccessibility *adapter = user_data;
  if (g_strcmp0(interface_name, "org.a11y.atspi.Application") == 0 && g_strcmp0(property_name, "Id") == 0 && g_variant_is_of_type(value, G_VARIANT_TYPE_INT32)) {
    adapter->app_id = g_variant_get_int32(value);
    return TRUE;
  }
  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_PROPERTY_READ_ONLY, "Kiwi accessibility property is read-only");
  return FALSE;
}

static const GDBusInterfaceVTable kiwi_a11y_vtable = {
    .method_call = kiwi_a11y_method_call,
    .get_property = kiwi_a11y_get_property,
    .set_property = kiwi_a11y_set_property,
};

static void kiwi_a11y_unregister(KiwiAccessibility *adapter) {
  if (adapter->connection == NULL) return;
  if (adapter->terminal_text_registration != 0) g_dbus_connection_unregister_object(adapter->connection, adapter->terminal_text_registration);
  if (adapter->terminal_accessible_registration != 0) g_dbus_connection_unregister_object(adapter->connection, adapter->terminal_accessible_registration);
  if (adapter->root_application_registration != 0) g_dbus_connection_unregister_object(adapter->connection, adapter->root_application_registration);
  if (adapter->root_accessible_registration != 0) g_dbus_connection_unregister_object(adapter->connection, adapter->root_accessible_registration);
  adapter->terminal_text_registration = 0;
  adapter->terminal_accessible_registration = 0;
  adapter->root_application_registration = 0;
  adapter->root_accessible_registration = 0;
}

KiwiAccessibility *kiwi_accessibility_new(void) {
  kiwi_accessibility_error[0] = '\0';
  KiwiAccessibility *adapter = g_new0(KiwiAccessibility, 1);
  GError *error = NULL;
  GDBusConnection *session = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
  if (session == NULL) {
    kiwi_a11y_set_error("could not connect to the session bus", error);
    g_clear_error(&error);
    g_free(adapter);
    return NULL;
  }
  GVariant *address_reply = g_dbus_connection_call_sync(session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress", NULL,
                                                        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NONE, 1000, NULL, &error);
  g_object_unref(session);
  if (address_reply == NULL) {
    kiwi_a11y_set_error("could not obtain the AT-SPI bus address", error);
    g_clear_error(&error);
    g_free(adapter);
    return NULL;
  }
  const gchar *address = NULL;
  g_variant_get(address_reply, "(&s)", &address);
  adapter->address = g_strdup(address);
  g_variant_unref(address_reply);
  adapter->connection = g_dbus_connection_new_for_address_sync(adapter->address,
                                                                 G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT | G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION,
                                                                 NULL, NULL, &error);
  if (adapter->connection == NULL) {
    kiwi_a11y_set_error("could not connect to the AT-SPI bus", error);
    g_clear_error(&error);
    kiwi_accessibility_destroy(adapter);
    return NULL;
  }
  adapter->node = g_dbus_node_info_new_for_xml(kiwi_accessibility_xml, &error);
  if (adapter->node == NULL) {
    kiwi_a11y_set_error("could not parse the AT-SPI interface contract", error);
    g_clear_error(&error);
    kiwi_accessibility_destroy(adapter);
    return NULL;
  }
  GDBusInterfaceInfo *accessible = g_dbus_node_info_lookup_interface(adapter->node, "org.a11y.atspi.Accessible");
  GDBusInterfaceInfo *application = g_dbus_node_info_lookup_interface(adapter->node, "org.a11y.atspi.Application");
  GDBusInterfaceInfo *text = g_dbus_node_info_lookup_interface(adapter->node, "org.a11y.atspi.Text");
  adapter->text = g_strdup("");
  adapter->title = g_strdup("Kiwi terminal");
  adapter->root_accessible_registration = g_dbus_connection_register_object(adapter->connection, KIWI_A11Y_ROOT_PATH, accessible, &kiwi_a11y_vtable, adapter, NULL, &error);
  if (adapter->root_accessible_registration == 0) goto failed;
  adapter->root_application_registration = g_dbus_connection_register_object(adapter->connection, KIWI_A11Y_ROOT_PATH, application, &kiwi_a11y_vtable, adapter, NULL, &error);
  if (adapter->root_application_registration == 0) goto failed;
  adapter->terminal_accessible_registration = g_dbus_connection_register_object(adapter->connection, KIWI_A11Y_TERMINAL_PATH, accessible, &kiwi_a11y_vtable, adapter, NULL, &error);
  if (adapter->terminal_accessible_registration == 0) goto failed;
  adapter->terminal_text_registration = g_dbus_connection_register_object(adapter->connection, KIWI_A11Y_TERMINAL_PATH, text, &kiwi_a11y_vtable, adapter, NULL, &error);
  if (adapter->terminal_text_registration == 0) goto failed;
  const char *bus = g_dbus_connection_get_unique_name(adapter->connection);
  GVariant *embedded = g_dbus_connection_call_sync(adapter->connection, "org.a11y.atspi.Registry", KIWI_A11Y_ROOT_PATH,
                                                    "org.a11y.atspi.Socket", "Embed", g_variant_new("((so))", bus, KIWI_A11Y_ROOT_PATH),
                                                    G_VARIANT_TYPE("((so))"), G_DBUS_CALL_FLAGS_NONE, 1000, NULL, &error);
  if (embedded == NULL) goto failed;
  g_variant_unref(embedded);
  adapter->embedded = TRUE;
  return adapter;

failed:
  kiwi_a11y_set_error("could not register the Kiwi AT-SPI provider", error);
  g_clear_error(&error);
  kiwi_accessibility_destroy(adapter);
  return NULL;
}

void kiwi_accessibility_destroy(KiwiAccessibility *adapter) {
  if (adapter == NULL) return;
  kiwi_a11y_unregister(adapter);
  if (adapter->node != NULL) g_dbus_node_info_unref(adapter->node);
  if (adapter->connection != NULL) g_object_unref(adapter->connection);
  g_free(adapter->address);
  g_free(adapter->text);
  g_free(adapter->title);
  g_free(adapter);
}

static void kiwi_a11y_emit_text_properties(KiwiAccessibility *adapter) {
  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&changed, "{sv}", "CharacterCount", g_variant_new_int32(adapter->character_count));
  g_variant_builder_add(&changed, "{sv}", "CaretOffset", g_variant_new_int32(adapter->caret_offset));
  g_dbus_connection_emit_signal(adapter->connection, NULL, KIWI_A11Y_TERMINAL_PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                g_variant_new("(s@a{sv}@as)", "org.a11y.atspi.Text", g_variant_builder_end(&changed), g_variant_new_strv(NULL, 0)), NULL);
}

static void kiwi_a11y_emit_object_event(KiwiAccessibility *adapter, const char *name, const char *detail,
                                         gint first, gint second, GVariant *value) {
  g_dbus_connection_emit_signal(adapter->connection, NULL, KIWI_A11Y_TERMINAL_PATH,
                                "org.a11y.atspi.Event.Object", name,
                                g_variant_new("(siiv@a{sv})", detail, first, second,
                                              g_variant_new_variant(value), kiwi_a11y_empty_properties()), NULL);
}

int kiwi_accessibility_update(KiwiAccessibility *adapter, const char *text, size_t text_bytes, int32_t character_count,
                              int32_t caret_offset, int32_t selection_start, int32_t selection_end, int focused, const char *title) {
  if (adapter == NULL || text == NULL || title == NULL || text_bytes > KIWI_A11Y_MAX_TEXT_BYTES || strlen(title) > KIWI_A11Y_MAX_TITLE_BYTES ||
      memchr(text, '\0', text_bytes) != NULL || !g_utf8_validate(text, (gssize)text_bytes, NULL) || !g_utf8_validate(title, -1, NULL)) {
    snprintf(kiwi_accessibility_error, sizeof(kiwi_accessibility_error), "invalid bounded AT-SPI projection");
    return 0;
  }
  const gint computed_count = (gint)g_utf8_strlen(text, (gssize)text_bytes);
  if (character_count != computed_count) {
    snprintf(kiwi_accessibility_error, sizeof(kiwi_accessibility_error), "AT-SPI projection character count does not match UTF-8 text");
    return 0;
  }
  const gboolean text_changed = g_strcmp0(adapter->text, text) != 0;
  gchar *previous_text = text_changed ? g_strdup(adapter->text) : NULL;
  const gint previous_count = adapter->character_count;
  const gint previous_caret = adapter->caret_offset;
  const gint previous_selection_start = adapter->selection_start;
  const gint previous_selection_end = adapter->selection_end;
  const gboolean previous_focused = adapter->terminal_focused;
  g_free(adapter->text);
  adapter->text = g_strndup(text, text_bytes);
  g_free(adapter->title);
  adapter->title = g_strdup(title);
  adapter->character_count = computed_count;
  adapter->caret_offset = kiwi_a11y_clamp_offset(adapter, caret_offset);
  adapter->selection_start = selection_start < 0 ? -1 : kiwi_a11y_clamp_offset(adapter, selection_start);
  adapter->selection_end = selection_end < 0 ? -1 : kiwi_a11y_clamp_offset(adapter, selection_end);
  if (adapter->selection_end >= 0 && adapter->selection_end < adapter->selection_start) {
    const gint swap = adapter->selection_start;
    adapter->selection_start = adapter->selection_end;
    adapter->selection_end = swap;
  }
  adapter->terminal_focused = focused != 0;
  if (text_changed || previous_caret != adapter->caret_offset) kiwi_a11y_emit_text_properties(adapter);
  if (text_changed) {
    if (previous_count > 0) kiwi_a11y_emit_object_event(adapter, "TextChanged", "delete", 0, previous_count, g_variant_new_string(previous_text));
    if (adapter->character_count > 0) kiwi_a11y_emit_object_event(adapter, "TextChanged", "insert", 0, adapter->character_count, g_variant_new_string(adapter->text));
  }
  if (previous_caret != adapter->caret_offset) {
    kiwi_a11y_emit_object_event(adapter, "TextCaretMoved", "", adapter->caret_offset, 0, g_variant_new_int32(adapter->caret_offset));
  }
  if (previous_selection_start != adapter->selection_start || previous_selection_end != adapter->selection_end) {
    kiwi_a11y_emit_object_event(adapter, "TextSelectionChanged", "", 0, 0, g_variant_new_string(""));
  }
  if (previous_focused != adapter->terminal_focused) {
    kiwi_a11y_emit_object_event(adapter, "StateChanged", "focused", adapter->terminal_focused ? 1 : 0, 0,
                                g_variant_new_boolean(adapter->terminal_focused));
  }
  g_free(previous_text);
  return 1;
}

void kiwi_accessibility_poll(KiwiAccessibility *adapter) {
  if (adapter == NULL) return;
  for (int iteration = 0; iteration < 32 && g_main_context_pending(NULL); ++iteration) {
    g_main_context_iteration(NULL, FALSE);
  }
}

int kiwi_accessibility_active(const KiwiAccessibility *adapter) {
  return adapter != NULL && adapter->embedded;
}

const char *kiwi_accessibility_bus_name(const KiwiAccessibility *adapter) {
  if (adapter == NULL || adapter->connection == NULL) return "";
  const char *name = g_dbus_connection_get_unique_name(adapter->connection);
  return name == NULL ? "" : name;
}

const char *kiwi_accessibility_last_error(void) {
  return kiwi_accessibility_error;
}
