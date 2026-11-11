# Aurora

Reproductor de música en Flutter y Dart para **Windows x64, Linux x64 y Android 7+**. Interfaz en español, biblioteca local y búsqueda de YouTube Music mediante InnerTube, con reproducción nativa de solo audio (versión 1.1.0). yt-dlp queda como respaldo de resolución y para descargas explícitas.

## Motor de audio

- **Búsqueda** en YouTube Music vía InnerTube, sin clave de API ([`innertube_source.dart`](lib/sources/innertube_source.dart)): canciones, álbumes, artistas y vídeos, con paginación y navegación de álbum/artista.
- **Reproducción nativa**: el audio de YouTube se resuelve por InnerTube y suena en el motor nativo (Android Media3; Windows y Linux, el motor Rust `aurora_playback` con Symphonia + CPAL) a través de un proxy local en `127.0.0.1` que pide trozos acotados al CDN ([`lib/sources/stream/`](lib/sources/stream/)). Sin tokens PO ni descifrado de firmas. Si YouTube bloquea una canción, se muestra el error de reproducción normal.
- **Ecualizador y espectro** en el motor nativo.
- **Avisos de amigos**: canciones, listas e invitaciones a una Jam llegan como notificación del sistema (Windows, Android, Linux) cuando Aurora está abierta pero no a la vista; con la app cerrada no llega nada (haría falta un servicio push).
- **Controles del sistema** (notificación Media3 en Android, SMTC en Windows).
- **yt-dlp** solo para descargas explícitas e importación de listas.
- **La cola nunca termina**: cuando empieza la última canción, el DJ añade canciones según tus gustos (perfil local con vectores, MMR y enfriamiento por artista), con la radio de YouTube y Last.fm como fuentes de candidatos y tu biblioteca como respaldo ([docs/dj.md](docs/dj.md)).

Detalles y límites: [docs/youtube_music_audio_engine.md](docs/youtube_music_audio_engine.md).

## Funciones

