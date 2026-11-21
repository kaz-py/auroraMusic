# Handoff: RAM de Aurora en Linux (WSL) — 2026-11-20

Este archivo es para retomar el trabajo. No se incluye en el commit.

## Objetivo
En Linux (WSL), Aurora marca unos 0,5 GB de RSS (medido dentro de Ubuntu); en Windows 11, unos 112 MB en el Administrador de tareas. Hay que verificar la causa, corregirla y medir el resultado.

Plan aprobado: `C:/Users/pc1/.claude/plans/quizzical-doodling-walrus.md`.

## Dónde se trabaja
- Worktree `C:/Users/pc1/orca/projects/reproductor-flutter-1.5.2`, rama `rust-migration` (HEAD 03c649e, 1.6.0-beta.10+29).
- El worktree incluye trabajo sin confirmar anterior («fix clientes Windows»): `stream_orchestrator`, `upstream_network`, `yt_dlp_source`, `audio_proxy`, `innertube_source`, `lib/main.dart`, `verify_playback.sh`, `verify_stream_chain.dart`, etc. **No se toca y no se incluye en el commit.**
- `C:/Users/pc1/Desktop/Aurora-1.6.0-beta.10-fix-clientes-windows` es una copia de la build de Windows de ese árbol (mismo md5 de `app.so` y de la dll de Rust).
- La carpeta antigua `reproductor-flutter` (rama `rust-migration-1.4.0`) no se usa.

## Decisiones del usuario
- Haiku para investigar, leer archivos, compilar y lanzar. El agente principal se encarga de los tests. Sin escritorio remoto.
- Al terminar:
  - Commit local en `rust-migration`, sin push, **solo con los archivos de esta tarea**.
  - Mensaje corto en imperativo, sin atribución (lo dice CLAUDE.md).
- Al terminar, **dejar la build de Windows compilada en el Escritorio**, en una carpeta nueva (no sobrescribir `fix-clientes-windows`). Además, el bundle de Linux en `C:/Users/pc1/Desktop/Aurora-1.6.0-beta.10-ram-linux`.

## Hecho
Archivos de esta tarea (los únicos que van al commit):
- `linux/runner/main.cc`: `mallopt(M_ARENA_MAX, 2)` antes de `g_application_run` (con guarda `__GLIBC__`; respeta `MALLOC_ARENA_MAX` si el usuario lo define).
- `lib/core/linux_memory.dart` (`LinuxMemoryTuning`), que solo actúa en Linux:
  - Llama a `malloc_trim(0)` por FFI al pasar a inactive/hidden/paused (con espera de 2 s y antirrebote) y cada 2 min cuando no hay animaciones (tarea `Priority.idle`), con al menos 20 s entre recortes.
  - Fija el techo de la caché de Skia con `Skia.setResourceCacheMaxBytes` en 48 MB.
- `lib/ui/aurora_shell.dart`: el campo `_memory`, `start()` en initState, el aviso en `didChangeAppLifecycleState` y `dispose()`.
- `test/linux_memory_test.dart`: 10 tests; el de FFI real solo corre en Linux.
- `scripts/linux/measure_memory.sh [pid|auto] [segundos]`: smaps_rollup, categorías y top de mapeos, y driver de GL.
- `scripts/windows/measure_memory.ps1 [-ProcessId] [-Seconds]`: lleva BOM UTF-8, porque PowerShell 5.1 lo necesita.

Comprobaciones en Windows:
- `dart format`: correcto.
- `flutter analyze` de los archivos tocados: sin incidencias.
- `flutter test` completo: **1681 correctos, 5 omitidos, 0 fallos**.

## Mediciones (app en reposo con el perfil normal, o uso con 8 cambios de canción vía API remota)
Linux = WSL, Ubuntu 24.04, ventana de 1280×720. «Sucia» = Private_Dirty, la cifra comparable con el working set privado de Windows.

