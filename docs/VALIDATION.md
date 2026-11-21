# Validación de Aurora

## Entorno y alcance

Windows x64, Flutter 3.38.8 / Dart 3.10.7; Android API 36.1 en emulador x86_64. La plataforma mínima configurada es Android API 24. Las pruebas de emulador no sustituyen pruebas en teléfonos o auriculares físicos.

> **Nota (motor Rust).** Los resultados y comandos históricos de esta página que citan SoLoud, FFmpeg, `audio_smoke_test` o `audio_soak_runner` describen el motor de escritorio anterior a 1.5.2 y ya no se pueden repetir: ese motor se eliminó. El motor actual se valida con `cargo test --workspace --release` y el humo real `--test device` (ver `MIGRATION_AUDIT.md`).

## Pruebas reproducibles

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/interface_smoke_test.dart -d windows --no-pub
flutter test integration_test/app_smoke_test.dart -d windows --no-pub
flutter test integration_test/app_smoke_test.dart -d <android-id> --no-pub
cargo test --workspace --release --manifest-path rust/Cargo.toml
cargo test -p aurora_playback --release --test device --manifest-path rust/Cargo.toml -- --ignored --nocapture
```

Las pruebas nativas generan tonos de volumen bajo y archivos temporales, que eliminan al finalizar. No ejecutes dos compilaciones Windows simultáneamente sobre el mismo directorio de salida.

La comprobación online es explícita porque depende del proveedor:

```powershell
flutter test integration_test/source_smoke_test.dart -d windows --no-pub --dart-define=AURORA_ONLINE_SMOKE=true --dart-define=AURORA_TOOLS=C:/ruta/tools/windows --dart-define=AURORA_SAMPLE_URL=https://www.youtube.com/watch?v=jNQXAC9IVRw
```

Usa un video público permitido para probar extracción, reproducción y descarga. El archivo de prueba no se conserva.

## Resultados

| Comprobación | Resultado |
| --- | --- |
| Unitarias y widgets | 60 pruebas aprobadas: cola y duplicados, carreras asíncronas, cierre, restauración, biblioteca, carpeta de descargas persistente, borrado seguro, letras y caché/importación, sesión opcional, DSP, layouts, contraste y prevención de búsquedas duplicadas. |
| Rediseño y centrado | Capturas nativas a 1440×900 y 390×844; navegación, biblioteca, búsqueda, descargas, ajustes, vinilo, cola y letras. Botón de reproducción centrado a 1440/900 dp; metadatos móviles separados de controles; disco, etiqueta y agujero del vinilo concéntricos con tolerancia de 1 dp, también a 320 dp con texto al 200 %. |
| Layouts | 320, 800 y 1440 dp; texto al 200%; reproductor, cola y EQ; confirmar/cancelar borrado. |
| Contraste | 24 tonos de portada en temas claro/oscuro; acciones y texto ≥4,5:1. |
| Audio Windows | WAV y PCM FFmpeg aprobados: reloj consumido, pausa, seek, FFT, RMS del EQ, buffer reciclado, cambios rápidos y EOF. |
| Arranque Windows | Base SQLite, audio, EQ inicialmente apagado, controles multimedia e interfaz sin error. Herramientas preparadas al compilar y detectadas automáticamente; diagnóstico yt-dlp aprobado. |
| Arranque Android | Base SQLite, audio y pantalla principal aprobados en emulador. |
| Audio Android | WAV y PCM FFmpeg aprobados: pausa, seek, FFT, EQ, cancelación y EOF. Excepción de cierre del worker corregida y comprobada. |
| Reproducción continua Windows | Ejecutable release independiente: 30 minutos aprobados, 1801 s de reloj consumido, crecimiento máximo de memoria de 909312 bytes. Log `build/native_audio_soak_release_30min.jsonl`, evento final `complete`. |
| YouTube Windows (2026-10-11) | Búsqueda por texto y extracción CLI aprobadas sin sesión. Prueba nativa aprobada con `jNQXAC9IVRw`: metadatos, extracción HTTPS, reproducción real, descarga MP3, reproducción local y seek. El bloqueo 429 observado el día anterior no se reprodujo hoy; el resultado no garantiza disponibilidad de todos los videos o redes. |
| Paquetes del rediseño | Windows release: `dist/redisenado/Aurora-Windows.zip`, herramientas/licencias incluidas; hash del motor release verificado y ejecutable independiente activo tras cinco segundos de arranque. Android ARM64 release: `dist/redisenado/Aurora-Android-arm64-release.apk`, firma privada de Aurora verificada con apksigner, `debuggable=false`, 65417188 bytes. Ambos tienen archivos SHA-256. Las comprobaciones online y de audio de las filas anteriores corresponden a la validación previa del motor, conservado en este rediseño. |
| Alineación Android | ZIP de 16 KB y 265 ELF ARM64, incluyendo dependencias archivadas Python/FFmpeg: aprobados. WebP recompilado y avisos de licencia presentes en APK. |

La inspección de dependencias detectó cinco ELF WebP de 4 KB dentro del archivo FFmpeg original. `scripts/rebuild_android_webp.ps1` recompila esas bibliotecas desde código oficial con NDK 28 y verifica sus símbolos/SONAME; `scripts/verify_android_alignment.ps1` revisa tanto las bibliotecas visibles del APK como las dependencias archivadas de Python/FFmpeg. La comprobación estática y la ejecución en un dispositivo de 16 KB son verificaciones diferentes.

El runner escribe muestras cada 10 segundos y eventos `complete`/`failed`; el código de salida es 0/1. Durante esta implementación se ejecutó una copia aislada en `build/soak-runner-bin`, permitiendo compilar la aplicación simultáneamente.

Los logs de ejecución quedan en `build/` y los artefactos en `dist/`; ambos están excluidos de Git.

El rediseño se verificó con `build/ui-union-tests.log` (60 pruebas),
`build/ui-analyze.log`, `build/interface-native.log`,
`build/app-native-redesign.log` y `build/android-redesign-alignment.log`.
Las capturas `build/screenshots/aurora-redesign-*.png` utilizan audio simulado y
portadas geométricas originales para comparar el diseño sin datos personales;
la prueba de arranque utiliza SQLite y el motor de audio nativos.

La compilación Android release y sus comprobaciones quedan en
`build/android-release-build.log`, `build/android-release-signature.log`,
`build/android-release-debuggable.log` y `build/android-release-alignment.log`.
No se comprobó este APK release en un teléfono físico.

Para repetirla con la configuración de firma local existente:

```powershell
flutter build apk --release --target-platform android-arm64
```

Conserva una copia privada de la clave y sus credenciales fuera del repositorio.
No uses `--no-pub` después de pruebas de integración: la regeneración del
registro de plugins debe excluir las dependencias de desarrollo del release.

La búsqueda se envía solo con Enter o la flecha. La prueba de interfaz comprueba que escribir y repetir Enter durante una consulta pendiente no duplique solicitudes. La importación de sesión es voluntaria: valida Netscape y cookies de YouTube, conserva el original, protege cambios durante operaciones activas y no expone valores en errores. No se probó con credenciales reales de un usuario.

## Correcciones de reproducción y búsqueda (2026-10-11)

- `flutter test`: 68 pruebas aprobadas; `flutter analyze`: sin incidencias. Incluye redondeo float32 del contador nativo y rechazo de audio incompleto.
- `integration_test/stream_recovery_test.dart` en Windows: cuatro pruebas nativas aprobadas. Audio HTTP de 130 s todavía activo después de 122 s, una sola finalización al llegar al EOF; respuesta truncada con duración declarada mayor y pausa sin avanzar la cola.
- `integration_test/stream_online_continuity_test.dart`: YouTube HTTPS real (`M7lc1UVf-VE`) reprodujo 130 s sin errores ni finalización anticipada. Activar con `AURORA_ONLINE_SMOKE=true`, `AURORA_TOOLS` y `AURORA_SAMPLE_URL`.
- Android release x86_64: cierre reproducido al buscar «musica» en API 36.1. R8 había optimizado clases ZIP de Commons Compress utilizadas mediante reflexión. Reglas específicas conservan sus constructores; los errores de enlace se devuelven al canal Flutter.
- APK release corregido: búsquedas «musica», «piano» y enlace directo devolvieron resultados; mismo proceso vivo y ningún error fatal. Un 403 posterior se resolvió en la prueba actualizando el yt-dlp empaquetado a 2026.08.19 con EJS 0.8.0. Se verificó la actualización sobre una instalación existente: reproducción de 157 s, misma canción y duración de 22:24, sin error. Evidencias: `build/android-online-release-continuity-ui.xml` y `build/android-updated-ytdlp-runtime.log`. La ejecución fue en emulador x86_64; los teléfonos físicos siguen pendientes.
- Windows: el video reportado (`dkjCa1uhh_A`) pasó 130 s de reproducción silenciosa. Una segunda prueba partió de 45.994 s, reprodujo otros 130 s y verificó una sola finalización tras buscar los últimos tres segundos. No se reprodujo el corte concreto del usuario; el margen del contador no se considera su causa demostrada.
- Evidencias: `build/runtime-final-unit-tests.log`, `build/runtime-final-analyze.log`, `build/stream-recovery-native.log`, `build/stream-online-continuity-native.log`, `build/stream-user-resume-eof-native.log`, `build/android-search-crash.log`, `build/android-search-fixed.log` y `build/android-search-fixed-ui.xml`.

## Matriz de dispositivos pendiente

## Cambios y comprobaciones de 1.0.2+3

- `flutter analyze`: sin incidencias; `flutter test`: 107 pruebas aprobadas. Incluyen reintentos automáticos sin una segunda notificación manual, pausa durante resolución y espera, conservación de posición/aparición de la cola, duración redondeada y rechazo de truncamientos reales.
- Windows, canción reportada `__qvPGatwus` (Ado): el acceso directo FFmpeg devolvió HTTP 403 en la prueba inicial, mientras yt-dlp descargó 2 942 234 bytes y ffprobe midió 187.981 s. La prueba nativa silenciosa reprodujo toda la canción hasta una única finalización natural; después verificó saltos rápidos y que una pausa durante un salto prevalezca. No se afirma que el 403 inicial demuestre la causa exacta del corte observado a 02:05.
- Caché Windows: publicación tras finalizar yt-dlp y validar audio/duración, rutas privadas restringidas, límite de 512 MB, limpieza automática y manual que protege el archivo cargado. Pruebas cubren duración incompleta, cancelación durante ffprobe, archivos ajenos, enlaces y conservación de reproducción/biblioteca. Una comprobación nativa adicional reprodujo y buscó el EOF usando un ID estable de una canción importada de Spotify.
- Spotify: JSON de playlists y CSV, selección/cancelación, orden y repeticiones, persistencia de metadatos, elección explícita de YouTube y errores de guardado. Diálogos probados a 320 dp con texto al 200 %. La importación no utiliza la API de Spotify y no transfiere audio, credenciales ni historial de escucha.
- Interfaz nativa Windows: navegación, biblioteca con Me gusta/listas, temas, vinilo, descargas, cola, letras y vista previa Spotify a 1440×900 y 390×844. Capturas con datos de prueba; paleta Morado inspeccionada visualmente. La selección manual de paleta prevalece sobre extracciones de portada pendientes.
- Evidencias locales: `build/aurora-102-final-unit.log`, `build/aurora-102-final-analyze.log`, `build/aurora-102-ado-full-native.log`, `build/aurora-102-native-imported-cache.log`, `build/aurora-102-native-truncation-pause.log` y `build/aurora-102-final-ui-native.log`.

La matriz física de auriculares y teléfonos sigue pendiente. Las comprobaciones de paquetes release se registran al terminar su compilación; no se deducen de pruebas con audio simulado.

### Distribución sincronizada 1.0.1+2

Android ARM64: `dist/actualizado/Aurora-Android-arm64-release.apk`; manifest 1.0.1, código 2, `debuggable=false`, firma privada v2, 265 ELF alineados a 16 KB y hash del recurso yt-dlp verificado dentro del APK. Windows: `dist/actualizado/Aurora-Windows-20261011-155409-b1fdc9cc.zip`; ejecutable 1.0.1+2, motor Flutter release verificado y arranque independiente aprobado. Ambos se compilaron secuencialmente desde el mismo código y usan yt-dlp 2026.08.19. Sus SHA-256 acompañan los paquetes. Logs finales: `build/android-final-synchronized-build.log`, `build/android-final-synchronized-signature.log`, `build/android-final-synchronized-alignment.log`, `build/windows-final-synchronized-build.log` y `build/windows-final-synchronized-package.log`.

## Comprobaciones de 1.0.3+4

- Verificación integrada: `flutter test --no-pub`, 163 pruebas aprobadas; `flutter analyze --no-pub`, sin incidencias. Evidencias: `build/aurora-103-final-unit.log` y `build/aurora-103-final-analyze.log`.
- Letras: prueba nativa Windows a 1440×900 y 390×844. Tocar versos avanza/retrocede sin pausar, el volumen responde y **Volver** cierra la vista. Captura: `build/screenshots/aurora-103-mobile-lyrics.png`; log: `build/aurora-103-final-native-ui.log`.
- Saturación: regresión offline sobre SoLoud real, sin salida audible. Desactivar `CLIP_ROUNDOFF` redujo el error RMS del seno de 440 Hz de 0.077386 a 0.000000 respecto a la referencia de baja ganancia. Con refuerzos de EQ y preamplificación preventiva, no hubo muestras recortadas; la transición previa recortaba 5389. Evidencia: `build/aurora-103-offline-pcm.log`, reproducible con `scripts/run_so_loud_pcm_regression.ps1`. Esto verifica el DSP, no todos los altavoces o auriculares.
- Motor Windows: reloj, pausa, seek, FFT, EQ real, reposición de buffers y cancelación de cambios rápidos, comprobados en `build/aurora-103-native-audio.log`.
- Regresión nativa final: `build/aurora-103-final-native-audio.log`, dos pruebas aprobadas y soak opcional omitido. Un decodificador que termina correctamente con una validación de descarga fallida genera error y cero eventos de finalización.
- Android, emulador API 36.1 x86_64: búsqueda real de Ado (`__qvPGatwus`), resolución a archivo privado completo, reproducción silenciosa de 130 s sin errores ni finalización anticipada y seek a los últimos tres segundos hasta una única finalización natural. La prueba nativa pasó; `build/aurora-103-android-native-cache.log`. La primera instalación se reintentó automáticamente por falta de espacio del emulador. Esta prueba usa una compilación de integración; el APK distribuido se compila y firma en release por separado.
- Descarga progresiva: FFmpeg empaquetado decodificó un WebM Opus de 12 s mientras se escribían bloques de 4096 bytes cada 130 ms. Produjo PCM antes de completar la descarga y terminó con 576000 frames estéreo y salida 0. Evidencia: `build/aurora-103-progressive-native-ffmpeg.log`. Esta prueba controlada verifica el relé local; las restricciones de YouTube siguen dependiendo del proveedor.
- Prueba reproducible final `scripts/progressive_audio_smoke.dart`: PCM antes de completar la descarga y saltos hacia adelante/atrás con 576000, 144048 y 528048 frames, sin EOF falso. Evidencia: `build/aurora-103-progressive-final-smoke.log`. El modo progresivo en Android no se comprobó en un teléfono físico.
- El DJ es determinista y no usa voz. Las pruebas cubren preferencias, diversidad, límites de descubrimiento, cancelación de resultados antiguos y conservación de canción/posición/pausa al activarlo con recomendaciones ya presentes en la cola.
- Distribuciones finales: `dist/aurora-1.0.3/Aurora-Windows.zip` y `Aurora-Android-arm64-release.apk`, ambos 1.0.3+4. Windows verifica la DLL del motor release y los hashes de herramientas; su archivo no contiene biblioteca, audio personal, cookies ni caché. Android: código 4, `debuggable=false`, firma v2 con la clave existente, recurso yt-dlp fijado por SHA-256 y 265 ELF ARM64 alineados a 16 KB. Evidencias: `build/aurora-103-windows-release-build.log`, `build/aurora-103-windows-package.log`, `build/aurora-103-android-release-build.log`, `build/aurora-103-android-signature.log` y `build/aurora-103-android-alignment.log`. Cada paquete tiene un archivo `.sha256`.

### Comprobaciones físicas

En un teléfono real y en Windows, comprobar con un archivo local y una fuente online disponible:

- Auriculares cableados, USB y Bluetooth: reproducción, pausa, controles, cambios de salida y desconexión sin reproducción inesperada.
- Android: pantalla bloqueada, segundo plano, llamada entrante, pérdida/recuperación de foco, restricciones de batería y notificación multimedia.
- Windows: controles SMTC/teclas multimedia, cambio de dispositivo predeterminado y suspensión/reanudación.
- Descarga: pérdida de red, poco espacio, cancelación, reinicio de app y reproducción completamente sin conexión.
- Teléfono con páginas de 16 KB: instalación, arranque, extracción, seek y reproducción; revisar también alineación ELF y ZIP del APK.
- Distribución: instalar APK firmado con clave privada; verificar actualización conservando biblioteca. Extraer ZIP Windows en equipo limpio y ejecutar diagnóstico sin Python instalado.

No se declara compatibilidad universal con modelos de auriculares ni certificación de hardware a partir de estas pruebas automatizadas.

## Verificación integrada del 12 de octubre de 2026

- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub`: **269 pruebas aprobadas**, incluyendo metadatos simulados, recomendaciones/filtros/deduplicación, gestos DJ, carruseles, Jam LAN/reconexión/permisos/sincronía, paneles y navegación persistente. Log: `build/aurora-final-integrated-tests.log`.
- Windows release: `build/windows/x64/runner/Release/aurora_music.exe`. Log: `build/design-final-windows-build.log`.
- Android ARM64 debug y release: `build/app/outputs/flutter-apk/app-debug.apk` y `app-release.apk`; logs `build/design-android-debug-build.log` y `build/design-final-android-release-build.log`.
- APK release: `apksigner verify` aprobado, `debuggable=false` y **268 ELF ARM64** con segmentos LOAD de al menos 16 KB; ZIP también alineado. Log: `build/design-android-alignment.log`.
- `scripts/test_ci_android_signing.ps1`: secretos ausentes, Base64 inválido, restauración, ACL y limpieza idempotente aprobados. Los cuatro Repository Secrets reales Android están configurados; se conserva la identidad existente.
- Los workflows YAML conservan las traducciones remotas y la licencia MIT añadida por el propietario. La referencia del alias se corrigió a `secrets.ANDROID_KEY_ALIAS`; firma segura, limpieza y artefactos se mantienen. Las traducciones no sustituyen los controles de seguridad.
- Capturas Flutter completas y offline en `build/ui-review/design_idea_shell/`: Inicio a 1286×1029, 1300×1029, 1286×1600 y 320×800 con texto al 200 %. Descargas y Letras: `build/ui-review/studio-*.png`. No son fondos del producto.
- Los siete originales de `diseñoidea/` coinciden con el ZIP suministrado. No hubo migración de base de datos.
- Cámara, sesiones entre dispositivos físicos, sincronía audible, controles Win32, Bluetooth y páginas de 16 KB en un teléfono requieren comprobación manual. Las pruebas automatizadas y compilaciones no certifican estos escenarios.
