#include "tray_linux.h"

#include <unistd.h>

#include <string>
#include <vector>

// StatusNotifierItem (org.kde.StatusNotifierItem) y su menú
// (com.canonical.dbusmenu) implementados con GDBus, sin libayatana: esa
// biblioteca ignora «Activate» (clic izquierdo) y solo abre el menú.

namespace {

const char kItemPath[] = "/StatusNotifierItem";
const char kMenuPath[] = "/MenuBar";
const char kWatcherName[] = "org.kde.StatusNotifierWatcher";

const char kItemXml[] = R"XML(
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="Activate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="SecondaryActivate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="Scroll">
      <arg name="delta" type="i" direction="in"/>
      <arg name="orientation" type="s" direction="in"/>
    </method>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewAttentionIcon"/>
    <signal name="NewOverlayIcon"/>
    <signal name="NewToolTip"/>
    <signal name="NewStatus">
      <arg name="status" type="s"/>
    </signal>
  </interface>
</node>)XML";

const char kMenuXml[] = R"XML(
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/>
      <arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/>
      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg name="id" type="i" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/>
      <arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/>
      <arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg name="events" type="a(isvu)" direction="in"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/>
      <arg name="needUpdate" type="b" direction="out"/>
    </method>
    <method name="AboutToShowGroup">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="updatesNeeded" type="ai" direction="out"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <signal name="ItemsPropertiesUpdated">
      <arg name="updatedProps" type="a(ia{sv})"/>
      <arg name="removedProps" type="a(ias)"/>
    </signal>
    <signal name="LayoutUpdated">
      <arg name="revision" type="u"/>
      <arg name="parent" type="i"/>
    </signal>
    <signal name="ItemActivationRequested">
      <arg name="id" type="i"/>
      <arg name="timestamp" type="u"/>
    </signal>
  </interface>
</node>)XML";

// Entradas del menú. El id 0 es la raíz.
enum MenuId {
  kNowPlaying = 1,
  kNowSeparator,
  kShow,
  kPlayPause,
  kNext,
  kPrevious,
  kQuitSeparator,
  kQuit,
  kLastId = kQuit,
};

}  // namespace

struct _AuroraTray {
  GDBusConnection* bus = nullptr;
  GDBusNodeInfo* item_info = nullptr;
  GDBusNodeInfo* menu_info = nullptr;
  guint item_registration = 0;
  guint menu_registration = 0;
  guint owner_id = 0;
  guint watcher_id = 0;
  std::string bus_name;
  std::string icon_dir;
  std::string icon_name;
  GVariant* icon_pixmap = nullptr;  // a(iiay), referencia propia.
  std::string now;                  // «Título – Artista» o vacío.
  bool playing = false;
  guint32 revision = 1;
  AuroraTrayCallback callback = nullptr;
  gpointer data = nullptr;
};

namespace {

void Dispatch(AuroraTray* tray, AuroraTrayCommand command) {
  if (tray->callback != nullptr) tray->callback(command, tray->data);
}

std::string TitleOf(const AuroraTray* tray) {
  return tray->now.empty() ? "Aurora Music" : tray->now;
}

// Icono en ARGB32 big-endian, para anfitriones que no leen IconThemePath.
GVariant* LoadPixmap(const std::string& dir, const std::string& name) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a(iiay)"));
  g_autofree gchar* file =
      g_strdup_printf("%s/%s.png", dir.c_str(), name.c_str());
  g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_file(file, nullptr);
  if (pixbuf != nullptr) {
    const int width = gdk_pixbuf_get_width(pixbuf);
    const int height = gdk_pixbuf_get_height(pixbuf);
    const int channels = gdk_pixbuf_get_n_channels(pixbuf);
    const int stride = gdk_pixbuf_get_rowstride(pixbuf);
    const bool alpha = gdk_pixbuf_get_has_alpha(pixbuf);
    const guchar* pixels = gdk_pixbuf_read_pixels(pixbuf);
    std::vector<guchar> argb(static_cast<size_t>(width) * height * 4);
    size_t out = 0;
    for (int y = 0; y < height; ++y) {
      const guchar* row = pixels + static_cast<size_t>(y) * stride;
      for (int x = 0; x < width; ++x) {
        const guchar* p = row + x * channels;
        argb[out++] = alpha ? p[3] : 0xff;
        argb[out++] = p[0];
        argb[out++] = p[1];
        argb[out++] = p[2];
      }
    }
    GVariant* bytes = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                                argb.data(), argb.size(), 1);
    g_variant_builder_add(&builder, "(ii@ay)", width, height, bytes);
  }
  return g_variant_ref_sink(g_variant_builder_end(&builder));
}

