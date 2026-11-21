#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <unistd.h>

#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "tray_linux.h"

// Lo que Dart tarda como mucho en confirmar un cierre real (pausar el audio)
// antes de cerrar igualmente.
constexpr guint kCloseTimeoutMs = 3000;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* channel;
  AuroraTray* tray;
  // La X oculta la ventana en la bandeja (preferencia de Dart).
  gboolean close_to_tray;
  // Cierre real en curso (Salir, hardExit o la X sin bandeja).
  gboolean closing;
  gboolean close_confirmed;
  guint close_timeout;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void show_window(MyApplication* self) {
  if (self->window == nullptr) return;
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_present(self->window);
}

// Cierre definitivo: destruir la ventana termina la aplicación.
static void finish_close(MyApplication* self) {
  if (self->close_timeout != 0) {
    g_source_remove(self->close_timeout);
    self->close_timeout = 0;
  }
  if (self->close_confirmed) return;
  self->close_confirmed = TRUE;
  // El canal suelta su manejador mientras el motor sigue vivo; después de
  // destruir la ventana avisaría de un mensajero sin motor.
  g_clear_object(&self->channel);
  if (self->window != nullptr) {
    gtk_widget_destroy(GTK_WIDGET(self->window));
  } else {
    g_application_quit(G_APPLICATION(self));
  }
}

static gboolean close_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->close_timeout = 0;
  finish_close(self);
  return G_SOURCE_REMOVE;
}

static void confirm_close_cb(GObject* object, GAsyncResult* result,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), result, &error);
  finish_close(self);
  g_object_unref(self);
}

// Avisa a Dart (pausa el audio) y cierra al responder o a los 3 s.
static void request_real_close(MyApplication* self) {
  if (self->closing) return;
  self->closing = TRUE;
  if (self->channel == nullptr) {
    finish_close(self);
    return;
  }
  self->close_timeout = g_timeout_add(kCloseTimeoutMs, close_timeout_cb, self);
  g_autoptr(FlValue) args = fl_value_new_bool(TRUE);
  fl_method_channel_invoke_method(self->channel, "confirmClose", args, nullptr,
                                  confirm_close_cb, g_object_ref(self));
}

// Vigilante del cierre pedido por Dart: si el proceso sigue vivo, termina.
static gboolean hard_exit_watchdog_cb(gpointer) {
  _exit(0);
  return G_SOURCE_REMOVE;
}

static gboolean delete_event_cb(GtkWidget* widget, GdkEvent*,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->close_confirmed) return FALSE;
  if (!self->closing && self->close_to_tray && self->tray != nullptr &&
      aurora_tray_host_available()) {
    gtk_widget_hide(widget);
    return TRUE;
  }
  request_real_close(self);
  return TRUE;
}

static void send_tray_action(MyApplication* self, const gchar* action) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string(action);
  fl_method_channel_invoke_method(self->channel, "trayAction", args, nullptr,
                                  nullptr, nullptr);
}

static void tray_command_cb(AuroraTrayCommand command, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  switch (command) {
    case AURORA_TRAY_SHOW:
      show_window(self);
      break;
    case AURORA_TRAY_PLAY_PAUSE:
      send_tray_action(self, "playPause");
      break;
    case AURORA_TRAY_NEXT:
      send_tray_action(self, "next");
      break;
    case AURORA_TRAY_PREVIOUS:
      send_tray_action(self, "previous");
      break;
    case AURORA_TRAY_QUIT:
      request_real_close(self);
      break;
  }
}

static const gchar* map_string(FlValue* map, const gchar* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : "";
}

