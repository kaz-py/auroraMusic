# Migración a Rust: lo que NO se ha hecho todavía

Lista viva. Cada vez que una fase deja algo fuera a propósito, se anota aquí con el motivo y el siguiente paso. Lo que sí está hecho vive en `MIGRATION_AUDIT.md`. Base: Aurora 1.5.2+19.

Estados: **Pendiente** (no empezado), **Aplazado** (decidido no portar aún, con motivo), **Sin verificar** (hecho pero no probado en el entorno real).

## Fases enteras

| Fase | Contenido | Estado |
|---|---|---|
| 2b | Reproducción de escritorio con Symphonia + CPAL en lugar de SoLoud + ffmpeg | **Hecha y SoLoud/FFmpeg retirados de escritorio**; quedan los puntos de abajo |
| 3.2+ | Orquestador de streams, proxy local de audio, cliente InnerTube con red | Pendiente; **medido: no mejora la latencia** (ver `MIGRATION_AUDIT.md`, resolver ≈ 0,4–0,6 s es red). Solo valdría por consolidar código, y exige decidir el modelo asíncrono. |
| 4 (resto) | Ejecutor de yt-dlp (procesos, progreso, tope de salida, matar el árbol), cola de descargas, reanudación (la caché de audio ya está: 4.1; ffmpeg/ffprobe ya no existen en escritorio) | Pendiente |
| 5 | Jam (servidor WS LAN, comandos, codec de invitaciones, deriva) | Pendiente |
| 6 | Sincronización (LWW, Last.fm) | Pendiente |
| 7 | Núcleo: cola y reproducción, puerta de coherencia, DJ restante | Pendiente |
| 8 | Plataforma: Discord/Duvet, actualizador | Pendiente |

## Fase 2b: lo que falta

| Qué | Motivo / estado | Siguiente paso |
|---|---|---|
| Escucharlo: calidad, inicio de pista, saltos, pausa, EQ, volumen, fin de pista | No se puede validar sin oído; solo hay pruebas numéricas y una de dispositivo en silencio. | Probar en Windows (`Aurora-1.5.2-windows`); si algo suena mal, volver a la etiqueta `rust-antes-de-quitar-soloud`. |
| HTTPS remoto: prueba real | Hecho (TLS del sistema, reconexión con `Range`) y probado con servidor local y corte simulado; **no** contra un CDN https real ni con un certificado inválido. | Reproducir un https público y comprobar el rechazo de un certificado caducado. |
| HE-AAC (SBR/PS) | Symphonia solo decodifica AAC-LC; se rechaza solo si el `AudioSpecificConfig` lo declara explícito (tipos 5 y 29). Con SBR implícito sonaría a media frecuencia. | Fixture HE-AAC (no hay codificador en el FFmpeg incluido) y detección por la frecuencia decodificada. |
| Wma, Ape, Opus multicanal, HE-AAC, etc. | Fuera de Symphonia / `opus-decoder`: ahora fallan con «Formato de audio no admitido» (ya no hay motor de respaldo). | Ampliar solo si hace falta. |
| Escala del espectro | `spectrumBars` espera la escala de SoLoud; la de Rust es amplitud de senoide (1 = escala completa) y no está calibrada. | Comparar visualmente con SoLoud y ajustar. |
| Cambio del dispositivo de salida por defecto | Si el dispositivo **desaparece** (auriculares desenchufados) el flujo falla, `RustMusicAudio` abre un motor nuevo y sigue por donde iba (hecho y probado con un fallo simulado). Si solo se cambia el predeterminado sin que el actual falle, `cpal` no lo sigue. | Escuchar el cambio de dispositivo predeterminado del sistema. |
| Sin reproducción sin huecos (gapless) | Igual que antes; la pista siguiente se carga al terminar. | Decisión de producto. |
| Descargas sin MP3 | Desktop guarda Opus (`.opus`) o M4A tal cual; Android sigue entregando MP3 (FFmpeg de `youtubedl-android`). No se probó una descarga real de YouTube de principio a fin con este cambio ni reproducirla en otros reproductores. | Descargar una canción real y abrirla en Aurora y en otro reproductor. |
| FFmpeg en Android | `youtubedl-android` lo trae y se usa en descargas/caché de Android (MP3). Retirarlo exige otro camino nativo. | Aplazado; fuera de Rust de escritorio. |
| Validación de descargas: resincronización | El desmultiplexor salta fotogramas dañados sin error; solo se detecta si cambia la duración total. | Contar fotogramas saltados si Symphonia lo expone. |
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
| Curva de respuesta del EQ (`eqResponseCurve`, `eqAutoPreamp`) | `lib/audio/eq_model.dart` | La usa la UI para dibujar; el preamp se calcula en Dart y se pasa a Rust. | Decidir si la UI llama a Rust. |
| Comprobación de seguridad de la carpeta de caché (`_audioCacheDirectory`) | `yt_dlp_source.dart` | Resuelve enlaces y rechaza salidas del directorio de soporte; sigue en Dart. | Fase 4 completa. |
| Caché de audio: canonicalización de rutas | `aurora_cache::clear_audio_cache` | Usa `canonicalize` de Rust (en Windows devuelve `\\?\`); probado solo en Windows con rutas temporales. | Probar en Android y Linux. |
| `_cachedAudioDuration`, `_audioDuration`, `_finalizeAudio` | `yt_dlp_source.dart` | La duración y el remux ya son Rust; la orquestación (cancelación, progreso, carpetas temporales) sigue en Dart. | Fase 4 (ejecutor). |
| Validadores de URL de yt-dlp (`validateYouTube`, `validateVideoUrl`) | `yt_dlp_source.dart` | Mismo riesgo que `stream_guard`. | Con `stream_guard`. |
| Scorers de coincidencia (`youtube_match.dart`, `lyrics_match.dart`) | `lib/metadata`, `lib/lyrics` | Dependen de `recsNormalizeTitle` y del DJ. | Fase 3 (metadatos). |

## Sin verificar

| Voz con Whisper en Linux, micrófono real y letras contra una referencia sincronizada | La compilación en Linux y la precisión de la alineación no se midieron (ver `MIGRATION_AUDIT.md`, «Voz con Whisper»). |
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

## Retirado: respaldo WebView

El respaldo de reproducción en WebView oculto (sitio oficial de YouTube Music) se eliminó entero, con su dependencia `flutter_inappwebview`; no queda nada pendiente ni aplazado sobre él. Si YouTube bloquea una canción, el usuario ve el error de reproducción normal (detalle en `docs/youtube_music_audio_engine.md`).