// ---- StatusNotifierItem ----------------------------------------------------

GVariant* ItemGetProperty(GDBusConnection*, const gchar*, const gchar*,
                          const gchar*, const gchar* name, GError**,
                          gpointer user_data) {
  auto* tray = static_cast<AuroraTray*>(user_data);
  const std::string prop = name;
  if (prop == "Category") return g_variant_new_string("ApplicationStatus");
  if (prop == "Id") return g_variant_new_string("aurora-music");
  if (prop == "Title") return g_variant_new_string(TitleOf(tray).c_str());
  if (prop == "Status") return g_variant_new_string("Active");
  if (prop == "WindowId") return g_variant_new_int32(0);
  if (prop == "IconName") return g_variant_new_string(tray->icon_name.c_str());
  if (prop == "IconThemePath") {
    return g_variant_new_string(tray->icon_dir.c_str());
  }
  if (prop == "IconPixmap") return g_variant_ref(tray->icon_pixmap);
  if (prop == "OverlayIconName" || prop == "AttentionIconName") {
    return g_variant_new_string("");
  }
  if (prop == "ToolTip") {
    return g_variant_new("(s@a(iiay)ss)", tray->icon_name.c_str(),
                         g_variant_new_array(G_VARIANT_TYPE("(iiay)"), nullptr,
                                             0),
                         "Aurora Music", tray->now.c_str());
  }
  if (prop == "ItemIsMenu") return g_variant_new_boolean(FALSE);
  if (prop == "Menu") return g_variant_new_object_path(kMenuPath);
  return nullptr;
}

void ItemMethodCall(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                    const gchar* method, GVariant*,
                    GDBusMethodInvocation* invocation, gpointer user_data) {
  auto* tray = static_cast<AuroraTray*>(user_data);
  const std::string name = method;
  // Responder antes de actuar: el anfitrión no espera a que se abra la ventana.
  g_dbus_method_invocation_return_value(invocation, nullptr);
  if (name == "Activate") {
    Dispatch(tray, AURORA_TRAY_SHOW);
  } else if (name == "SecondaryActivate") {
    Dispatch(tray, AURORA_TRAY_PLAY_PAUSE);
  }
  // ContextMenu: el anfitrión dibuja el menú con dbusmenu. Scroll: nada.
}

const GDBusInterfaceVTable kItemVTable = {ItemMethodCall, ItemGetProperty,
                                          nullptr, {nullptr}};

// ---- com.canonical.dbusmenu ------------------------------------------------