| Escenario | RSS | Privada sucia |
|---|---|---|
| Base, reposo 60 s | 323,7 | 180,7 |
| Base, reposo 300 s | 324,9 | 182,0 |
| Base + `MALLOC_ARENA_MAX=2`, 300 s | 309,9 | 166,6 |
| Base + `LIBGL_ALWAYS_SOFTWARE=1`, 300 s | 296,2 | 159,4 |
| Base + `GDK_BACKEND=x11`, 300 s | 297,6 | 163,8 |
| **Corregida, reposo 60 s** | 304,8 | 162,7 |
| **Corregida, reposo 300 s** | **293,6** | **151,6** |
| Base, uso: inicio → reproduciendo → pausa 60 s | 310,5 → 374,3 → 374,8 | 166,8 → 226,9 → 227,5 |
| **Corregida, uso: inicio → reproduciendo → pausa 60 s** | 308,2 → **344,7** → **343,3** | 165,4 → **198,3** → **196,7** |
| Corregida + `GALLIUM_DRIVER=d3d12`, reposo 60 s | 297,5 | **129,4** |
| Windows (build del Escritorio), 60 s / 331 s | WS 157,4 / 159,1 | privado 93,8 / 95,1 (comprometido 212,6 / 243,2) |

Resultados ya leídos: `fix-uso-pausa` y `fix-d3d12`.

En pausa, la build corregida baja 31 MiB respecto a la base (374,8 → 343,3 de RSS y 227,5 → 196,7 de sucia). En ese momento el `[heap]` está en 102,7 MiB: al pasar a pausa no hay cambio de ciclo de vida, así que el siguiente recorte llega con el temporizador de 2 min.

Con `GALLIUM_DRIVER=d3d12`:
- Se cargan `libd3d12.so` y `libd3d12core.so`, y en el log solo hay avisos (`MESA-LOADER: failed to retrieve device information`, `failed to get driver name for fd -1`, libsecret y ALSA). No hay errores fatales.
- La memoria privada sucia baja de 162,7 a 129,4 MiB (−33 MiB), el `[heap]` de 60 a 57 MiB y los hilos de 69 a 47.
- `libLLVM` sigue mapeada porque libgallium la enlaza siempre.
- **`/dev/dxg` no aparece en el mapa de memoria**: no está confirmado que la GPU se use de verdad. Comprobarlo, por ejemplo con `MESA_DEBUG=1`/`EGL_LOG_LEVEL=debug`, o fijándose en el uso de CPU con el espectro animado.
- Falta confirmar que la ventana se pinta bien. Sin escritorio remoto, se puede comprobar con la CPU mientras suena, que en llvmpipe era del 228 %.

## Diagnóstico
- **En este WSL, Mesa usa llvmpipe (renderizado por software).** d3d12 y zink fallan (`ZINK: failed to choose pdev`, `failed to create dri2 screen`) y Mesa se queda en llvmpipe.
  - Se cargan `libLLVM.so.20.1` (60 MiB) y `libgallium` (12 MiB), que cuentan en el RSS.
  - Las texturas de Skia están en la RAM del proceso; en Windows están en la VRAM.
  - Con la música sonando, la CPU llegó a un 228 % de media en la sesión anterior: es el software renderizando el espectro y el vinilo.
- Las arenas de glibc retienen memoria liberada: ahorro de unos 15 MiB con `MALLOC_ARENA_MAX=2`. `malloc_trim` devuelve otros unos 11 MiB en reposo.
- Los intentos fallidos de Vulkan/zink cuestan unos 29 MiB: es lo que ahorra `LIBGL_ALWAYS_SOFTWARE=1`.
- El código de Dart y de Rust no reserva más en Linux que en Windows: mismo motor `RustMusicAudio`, caché de imágenes de 32 MB y cachés con límite.
- El RSS de Linux equivale al working set de Windows (159 MiB), no a los 112 MB del Administrador de tareas (working set privado).
- Los 0,5 GB salen del uso prolongado (portadas y vinilo con texturas en RAM por llvmpipe), sobre una base de unos 325 MiB.

