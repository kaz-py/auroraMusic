> **Actualización.** Las canciones de YouTube se resuelven por InnerTube y suenan en Media3 a través de un proxy local en `127.0.0.1` ([youtube_music_audio_engine.md](youtube_music_audio_engine.md)). Media3 reproduce además los archivos locales. yt-dlp queda para descargas. Lo que sigue describe descargas y reproducción local.

# Reproducción Android, streaming y música sin conexión

## Flujo por plataforma

Android conserva Flutter, el controlador y su cola. `YtDlpSource` busca y consulta
playlists con yt-dlp; para reproducir ejecuta `--dump-single-json --skip-download`
y devuelve una URL HTTPS con sus cabeceras ordinarias. `AndroidMusicAudio` envía
esa descripción por `aurora/audio`; Kotlin reproduce directamente con Media3
ExoPlayer 1.11.1. No pasan bytes de audio por MethodChannel.

`AuroraPlaybackService` es un `MediaSessionService`, con foco de audio, pausa al
desconectar auriculares, notificación y controles de segundo plano. Sus acciones
de siguiente/anterior vuelven al controlador Flutter: no existe una segunda cola
nativa. `aurora/audio/events` comunica estado, posición, final y errores con una
generación para descartar eventos de pistas anteriores. La sesión y el motor
Flutter permanecen al pasar a segundo plano.

El búfer de ExoPlayer está limitado a 15–30 segundos y 8 MiB. Es memoria de
streaming, sin un descargador ni una caché de archivos de la canción. Su lectura
progresiva comprueba límites por bloques: un audio pequeño puede caber completo
en el búfer; no espera una descarga completa para iniciar ni publica un archivo
sin conexión. Se deshabilitan reintentos internos ante 403/429; otros errores de
carga tienen un reintento antes del control de recuperación de Aurora.

Windows usa el motor Rust (ya sin SoLoud ni FFmpeg), su caché validada y el relay progresivo opcional
existentes. Cambian el canal nightly, su actualización segura y los límites de
solicitudes. No se modifica la base de datos ni se migra la biblioteca.

## Runtime de yt-dlp en Android

La dependencia es `io.github.junkfood02.youtubedl-android:library:0.18.1` y FFmpeg
0.18.1. Kotlin inicializa ambos y ejecuta yt-dlp mediante el Python nativo de la
biblioteca; QuickJS y EJS resuelven los desafíos JavaScript. FFmpeg se utiliza en
descargas/conversión y validación local, no como motor de reproducción Android.
El antiguo canal PCM `aurora/pcm` se elimina.

Android mínimo: API 24. ABI configuradas: `arm64-v8a` y `x86_64`; no se promete
soporte de 32 bits. AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14 y compileSdk 36 se
conservan. La variante FFmpeg local mantiene las bibliotecas WebP reconstruidas
para páginas de 16 KB. El APK incluye permisos normales de Internet, wake lock,
foreground playback y modificación de ajustes de audio. Los archivos viven en
almacenamiento privado: no se solicita un permiso de almacenamiento adicional.

## Descarga explícita

En Ajustes → **Música sin conexión**, «Descargar una canción» muestra canciones
reales disponibles; seleccionarla añade un trabajo al gestor existente.
«Gestionar descargas» abre progreso, cancelación, errores y canciones terminadas.
Reproducir o aceptar una recomendación no activa esta función automáticamente.

La descarga usa yt-dlp y FFmpeg para producir un MP3 en una carpeta temporal;
se publica al terminar, sin sobrescribir archivos existentes. Se limita a
512 MiB y 30 minutos. Cancelar mata el proceso y descarta la carpeta temporal;
una cancelación tardía impide publicar el archivo. Los trabajos completados
se reutilizan mediante los identificadores existentes del controlador.

Si existe una antigua caché Android validada `yt-dlp-audio/<videoId>.audio`, se
convierte localmente con FFmpeg en lugar de volver a solicitar el audio.
Las canciones terminadas se resuelven a su ruta local y Media3 las reproduce sin
red. El ecualizador usa el efecto Android cuando está disponible; FFT no está
disponible en este backend y la interfaz desactiva esa captura.

## Solicitudes y nightly

Dos operaciones concurrentes como máximo, ocho pendientes y un segundo entre
inicios. yt-dlp usa además `--sleep-requests 1` en Android y Windows: un segundo
entre sus peticiones internas durante la extracción, sin ralentizar el audio
que ya reproduce ExoPlayer. Búsquedas/consultas repetidas comparten la petición
y caché de cinco minutos; URLs resueltas se reutilizan con margen de dos minutos. La cancelación
antes de despachar una resolución evita iniciar un proceso ya descartado.

