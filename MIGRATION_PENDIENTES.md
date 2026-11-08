# Migración a Rust: lo que NO se ha hecho todavía

Lista viva. Cada vez que una fase deja algo fuera a propósito, se anota aquí con el motivo y el siguiente paso. Lo que sí está hecho vive en `MIGRATION_AUDIT.md`. Base: Aurora 1.5.2+19.

Estados: **Pendiente** (no empezado), **Aplazado** (decidido no portar aún, con motivo), **Sin verificar** (hecho pero no probado en el entorno real).

## Fases enteras

| Fase | Contenido | Estado |
|---|---|---|
| 2b | Reproducción de escritorio con Symphonia + CPAL en lugar de SoLoud + ffmpeg | Pendiente |
| 3.2+ | Orquestador de streams, proxy local de audio, cliente InnerTube con red | Pendiente |
| 4 (resto) | Ejecutor de yt-dlp/ffmpeg/ffprobe, cola de descargas, reanudación y verificación (la caché de audio ya está: 4.1) | Pendiente |
| 5 | Jam (servidor WS LAN, comandos, codec de invitaciones, deriva) | Pendiente |
| 6 | Sincronización (LWW, Last.fm) | Pendiente |
| 7 | Núcleo: cola y reproducción, puerta de coherencia, DJ restante | Pendiente |
| 8 | Plataforma: Discord/Duvet, actualizador | Pendiente |

## Partes de fases ya hechas que se dejaron en Dart

| Qué | Dónde | Por qué se aplazó | Siguiente paso |
|---|---|---|---|
| `stream_guard` (`assertNotRawYouTube`) | `lib/audio/stream_guard.dart` | Es el punto único que impide que una URL cruda de YouTube llegue a un decodificador y depende de cómo `Uri.parse` de Dart interpreta el host. Una diferencia de análisis sería un fallo de seguridad. | Corpus adversario amplio (percent-encoding, `userinfo`, esquemas sin autoridad, Unicode) comparado con Dart antes de portarlo. |
| `YouTubeRequestPolicy`: cola, enfriamiento, reintentos | `lib/sources/youtube_request_policy.dart` | Futuros y reloj/`sleep` inyectados en las pruebas; no se puede portar sin un tiempo de ejecución asíncrono en Rust. | Decidir el modelo asíncrono (ver «Decisiones abiertas»). |
| `YouTubeRequestPolicy.classify` | ídem | Pura y portable; no se hizo por ser pequeña. | Portar con corpus de oro cuando se porte la cola. |
| Buscador de token de continuación de `_artistAllSongs` | `innertube_source.dart` | Está dentro del bucle de red y se queda con el **último** token (los analizadores toman el primero). | Portar junto al cliente InnerTube. |
| `isValidVideoId` y expresiones de ID en Dart | `innertube_source.dart`, `yt_dlp_source.dart` | Triviales; duplicadas con Rust. | Unificar al portar el cliente. |
| Puerta de coherencia y `scoreCoherence` | `lib/dj/coherence.dart` | Es la lógica de la 1.5.x; `rankDjCandidates` la ejecuta en Dart y pasa a Rust `coherence_bonus`. | Fase 7. |
| Ranking y perfil propios de sugerencias | `lib/dj/suggestions_api.dart` (`_rank`, constructor de perfil) | No comparten código con `ai_dj.dart`; `djCosine`/`djNormalize` se usan en bucles calientes. | Fase 7. |
| Modos del DJ, memoria anti-repetición, `djDiscoveryQueries` | `lib/dj/*` | Dependen del estado de la app. | Fase 7. |
| `djCosine` y `djNormalize` duplicados en Dart | `lib/dj/ai_dj.dart` | Una llamada FFI por par cuesta más que el bucle. | Mover con `aurora_core`. |
| `equalizerGain`, `equalizerPreamp`, `ffmpegHttpsOptions`, `redactAudioError`, `shouldResumeAfterSeek` | `lib/audio/audio_math.dart` | Triviales o ligadas a SoLoud/ffmpeg. | Fase 2b. |
| Curva de respuesta del EQ (`eqResponseCurve`, `eqAutoPreamp`) | `lib/audio/eq_model.dart` | La usa la UI para dibujar; el preamp se calcula en Dart y se pasa a Rust. | Decidir si la UI llama a Rust. |
| Comprobación de seguridad de la carpeta de caché (`_audioCacheDirectory`) | `yt_dlp_source.dart` | Resuelve enlaces y rechaza salidas del directorio de soporte; sigue en Dart. | Fase 4 completa. |
| Caché de audio: canonicalización de rutas | `aurora_cache::clear_audio_cache` | Usa `canonicalize` de Rust (en Windows devuelve `\\?\`); probado solo en Windows con rutas temporales. | Probar en Android y Linux. |
| `_cachedAudioDuration`, `_audioDuration` (ffprobe) | `yt_dlp_source.dart` | Lanzan procesos externos. | Fase 4 (ejecutor). |
| Validadores de URL de yt-dlp (`validateYouTube`, `validateVideoUrl`) | `yt_dlp_source.dart` | Mismo riesgo que `stream_guard`. | Con `stream_guard`. |
| Scorers de coincidencia (`youtube_match.dart`, `lyrics_match.dart`) | `lib/metadata`, `lib/lyrics` | Dependen de `recsNormalizeTitle` y del DJ. | Fase 3 (metadatos). |

## Sin verificar

| Qué | Motivo |
|---|---|
| Arranque de la versión de Windows (`aurora_music.exe`) con `rust_lib_aurora_music.dll` | La instancia instalada de Aurora estaba abierta y la nueva cede el control y sale. Pendiente de lanzarla con la otra cerrada. |
| APK release en dispositivo (rendimiento, base de datos, DJ, EQ) | No hay dispositivo conectado a esta máquina. |
| Pasos de CI (`cargo build --release` antes de `flutter test`) | No se han ejecutado en GitHub Actions. |
| Linux | No se puede compilar en este equipo. |
| Rendimiento percibido en el celular | Se reportó lento con un APK debug sobre 1.4.0; el release sobre 1.5.2 no se ha medido. |
| Coste de volver a serializar JSON para los analizadores de InnerTube | Sin medir en dispositivo. |
| Arranque con la base real tras migrar (`aurora.sqlite` abierta por código nuevo en la app) | Solo se probó con una copia desde Rust, no desde la app. Copia de seguridad en `%LOCALAPPDATA%\\Temp\\aurora.sqlite.backup`. |

## Divergencias deliberadas con Dart

- Ranking del DJ: orden estable por `prior` (Dart usaba un sort inestable).
- Analizadores de InnerTube: `Uri.tryParse` se aproxima (ver pruebas de oro); fuera del corpus puede haber URLs raras que Dart acepte y Rust no, o al revés.
- Las podas de caché (`artwork_cache`, `lyrics_service`, caché de audio) corren en el hilo de Dart como funciones síncronas; antes usaban E/S asíncrona.

## Decisiones abiertas

- **Modelo asíncrono en Rust.** Todas las funciones del puente son `sync` porque las pruebas de widgets corren bajo `FakeAsync` y las llamadas asíncronas de FRB no avanzan allí. Las fases 3.2, 4, 5 y 6 (red, procesos, WebSocket) necesitan un tiempo de ejecución asíncrono y una forma de probarlo (pruebas en Rust con `tokio` y simulación en el puente).
- **Dónde probar audio real (2b):** hace falta un equipo con dispositivo de audio y sesiones de escucha; el arnés actual solo mide RSS y deriva de reloj.
