#include "tray_linux.h"

#include <dlfcn.h>

#include <string>

namespace {

// Subconjunto de la API de libayatana-appindicator3 / libappindicator3.
typedef struct _AppIndicator AppIndicator;
constexpr int kCategoryApplicationStatus = 0;
constexpr int kStatusActive = 1;

using NewFn = AppIndicator* (*)(const gchar*, const gchar*, int);
using SetStatusFn = void (*)(AppIndicator*, int);
using SetMenuFn = void (*)(AppIndicator*, GtkMenu*);
using SetStringFn = void (*)(AppIndicator*, const gchar*);
using SetWidgetFn = void (*)(AppIndicator*, GtkWidget*);

struct Api {
  void* handle = nullptr;
  NewFn create = nullptr;
  SetStatusFn set_status = nullptr;
  SetMenuFn set_menu = nullptr;
  SetStringFn set_title = nullptr;
  SetStringFn set_icon_theme_path = nullptr;
  SetWidgetFn set_secondary_activate_target = nullptr;
};

bool LoadApi(Api* api) {
  static const char* const kLibraries[] = {
      "libayatana-appindicator3.so.1",
      "libappindicator3.so.1",
  };
  for (const char* name : kLibraries) {
    api->handle = dlopen(name, RTLD_LAZY | RTLD_LOCAL);
    if (api->handle != nullptr) break;
  }
  if (api->handle == nullptr) return false;
  api->create =
      reinterpret_cast<NewFn>(dlsym(api->handle, "app_indicator_new"));
  api->set_status = reinterpret_cast<SetStatusFn>(
      dlsym(api->handle, "app_indicator_set_status"));
  api->set_menu =
      reinterpret_cast<SetMenuFn>(dlsym(api->handle, "app_indicator_set_menu"));
  api->set_title = reinterpret_cast<SetStringFn>(
      dlsym(api->handle, "app_indicator_set_title"));
  api->set_icon_theme_path = reinterpret_cast<SetStringFn>(
      dlsym(api->handle, "app_indicator_set_icon_theme_path"));
  api->set_secondary_activate_target = reinterpret_cast<SetWidgetFn>(
      dlsym(api->handle, "app_indicator_set_secondary_activate_target"));
  if (api->create == nullptr || api->set_status == nullptr ||
      api->set_menu == nullptr) {
    dlclose(api->handle);
    api->handle = nullptr;
    return false;
  }
  return true;
}

}  // namespace

struct _AuroraTray {
  Api api;
  AppIndicator* indicator = nullptr;
  GtkWidget* menu = nullptr;
  GtkWidget* now_playing = nullptr;
  GtkWidget* now_separator = nullptr;
  GtkWidget* show = nullptr;
  GtkWidget* play_pause = nullptr;
  AuroraTrayCallback callback = nullptr;
  gpointer data = nullptr;
};

static void on_item_activate(GtkMenuItem* item, gpointer user_data) {
  auto* tray = static_cast<AuroraTray*>(user_data);
  const auto command = static_cast<AuroraTrayCommand>(
      GPOINTER_TO_INT(g_object_get_data(G_OBJECT(item), "aurora-command")));
  if (tray->callback != nullptr) tray->callback(command, tray->data);
}

static GtkWidget* add_item(AuroraTray* tray, const gchar* label,
                           AuroraTrayCommand command) {
  GtkWidget* item = gtk_menu_item_new_with_label(label);
  g_object_set_data(G_OBJECT(item), "aurora-command",
                    GINT_TO_POINTER(command));
  g_signal_connect(item, "activate", G_CALLBACK(on_item_activate), tray);
  gtk_menu_shell_append(GTK_MENU_SHELL(tray->menu), item);
  gtk_widget_show(item);
  return item;
}

static void add_separator(AuroraTray* tray) {
  GtkWidget* separator = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(tray->menu), separator);
  gtk_widget_show(separator);
}