## Pendiente (en orden)
1. d3d12 da buen resultado en reposo (ver arriba). Falta medirlo a 300 s y con uso (`run.sh uso` admite variables si se le añaden; hoy solo admite `HOME`) y comprobar la CPU mientras suena. Si se confirma, proponer al usuario fijarlo en `main.cc` **solo en WSL**: si existe `/dev/dxg` y no están definidos `GALLIUM_DRIVER` ni `LIBGL_ALWAYS_SOFTWARE`, hacer `setenv("GALLIUM_DRIVER","d3d12",0)` antes de GTK. Medir de nuevo el reposo y el uso.
2. Techo de Skia: 48 MB no recorta nada a 1280×720 (el motor da unos 44 MB); solo actúa con la ventana maximizada o en pantallas grandes. Valorar bajarlo a 32 MB y medir el uso de nuevo.
3. Tests en Linux (los hace el agente principal): en WSL, `cd ~/aurora-verify && ~/flutter/bin/flutter test test/linux_memory_test.dart`. Antes, volver a sincronizar si cambió algo. `flutter_test_config.dart` carga `RustLib` (`rust/target` existe en la copia).
4. `docs/LINUX.md`: sección «Memoria», con cómo medir (sucia frente a RSS, los scripts nuevos), la nota sobre llvmpipe/WSLg y la tabla de antes y después.
5. Build de Windows release con los cambios (`$env:PATH = "$PWD/build/build-tools/nuget;$env:PATH"; flutter build windows --release` con los dart-define de siempre: mirar `scripts/make_dart_defines.ps1`). Copiar `build/windows/x64/runner/Release` al Escritorio en una carpeta nueva, p. ej. `Aurora-1.6.0-beta.10-ram-windows`.
6. Copiar el bundle de Linux de `~/aurora-verify/build/linux/x64/release/bundle` a `C:/Users/pc1/Desktop/Aurora-1.6.0-beta.10-ram-linux`.
7. Commit solo de los archivos listados en «Hecho» y de `docs/LINUX.md`, con `git add <rutas>`. Este HANDOFF no se incluye.
8. Informe al usuario: la tabla en igualdad de condiciones con Windows y qué parte es propia de WSL.

## Cómo medir (trucos aprendidos)
- WSL desde Git Bash: `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -e bash -lc '...'`. Usa `-e`, no `--`: con `--` se expanden los `$`.
- Flutter de Linux: `~/flutter/bin/flutter` (3.38.8). **No** el de `/mnt/c`. Cargo está en `~/.cargo/bin`.
- Copia de compilación: `~/aurora-verify`. Se sincroniza con rsync desde el worktree, excluyendo `.git .claude .agents diseñoidea android windows ios macos graphify-out build .dart_tool rust/target linux/flutter/ephemeral`. **Después hay que quitar los CRLF** de `*.sh` en la copia (`sed -i 's/\r$//'`); si no, cargokit falla con `bash\r`.
- Compilar: `~/flutter/bin/flutter build linux --release --dart-define-from-file=$HOME/aurora-defines.json`. Ese archivo tiene claves: no imprimirlo.
- Script de mediciones: `~/aurora-ram/run.sh`.
  - `run.sh idle <nombre> "<VARS>" largo|corto`: reposo, a 60 s y 300 s.
  - `run.sh uso <nombre> <bundle>`: copia `~/aurora-verify-home` (no se modifica) en `~/aurora-ram-home`, abre la app con ese HOME, usa la API remota del puerto y el token de `remote_control.json` (`play`, 8× `next` cada 25 s, `pause`) y mide al inicio, reproduciendo y en pausa.
  - Ejecutarlo con el REPL esperando (`await`), con `timeout` alto. Una cadena larga en un agente Haiku se colgó (watchdog de 600 s).
- Resultados en `~/aurora-ram/*.txt` y `*.log`. La build de base está en `~/aurora-ram/bundle-base`. Las mediciones de Windows están en el scratchpad de la sesión (`…/scratchpad/ram/win-*.txt`); las cifras ya están en la tabla de arriba.
