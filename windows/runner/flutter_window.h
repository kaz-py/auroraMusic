#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  bool close_request_pending_ = false;
  bool close_confirmed_ = false;
  bool watchdog_armed_ = false;
  bool created_ = false;
  // Cierre real (Alt+F4, menu del sistema, «Salir» de la bandeja): ignora la
  // preferencia de bandeja. Solo el boton X de Aurora puede ocultar a la bandeja.
  bool real_exit_ = false;
  bool close_to_tray_ = true;
  bool playing_ = false;
  bool start_minimized_ = false;
  std::wstring track_title_, track_artist_;
  NOTIFYICONDATAW tray_ = {};
  bool tray_added_ = false;
  UINT taskbar_created_msg_ = 0;
  RECT normal_rect_ = {};
  bool saved_maximized_ = false;
  bool has_saved_geometry_ = false;
  // Modo mini (ventana compacta): guarda la colocacion para restaurarla.
  bool mini_active_ = false;
  WINDOWPLACEMENT mini_restore_ = {};
  // Pantalla completa: colocacion previa para restaurarla al salir.
  WINDOWPLACEMENT fullscreen_restore_ = {};

  // Estado maximizado a guardar (el previo a la pantalla completa, si esta).
  bool SavedZoomed();

  void AddTray();
  void UpdateTrayTip();
  void RemoveTray();
  void ShowTrayMenu();
  void RestoreFromTray();
  void HideToTray();
  void RequestClose();
  void ArmExitWatchdog(bool save_geometry = true);
  void SendTrayAction(const char* action);
  void ShowInitial();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
