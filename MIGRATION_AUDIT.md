# Auditoría de migración a Flutter + Rust

Base de la migración: **1.5.2+19** (rama `integracion-1.5.0`, commit `bf3af15`); `rust-migration` parte de ahí. Las fases 1 y 2a se hicieron primero sobre 1.4.0 (`rust-migration-1.4.0`, conservada) y se portaron a 1.5.2: el único conflicto fue `lib/dj/ai_dj.dart`, donde 1.5.x añadió la puerta de coherencia del DJ. Las cifras de líneas de código y las medidas de §8 son de 1.4.0, salvo las marcadas «1.5.2». Todo lo siguiente sale de leer el código; lo que no existe se marca **NO ENCONTRADO**.

## 1. Arquitectura actual

Aplicación Flutter/Dart (Windows x64, Android ARM64, Linux x64). Sin Rust, sin FFI propio salvo `lib/core/duvet_presence.dart` (kernel32 por `package:ffi`).

| Capa | Ubicación | Notas |
|---|---|---|
| Interfaz | `lib/ui/**` (temas Modern, Atelier, Brasa, Slush) | Riverpod 3 + `ChangeNotifier` |
| Coordinador | `lib/app_controller.dart` (4042 líneas) | cola, reproducción, DJ, descargas, Spotify, Jam, ajustes |
| Modelos/contratos | `lib/core/` (`models.dart` 148, `audio_backend.dart` 41, `queue_policy.dart`) | `Track`, `MusicPlaylist`, `DownloadJob`, `ResolvedAudio` |
| Audio | `lib/audio/`, `lib/audio_web/` | `RoutedMusicAudio` elige motor por `ResolvedAudio.engine` |
| Fuentes | `lib/sources/`, `lib/lyrics/`, `lib/metadata/`, `lib/import/` | InnerTube, proxy local, yt-dlp, LRCLIB, Spotify |
| Datos | `lib/library/library_database.dart` (314 líneas antes de la fase 1) | SQLite vía drift (solo SQL crudo); ahora fachada sobre `rust/crates/aurora_database` |
| Cuentas/red | `lib/account/`, `lib/friends/`, `lib/follow/`, `lib/lastfm/`, `lib/jam/` | Supabase (Dart puro), Last.fm |
| Plataforma | Android: `android/app/src/main/kotlin/.../{MainActivity,AuroraPlaybackService,AuroraAudioPlugin,AuroraYtDlpUpdater,AuroraApkInstaller}.kt`; Windows: `windows/runner/*.cpp`; Linux: `linux/runner` (plantilla) | |

Motores de audio (`lib/main.dart:111-113`): Android `AndroidMusicAudio` → Media3/ExoPlayer en `AuroraPlaybackService` (canal `aurora/audio`); Windows/Linux `MusicAudio` → `flutter_soloud` 3.5.4 parcheado + proceso `ffmpeg` que escupe PCM f32le 48 kHz por `pipe:1`; respaldo `WebMusicAudio` (WebView oculto, solo Windows).

## 2. Funcionalidades existentes (verificadas en código)

- Búsqueda InnerTube (`WEB_REMIX`), resolución de audio por `player` (cliente único `VISIONOS`), proxy loopback con trozos de 4 MiB, 6 descargas upstream, caché LRU de 50 streams, lista negra por vídeo 30 min, cliente malo 10/2 min.
- yt-dlp/ffmpeg/ffprobe/deno solo para descargas explícitas, importación de listas y (Windows/Linux) resolución de respaldo. Cookies Netscape opcionales.
- Cola persistente en SharedPreferences (`queue`, `queueIndex`, `position`); restaura en pausa.
- Ecualizador de 8 bandas (biquad RBJ) y espectro FFT de 48 barras en escritorio.
- DJ local: embeddings por hashing (256 dims), perfil de gustos con decaimiento (14 días), ranking MMR, modos, coherencia de artista, memoria anti-repetición, fuentes de candidatos InnerTube/Spotify/Last.fm.
- Jam: servidor WebSocket LAN (en `jam_service.dart`) y transporte Supabase (`transport/`), QR (`zxing2` + `mobile_scanner`), sincronía de reproducción por deriva de reloj.
- Descargas MP3 secuenciales (concurrencia 1), sin reanudación; interrumpidas pasan a «fallida».
- Cuentas Supabase con sincronización LWW de me gusta/listas/historial/gustos; amigos; seguidos y novedades; Last.fm (scrobbling, estadísticas, candidatos DJ); Discord y Duvet; actualizador por GitHub Releases; letras LRCLIB→lyrics.ovh; metadatos Spotify por web-player anónimo.