GVariant* MenuItemProperties(const AuroraTray* tray, int id) {
  GVariantBuilder props;
  g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
  auto label = [&](const char* text) {
    g_variant_builder_add(&props, "{sv}", "label", g_variant_new_string(text));
  };
  switch (id) {
    case 0:
      g_variant_builder_add(&props, "{sv}", "children-display",
                            g_variant_new_string("submenu"));
      break;
    case kNowPlaying:
      label(tray->now.c_str());
      g_variant_builder_add(&props, "{sv}", "enabled",
                            g_variant_new_boolean(FALSE));
      g_variant_builder_add(&props, "{sv}", "visible",
                            g_variant_new_boolean(!tray->now.empty()));
      break;
    case kNowSeparator:
    case kQuitSeparator:
      g_variant_builder_add(&props, "{sv}", "type",
                            g_variant_new_string("separator"));
      if (id == kNowSeparator) {
        g_variant_builder_add(&props, "{sv}", "visible",
                              g_variant_new_boolean(!tray->now.empty()));
      }
      break;
    case kShow:
      label("Mostrar Aurora");
      break;
    case kPlayPause:
      label(tray->playing ? "Pausa" : "Reproducir");
      break;
    case kNext:
      label("Siguiente");
      break;
    case kPrevious:
      label("Anterior");
      break;
    case kQuit:
      label("Salir");
      break;
    default:
      break;
  }
  return g_variant_builder_end(&props);
}

GVariant* MenuNode(const AuroraTray* tray, int id, bool with_children) {
  GVariantBuilder children;
  g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
  if (id == 0 && with_children) {
    for (int child = kNowPlaying; child <= kLastId; ++child) {
      g_variant_builder_add(&children, "v", MenuNode(tray, child, false));
    }
  }
  return g_variant_new("(i@a{sv}av)", id, MenuItemProperties(tray, id),
                       &children);
}

bool ValidId(int id) { return id >= 0 && id <= kLastId; }

void MenuEvent(AuroraTray* tray, int id, const gchar* event) {
  if (g_strcmp0(event, "clicked") != 0) return;
  switch (id) {
    case kShow:
      Dispatch(tray, AURORA_TRAY_SHOW);
      break;
    case kPlayPause:
      Dispatch(tray, AURORA_TRAY_PLAY_PAUSE);
      break;
    case kNext:
      Dispatch(tray, AURORA_TRAY_NEXT);
      break;
    case kPrevious:
      Dispatch(tray, AURORA_TRAY_PREVIOUS);
      break;
    case kQuit:
      Dispatch(tray, AURORA_TRAY_QUIT);
      break;
    default:
      break;
  }
}

GVariant* MenuGetProperty(GDBusConnection*, const gchar*, const gchar*,
                          const gchar*, const gchar* name, GError**, gpointer) {
  const std::string prop = name;
  if (prop == "Version") return g_variant_new_uint32(3);
  if (prop == "TextDirection") return g_variant_new_string("ltr");
  if (prop == "Status") return g_variant_new_string("normal");
  if (prop == "IconThemePath") return g_variant_new_strv(nullptr, 0);
  return nullptr;
}