- Inicio, búsqueda, importación de enlaces/listas de YouTube y archivos locales.
- Favoritos, playlists editables, historial y cola reordenable; aleatorio, repetición, volumen, avance y temporizador.
- Importación gratuita de playlists de Spotify desde JSON/CSV local o pegando el enlace de una playlist, álbum, artista o canción públicos (sin iniciar sesión; hasta 100 canciones por lista sin cuenta), con vista previa y elección explícita de la versión en YouTube; sin configurar claves de API. Lee la página pública de incrustación de Spotify, que no es una API estable: si cambia, la importación por enlace avisa y las demás vías siguen funcionando.
- Búsqueda de canciones, artistas, álbumes y playlists de Spotify mediante el proveedor de metadatos adaptado de Nuclear, sin cuenta personal ni Premium.
- Descargas locales MP3 con progreso, cancelación, reintento y eliminación; carpeta de destino configurable en Windows y biblioteca disponible sin conexión.
- Interfaz Atelier Sonoro reconstruida en Flutter a partir de los originales de `diseñoidea/`: Newsreader normal e italic, Plus Jakarta Sans, símbolos locales y navegación adaptable.
- Biblioteca en cuadrícula, cola con vista propia y ajustes por secciones. **Modo Vinilo** gira durante la reproducción y permite desplazar la posición arrastrando el disco.
- Botón **Letras**: búsqueda exacta en LRCLIB, texto sincronizado o tradicional, caché privada e importación de archivos LRC/TXT.
- Letras interactivas: toca un verso sincronizado para avanzar o retroceder y ajusta el volumen. Buscar una posición conserva tu decisión de reproducir o pausar.
- Inicio con carruseles horizontales de datos reales; DJ de descubrimiento con gestos: izquierda omite, derecha guarda el favorito y encola.
- **Para ti** recomienda según favoritos, listas y escuchas recientes. **DJ personal**, sin voz, continúa la cola con esas preferencias; las novedades de YouTube son opcionales y se consultan con límites visibles.
- **Jam**: cola compartida en red local o en línea (Supabase), QR, permisos del anfitrión y reproducción sincronizada opcional con fuentes de audio propias.
- Colores extraídos de la portada, ambiente reactivo a la energía y visualizador FFT del audio real.
- Ecualizador DSP de ocho bandas, presets y reducción automática de ganancia para los refuerzos.
- Controles multimedia del sistema, servicio de audio Android, pausa por desconexión e interrupciones de audio.
- SQLite local; restaura cola y posición **en pausa**. Temas claro/oscuro/sistema y movimiento reducido.
- Paletas Automático, Morado, Terracota, Ámbar y Verde bosque para toda la interfaz.
- **Temas** Modern (por defecto), Atelier, Brasa y Slush, con logo propio.
- **Aleatorio** que no gasta las canciones saltadas: siguen en la cola y pueden volver a salir (nunca dos veces seguidas).
- **Mini reproductor** (Windows): ventana compacta siempre visible con portada, progreso y controles, como el Miniplayer de Spotify; se activa en Ajustes o desde el menú de la canción (clic en la portada o el título de la barra de abajo).
- **Tarjeta de acciones de la canción**: pulsación larga sobre el mini (Android) o botón ⋯ del reproductor completo; cola de reproducción, añadir a la cola, Jam, favorito, compartir, enviar a un amigo y añadir a una lista. Las filas de canciones conservan su menú.
- **Avisos** flotantes y con el mismo aspecto en los cuatro temas; se cierran solos, también los que llevan acción (Deshacer).
- Al pasar el cursor sobre la línea de progreso del mini, la zona de pulsación crece y la línea se engorda para adelantar con facilidad (en los cuatro temas).
- **Modo letra**: apartado inmersivo (portada difuminada a pantalla completa, portada grande con progreso y título, letra sincronizada y controles) que oculta la barra de abajo; se abre con **Letras**. Tiene pantalla completa (botón, **F11** y **Esc**; en Android, modo inmersivo), **Copiar letra** y respeta las barras del sistema. Sin letra muestra solo la portada, centrada, y el aviso se oculta solo. Entra siempre en el verso que suena. **Salir del modo letra** vuelve a la sección anterior.
- **Cuenta Aurora** (Supabase, gratis): correo, contraseña y nombre de usuario, foto de perfil (genérica hasta que subas una; la anterior se borra del almacenamiento). Sincroniza me gusta, playlists, historial y perfil de gustos del DJ entre dispositivos.
- **Amigos** (escritorio y Android): solicitudes por nombre de usuario; envía canciones y playlists o invita a tu Jam en línea (con una nota opcional de 200 caracteres). En móvil están en **Más vistas**, con insignia de solicitudes pendientes. La pestaña «Chats» guarda el historial de envíos con cada amigo, en los dos sentidos, con un diseño propio por tema; pulsar en cualquier parte de una fila abre su chat. Las invitaciones a Jam desaparecen a las 2 h. Llegan en tiempo real con aviso en la app.
- **Last.fm**: cada usuario conecta su cuenta para registrar lo que escucha (scrobbling), ver sus estadísticas en Perfil y alimentar el DJ. La contraseña solo se usa para iniciar sesión y no se guarda.
- **Discord y Duvet**: muestran «Escuchando Aurora Music» con canción, artista, tiempo y portada (Windows y Linux); en una Jam indica que escuchas en grupo.

Spotify aporta descripciones y portadas; el audio proviene de archivos locales y
YouTube. El DJ usa señales locales y filtros persistentes por artista, canción y
género conocido.

### Explorar Spotify y personalizar el DJ

Abre **Buscar → Metadatos · Spotify**, escribe el nombre y elige canciones,
artistas, álbumes o playlists. Las colecciones muestran sus canciones y permiten
cargar más resultados. **Añadir a la cola** abre la búsqueda de coincidencias de
YouTube: elige una fuente y confirma **Añadir a la cola** o **Reproducir**.
La cola elimina duplicados por canción, URL canónica y referencia de Spotify.

En **DJ**, desliza a la izquierda para omitir una tarjeta y a la derecha para guardar el favorito y añadirla a la cola; también hay botones equivalentes. Estas omisiones son elecciones de la sesión, no un historial de saltos de reproducción.

En **Inicio → Para ti → Personalizar el DJ**, selecciona artistas, canciones o
géneros de tu biblioteca. Las dimensiones se combinan; **Quitar filtros** las
restablece. Los géneros solo se ofrecen cuando existen en los datos. Las
recomendaciones explican sus señales y se actualizan con favoritos, playlists e
historial reciente. Los filtros afectan incorporaciones nuevas del DJ.