**No existen** (búsqueda por `grep` sin resultados en `lib/`, `android/app/src`, `windows/runner`): crossfade, reproducción sin huecos (*gapless*), análisis de audio (BPM/tonalidad), transiciones inteligentes (solo `djTransitionComment`, texto de plantilla, y una heurística de «energía» por palabras clave), Cloudinary, ListenBrainz (solo limpieza de datos heredados en `lastfm_storage.dart:83-94`), SQLx, MPRIS/D-Bus, canal `aurora/pcm` (rama muerta en `music_audio.dart`). Decisión del usuario: `aurora_sync` integra **Last.fm** y **Supabase**; Cloudinary queda fuera (los avatares ya usan el bucket `avatars` de Supabase). Crossfade y transiciones no se implementan: no existen y no se inventan.

## 3. Dependencias

Directas (`pubspec.yaml`): `flutter_riverpod`, `drift` (solo como envoltorio de SQLite), `path_provider`, `path`, `ffi`, `file_picker`, `flutter_soloud` (parche local en `scripts/patch_flutter_soloud.cmake` y `android/build.gradle.kts`), `audio_service`, `audio_session`, `audio_service_win`, `shared_preferences`, `crypto`, `package_info_plus`, `zxing2`, `mobile_scanner`, `flutter_inappwebview`, `url_launcher`, `adblocker_webview`, `supabase`, `flutter_secure_storage`. Nativas: Media3 1.11.1, `youtubedl-android` 0.18.1 (Python, yt-dlp, ffmpeg), WebView2 en Windows.

Binarios fijados: yt-dlp nightly 2026.10.10.233141, deno 2.9.7, ffmpeg autobuild-2026-10-09 (`scripts/windows_tools.lock.json`, `scripts/android_ytdlp.lock.json`).

Redundancia: ninguna dependencia directa está sin uso. Candidatas débiles: `url_launcher` (un import) y `adblocker_webview` (solo motor WebView). `drift` se retiró en la fase 1 (arrastraba `sqlite3` como activo nativo). `mobile_scanner` (cámara) y `zxing2` (generar/decodificar) no se solapan.

## 4. Componentes migrables a Rust

| Componente | Archivos | Fase |
|---|---|---|
| Base SQLite, migraciones v1→v4, vectores, sync_meta, seguidos | `library_database.dart`, `sync_store.dart`, `follow_repository.dart` | **1 (hecha)** |
| Embeddings, perfil de gustos, ranking MMR | `lib/dj/ai_dj.dart` | **1 (hecha)** |
| Poda LRU de directorios | `artwork_cache.dart`, `lyrics_service.dart` | **1 (hecha)** |
| `ParametricEqualizer`, `spectrumBars`, `isCompleteAudioStream` | `eq_dsp.dart`, `audio_math.dart` | **2a (hecha)** |
| Bomba PCM de escritorio (SoLoud + ffmpeg → Symphonia + CPAL) | `music_audio.dart` | 2b (pendiente) |
| Analizadores de respuestas de InnerTube (`parseSearchPage`, `parseRelated`, `parseArtistPage`, `parseBrowseTracks`) | `innertube_source.dart` | **3.1 (hecha)** |
| `stream_guard`, política de peticiones, `StreamOrchestrator`, `AudioProxy`, cliente InnerTube con red | `lib/sources/**`, `lib/audio/stream_guard.dart` | 3.2+ (pendiente) |
| Letras (LRCLIB), Spotify (auth TOTP, GraphQL persistido, importación CSV/JSON) | `lib/lyrics/`, `lib/metadata/spotify/`, `lib/import/` | 3 |
| Ejecutor de yt-dlp/ffmpeg/ffprobe (argumentos, límites, actualizador de escritorio) | `yt_dlp_source.dart`, `ytdlp_updater.dart` | 4 |
| Caché de audio de reproducción (info, vaciado, poda con reserva) | `yt_dlp_source.dart` | **4.1 (hecha)** |
| Cola de descargas (añadir reanudación y verificación) | `app_controller.dart:3315-3625` | 4 (pendiente) |
| Jam: máquina de estados de comandos, servidor WS LAN, codec de invitaciones, matemática de deriva | `jam_service.dart`, `jam_models.dart`, `jam_playback_bridge.dart` (solo cálculo) | 5 |
| Motor de sincronización LWW, Last.fm (firma md5, scrobbler) | `sync_store.dart`, `sync_service.dart`, `lib/lastfm/` | 6 |
| Máquina de estados de cola/reproducción | `app_controller.dart:1888-2682` | 7 (tras 2 y 3) |
| Presencia Discord/Duvet (pipes/sockets), descarga y verificación del actualizador | `lib/discord/`, `duvet_presence.dart`, `lib/updater/` | 8 |

