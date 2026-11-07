#include "desktop_features.h"

#include <shellapi.h>

#include <algorithm>

namespace {

constexpr wchar_t kMutexName[] = L"Local\\AuroraMusicSingleInstance";
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"AuroraMusic";
constexpr wchar_t kGeometryKey[] = L"Software\\AuroraMusic\\Window";
// Tamano minimo logico (a 96 dpi); se escala con el dpi de la ventana.
constexpr int kMinWidth = 720;
constexpr int kMinHeight = 540;
// Minimo del modo mini (ventana compacta).
constexpr int kMiniMinWidth = 300;
constexpr int kMiniMinHeight = 120;
bool g_mini_mode = false;

bool ReadDword(HKEY key, const wchar_t* name, int* value) {
  DWORD data = 0, size = sizeof(data), type = 0;
  if (RegGetValueW(key, nullptr, name, RRF_RT_REG_DWORD, &type, &data,
                   &size) != ERROR_SUCCESS) {
    return false;
  }
  *value = static_cast<int>(data);
  return true;
}

void WriteDword(HKEY key, const wchar_t* name, int value) {
  const DWORD data = static_cast<DWORD>(value);
  RegSetValueExW(key, name, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&data), sizeof(data));
}

}  // namespace

std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  if (n <= 0) return std::wstring();
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      out.data(), n);
  return out;
}

namespace {
HANDLE g_instance_mutex = nullptr;
}

void ReleaseInstanceMutex() {
  if (g_instance_mutex) {
    CloseHandle(g_instance_mutex);
    g_instance_mutex = nullptr;
  }
}

bool ForwardToExistingInstance(const std::wstring& arguments) {
  // Hasta ~8 s: la primera instancia puede estar creando su ventana, o morir
  // (proceso agonizante que aun retiene el mutex pero ya sin ventana).
  for (int i = 0; i < 80; ++i) {
    // El handle se mantiene abierto hasta que el proceso termina.
    HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
    if (mutex && GetLastError() != ERROR_ALREADY_EXISTS) {
      g_instance_mutex = mutex;
      return false;
    }
    if (mutex) CloseHandle(mutex);

    // Solo la clase: el titulo puede cambiar y la ventana puede estar oculta
    // (FindWindow tambien encuentra ventanas ocultas).
    HWND target = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (target) {
      DWORD pid = 0;
      GetWindowThreadProcessId(target, &pid);
      AllowSetForegroundWindow(pid);
      COPYDATASTRUCT data = {};
      data.dwData = kForwardArgsMagic;
      data.cbData =
          static_cast<DWORD>((arguments.size() + 1) * sizeof(wchar_t));
      data.lpData = const_cast<wchar_t*>(arguments.c_str());
      DWORD_PTR handled = 0;
      if (SendMessageTimeoutW(target, WM_COPYDATA, 0,
                              reinterpret_cast<LPARAM>(&data),
                              SMTO_ABORTIFHUNG, 3000, &handled) &&
          handled) {
        return true;
      }
    }
    Sleep(100);
  }
  // Nadie respondio (instancia colgada): arrancar normal en vez de salir sin
  // ventana, que dejaba al usuario sin Aurora.
  return false;
}

bool IsAutostartEnabled() {
  return RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                      nullptr, nullptr, nullptr) == ERROR_SUCCESS;
}

bool SetAutostart(bool enabled) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LONG result;
  if (enabled) {
    wchar_t path[MAX_PATH];
    const DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    // Arranca oculto en la bandeja.
    const std::wstring command = L"\"" + std::wstring(path, n) + L"\" --minimized";
    result = RegSetValueExW(
        key, kRunValue, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(key, kRunValue);
    if (result == ERROR_FILE_NOT_FOUND) result = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

bool LoadGeometry(SavedGeometry* out) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kGeometryKey, 0, KEY_QUERY_VALUE,
                    &key) != ERROR_SUCCESS) {
    return false;
  }
  int x = 0, y = 0, w = 0, h = 0, maximized = 0;
  const bool ok = ReadDword(key, L"x", &x) && ReadDword(key, L"y", &y) &&
                  ReadDword(key, L"w", &w) && ReadDword(key, L"h", &h);
  ReadDword(key, L"maximized", &maximized);
  RegCloseKey(key);
  if (!ok || w < 300 || h < 200 || w > 20000 || h > 20000) return false;

  RECT rect = {x, y, x + w, y + h};
  // Debe seguir visible en algun monitor (puede haberse desconectado).
  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONULL);
  if (!monitor) return false;
  MONITORINFO info = {sizeof(info)};
  GetMonitorInfoW(monitor, &info);
  RECT visible;
  if (!IntersectRect(&visible, &rect, &info.rcWork) ||
      visible.right - visible.left < 160 || visible.bottom - visible.top < 80) {
    return false;
  }
  out->rect = rect;
  out->maximized = maximized != 0;
  return true;
}

void SaveGeometry(const RECT& r, bool maximized) {
  if (r.right - r.left < 300 || r.bottom - r.top < 200) return;
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kGeometryKey, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  WriteDword(key, L"x", r.left);
  WriteDword(key, L"y", r.top);
  WriteDword(key, L"w", r.right - r.left);
  WriteDword(key, L"h", r.bottom - r.top);
  WriteDword(key, L"maximized", maximized ? 1 : 0);
  RegCloseKey(key);
}

void FillMinMaxInfo(HWND hwnd, MINMAXINFO* info) {
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {sizeof(mi)};
  if (GetMonitorInfoW(monitor, &mi)) {
    RECT work = mi.rcWork;
    // Con la barra de tareas autoocultada rcWork == pantalla completa y la
    // barra no podria reaparecer: deja 1 px libre en su borde.
    for (UINT edge = ABE_LEFT; edge <= ABE_BOTTOM; ++edge) {
      APPBARDATA abd = {sizeof(abd)};
      abd.uEdge = edge;
      abd.rc = mi.rcMonitor;
      if (SHAppBarMessage(ABM_GETAUTOHIDEBAREX, &abd)) {
        if (edge == ABE_LEFT) work.left += 1;
        if (edge == ABE_TOP) work.top += 1;
        if (edge == ABE_RIGHT) work.right -= 1;
        if (edge == ABE_BOTTOM) work.bottom -= 1;
      }
    }
    info->ptMaxPosition.x = work.left - mi.rcMonitor.left;
    info->ptMaxPosition.y = work.top - mi.rcMonitor.top;
    info->ptMaxSize.x = work.right - work.left;
    info->ptMaxSize.y = work.bottom - work.top;
  }
  const UINT dpi = std::max<UINT>(GetDpiForWindow(hwnd), 96);
  // En modo mini (ventana compacta) el minimo es el del mini reproductor.
  info->ptMinTrackSize.x =
      MulDiv(g_mini_mode ? kMiniMinWidth : kMinWidth, dpi, 96);
  info->ptMinTrackSize.y =
      MulDiv(g_mini_mode ? kMiniMinHeight : kMinHeight, dpi, 96);
}

void SetMiniMode(bool enabled) { g_mini_mode = enabled; }
