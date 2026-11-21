#ifndef RUNNER_CRASH_HANDLER_H_
#define RUNNER_CRASH_HANDLER_H_

// Cierres nativos (fallo de memoria, desbordamiento de pila, abort()) en
// %APPDATA%\com.aurora\Aurora\logs: native-AAAAMMDD-HHMMSS.txt con el código y
// el módulo culpable, y .dmp (minivolcado) para depurarlo.
void InstallCrashHandler();

#endif  // RUNNER_CRASH_HANDLER_H_