## 5. Componentes que permanecen en Flutter/plataforma

- Toda la UI, Riverpod, `ChangeNotifier`.
- Android: `AuroraPlaybackService` (sesión Media3, notificación, foco de audio, `WAKE_MODE_NETWORK`, ecualizador `audiofx`), `MainActivity`, `youtubedl-android`. Rust no puede sustituir la sesión de medios del sistema.
- Windows SMTC (`audio_service_win`), `audio_session`, canal `aurora/updater`, `hard_exit`.
- Motor WebView (`flutter_inappwebview`, `adblocker_webview`): único respaldo cuando YouTube bloquea.
- Cámara QR (`mobile_scanner`), selector de archivos, `flutter_secure_storage`, SharedPreferences.
- Supabase Auth/Realtime/Storage: no hay SDK de Rust oficial; Realtime v2 (canales privados, presencia) habría que construirlo. Se mantiene en Dart; el motor LWW sí puede ir a Rust tras `SyncRemote`.

## 6. Riesgos técnicos

1. **Pruebas bajo `FakeAsync`**: las pruebas de widgets esperan futuros que no dependen de puertos reales. Las funciones de FRB asíncronas usan hilos y `ReceivePort`; colgarían. Por eso la base, el DJ y la caché usan funciones **síncronas** de FRB (`#[frb(sync)]`) tras envoltorios Dart con firma `Future`.
2. **Paridad numérica**: Dart usa `Float32List` con acumulación en `double` y orden de inserción de mapas; el hash FNV opera sobre unidades UTF-16; `toLowerCase` de Dart no aplica sigma final; `\b` de Dart (sin `unicode`) es ASCII. Rust debe imitarlo (ver plan de la fase 1).
3. **Hilo de UI**: las funciones síncronas bloquean el hilo de Dart. Se mide `readTracks` (10 000 pistas) y `nearestTracks` (5000×256).
4. **Android**: `ndkVersion = flutter.ndkVersion` sin fijar; CI instala `ndk;28.2.13676358`. `rusqlite` con `bundled` compila C con el NDK (compila: ver §9). Los pasos de CI que compilan Rust antes de `flutter test` están añadidos pero no se han ejecutado en GitHub Actions.
5. **Reglas de YouTube** (CLAUDE.md): ninguna URL de YouTube/googlevideo llega a FFmpeg/Media3 sin el proxy; prohibidos tokens PO, descifrado de firmas y copiar código GPL (LIMusic). El puerto de la fase 3 debe conservarlas y sus pruebas.
6. **Spotify**: hashes GraphQL y diccionario de secretos no oficiales; código adaptado de Nuclear (AGPL-3.0): el puerto hereda la licencia y los avisos.
7. **Esquema**: `PRAGMA user_version` lo escribe drift (4); Rust debe respetarlo y reproducir los 4 pasos. Sin WAL hoy; no se cambia.
8. **1.5.x ya integrada**: `ArtistGraph`/coherencia en `lib/dj/*` y `AudioQuality` en `stream_orchestrator.dart` forman parte de la base. La puerta de coherencia (`coherence.dart`) sigue en Dart hasta la fase 7: `rankDjCandidates` deduplica, puntúa y filtra en Dart y pasa a Rust solo los candidatos admitidos con su bono de coherencia (`coherence_bonus`).
9. **Documentación desfasada**: `docs/architecture.md` dice esquema 1, `docs/dj.md` esquema 2 (real: 4); `CONTINUAR.md` apunta a la rama 1.2.3.

## 7. Plan de migración