void MenuMethodCall(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                    const gchar* method, GVariant* params,
                    GDBusMethodInvocation* invocation, gpointer user_data) {
  auto* tray = static_cast<AuroraTray*>(user_data);
  const std::string name = method;
  if (name == "GetLayout") {
    gint32 parent = 0;
    gint32 depth = -1;
    g_variant_get(params, "(ii^a&s)", &parent, &depth, nullptr);
    if (!ValidId(parent)) {
      g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                            G_DBUS_ERROR_INVALID_ARGS,
                                            "Entrada %d desconocida", parent);
      return;
    }
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(u@(ia{sv}av))", tray->revision,
                                  MenuNode(tray, parent, depth != 0)));
  } else if (name == "GetGroupProperties") {
    g_autoptr(GVariant) ids = g_variant_get_child_value(params, 0);
    GVariantBuilder out;
    g_variant_builder_init(&out, G_VARIANT_TYPE("a(ia{sv})"));
    gsize count = 0;
    const gint32* values = static_cast<const gint32*>(
        g_variant_get_fixed_array(ids, &count, sizeof(gint32)));
    // Lista vacía = todas las entradas.
    if (count == 0) {
      for (int id = 0; id <= kLastId; ++id) {
        g_variant_builder_add(&out, "(i@a{sv})", id,
                              MenuItemProperties(tray, id));
      }
    }
    for (gsize i = 0; i < count; ++i) {
      if (!ValidId(values[i])) continue;
      g_variant_builder_add(&out, "(i@a{sv})", values[i],
                            MenuItemProperties(tray, values[i]));
    }
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(a(ia{sv}))", &out));
  } else if (name == "GetProperty") {
    gint32 id = 0;
    const gchar* prop = nullptr;
    g_variant_get(params, "(i&s)", &id, &prop);
    g_autoptr(GVariant) props = MenuItemProperties(tray, id);
    g_autoptr(GVariant) value = g_variant_lookup_value(props, prop, nullptr);
    if (!ValidId(id) || value == nullptr) {
      g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                            G_DBUS_ERROR_INVALID_ARGS,
                                            "Propiedad desconocida");
      return;
    }
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(v)", value));
  } else if (name == "Event") {
    gint32 id = 0;
    const gchar* event = nullptr;
    g_variant_get(params, "(i&svu)", &id, &event, nullptr, nullptr);
    g_dbus_method_invocation_return_value(invocation, nullptr);
    MenuEvent(tray, id, event);
  } else if (name == "EventGroup") {
    g_autoptr(GVariantIter) iter = nullptr;
    g_variant_get(params, "(a(isvu))", &iter);
    std::vector<std::pair<int, std::string>> events;
    gint32 id = 0;
    const gchar* event = nullptr;
    GVariant* data = nullptr;
    guint32 timestamp = 0;
    while (g_variant_iter_next(iter, "(i&svu)", &id, &event, &data,
                               &timestamp)) {
      events.emplace_back(id, event);
      g_variant_unref(data);
    }
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(@ai)", g_variant_new_array(
                                               G_VARIANT_TYPE_INT32, nullptr, 0)));
    for (const auto& e : events) MenuEvent(tray, e.first, e.second.c_str());
  } else if (name == "AboutToShow") {
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(b)", FALSE));
  } else if (name == "AboutToShowGroup") {
    GVariant* empty1 = g_variant_new_array(G_VARIANT_TYPE_INT32, nullptr, 0);
    GVariant* empty2 = g_variant_new_array(G_VARIANT_TYPE_INT32, nullptr, 0);
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(@ai@ai)", empty1, empty2));
  } else {
    g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                          G_DBUS_ERROR_UNKNOWN_METHOD,
                                          "Método desconocido");
  }
}

const GDBusInterfaceVTable kMenuVTable = {MenuMethodCall, MenuGetProperty,
                                          nullptr, {nullptr}};

// ---- Registro en el StatusNotifierWatcher ----------------------------------

void RegisterWithWatcher(AuroraTray* tray) {
  g_dbus_connection_call(
      tray->bus, kWatcherName, "/StatusNotifierWatcher", kWatcherName,
      "RegisterStatusNotifierItem",
      g_variant_new("(s)", tray->bus_name.c_str()), nullptr,
      G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr, nullptr);
}

void OnWatcherAppeared(GDBusConnection*, const gchar*, const gchar*,
                       gpointer user_data) {
  RegisterWithWatcher(static_cast<AuroraTray*>(user_data));
}

void Emit(AuroraTray* tray, const char* path, const char* iface,
          const char* signal, GVariant* params) {
  g_dbus_connection_emit_signal(tray->bus, nullptr, path, iface, signal, params,
                                nullptr);
}

}  // namespace