El método de Spotify depende de interfaces privadas que pueden cambiar. La
adaptación conserva la licencia AGPL-3.0 y sus avisos. Consulta
[metadatos](docs/spotify_metadata.md), [DJ](docs/dj.md) e
[interfaz](docs/music_ui.md) para detalles y límites.

### Compartir una Jam local

Abre **Jam → Crear Jam**, elige la dirección privada de tu Wi-Fi/Ethernet y pulsa
**Iniciar sesión local**. Aurora muestra el QR; las demás personas lo leen desde
Jam. Android permite cámara bajo demanda. Windows permite importar una imagen QR
o pegar la invitación copiada por el anfitrión.

**Cola compartida** permite agregar a todos y muestra quién eligió cada canción;
el anfitrión concede permisos para omitir, reordenar y quitar. En **Reproducción
sincronizada**, controla canción, pausa y posición; los invitados activan audio
local y cada dispositivo utiliza su propia biblioteca/proveedores. Una canción
no disponible genera un aviso sin cerrar la cola. La sincronía es aproximada.

La sesión y sus accesos son temporales, con hasta 16 identidades y 200 canciones.
No se transfieren archivos, rutas ni credenciales; la conexión LAN no está cifrada
ni se publica en Internet. Usa una red de confianza. **Reconectar** recupera la
identidad durante la sesión; **Salir/Cerrar Jam** invalida el acceso correspondiente.
La cola personal permanece separada. Consulta [Jam](docs/jam.md) para límites,
permisos de plataforma y comprobaciones físicas pendientes.

### Diseño y funciones pendientes

La [implementación del diseño original](docs/design_idea_implementation.md)
identifica los tres HTML, tres PNG, DESIGN.md y ZIP preservados, los veinte recursos
con sus URLs/hashes y las fuentes incluidas. Inicio, transporte, descargas y letras
usan datos y acciones reales. La simulación de válvulas/cinta, exportación USB,
auditoría musical CRC/Hash, respaldo y traducción siguen pendientes y se señalan
como tales en la interfaz. Las etiquetas editoriales no certifican fidelidad,
latencia ni DSP analógico.

### Encontrar descargas y letras

Abre **Descargas locales** en la navegación o desde Inicio. La ruta aparece en la página: **Cambiar carpeta** selecciona un destino para futuras descargas y **Abrir carpeta** lo abre en Explorer. Las descargas existentes conservan su ubicación; no se trasladan ni sobrescriben archivos. Espera a que terminen los trabajos activos antes de cambiarla. **Biblioteca → Archivos locales** reúne los archivos importados y descargados.

En Android, las descargas permanecen en el almacenamiento privado de Aurora; la selección de una carpeta externa aún no está implementada.

El botón **Letras** está en el reproductor inferior y en la cabecera del reproductor completo. Las letras se guardan en la caché privada: una letra guardada se abre al instante, sin esperar a la red, y solo se vuelve a consultar a los 30 días o al forzar la búsqueda. Si no está guardada, se envían título y artista a LRCLIB. Las letras sincronizadas siguen la posición de reproducción y, al entrar a mitad de canción, aparecen ya colocadas en el verso actual. No todas las pistas tienen coincidencia: puedes importar tu propio `.lrc` o `.txt` (máximo 1 MiB), cuyo original permanece intacto. Las letras guardadas funcionan sin conexión.

En escritorio, la entrada **Letras** abre el **modo letra** (el antiguo modo artista) a pantalla completa con sus propios controles. En móvil, **Más vistas** abre vinilo, cola, letras y Amigos, conservando los cuatro destinos principales. En la cola, el menú de cada pista permite quitar esa aparición sin borrar el archivo. Las referencias y la preferencia de trabajar con subagentes Luna están en [docs/design/README.md](docs/design/README.md).

## Ejecutar desde el código

Las ramas de desarrollo y pruebas usan `aurora/<cambio-o-prueba>` (por ejemplo, `aurora/corregir-cache`). Cada subagente trabaja en su propia rama y checkout; la integración y las pruebas preceden a la publicación en `main`.