Cada fase mantiene la aplicación funcional y sus pruebas en verde; Dart conserva las firmas públicas (envoltorios finos) hasta que el llamador pueda migrar.

- **Fase 1 (hecha, ver §9)**: workspace `rust/`, `flutter_rust_bridge` 2.13.0 (Cargokit), `aurora_database`, `aurora_ai_dj`, `aurora_cache`; retirada de `drift`.
- **Fase 2 – `aurora_audio`**: **2a (hecha, ver §9)**: EQ paramétrico, barras de espectro y regla de fin de flujo en Rust. **2b (pendiente)**: bomba PCM de escritorio con Symphonia + CPAL en lugar de SoLoud + ffmpeg (elimina el parche `patch_flutter_soloud.cmake`); exige validar audio real (salida, *seek*, búfer, volumen, FFT del mezclador) con `audio_soak_runner` y `audio_smoke_test` en un equipo con dispositivo de audio. Android sigue en Media3.
- **Fase 3 – `aurora_sources`**: orden: `stream_guard` → política de peticiones → orquestador → proxy → InnerTube. Deben pasar las suites `stream_orchestrator_test`, `audio_proxy_test`, `innertube_source_test`, `youtube_request_policy_test`.
- **Fase 4 – `aurora_download` + `aurora_cache` ampliado**: ejecutor de herramientas externas, reanudación, verificación ffprobe, caché de audio 512 MiB con la validación de nombre/enlaces simbólicos actual.
- **Fase 5 – `aurora_jam`**: servidor WS LAN (`tokio-tungstenite`), límites actuales (16 identidades, 200 canciones, 10 comandos/5 s); suites `jam_*_test` como especificación.
- **Fase 6 – `aurora_sync`**: LWW y Last.fm; Supabase por HTTP/PostgREST solo si compensa.
- **Fase 7 – `aurora_core`**: cola y reproducción; solo cuando 2 y 3 estén estables.
- **Fase 8 – `aurora_platform`**: Discord/Duvet, actualizador.

Crates que no se crean en la fase 1 (`aurora_core`, `aurora_audio`, `aurora_sources`, `aurora_download`, `aurora_jam`, `aurora_sync`, `aurora_platform`): no tienen aún código real; se añaden con su fase.

## 8. Métricas

«Antes» = Windows x64, Flutter 3.38.8, rama `rust-migration` recién creada, sin tocar código. «Después» = misma máquina con la fase 1 aplicada. Una sola ejecución por celda: son órdenes de magnitud, no benchmarks.

| Métrica | Antes | Después |
|---|---|---|
| Líneas `lib/**/*.dart` (sin `lib/bridge`, generado) | 59 528 | 59 144 |
| `flutter test`: pasan / omitidas / fallan | 996 / 2 / 1 ² | 997 / 2 / 0 |
| `flutter test`: tiempo total | 58 s y 86 s (dos ejecuciones) | 61 s y 71 s (dos ejecuciones) |
| `flutter test test/database_test.dart` | 2,7 s (con caché caliente) | 2,8 s |
| `flutter analyze` | sin problemas (87 s en frío) | sin problemas |
| Tamaño de `build/windows/x64/runner/Release` | no medido ³ | no medido ³ |
| RSS soak 2 min (inicio / máximo / crecimiento) | no medido ³ | no medido ³ |
| APK debug arm64 (`flutter build apk --debug --target-platform android-arm64`) | no medido | 131,2 MiB; incluye `lib/arm64-v8a/librust_lib_aurora_music.so` (7,1 MiB, debug) |
| `rust_lib_aurora_music.dll` (`cargo build --release`, Windows x64) | — | 4,05 MiB |
| `read_tracks`, 10 000 pistas (release, Rust, ejecución sin Dart) | — | 3,4 ms |
| `nearest_tracks`, 5000×256 vectores, k=20 (release, Rust) | — | 2,8 ms |
| Pruebas Rust (`cargo test --workspace`) | — | 45 pasan, 3 ignoradas (2 benchmarks + `open_user_copy`) |
| EQ de 8 bandas activas, 12,3 s de audio estéreo en trozos de 64 KiB (incluye copias FFI) | Dart: 87 ms ⁴ | Rust: 19 ms ⁴ |

