#include "flutter_window.h"

#include <dwmapi.h>
#include <windowsx.h>
#include <commctrl.h>
#include <algorithm>
#include <optional>
#include <thread>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

#include "desktop_features.h"
#include "utils.h"
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr UINT_PTR kCloseTimer = 1;
enum TrayCommand {
  kCmdShow = 1,
  kCmdPlayPause,
  kCmdNext,
  kCmdPrevious,
  kCmdQuit,
};
bool g_fullscreen = false;
}  // namespace

// Sin marco nativo: el redimensionado se resuelve en los bordes de la ventana.
static LRESULT EdgeHit(HWND host, LPARAM lparam) {
  RECT r;
  GetWindowRect(host, &r);
  const int b = std::max(6, MulDiv(6, static_cast<int>(GetDpiForWindow(host)), 96));
  const POINT p{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  const bool l = p.x < r.left + b, rt = p.x >= r.right - b;
  const bool t = p.y < r.top + b, bt = p.y >= r.bottom - b;
  if (t && l) return HTTOPLEFT;
  if (t && rt) return HTTOPRIGHT;
  if (bt && l) return HTBOTTOMLEFT;
  if (bt && rt) return HTBOTTOMRIGHT;
  if (l) return HTLEFT;
  if (rt) return HTRIGHT;
  if (t) return HTTOP;
  if (bt) return HTBOTTOM;
  return HTCLIENT;
}

// La vista de Flutter cubre toda la ventana: en los bordes cede el ratón al host.
static LRESULT CALLBACK EdgeSubclassProc(HWND h, UINT msg, WPARAM w, LPARAM l,
                                         UINT_PTR, DWORD_PTR) {
  if (msg == WM_NCHITTEST) {
    HWND host = GetParent(h);
    if (host && !IsZoomed(host) && !g_fullscreen &&
        EdgeHit(host, l) != HTCLIENT) {
      return HTTRANSPARENT;
    }
  }
  return DefSubclassProc(h, msg, w, l);
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  SetWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                    EdgeSubclassProc, 1, 0);

  // The supplied studio design includes its own Flutter title bar. Keep native
  // resizing while removing the duplicate OS caption; all controls use Win32.
  const HWND host = GetHandle();
  SetWindowLongPtr(host, GWL_STYLE, GetWindowLongPtr(host, GWL_STYLE) & ~WS_CAPTION);
  SetWindowPos(host, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  // Windows 11: sin el borde de 1 px que DWM pinta claro al activar.
  const DWORD no_border = 0xFFFFFFFE;  // DWMWA_COLOR_NONE
  DwmSetWindowAttribute(host, 34 /* DWMWA_BORDER_COLOR */, &no_border,
                        sizeof(no_border));

  // Posicion/tamano de la sesion anterior (validados contra los monitores).
  SavedGeometry saved;
  if (LoadGeometry(&saved)) {
    has_saved_geometry_ = true;
    saved_maximized_ = saved.maximized;
    // Geometrias guardadas con el marco antiguo pueden asomar fuera del area util.
    RECT r = saved.rect;
    MONITORINFO mi{sizeof(mi)};
    if (GetMonitorInfo(MonitorFromRect(&r, MONITOR_DEFAULTTONEAREST), &mi) &&
        r.top < mi.rcWork.top) {
      r.bottom += mi.rcWork.top - r.top;
      r.top = mi.rcWork.top;
    }
    SetWindowPos(host, nullptr, r.left, r.top, r.right - r.left, r.bottom - r.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  GetWindowRect(host, &normal_rect_);
  start_minimized_ = wcsstr(GetCommandLineW(), L"--minimized") != nullptr;
  taskbar_created_msg_ = RegisterWindowMessageW(L"TaskbarCreated");
  AddTray();

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "aurora/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this, host](const auto& call, auto result) {
        const auto& name = call.method_name();
        const auto* args = call.arguments();
        if (name == "minimize") {
          ShowWindow(host, SW_MINIMIZE);
        } else if (name == "maximize") {
          ShowWindow(host, IsZoomed(host) ? SW_RESTORE : SW_MAXIMIZE);
        } else if (name == "close") {
          // Boton X de Aurora: puede ocultar a la bandeja (ver WM_CLOSE).
          PostMessage(host, WM_CLOSE, 0, 0);
        } else if (name == "hardExit") {
          // Cierre real pedido por Dart (actualizador): ignora la bandeja.
          real_exit_ = true;
          PostMessage(host, WM_CLOSE, 0, 0);
          // Solo este camino lleva vigilante: el instalador necesita el proceso muerto.
          ArmExitWatchdog();
        } else if (name == "setBackground") {
          // Color del tema (RGB): fondo de la ventana mientras se redimensiona.
          const auto* rgb = args ? std::get_if<int32_t>(args) : nullptr;
          if (rgb) {
            HBRUSH brush = CreateSolidBrush(RGB((*rgb >> 16) & 0xFF,
                                                (*rgb >> 8) & 0xFF, *rgb & 0xFF));
            HBRUSH old = reinterpret_cast<HBRUSH>(
                SetClassLongPtr(host, GCLP_HBRBACKGROUND,
                                reinterpret_cast<LONG_PTR>(brush)));
            if (old) DeleteObject(old);
            InvalidateRect(host, nullptr, TRUE);
          }
        } else if (name == "drag") {
          ReleaseCapture();
          PostMessage(host, WM_NCLBUTTONDOWN, HTCAPTION, GetMessagePos());
        } else if (name == "showWindow") {
          RestoreFromTray();
        } else if (name == "setCloseToTray") {
          const auto* v = args ? std::get_if<bool>(args) : nullptr;
          if (v) close_to_tray_ = *v;
        } else if (name == "setPlayback") {
          const auto* map = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
          if (map) {
            auto text = [map](const char* key) {
              auto it = map->find(flutter::EncodableValue(key));
              const auto* s = it == map->end() ? nullptr : std::get_if<std::string>(&it->second);
              return s ? WideFromUtf8(*s) : std::wstring();
            };
            auto it = map->find(flutter::EncodableValue("playing"));
            const auto* p = it == map->end() ? nullptr : std::get_if<bool>(&it->second);
            playing_ = p && *p;
            track_title_ = text("title");
            track_artist_ = text("artist");
            UpdateTrayTip();
          }
        } else if (name == "getAutostart") {
          result->Success(flutter::EncodableValue(IsAutostartEnabled()));
          return;
        } else if (name == "setAutostart") {
          const auto* v = args ? std::get_if<bool>(args) : nullptr;
          if (!v || !SetAutostart(*v)) {
            result->Error("autostart", "No se pudo cambiar el inicio con Windows");
            return;
          }
        } else if (name == "setMini") {
          // Modo mini: ventana compacta siempre visible, abajo a la derecha del
          // monitor; al salir se restaura la posicion y el tamano previos.
          const auto* map =
              args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
          auto number = [map](const char* key, int fallback) {
            if (!map) return fallback;
            auto it = map->find(flutter::EncodableValue(key));
            const auto* v =
                it == map->end() ? nullptr : std::get_if<int32_t>(&it->second);
            return v ? static_cast<int>(*v) : fallback;
          };
          const bool enabled = [map] {
            if (!map) return false;
            auto it = map->find(flutter::EncodableValue("enabled"));
            const auto* b =
                it == map->end() ? nullptr : std::get_if<bool>(&it->second);
            return b && *b;
          }();
          if (enabled) {
            if (!mini_active_) {
              mini_restore_.length = sizeof(mini_restore_);
              GetWindowPlacement(host, &mini_restore_);
              mini_active_ = true;
              SetMiniMode(true);
              if (IsZoomed(host) || IsIconic(host)) ShowWindow(host, SW_RESTORE);
              UINT dpi = GetDpiForWindow(host);
              if (dpi < 96) dpi = 96;
              const int w = MulDiv(number("width", 380), dpi, 96);
              const int h = MulDiv(number("height", 150), dpi, 96);
              MONITORINFO mi{sizeof(mi)};
              GetMonitorInfoW(MonitorFromWindow(host, MONITOR_DEFAULTTONEAREST),
                              &mi);
              const int margin = MulDiv(16, dpi, 96);
              SetWindowPos(host, HWND_TOPMOST, mi.rcWork.right - w - margin,
                           mi.rcWork.bottom - h - margin, w, h, SWP_SHOWWINDOW);
            }
          } else if (mini_active_) {
            mini_active_ = false;
            SetMiniMode(false);
            SetWindowPos(host, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            SetWindowPlacement(host, &mini_restore_);
          }
        } else if (name == "setFullscreen") {
          // Pantalla completa: cubre todo el monitor (tambien la barra de
          // tareas); al salir se restaura la colocacion previa.
          const auto* map =
              args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
          const bool enabled = [map] {
            if (!map) return false;
            auto it = map->find(flutter::EncodableValue("enabled"));
            const auto* b =
                it == map->end() ? nullptr : std::get_if<bool>(&it->second);
            return b && *b;
          }();
          if (enabled && !g_fullscreen && !mini_active_) {
            fullscreen_restore_.length = sizeof(fullscreen_restore_);
            GetWindowPlacement(host, &fullscreen_restore_);
            g_fullscreen = true;
            // SW_MAXIMIZE lo limita al area de trabajo (deja la barra de tareas).
            if (IsZoomed(host)) ShowWindow(host, SW_RESTORE);
            MONITORINFO mi{sizeof(mi)};
            GetMonitorInfoW(MonitorFromWindow(host, MONITOR_DEFAULTTONEAREST),
                            &mi);
            SetWindowPos(host, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                         mi.rcMonitor.right - mi.rcMonitor.left,
                         mi.rcMonitor.bottom - mi.rcMonitor.top,
                         SWP_FRAMECHANGED | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
          } else if (!enabled && g_fullscreen) {
            g_fullscreen = false;
            SetWindowPlacement(host, &fullscreen_restore_);
          }
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      });


  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Native audio tests can keep their window hidden without stealing focus.
    wchar_t hidden[2] = {};
    if (GetEnvironmentVariableW(L"AURORA_HIDE_WINDOW", hidden, 2) != 1 ||
        hidden[0] != L'1') {
      this->ShowInitial();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  created_ = true;
  return true;
}

// Red de seguridad del actualizador: si 3 s despues el proceso sigue vivo
// (Dart colgado, audio sin soltar), lo termina.
// Hilo nativo independiente de Dart.
void FlutterWindow::ArmExitWatchdog(bool save_geometry) {
  if (watchdog_armed_) return;
  watchdog_armed_ = true;
  const NOTIFYICONDATAW tray = tray_;
  const RECT rect = normal_rect_;
  const bool maximized = SavedZoomed();
  std::thread([tray, rect, maximized, save_geometry]() {
    Sleep(3000);
    if (save_geometry) SaveGeometry(rect, maximized);
    NOTIFYICONDATAW t = tray;
    Shell_NotifyIconW(NIM_DELETE, &t);
    ReleaseInstanceMutex();
    // Ultimo recurso si ExitProcess se cuelga en un DLL.
    std::thread([]() {
      Sleep(2000);
      TerminateProcess(GetCurrentProcess(), 0);
    }).detach();
    ExitProcess(0);
  }).detach();
}

void FlutterWindow::OnDestroy() {
  // Sin ventana ya no hay a quien avisar: libera el mutex para que un nuevo
  // lanzamiento arranque limpio, y garantiza que el proceso muera aunque el
  // motor de audio se cuelgue al cerrar (antes quedaba zombi sin ventana).
  // OnDestroy tambien se llama desde Create() y el destructor: solo la primera
  // vez tras una creacion real.
  if (created_) {
    created_ = false;
    ReleaseInstanceMutex();
    ArmExitWatchdog(false);
  }
  RemoveTray();
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ShowInitial() {
  if (start_minimized_) return;  // arranque con Windows: solo bandeja
  if (has_saved_geometry_ && saved_maximized_) {
    ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
  } else {
    Show();
  }
}

void FlutterWindow::AddTray() {
  tray_ = {};
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = kTrayId;
  tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_.uCallbackMessage = kTrayMessage;
  // Icono pequeno (16 px a 100% dpi): LoadIcon devolveria el de 32 px.
  tray_.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
  wcscpy_s(tray_.szTip, L"Aurora");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
  if (!tray_added_) {
    wchar_t msg[64];
    swprintf_s(msg, L"Aurora: Shell_NotifyIcon fallo (%lu)\n", GetLastError());
    OutputDebugStringW(msg);
  }
}

void FlutterWindow::UpdateTrayTip() {
  if (!tray_added_) return;
  std::wstring tip = L"Aurora";
  if (!track_title_.empty()) {
    tip = track_title_ + (track_artist_.empty() ? L"" : L" - " + track_artist_);
  }
  tray_.uFlags = NIF_TIP;
  wcsncpy_s(tray_.szTip, tip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &tray_);
}

void FlutterWindow::RemoveTray() {
  if (!tray_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_);
  tray_added_ = false;
}

void FlutterWindow::RestoreFromTray() {
  const HWND host = GetHandle();
  ShowWindow(host, IsIconic(host) ? SW_RESTORE : SW_SHOW);
  if (!SetForegroundWindow(host)) {
    // Windows puede negar el foco: alternar TOPMOST sube la ventana igualmente.
    SetWindowPos(host, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    SetWindowPos(host, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
  }
}

// En pantalla completa la ventana no esta «maximizada» para Windows: el estado
// a guardar es el que tenia antes de entrar.
bool FlutterWindow::SavedZoomed() {
  return g_fullscreen ? fullscreen_restore_.showCmd == SW_SHOWMAXIMIZED
                      : IsZoomed(GetHandle()) != FALSE;
}

void FlutterWindow::HideToTray() {
  SaveGeometry(normal_rect_, SavedZoomed());
  ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::SendTrayAction(const char* action) {
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "trayAction", std::make_unique<flutter::EncodableValue>(action));
  }
}

void FlutterWindow::ShowTrayMenu() {
  const HWND host = GetHandle();
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  if (!track_title_.empty()) {
    const std::wstring now =
        track_title_ + (track_artist_.empty() ? L"" : L" - " + track_artist_);
    AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, now.c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  }
  AppendMenuW(menu, MF_STRING, kCmdShow, L"Mostrar Aurora");
  AppendMenuW(menu, MF_STRING, kCmdPlayPause, playing_ ? L"Pausa" : L"Reproducir");
  AppendMenuW(menu, MF_STRING, kCmdNext, L"Siguiente");
  AppendMenuW(menu, MF_STRING, kCmdPrevious, L"Anterior");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kCmdQuit, L"Salir");
  SetMenuDefaultItem(menu, kCmdShow, FALSE);

  POINT pt;
  GetCursorPos(&pt);
  // Necesario para que el menu se cierre al hacer clic fuera.
  SetForegroundWindow(host);
  const int cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x,
                                 pt.y, 0, host, nullptr);
  PostMessage(host, WM_NULL, 0, 0);
  DestroyMenu(menu);
  switch (cmd) {
    case kCmdShow: RestoreFromTray(); break;
    case kCmdPlayPause: SendTrayAction("playPause"); break;
    case kCmdNext: SendTrayAction("next"); break;
    case kCmdPrevious: SendTrayAction("previous"); break;
    case kCmdQuit:
      real_exit_ = true;
      PostMessage(host, WM_CLOSE, 0, 0);
      break;
  }
}

// Cierre definitivo: avisa a Dart (pausar audio) y solo entonces destruye la
// ventana.
void FlutterWindow::RequestClose() {
  if (close_request_pending_) return;
  const HWND hwnd = GetHandle();
  auto proceed = [this, hwnd]() {
    close_request_pending_ = false;
    KillTimer(hwnd, kCloseTimer);
    close_confirmed_ = true;
    PostMessage(hwnd, WM_CLOSE, 0, 0);
  };
  close_request_pending_ = true;
  // Un Dart que no responde no debe impedir salir.
  SetTimer(hwnd, kCloseTimer, 3000, nullptr);
  window_channel_->InvokeMethod(
      "confirmClose", std::make_unique<flutter::EncodableValue>(true),
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [this, hwnd, proceed](const flutter::EncodableValue* result) {
            const auto* accepted = result ? std::get_if<bool>(result) : nullptr;
            if (accepted && *accepted) {
              proceed();
            } else {
              close_request_pending_ = false;
              real_exit_ = false;
              KillTimer(hwnd, kCloseTimer);
            }
          },
          [proceed](const std::string&, const std::string&,
                    const flutter::EncodableValue*) { proceed(); },
          [proceed]() { proceed(); }));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Alt+F4 llega como WM_SYSKEYDOWN y luego SC_CLOSE; el menu de sistema y la
  // barra de tareas tambien usan SC_CLOSE. Todos son cierre real. El boton X
  // de Aurora envia WM_CLOSE directo y por eso puede ir a la bandeja.
  if (message == WM_SYSKEYDOWN && wparam == VK_F4) {
    real_exit_ = true;
  } else if (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_CLOSE) {
    real_exit_ = true;
  } else if (message == WM_CLOSE && !close_confirmed_) {
    if (!real_exit_ && close_to_tray_ && (tray_added_ || (AddTray(), tray_added_))) {
      HideToTray();
      return 0;
    }
    if (window_channel_) {
      RequestClose();
      return 0;
    }
  } else if (message == WM_CLOSE) {
    SaveGeometry(normal_rect_, SavedZoomed());
  } else if (message == WM_TIMER && wparam == kCloseTimer) {
    KillTimer(hwnd, kCloseTimer);
    if (close_request_pending_) {
      close_request_pending_ = false;
      close_confirmed_ = true;
      PostMessage(hwnd, WM_CLOSE, 0, 0);
    }
    return 0;
  } else if (message == kTrayMessage) {
    if (LOWORD(lparam) == WM_LBUTTONUP) {
      RestoreFromTray();
    } else if (LOWORD(lparam) == WM_RBUTTONUP) {
      ShowTrayMenu();
    }
    return 0;
  } else if (message == taskbar_created_msg_ && taskbar_created_msg_ != 0) {
    tray_added_ = false;  // el explorador se reinicio: recrear el icono
    AddTray();
    UpdateTrayTip();
  } else if (message == WM_COPYDATA) {
    // Segunda instancia: enfocar y pasar argumentos a Dart.
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (data && data->dwData == kForwardArgsMagic) {
      std::wstring args(static_cast<const wchar_t*>(data->lpData),
                        data->cbData / sizeof(wchar_t));
      while (!args.empty() && args.back() == L'\0') args.pop_back();
      if (args.find(L"--minimized") == std::wstring::npos) RestoreFromTray();
      if (!args.empty() && window_channel_) {
        window_channel_->InvokeMethod(
            "arguments", std::make_unique<flutter::EncodableValue>(
                             Utf8FromUtf16(args.c_str())));
      }
      return TRUE;
    }
  } else if (message == WM_GETMINMAXINFO) {
    FillMinMaxInfo(hwnd, reinterpret_cast<MINMAXINFO*>(lparam));
    return 0;
  } else if (message == WM_ERASEBKGND) {
    RECT area;
    GetClientRect(hwnd, &area);
    FillRect(reinterpret_cast<HDC>(wparam), &area,
             reinterpret_cast<HBRUSH>(GetClassLongPtr(hwnd, GCLP_HBRBACKGROUND)));
    return 1;
  } else if (message == WM_NCACTIVATE) {
    // Activar (un simple clic) no debe repintar el marco: lParam = -1 lo evita.
    return DefWindowProc(hwnd, message, wparam, -1);
  } else if (message == WM_NCPAINT) {
    return 0;  // no hay marco no cliente que pintar
  } else if (message == WM_NCHITTEST && !IsZoomed(hwnd) && !g_fullscreen) {
    const LRESULT hit = DefWindowProc(hwnd, message, wparam, lparam);
    return hit != HTCLIENT ? hit : EdgeHit(hwnd, lparam);
  } else if (message == WM_NCCALCSIZE && wparam) {
    // El cliente ocupa toda la ventana: sin marco nativo no hay franja blanca
    // (ni arriba ni a los lados) que DWM pinte al activar o redimensionar.
    return 0;
  } else if ((message == WM_MOVE || message == WM_SIZE) && IsWindowVisible(hwnd) &&
             !IsZoomed(hwnd) && !IsIconic(hwnd) && !mini_active_ &&
             !g_fullscreen) {
    GetWindowRect(hwnd, &normal_rect_);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
