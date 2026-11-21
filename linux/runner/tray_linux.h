#ifndef RUNNER_TRAY_LINUX_H_
#define RUNNER_TRAY_LINUX_H_

#include <gtk/gtk.h>

// Icono de Aurora en la bandeja del sistema: StatusNotifierItem y menú
// dbusmenu propios sobre GDBus (sin libayatana-appindicator). Clic izquierdo
// muestra la ventana, clic central reproduce/pausa y el derecho abre el menú.
// Sin anfitrión de bandeja la X cierra de verdad.

typedef struct _AuroraTray AuroraTray;

typedef enum {
  AURORA_TRAY_SHOW,
  AURORA_TRAY_PLAY_PAUSE,
  AURORA_TRAY_NEXT,
  AURORA_TRAY_PREVIOUS,
  AURORA_TRAY_QUIT,
} AuroraTrayCommand;

typedef void (*AuroraTrayCallback)(AuroraTrayCommand command, gpointer data);

// NULL si no hay bus de sesión.
// [icon_dir] contiene [icon_name].png.
AuroraTray* aurora_tray_new(const gchar* icon_dir, const gchar* icon_name,
                            AuroraTrayCallback callback, gpointer data);

// Título, artista y estado para el menú y el título del icono.
void aurora_tray_set_playback(AuroraTray* tray, const gchar* title,
                              const gchar* artist, gboolean playing);

void aurora_tray_free(AuroraTray* tray);

// Hay un anfitrión de bandeja (org.kde.StatusNotifierWatcher) en el bus de
// sesión: solo entonces tiene sentido ocultar la ventana en ella.
gboolean aurora_tray_host_available(void);

#endif  // RUNNER_TRAY_LINUX_H_