¹ `lib/bridge/**` (generado por `flutter_rust_bridge_codegen`, 5 935 líneas) no cuenta: se excluye del análisis.
² El fallo previo es `test/audio_proxy_test.dart: client leaving during a pending flush raises no uncaught error` (sockets abiertos al final). Falló en las dos ejecuciones previas a la migración y pasó en la posterior; no toca ningún código de esta fase (parece dependiente de sockets/temporización).
³ `flutter build windows` aborta en esta máquina con «Building with plugins requires symlink support» (el Modo de desarrollador de Windows está desactivado y la sesión no es administrador). Sin esa compilación no hay carpeta `Release`, no hay `soak_before/after.jsonl` ni se puede arrancar el ejecutable. No se cambió el ajuste del sistema. Para medirlo: activar el Modo de desarrollador y repetir `flutter build windows --release -t integration_test/audio_soak_runner.dart --dart-define=AURORA_SOAK_MINUTES=2 --dart-define=AURORA_SOAK_LOG=<ruta>`.

⁴ Una sola medición en `flutter test`, es decir Dart en JIT (no AOT de release): sirve como orden de magnitud. El EQ procesa hoy una fracción pequeña del tiempo real en cualquiera de los dos; la ganancia útil es CPU y asignaciones por trozo, no un cuello de botella.

Huecos del arnés actual: el soak solo mide RSS y deriva de reloj; no hay CPU, arranque ni latencia. Pruebas nativas: `integration_test/audio_smoke_test.dart`, `scripts/progressive_audio_smoke.dart`, `scripts/run_so_loud_pcm_regression.ps1`. Sin medir en dispositivo: Android en segundo plano, Bluetooth, SMTC, audio Linux.

Ganancia esperada de la fase 1: infraestructura y menos sobrecarga en DJ/base; no recorta por sí sola la RAM de forma apreciable. Las ganancias grandes de RAM/CPU (EQ en `double` por muestra, copias por trozo y asignaciones de FFT cada 33 ms en `music_audio.dart`) llegan en la fase 2.

## 9. Estado de la fase 1

Hecho y verificado en esta máquina (Windows x64):

- Workspace `rust/` (paquete raíz `rust_lib_aurora_music` = puente FRB + miembros `aurora_database`, `aurora_ai_dj`, `aurora_cache`), toolchain fijado en `rust/rust-toolchain.toml` (1.96.1), `rust/Cargo.lock` versionado. `flutter_rust_bridge` 2.13.0 con Cargokit (`rust_builder/`, sin tocar tras generarlo).
- `cargo test --workspace`: 33 pruebas verdes, incluidas
  - `drift_written_database_opens_and_reads_back_every_value`: una base escrita por drift (v4, `tests/fixtures/drift_v4.sqlite`, generada con el código Dart anterior) se abre, devuelve cada valor y conserva `user_version = 4`;
  - migraciones v1/v2/v3 → v4 con filas conservadas, rechazo de `user_version = 5`, límite de 5000 vectores, orden por coseno, marcas de sincronización, `follow_remove` y descargas;
  - pruebas de oro del DJ (`tests/golden.rs`): 91 pistas (acentos, cirílico, CJK, emoji, sigma final, `Caféfeat`, espacios Unicode, `İ`, pares sustitutos), 3 perfiles y 10 escenarios de ranking contra la salida del código Dart v1.4.0: vectores y perfiles **idénticos bit a bit**, mismo orden de elección, afinidad dentro de 1e-12;
  - poda de directorios (más antiguo primero, por bytes/número, sufijo y exclusiones, subdirectorios, enlaces, archivo no borrable).
- `flutter analyze`: sin problemas. `flutter test`: 997 pasan, 2 omitidas, 0 fallan. Los widget tests siguen bajo `FakeAsync` porque todas las funciones de FRB de esta fase son `#[frb(sync)]`.
- Datos reales: una copia de la `aurora.sqlite` del desarrollador (`user_version 4`, 1310 pistas, 123 favoritos, 3 listas, 17 descargas, 1470 vectores, 6 artistas seguidos, 4 novedades, 590 filas `sync_meta`) se abre con el código nuevo y devuelve los mismos recuentos que `sqlite3` (el historial devuelve 100 por el `LIMIT 100` original; la tabla tiene 459). La copia se borró; la base original no se abrió con el código nuevo.
- Android: `flutter build apk --debug --target-platform android-arm64` termina bien (Cargokit instaló los destinos de Rust y compiló `rusqlite` con el NDK por defecto de Flutter) y el APK contiene `librust_lib_aurora_music.so`. `ndkVersion` no se tocó. **No se ejecutó en dispositivo.**

