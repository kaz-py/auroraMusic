# Migración a Rust: lo que NO se ha hecho todavía

Lista viva. Cada vez que una fase deja algo fuera a propósito, se anota aquí con el motivo y el siguiente paso. Lo que sí está hecho vive en `MIGRATION_AUDIT.md`. Base: Aurora 1.5.2+19.

Estados: **Pendiente** (no empezado), **Aplazado** (decidido no portar aún, con motivo), **Sin verificar** (hecho pero no probado en el entorno real).

## Fases enteras

| Fase | Contenido | Estado |
|---|---|---|
| 2b | Reproducción de escritorio con Symphonia + CPAL en lugar de SoLoud + ffmpeg | **Primer corte hecho; falta validarlo de oído y retirar SoLoud/FFmpeg** (ver abajo) |
| 3.2+ | Orquestador de streams, proxy local de audio, cliente InnerTube con red | Pendiente |
| 4 (resto) | Ejecutor de yt-dlp/ffmpeg/ffprobe, cola de descargas, reanudación y verificación (la caché de audio ya está: 4.1) | Pendiente |
| 5 | Jam (servidor WS LAN, comandos, codec de invitaciones, deriva) | Pendiente |
| 6 | Sincronización (LWW, Last.fm) | Pendiente |
| 7 | Núcleo: cola y reproducción, puerta de coherencia, DJ restante | Pendiente |
| 8 | Plataforma: Discord/Duvet, actualizador | Pendiente |

## Fase 2b: lo que falta

| Qué | Motivo / estado | Siguiente paso |
|---|---|---|
| Escucharlo: calidad, inicio de pista, saltos, pausa, EQ, volumen, fin de pista | No se puede validar sin oído; solo hay pruebas numéricas y una de dispositivo en silencio. | Probar en Windows (`Aurora-1.5.2-windows`); si algo suena mal, `AURORA_AUDIO_ENGINE=soloud` vuelve al motor anterior. |
| HTTPS remoto (TLS verificado) | El lector HTTP solo acepta el bucle local; lo demás cae al motor anterior. | `ureq` con `rustls` y el almacén de certificados del sistema, con reintentos y tiempos como FFmpeg (`-rw_timeout 15 s`). |
| HE-AAC (SBR/PS) | Symphonia solo decodifica AAC-LC; se rechaza solo si el `AudioSpecificConfig` lo declara explícito (tipos 5 y 29). Con SBR implícito sonaría a media frecuencia. | Fixture HE-AAC (no hay codificador en el FFmpeg incluido) y detección por la frecuencia decodificada. |
| Wma, Ape, Opus multicanal, etc. | Fuera de Symphonia / `opus-decoder`; pasan al motor anterior. | Ampliar solo si hace falta. |
| Escala del espectro | `spectrumBars` espera la escala de SoLoud; la de Rust es amplitud de senoide (1 = escala completa) y no está calibrada. | Comparar visualmente con SoLoud y ajustar. |
| Cambio del dispositivo de salida por defecto | `cpal` no sigue el cambio una vez abierto. | Detectar el error de flujo y reabrir. |
| Reloj de salida y remuestreo | La frecuencia se fija al abrir el dispositivo. | Reabrir si cambia. |
| Sin reproducción sin huecos (gapless) | Igual que antes; la pista siguiente se carga al terminar. | Decisión de producto. |
| Retirar SoLoud + FFmpeg del camino de escritorio | Siguen como respaldo; el parche `scripts/patch_flutter_soloud.cmake` y `flutter_soloud` se quedan. | Cuando la validación de oído y el HTTPS remoto estén resueltos. |
| Linux | `cpal` enlaza ALSA (`libasound2-dev` ya está en CI y `libasound2` en el `.deb`); no se ha compilado ni probado. | Compilar y probar en una máquina Linux. |
| Arranque del `.exe` con el motor nuevo | La instancia instalada de Aurora estaba abierta (instancia única). | Lanzarlo con la otra cerrada. |

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
| `equalizerGain`, `equalizerPreamp`, `ffmpegHttpsOptions` | `lib/audio/audio_math.dart` | Solo las usa el motor anterior (SoLoud/FFmpeg). | Retirar con SoLoud. |
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