AuroraTray* aurora_tray_new(const gchar* icon_dir, const gchar* icon_name,
                            AuroraTrayCallback callback, gpointer data) {
  g_autoptr(GError) error = nullptr;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) return nullptr;

  auto* tray = new AuroraTray();
  tray->bus = bus;
  tray->callback = callback;
  tray->data = data;
  tray->icon_dir = icon_dir != nullptr ? icon_dir : "";
  tray->icon_name = icon_name != nullptr ? icon_name : "";
  tray->icon_pixmap = LoadPixmap(tray->icon_dir, tray->icon_name);
  tray->item_info = g_dbus_node_info_new_for_xml(kItemXml, nullptr);
  tray->menu_info = g_dbus_node_info_new_for_xml(kMenuXml, nullptr);
  if (tray->item_info == nullptr || tray->menu_info == nullptr) {
    aurora_tray_free(tray);
    return nullptr;
  }
  tray->item_registration = g_dbus_connection_register_object(
      bus, kItemPath, tray->item_info->interfaces[0], &kItemVTable, tray,
      nullptr, nullptr);
  tray->menu_registration = g_dbus_connection_register_object(
      bus, kMenuPath, tray->menu_info->interfaces[0], &kMenuVTable, tray,
      nullptr, nullptr);
  if (tray->item_registration == 0 || tray->menu_registration == 0) {
    aurora_tray_free(tray);
    return nullptr;
  }

  // Nombre propio según la especificación; el watcher lo recibe al registrar.
  static int instance = 0;
  g_autofree gchar* name = g_strdup_printf("org.kde.StatusNotifierItem-%d-%d",
                                           static_cast<int>(getpid()),
                                           ++instance);
  tray->bus_name = name;
  tray->owner_id = g_bus_own_name_on_connection(
      bus, name, G_BUS_NAME_OWNER_FLAGS_NONE, nullptr, nullptr, nullptr,
      nullptr);
  // Registro ahora y cada vez que el anfitrión (re)aparece.
  tray->watcher_id = g_bus_watch_name_on_connection(
      bus, kWatcherName, G_BUS_NAME_WATCHER_FLAGS_NONE, OnWatcherAppeared,
      nullptr, tray, nullptr);
  return tray;
}

void aurora_tray_set_playback(AuroraTray* tray, const gchar* title,
                              const gchar* artist, gboolean playing) {
  if (tray == nullptr) return;
  std::string now = title != nullptr ? title : "";
  if (!now.empty() && artist != nullptr && artist[0] != '\0') {
    now += " – ";
    now += artist;
  }
  const bool is_playing = playing != FALSE;
  if (now == tray->now && is_playing == tray->playing) return;
  const bool title_changed = now != tray->now;
  tray->now = now;
  tray->playing = is_playing;
  ++tray->revision;
  Emit(tray, kMenuPath, "com.canonical.dbusmenu", "LayoutUpdated",
       g_variant_new("(ui)", tray->revision, 0));
  if (title_changed) {
    Emit(tray, kItemPath, "org.kde.StatusNotifierItem", "NewTitle", nullptr);
    Emit(tray, kItemPath, "org.kde.StatusNotifierItem", "NewToolTip", nullptr);
  }
}

void aurora_tray_free(AuroraTray* tray) {
  if (tray == nullptr) return;
  if (tray->watcher_id != 0) g_bus_unwatch_name(tray->watcher_id);
  if (tray->owner_id != 0) g_bus_unown_name(tray->owner_id);
  if (tray->bus != nullptr) {
    if (tray->item_registration != 0) {
      g_dbus_connection_unregister_object(tray->bus, tray->item_registration);
    }
    if (tray->menu_registration != 0) {
      g_dbus_connection_unregister_object(tray->bus, tray->menu_registration);
    }
  }
  g_clear_pointer(&tray->item_info, g_dbus_node_info_unref);
  g_clear_pointer(&tray->menu_info, g_dbus_node_info_unref);
  g_clear_pointer(&tray->icon_pixmap, g_variant_unref);
  g_clear_object(&tray->bus);
  delete tray;
}

gboolean aurora_tray_host_available(void) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) return FALSE;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", kWatcherName), G_VARIANT_TYPE("(b)"),
      G_DBUS_CALL_FLAGS_NONE, 500, nullptr, &error);
  if (reply == nullptr) return FALSE;
  gboolean owned = FALSE;
  g_variant_get(reply, "(b)", &owned);
  return owned;
}
