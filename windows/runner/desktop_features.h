#ifndef RUNNER_DESKTOP_FEATURES_H_
#define RUNNER_DESKTOP_FEATURES_H_

#include <windows.h>

#include <string>

// Marca de WM_COPYDATA: una segunda instancia envia sus argumentos a la
// primera (p. ej. aurora://jam/CODIGO). La primera los reenvia a Dart por el
// canal 'aurora/window' (metodo 'arguments').
constexpr ULONG_PTR kForwardArgsMagic = 0x41555241;  // "AURA"

// Devuelve true si ya hay otra instancia: le pasa los argumentos y la enfoca.
// Si es la primera, deja el mutex abierto toda la vida del proceso.
bool ForwardToExistingInstance(const std::wstring& arguments);

// Libera el mutex de instancia unica (cierre forzado del actualizador).
void ReleaseInstanceMutex();

bool IsAutostartEnabled();
bool SetAutostart(bool enabled);

// Geometria guardada (coordenadas de pantalla). false si no hay o ya no es
// visible en ningun monitor.
struct SavedGeometry {
  RECT rect;
  bool maximized;
};
bool LoadGeometry(SavedGeometry* out);
void SaveGeometry(const RECT& normal_rect, bool maximized);

// Rellena WM_GETMINMAXINFO: maximizar usa el area de trabajo del monitor
// actual (sin tapar la barra de tareas, incluso autoocultada) y tamano minimo.
void FillMinMaxInfo(HWND hwnd, MINMAXINFO* info);

// Activa el tamano minimo del modo mini (ventana compacta) en FillMinMaxInfo.
void SetMiniMode(bool enabled);

std::wstring WideFromUtf8(const std::string& utf8);

#endif  // RUNNER_DESKTOP_FEATURES_H_