No verificado:

- **Windows release**: no compila en esta máquina (ver ³ de §8). Que `rust_lib_aurora_music.dll` quede junto al ejecutable lo hace Cargokit vía CMake y no se ha podido comprobar; solo está probado que la biblioteca carga desde `rust/target/release/` bajo `flutter test`. Tampoco se ha lanzado la aplicación.
- **Linux**: no se puede compilar en este equipo.
- **CI de GitHub Actions**: se añadió el paso `Compilar el motor Rust` a `windows.yml` y a los dos trabajos de `android.yml`; no se ha ejecutado.
- Hardware de audio, Bluetooth y audio en segundo plano: sin cambios en esta fase y sin probar.

### Base 1.5.2: medidas

- `flutter test`: 1621 pasan, 2 omitidas, 0 fallan. `flutter analyze` sin problemas. `cargo test --workspace`: 46 pasan, 3 ignoradas.
- `flutter build windows --release`: compila (necesita `nuget.exe` en el PATH para el plugin `flutter_inappwebview_windows`; en CI lo pone `NuGet/setup-nuget`). Carpeta `Release`: 485,7 MiB (incluye `tools/` con yt-dlp/ffmpeg/deno); `rust_lib_aurora_music.dll`: 4,24 MiB y queda junto al ejecutable. **No se pudo lanzar para comprobarlo**: la instancia instalada de Aurora estaba abierta y el ejecutable nuevo cede el control a la instancia existente y sale con código 0.
- `flutter build apk --release --target-platform android-arm64`, firmado: 73,9 MB, con `lib/arm64-v8a/librust_lib_aurora_music.so` (4,4 MiB). Sin probar en dispositivo.
- Los APK `--debug` (Dart sin optimizar, Rust sin optimizar) van mucho más lentos que un release; no sirven para valorar rendimiento.

### Fase 4.1 (hecha): caché de audio en `aurora_cache`

- `playbackCacheInfo`, `clearPlaybackCache` y `_pruneAudioCache` de `YtDlpSource` delegan en `aurora_cache::{audio_cache_info, clear_audio_cache, prune_audio_cache}`. Solo cuentan archivos regulares `^[A-Za-z0-9_-]{11}\.audio$`; enlaces simbólicos y el resto se ignoran; un archivo en uso se salta; la poda respeta la reserva (`max - reserve`, que puede ser negativa) y los archivos protegidos (el pedido y el progresivo activo) e informa `no_space` para que Dart lance el mismo `StateError`.
- Verificación: 10 pruebas Rust nuevas (nombres, conteos, orden por antigüedad, reserva, protegidos, enlaces, carpeta inexistente) y las pruebas de `source_backend_test.dart`, que ejercitan el código real a través de `YtDlpSource` (1621 pruebas de Flutter en verde).
- Sigue en Dart: la comprobación de que la carpeta de caché no sale del directorio de soporte (`_audioCacheDirectory`), el ejecutor de `ffprobe` y las duraciones. Ver `MIGRATION_PENDIENTES.md`.

### Fase 3.1 (hecha): analizadores de InnerTube en `aurora_sources`