// Canal "aurora/window": el mismo protocolo que el ejecutable de Windows. Lo
// que no existe en Linux (mini, pantalla completa, inicio con el sistema…)
// responde «no implementado» y Dart lo trata como `false`.
static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(name, "setCloseToTray") == 0) {
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
      self->close_to_tray = fl_value_get_bool(args);
    }
  } else if (g_strcmp0(name, "setPlayback") == 0) {
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* playing = fl_value_lookup_string(args, "playing");
      aurora_tray_set_playback(
          self->tray, map_string(args, "title"), map_string(args, "artist"),
          playing != nullptr &&
              fl_value_get_type(playing) == FL_VALUE_TYPE_BOOL &&
              fl_value_get_bool(playing));
    }
  } else if (g_strcmp0(name, "showWindow") == 0) {
    show_window(self);
  } else if (g_strcmp0(name, "close") == 0) {
    // Igual que la X de la ventana: puede ir a la bandeja.
    if (self->window != nullptr) gtk_window_close(self->window);
  } else if (g_strcmp0(name, "hardExit") == 0) {
    // Cierre real pedido por Dart: ignora la bandeja y no espera a nadie. Se
    // responde antes de cerrar, con el motor todavía vivo.
    fl_method_call_respond_success(call, nullptr, nullptr);
    g_timeout_add(kCloseTimeoutMs, hard_exit_watchdog_cb, nullptr);
    self->closing = TRUE;
    finish_close(self);
    return;
  } else if (g_strcmp0(name, "trayAvailable") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(
        self->tray != nullptr && aurora_tray_host_available());
    fl_method_call_respond_success(call, result, nullptr);
    return;
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // Otra activación con la app ya abierta (lanzador, segunda instancia).
  if (self->window != nullptr) {
    show_window(self);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Aurora Music");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Aurora Music");
  }

  gtk_window_set_default_size(window, 1280, 720);
  // Icono junto al ejecutable: <bundle>/data/icon.png (lo instala CMake). El de
  // la bandeja está en <bundle>/data/tray.
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* tray_dir = nullptr;
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon = g_build_filename(dir, "data", "icon.png", nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
    tray_dir = g_build_filename(dir, "data", "tray", nullptr);
  }
  g_signal_connect(window, "delete-event", G_CALLBACK(delete_event_cb), self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                        "aurora/window",
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);
  self->tray = aurora_tray_new(tray_dir, "aurora-music-tray", tray_command_cb,
                               self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::command_line. Con la app ya abierta (segunda
// instancia o enlace aurora://), muestra la ventana y pasa los argumentos a
// Dart; la primera vez, los guarda para el punto de entrada y la crea.
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  g_auto(GStrv) arguments =
      g_application_command_line_get_arguments(command_line, nullptr);
  // Strip out the first argument as it is the binary name.
  gchar** rest = arguments != nullptr && arguments[0] != nullptr
                     ? arguments + 1
                     : arguments;
  if (self->window == nullptr) {
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    self->dart_entrypoint_arguments = g_strdupv(rest);
    g_application_activate(application);
    return 0;
  }
  show_window(self);
  if (rest != nullptr && rest[0] != nullptr && self->channel != nullptr) {
    g_autofree gchar* joined = g_strjoinv(" ", rest);
    g_autoptr(FlValue) args = fl_value_new_string(joined);
    fl_method_channel_invoke_method(self->channel, "arguments", args, nullptr,
                                    nullptr, nullptr);
  }
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  g_clear_pointer(&self->tray, aurora_tray_free);
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->tray, aurora_tray_free);
  g_clear_object(&self->channel);
  if (self->close_timeout != 0) {
    g_source_remove(self->close_timeout);
    self->close_timeout = 0;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->close_to_tray = TRUE;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Una sola instancia: abrir Aurora otra vez (o un enlace aurora://) muestra
  // la ventana que ya existe, aunque esté oculta en la bandeja.
  // AURORA_MULTI_INSTANCE=1 permite varias (pruebas y mediciones).
  GApplicationFlags flags = G_APPLICATION_HANDLES_COMMAND_LINE;
  if (g_getenv("AURORA_MULTI_INSTANCE") != nullptr) {
    flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_NON_UNIQUE);
  }
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}