429, verificación/bloqueo y 403 sin expiración comprobable detienen reintentos
durante 1 minuto, incluso después de reiniciar la app. Una pausa guardada por
una versión anterior se acorta a un minuto como máximo. Esta pausa no garantiza
que YouTube levante la restricción. Un 403 solo permite
renovar la URL si su `expire`/`expires` realmente venció. La recuperación por
fallos temporales conserva posición, espera dos/cuatro segundos y se limita a
dos intentos. No se cambia de IP, cliente, cuenta ni sesión para evadir bloqueos.

La actualización nightly se programa después de 20 segundos y vuelve a ofrecer
una comprobación cada seis horas; solo consulta una vez por 24 horas y estando
inactiva. Descarga oficial, SHA-256, avisos de licencia, sustitución atómica,
backup y recuperación están descritos en [ytdlp_nightly.md](ytdlp_nightly.md).
Android actualiza automáticamente el payload interpretado; Python, QuickJS y
FFmpeg necesitan una actualización del APK. Un fallo de recuperación bloquea
el uso del candidato hasta restaurar una versión verificada.

## Verificación realizada

- `flutter analyze`: sin incidencias; **299 pruebas Flutter aprobadas**, con
  fuentes simuladas, cancelación, expiración, cooldown y estados offline.
- Compilaciones Windows release y Android debug x86_64/release ARM64.
- Emulador limpio API 36.1/x86_64: Media3 local, play/pause/seek/stop y tráfico
  local de cero bytes; conversión de caché con FFmpeg y reproducción offline,
  con cero invocaciones de extracción remota.
- Nightly real en Android: `2026.10.10.233141`, checksum oficial comprobado,
  resultado `upToDate` y segunda comprobación `throttled`.
- Streaming HTTPS del fixture oficial Media3, controles y un único EOF;
  prueba separada de YouTube, con caché de archivos sin cambios. Al iniciar se
  transfirieron **2097308 de 8882875 bytes**, en una solicitud de audio: lectura
  parcial antes de reproducir, sin esperar el archivo completo.
- Pruebas Kotlin de SHA-256, checksum ambiguo e integridad del bundle.
  Pruebas Dart del actualizador incluyen corrupción, rollback y recuperación
  de instalaciones interrumpidas, sin depender de servicios externos.
- APK ARM64 firmado: `apksigner verify` aprobado; 268 archivos ELF empaquetados
  con segmentos LOAD alineados a al menos 16 KB. Esta inspección estática no
  sustituye una prueba física con páginas de 16 KB.

La resolución real de YouTube se intentó en el emulador: la primera referencia
de prueba ya no estaba disponible y otra pública devolvió verificación/posible
bloqueo. Se detuvieron las solicitudes. **No se afirma que la extracción actual
de YouTube funcione en esta red**, aunque el runtime sí inicia en Android y
Media3 reproduce streaming. No hay evidencia para atribuir esa respuesta a las
descargas antiguas.

Antes, Android hacía una invocación `cacheAudio` y transfería/guardaba todo el
audio antes de reproducir. Ahora una resolución solicita metadatos y ExoPlayer
transfiere su búfer; descargar explícitamente sí transfiere el archivo completo.
Los contadores informan invocaciones de yt-dlp y bytes/peticiones del audio
nativo; no equivalen al número total de solicitudes HTTP internas a YouTube,
que no se capturó. Bluetooth, dispositivos ARM64 físicos y restricciones de
segundo plano de fabricantes necesitan pruebas adicionales en hardware.

## Archivos principales

```text
lib/audio/android_music_audio.dart       Contrato Flutter con el motor nativo
lib/sources/yt_dlp_source.dart            Búsqueda, resolución y descarga explícita
lib/sources/youtube_request_policy.dart   Concurrencia, espera y enfriamiento
lib/sources/ytdlp_updater.dart            Actualización Windows y recuperación
lib/ui/offline_settings_panel.dart       Gestión offline desde Ajustes
android/app/src/main/kotlin/com/aurora/aurora_music/
  AuroraAudioPlugin.kt                   Canales Flutter y enlace al servicio
  AuroraPlaybackService.kt               Media3, sesión, EQ y estado
  AuroraYtDlpUpdater.kt                   Payload nightly verificado de Android
  MainActivity.kt                        Resolver nativo y descargas/FFmpeg
```

Tres subagentes trabajaron en worktrees independientes: auditoría Android y CI
(`audit/android-ytdlp`, GPT-6 Luna), Media3 (`feat/android-media3`, GPT-6.1 Sol) y
nightly (`feat/ytdlp-nightly`, GPT-6.1 Sol). Sus commits se revisaron y fusionaron
en `main`; la integración de controlador, proveedor, ajustes y verificación se
realizó en la base principal, sin editar los diseños originales del usuario.