- Crate `rust/crates/aurora_sources`: port de los `static parse*` de `innertube_source.dart`, con el mismo recorrido en profundidad por orden de documento (`serde_json` con `preserve_order`), las mismas deduplicaciones y los mismos puntos donde Dart lanzaba por un tipo inesperado (`Err` en Rust; excepción en Dart).
- Pruebas de oro contra Dart 1.5.2: 654 casos (corpus escrito a mano, 69 URLs de miniatura, 350 documentos mutados al azar): 456 salidas idénticas y 198 errores coincidentes, 0 discrepancias. `Uri.tryParse` de Dart se aproxima (esquema, `userinfo`, puerto, IPv6, `@` repetido) y el corpus de URLs lo fija; Dart acepta espacios, `^`, `\` y no ASCII en el host, y Rust igual.
- Coste: Dart vuelve a serializar la respuesta con `jsonEncode` antes de pasarla a Rust (la red ya la había decodificado). Sin medir en dispositivo.
- **No se portó `stream_guard`** (`assertNotRawYouTube`): es el punto único que impide que una URL de YouTube llegue a un decodificador y su decisión depende de `Uri.parse` de Dart (percent-encoding del host, `userinfo`, esquemas sin autoridad). Una diferencia de análisis sería un fallo de seguridad; se queda en Dart hasta tener un corpus adversario más amplio. La cola de solicitudes (`YouTubeRequestPolicy`) depende de futuros y de un reloj inyectado en las pruebas, así que tampoco se mueve todavía; sí es portable su `classify` (puro).

### Fase 2a (hecha): `aurora_audio`

- Crate `rust/crates/aurora_audio`: `ParametricEqualizer` (8 bandas RBJ, rampas exponenciales, limitador de codo suave), `spectrum_bars` y `is_complete_audio_stream`. Dart conserva `ParametricEqualizer`, `spectrumBars` e `isCompleteAudioStream` como envoltorios; el preamp automático (`eqAutoPreamp`) lo sigue calculando Dart con la curva de `eq_model.dart` y se pasa a Rust.
- Pruebas de oro (`rust/crates/aurora_audio/tests/golden.rs`) contra la salida de Dart v1.4.0: 9 escenarios de EQ (arranque en frío, rampas, reconfiguración, apagado hasta quedar inactivo, reactivación, muestras NaN/∞, mono, lista de bandas incompleta y longitud impar), 9 vectores de espectro y 1008 combinaciones de fin de flujo. Resultado: **100 % de las muestras idénticas bit a bit**; el test tolera 2e-6 por si otra plataforma usa otra `libm`.
- `flutter test` completo en verde con el EQ de Rust (`test/eq_dsp_test.dart`, `audio_math_test.dart`, `audio_completion_test.dart` son ahora pruebas de integración del puente). La prueba `softLimit` pasó a Rust.
- **2b no se ha hecho** (reemplazo de SoLoud + ffmpeg por Symphonia + CPAL): es la parte con riesgo audible y no se puede validar sin dispositivo de audio y sesiones de escucha. La reproducción en escritorio sigue exactamente como en 1.4.0, salvo que el EQ se ejecuta en Rust.

Cambios de comportamiento y divergencias deliberadas:

- `rank_candidates` ordena con un sort **estable** por `prior`; el de Dart era inestable. Solo difiere con `prior` empatado, que las fuentes no producen (el prior es por posición). Las pruebas de oro usan priors distintos.
- `dart_lower` reproduce `String.toLowerCase` de Dart: minúsculas por carácter, sin sigma final contextual y con `İ → i` (Rust devolvería `i̇`). `\s` es el de ECMAScript (con U+FEFF, sin U+0085) y `` es ASCII.
- El puente expone tamaños como `i64` (no `u64`) para que Dart reciba `int` y no `BigInt`; las estructuras del DJ llevan prefijo `Dj` (`DjRankRequest`, `DjRankCandidate`, `DjPick`).
- Se añadió `save_tracks_and_playlists` (una transacción) porque `importSpotifyPlaylists` usaba `database.transaction`, que no existe fuera de drift.
- Las marcas de sincronización (`mark`) se escriben ahora en la misma transacción que el dato; antes eran dos sentencias.
- Las dos podas migradas (`artwork_cache`, `lyrics_service`) se ejecutan en el hilo de Dart (función síncrona); antes usaban E/S asíncrona. `YtDlpSource._pruneAudioCache` sigue en Dart (valida nombres, enlaces y espacio) y pasa a la fase 4.
- `djCosine` y `djNormalize` siguen duplicados en Dart a propósito: una llamada FFI por par cuesta más que el bucle y `suggestions_api.dart` los usa en bucles calientes.
- `analysis_options.yaml` excluye `rust_builder/**` (herramienta de Cargokit con su propio pubspec) y `lib/bridge/**` (generado).
- Prerrequisito de pruebas: `flutter test` carga `rust/target/release/rust_lib_aurora_music.dll` (`.so` en Linux); hay que ejecutar antes `cargo build --release --manifest-path rust/Cargo.toml` (`test/flutter_test_config.dart`).
- `flutter pub get` tras añadir el complemento `rust_lib_aurora_music` falla la primera vez en Windows sin Modo de desarrollador al crear el enlace simbólico del complemento; la segunda ejecución pasa (los archivos de resolución ya están escritos).
