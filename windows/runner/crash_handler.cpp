#include "crash_handler.h"

// clang-format off
#include <windows.h>
#include <dbghelp.h>
// clang-format on
#include <shlobj.h>

#include <csignal>
#include <cstdio>
#include <cwchar>

namespace {

// Misma carpeta que getApplicationSupportDirectory() + "logs" en Dart:
// CompanyName y ProductName de Runner.rc.
wchar_t g_logs[MAX_PATH];
EXCEPTION_POINTERS* g_exception = nullptr;
DWORD g_thread_id = 0;
LONG g_reported = 0;
LPTOP_LEVEL_EXCEPTION_FILTER g_previous = nullptr;

const char* ExceptionName(DWORD code) {
  switch (code) {
    case EXCEPTION_ACCESS_VIOLATION:
      return "acceso a memoria no válido";
    case EXCEPTION_STACK_OVERFLOW:
      return "desbordamiento de pila";
    case EXCEPTION_ILLEGAL_INSTRUCTION:
      return "instrucción no válida";
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
      return "división entre cero";
    case EXCEPTION_IN_PAGE_ERROR:
      return "error de página";
    case 0xC0000374:
      return "montón dañado";
    case 0xC0000409:
      return "desbordamiento de búfer de pila";
    case 0xE06D7363:
      return "excepción de C++ sin capturar";
    default:
      return "desconocida";
  }
}

void WriteFileUtf8(const wchar_t* path, const char* text, int length) {
  HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, text, static_cast<DWORD>(length), &written, nullptr);
  CloseHandle(file);
}

DWORD WINAPI WriteReport(LPVOID) {
  SHCreateDirectoryExW(nullptr, g_logs, nullptr);
  SYSTEMTIME t;
  GetSystemTime(&t);
  wchar_t path[MAX_PATH];
  const int base = swprintf_s(path, L"%s\\native-%04u%02u%02u-%02u%02u%02u",
                              g_logs, t.wYear, t.wMonth, t.wDay, t.wHour,
                              t.wMinute, t.wSecond);
  if (base < 0) return 0;

  char text[2048];
  int length = snprintf(text, sizeof text,
                        "[%04u-%02u-%02uT%02u:%02u:%02uZ] Aurora %s se cerró "
                        "en el hilo %lu\r\n",
                        t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute,
                        t.wSecond, FLUTTER_VERSION, g_thread_id);
  if (g_exception != nullptr) {
    const EXCEPTION_RECORD* record = g_exception->ExceptionRecord;
    HMODULE module = nullptr;
    wchar_t module_path[MAX_PATH] = L"?";
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           static_cast<LPCWSTR>(record->ExceptionAddress),
                           &module)) {
      GetModuleFileNameW(module, module_path, MAX_PATH);
    }
    char module_utf8[MAX_PATH * 3];
    WideCharToMultiByte(CP_UTF8, 0, module_path, -1, module_utf8,
                        sizeof module_utf8, nullptr, nullptr);
    length += snprintf(
        text + length, sizeof text - length,
        "Excepción 0x%08lX (%s) en %p\r\nMódulo: %s +0x%llX\r\n",
        record->ExceptionCode, ExceptionName(record->ExceptionCode),
        record->ExceptionAddress, module_utf8,
        static_cast<unsigned long long>(
            static_cast<const char*>(record->ExceptionAddress) -
            reinterpret_cast<const char*>(module)));
    if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
        record->NumberParameters >= 2) {
      length += snprintf(text + length, sizeof text - length,
                         "Al %s la dirección 0x%llX\r\n",
                         record->ExceptionInformation[0] == 0   ? "leer"
                         : record->ExceptionInformation[0] == 8 ? "ejecutar"
                                                                : "escribir",
                         static_cast<unsigned long long>(
                             record->ExceptionInformation[1]));
    }
  } else {
    length += snprintf(text + length, sizeof text - length,
                       "Llamada a abort() (fallo interno de una biblioteca)\r\n");
  }
  if (length > 0) {
    wcscpy_s(path + base, MAX_PATH - base, L".txt");
    WriteFileUtf8(path, text, length);
  }

  wcscpy_s(path + base, MAX_PATH - base, L".dmp");
  HANDLE dump = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (dump != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION info{g_thread_id, g_exception, FALSE};
    MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), dump,
                      MiniDumpWithThreadInfo,
                      g_exception != nullptr ? &info : nullptr, nullptr,
                      nullptr);
    CloseHandle(dump);
  }
  return 0;
}

void Report(EXCEPTION_POINTERS* exception) {
  if (InterlockedExchange(&g_reported, 1) != 0) return;  // Solo el primero.
  g_exception = exception;
  g_thread_id = GetCurrentThreadId();
  // Hilo aparte: el que falla puede haberse quedado sin pila.
  HANDLE worker = CreateThread(nullptr, 0, WriteReport, nullptr, 0, nullptr);
  if (worker != nullptr) {
    WaitForSingleObject(worker, 30000);
    CloseHandle(worker);
  }
}

LONG WINAPI OnException(EXCEPTION_POINTERS* exception) {
  Report(exception);
  // Sigue hacia Windows: el cierre también queda en el Visor de eventos.
  return g_previous != nullptr ? g_previous(exception)
                               : EXCEPTION_CONTINUE_SEARCH;
}

void OnAbort(int) { Report(nullptr); }

}  // namespace

void InstallCrashHandler() {
  PWSTR roaming = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                  &roaming))) {
    return;
  }
  const int written =
      swprintf_s(g_logs, L"%s\\com.aurora\\Aurora\\logs", roaming);
  CoTaskMemFree(roaming);
  if (written < 0) return;
  g_previous = SetUnhandledExceptionFilter(OnException);
  signal(SIGABRT, OnAbort);
}