Requisitos usados: Flutter 3.38.8 / Dart 3.10.7. Para Windows: Visual Studio con desarrollo de escritorio C++; para Android: SDK Android, Java 17+ y dispositivo/emulador de 64 bits. Usa el Dart incluido en Flutter.

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run -d windows --no-pub
# O selecciona un dispositivo Android:
flutter devices
flutter run -d <device-id> --no-pub
```

Si Windows impide crear los enlaces de plugins, ejecuta `./scripts/prepare_windows_plugins.ps1` después de `flutter pub get`. El script crea junctions dentro del proyecto, sin cambiar opciones del sistema.

### Linux

Instalación, compilación, requisitos y diferencias con Windows: [docs/LINUX.md](docs/LINUX.md).

### Herramientas Windows

`flutter run -d windows` y `flutter build windows` preparan automáticamente las herramientas durante la compilación: descargan las versiones fijadas si faltan, verifican sus hashes y las copian a `tools/` junto al ejecutable. Aurora las detecta sin configurar carpetas. La primera compilación necesita acceso a Internet; las siguientes reutilizan las herramientas verificadas.

```powershell
./scripts/setup_tools.ps1
```

Este comando permite prepararlas por separado. Descarga versiones oficiales verificadas de yt-dlp y Deno en `tools/windows/`, junto a hashes, versiones y licencias. `scripts/windows_tools.lock.json` fija las versiones predeterminadas. **Ajustes → Herramientas** permite un diagnóstico o una carpeta personalizada. No se ejecutan herramientas encontradas arbitrariamente en `PATH`.

Android incorpora Python, JavaScript, yt-dlp y FFmpeg mediante `youtubedl-android` 0.18.1; no necesita instalar Python. Las primeras operaciones preparan esos componentes localmente.

### Reproducción y reintentos

Las canciones de YouTube las reproduce el sitio oficial dentro de Aurora: no hay precarga ni reintentos automáticos de flujo; si el sitio no responde, Aurora muestra el motivo y basta con pulsar reproducir. Esto no evita restricciones de YouTube ni hace accesibles vídeos privados o eliminados. **Ajustes → Almacenamiento y biblioteca → Limpiar caché** conserva la canción actual y tus descargas locales.

### Importar playlists de Spotify gratis

1. Obtén el JSON de playlists con la [descarga de tus datos de Spotify](https://support.spotify.com/article/understanding-your-data/) o un CSV de canciones. Aurora admite columnas como `Track Name`, `Artist Name(s)`, `Album Name` y `Track URI`; si el CSV no tiene `PlaylistName`, usa el nombre del archivo.
2. Abre **Biblioteca → Importar de Spotify → Elegir archivo**, revisa las listas y pulsa **Importar**. Cancelar la vista previa no cambia la biblioteca.
3. Abre la lista y toca una canción pendiente para elegir su versión de YouTube. **Guardar** la vincula sin reproducir; **Guardar y reproducir** inicia el audio elegido.

Todo el archivo se procesa localmente, sin claves de API ni pagos. Se conservan los nombres, artistas, álbumes, referencias Spotify, orden y repeticiones. No se transfieren audio descargado de Spotify, credenciales ni estadísticas de escucha. El límite por archivo es 20 MB y 20 000 canciones; podcasts y archivos locales de Spotify se omiten con un aviso.

### Cuando YouTube limita solicitudes

Un HTTP 429 o una petición de verificar la sesión proviene de YouTube. Abre YouTube en tu navegador, inicia sesión y completa cualquier verificación que aparezca. Espera antes de repetir búsquedas. Aurora envía la búsqueda con Enter o la flecha, sin consultar mientras escribes ni duplicar una consulta pendiente.

Aurora no necesita cookies para reproducir. Si aun así necesitas usar tu sesión con yt-dlp (descargas), exporta **solo las cookies de YouTube** a un archivo `.txt` en formato Netscape siguiendo la [documentación oficial de yt-dlp](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies). En Aurora, abre **Ajustes → Sesión de YouTube → Importar sesión**. La app valida el archivo y guarda una copia en su carpeta privada; puedes reemplazarla o eliminarla desde esa misma sección. El archivo original permanece intacto. La sesión es opcional y no elimina un bloqueo de la dirección IP.

El archivo permite acceder a tu sesión: mantenlo privado y no lo adjuntes a incidencias ni al repositorio. Aurora no lo cifra ni lee automáticamente las credenciales del navegador. Si la sesión caduca, importa un archivo actualizado.

### Compatibilidad Android de 16 KB

La dependencia original contiene cinco bibliotecas WebP con alineación de 4 KB. Antes de distribuir un APK, prepara el parche reproducible:

```powershell
./scripts/rebuild_android_webp.ps1
```

Requiere NDK 28.2.13676358 y CMake 3.22.1 instalados en el SDK. Descarga WebP 1.6.0 desde su origen oficial, comprueba hashes y recompila las bibliotecas con alineación de 16 KB. Conserva nombres, símbolos y avisos de licencia. Gradle verifica el AAR resultante en `tools/android/`; si falta, utiliza el original y emite una advertencia. El parche y los binarios generados no se guardan en Git.

## Compilar y distribuir

```powershell
flutter build windows --release --no-pub
./scripts/package_windows.ps1
flutter build apk --debug --no-pub --target-platform android-arm64
./scripts/verify_android_alignment.ps1
```

El ZIP Windows queda en `dist/`, con herramientas verificadas y avisos de licencia. Extrae **toda** la carpeta y abre `aurora_music.exe`. El empaquetado comprueba que `flutter_windows.dll` sea la del motor release; no compiles debug y release simultáneamente sobre los mismos archivos. Si existe un paquete anterior, el nuevo recibe un nombre con fecha.

El APK de desarrollo queda en `build/app/outputs/flutter-apk/app-debug.apk`. Se instala directamente en teléfonos ARM64; autoriza la instalación desde el gestor de archivos. Es una compilación de desarrollo, firmada con la clave debug.

Para un APK optimizado, conserva la identidad de firma existente y configura
`android/key.properties` localmente con `storeFile`, `storePassword`, `keyAlias`
y `keyPassword`. Ejecuta
`flutter build apk --release --no-pub --target-platform android-arm64`.
Una compilación release sin configuración válida de firma falla expresamente.
Las claves y contraseñas están excluidas de Git. Para emuladores x64 usa
`--target-platform android-x64`.

GitHub Actions recibe los cuatro secretos Android mediante el contexto seguro,
restaura la keystore en un directorio temporal protegido y la elimina al terminar.
PR y ejecuciones manuales debug no necesitan secretos de release. Consulta
[firma y CI](docs/ci_signing.md) para nombres y configuración; no compartas claves
ni contraseñas en el chat. El ZIP Windows no tiene firma Authenticode.

## Arquitectura y seguridad

`lib/core/` define modelos y contratos; `lib/audio/` contiene el motor de escritorio (Rust) y los controles
del sistema; `lib/sources/` integra InnerTube (búsqueda) y yt-dlp (descargas); `lib/metadata/spotify/` consulta
metadatos; `lib/dj/` puntúa recomendaciones y aplica filtros; `lib/jam/` mantiene
sesiones LAN y audio temporal; `lib/ui/studio/` presenta el Atelier Sonoro; `lib/library/`
persiste la biblioteca; `lib/ui/` presenta las pantallas. `AppController`
coordina estado y reproducción. Consulta el [árbol de módulos](docs/architecture.md).

`rust/` contiene el motor en Rust (base de datos, DJ local y poda de cachés) expuesto con `flutter_rust_bridge`; compilar la aplicación requiere [rustup](https://rustup.rs), CMake y LLVM/libclang (el motor de voz compila whisper.cpp; ver [docs/voice_commands.md](docs/voice_commands.md#pruebas-y-compilación)) (la versión se fija en `rust/rust-toolchain.toml`). `flutter test` carga la biblioteca compilada, así que antes hay que ejecutar `cargo build --release --manifest-path rust/Cargo.toml`. Las pruebas del motor se lanzan con `cargo test --manifest-path rust/Cargo.toml --workspace`. En escritorio el audio local y el proxy de YouTube se decodifican y mezclan en Rust (`aurora_playback`); SoLoud y FFmpeg ya no existen: un formato que Symphonia no maneja o la falta de dispositivo de salida son errores de carga con su motivo. Las descargas de escritorio conservan el audio tal como lo sirve YouTube (Opus en Ogg o M4A, sin recodificar). Los comandos de voz («Aurora, pausa…») están descritos en [docs/voice_commands.md](docs/voice_commands.md) y el control remoto para Stream Deck en [docs/stream_deck.md](docs/stream_deck.md). Estado y hoja de ruta de la migración: [MIGRATION_AUDIT.md](MIGRATION_AUDIT.md); lo que falta, en [MIGRATION_PENDIENTES.md](MIGRATION_PENDIENTES.md).

Los procesos reciben argumentos separados, con plugins/configuración externa desactivados; entradas YouTube restringidas a HTTPS y hosts permitidos. TLS permanece verificado, salidas/colas/buffers tienen límites y las descargas se publican por renombrado desde archivos temporales. Los mensajes ocultan consultas firmadas, cookies y autorización. No se guardan URLs de reproducción temporales.

Los archivos importados y descargados se guardan en el directorio de soporte de Aurora del usuario. Limpiar caché conserva la biblioteca; eliminar una descarga requiere confirmación. La app usa la salida de audio elegida por el sistema, incluidos auriculares cableados, USB o Bluetooth; las combinaciones físicas requieren pruebas de dispositivo.

## Estado de la 1.1.0 y limitaciones

433 pruebas automáticas aprobadas y `flutter analyze` limpio. Incluye el respaldo de lectura QR por código de barras puro en Jam y pruebas de diseño móvil. **Pendiente en dispositivo real**: Android en segundo plano/pantalla apagada, Bluetooth y SMTC/teclas multimedia de Windows. El reproductor oficial oculto requiere verificación en dispositivo (segundo plano en Android, anuncios, salida limpia en Windows), YouTube puede limitar solicitudes y las duraciones de las canciones top de un artista pueden mostrarse como 0.

## Validación

Consulta [docs/VALIDATION.md](docs/VALIDATION.md) para pruebas reproducibles, resultados y comprobaciones pendientes. El 2026-10-11 pasaron búsqueda, extracción, reproducción online, descarga MP3 y reproducción local en Windows, sin importar una sesión. El día anterior YouTube devolvió HTTP 429/verificación de cuenta: estos límites pueden reaparecer y no se garantiza disponibilidad de todos los videos o redes. El audio local funciona independientemente.

## Publicar una versión

1. Sube `version:` en `pubspec.yaml` (p. ej. `1.2.0+10`) y haz commit en `main`.
2. Crea y empuja la etiqueta: `git tag v1.2.0 && git push origin v1.2.0` (`v1.2.0-beta.1` publica una pre-release, solo visible en el «Canal beta»).
3. `.github/workflows/release.yml` compila Windows (`Aurora-Setup-1.2.0.exe`, Inno Setup con `installer/aurora.iss`), Android (`Aurora-1.2.0.apk`, ARM64 firmado) y Linux (`Aurora-1.2.0-linux-x64.tar.gz`), genera `checksums.txt` (SHA-256) y crea el release con notas automáticas. Edita las notas en GitHub si quieres; la app las muestra.
4. Secretos del repositorio requeridos: `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. Para cuentas, Jam en línea, Last.fm y Discord: `AURORA_SUPABASE_URL`, `AURORA_SUPABASE_ANON_KEY` (solo la clave anónima), `AURORA_LASTFM_API_KEY`, `AURORA_LASTFM_SECRET` y `AURORA_DISCORD_CLIENT_ID`; sin ellos esas funciones aparecen como «no configurado». En local se pasan con `--dart-define-from-file` desde un `.env` que Git ignora. El SQL de Supabase está en `docs/jam_supabase.sql`, `docs/accounts_supabase.sql`, `docs/friends_supabase.sql` y `docs/friends_share_kinds.sql`. **El APK debe firmarse siempre con la misma keystore**; si cambia, Android rechaza la actualización.
5. La app consulta `releases/latest` de `kaz-py/auroraMusic` (sin token, con ETag) al iniciar, como máximo cada 6 h, y desde Ajustes → Actualizaciones. Nunca instala un archivo cuyo SHA-256 no coincida con `checksums.txt`.