AuroraTray* aurora_tray_new(const gchar* icon_dir, const gchar* icon_name,
                            AuroraTrayCallback callback, gpointer data) {
  auto* tray = new AuroraTray();
  if (!LoadApi(&tray->api)) {
    delete tray;
    return nullptr;
  }
  tray->callback = callback;
  tray->data = data;

  tray->menu = gtk_menu_new();
  g_object_ref_sink(tray->menu);
  // Lo que suena (informativo, sin acción); oculto mientras no haya pista.
  tray->now_playing = gtk_menu_item_new_with_label("");
  gtk_widget_set_sensitive(tray->now_playing, FALSE);
  gtk_menu_shell_append(GTK_MENU_SHELL(tray->menu), tray->now_playing);
  tray->now_separator = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(tray->menu), tray->now_separator);

  tray->show = add_item(tray, "Mostrar Aurora", AURORA_TRAY_SHOW);
  tray->play_pause = add_item(tray, "Reproducir", AURORA_TRAY_PLAY_PAUSE);
  add_item(tray, "Siguiente", AURORA_TRAY_NEXT);
  add_item(tray, "Anterior", AURORA_TRAY_PREVIOUS);
  add_separator(tray);
  add_item(tray, "Salir", AURORA_TRAY_QUIT);

  tray->indicator = tray->api.create("aurora-music", icon_name,
                                     kCategoryApplicationStatus);
  if (tray->indicator == nullptr) {
    aurora_tray_free(tray);
    return nullptr;
  }
  if (tray->api.set_icon_theme_path != nullptr && icon_dir != nullptr) {
    tray->api.set_icon_theme_path(tray->indicator, icon_dir);
  }
  if (tray->api.set_title != nullptr) {
    tray->api.set_title(tray->indicator, "Aurora Music");
  }
  tray->api.set_menu(tray->indicator, GTK_MENU(tray->menu));
  // Clic central (o el que el anfitrión asigne a la acción secundaria):
  // mostrar la ventana sin abrir el menú.
  if (tray->api.set_secondary_activate_target != nullptr) {
    tray->api.set_secondary_activate_target(tray->indicator, tray->show);
  }
  tray->api.set_status(tray->indicator, kStatusActive);
  return tray;
}

void aurora_tray_set_playback(AuroraTray* tray, const gchar* title,
                              const gchar* artist, gboolean playing) {
  if (tray == nullptr) return;
  gtk_menu_item_set_label(GTK_MENU_ITEM(tray->play_pause),
                          playing ? "Pausa" : "Reproducir");
  std::string now = title != nullptr ? title : "";
  if (!now.empty() && artist != nullptr && artist[0] != '\0') {
    now += " – ";
    now += artist;
  }
  if (now.empty()) {
    gtk_widget_hide(tray->now_playing);
    gtk_widget_hide(tray->now_separator);
  } else {
    gtk_menu_item_set_label(GTK_MENU_ITEM(tray->now_playing), now.c_str());
    gtk_widget_show(tray->now_playing);
    gtk_widget_show(tray->now_separator);
  }
  if (tray->api.set_title != nullptr) {
    const std::string label = now.empty() ? "Aurora Music" : now;
    tray->api.set_title(tray->indicator, label.c_str());
  }
}

void aurora_tray_free(AuroraTray* tray) {
  if (tray == nullptr) return;
  g_clear_object(&tray->indicator);
  if (tray->menu != nullptr) {
    gtk_widget_destroy(tray->menu);
    g_object_unref(tray->menu);
    tray->menu = nullptr;
  }
  // La biblioteca se queda cargada: GObject puede tener tipos registrados.
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
      g_variant_new("(s)", "org.kde.StatusNotifierWatcher"),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 500, nullptr, &error);
  if (reply == nullptr) return FALSE;
  gboolean owned = FALSE;
  g_variant_get(reply, "(b)", &owned);
  return owned;
}
