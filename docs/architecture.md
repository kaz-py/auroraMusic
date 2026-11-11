# Organización de Aurora

Aurora usa Flutter/Dart para Windows x64 y Android. Las mejoras conservan el
esquema SQLite versión 1, la biblioteca existente y los proveedores de audio.
La interfaz del Atelier Sonoro se reconstruye con widgets nativos de Flutter;
los HTML de referencia no se ejecutan dentro de un WebView.

```text
lib/
  main.dart                         Arranque, dependencias y tema compartido
  app_controller.dart               Estado personal, cola, reproducción y persistencia
  core/                             Track, playlists, contratos y controles de ventana
  audio/                            motor Rust (Symphonia + CPAL), EQ/FFT y controles multimedia
  sources/                          InnerTube (búsqueda), yt-dlp (descargas)
  library/
    library_database.dart           SQLite: biblioteca, favoritos, listas e historial
    local_file_metadata.dart        Tamaño y formato de archivos conocidos
  import/                           Lectura local de exportaciones JSON/CSV de Spotify
  metadata/spotify/                 Autenticación, Pathfinder, mapeo, caché y navegación
  dj/
    ai_dj.dart                      DJ IA local: vectores 256-d, perfil de gustos, MMR
    recommendations.dart            Puntuación, filtros, razones e identidad de canciones
    discovery_controller.dart       Elecciones de tarjetas durante la sesión del DJ
  jam/
    jam_models.dart                 Metadatos públicos, permisos, invitaciones y validación
    jam_service.dart                Servidor/cliente LAN, autoridad, cola y reconexión
    jam_controller.dart             Acciones y estado de la función Jam
    jam_playback_bridge.dart        Audio temporal, reloj, desfase y restauración personal
    jam_qr.dart                     Lectura de imágenes QR con límites de tamaño
  lyrics/                           Consulta, caché y modelos de letras
  ui/
    aurora_shell.dart               Navegación adaptable y conexión con controladores
    home_music_page.dart            Inicio con datos reales y secciones musicales
    horizontal_music_row.dart       Carruseles con tacto, rueda y controles de escritorio
    dj_discovery_page.dart          Tarjetas del DJ, gestos y botones equivalentes
    lyrics_panel.dart              Texto sincronizado, modos, tipografía y offset
    studio/                        Componentes del Atelier Sonoro
      studio_components.dart        Paneles y etiquetas del diseño
      studio_symbols.dart           Iconos de la fuente local
      studio_navigation.dart        Cabecera, barra lateral y acciones de ventana
      studio_transport.dart         Controles persistentes de audio personal
      home_introduction.dart        Cabecera editorial y fundas de discos
      session_aside.dart            Estado Jam, próximos temas y ecualizador real
      downloads_studio_page.dart    Descargas y archivo local, tabla/tarjetas adaptables
    jam/                            Conexión, sesión, QR y cámara bajo demanda
assets/
  design_idea/                      20 imágenes originales de referencia y sources.json
  fonts/                            Newsreader, Plus Jakarta Sans, símbolos y licencias
third_party/nuclear_spotify/         AGPL y atribución de la adaptación de metadatos
android/app/src/main/kotlin/         Audio e integración nativa Android
windows/                            Runner, audio y controles de ventana Windows
test/                               Pruebas unitarias, widgets y protocolo LAN simulado
integration_test/                   Comprobaciones con aplicación y audio nativos
scripts/                            Preparación, empaquetado, herramientas y firma de CI
docs/                               Arquitectura, diseño, funciones y validaciones
```

## Responsabilidades y dependencias

La navegación y los widgets reciben acciones del controlador; la lógica del DJ
permanece en `dj/`, y el acceso a archivos conocidos en `library/`. No se duplican
los importadores ni el motor de reproducción para construir las nuevas pantallas.
`AppController` sigue coordinando el estado personal; la base de datos y los
proveedores no dependen de los widgets. `WindowControls` encapsula el canal nativo
para arrastrar, minimizar, maximizar y cerrar la ventana.

Spotify se mantiene separado de `sources/`: aporta canciones, artistas, álbumes,
playlists y portadas. Antes de encolar metadatos, el usuario elige una coincidencia
de un proveedor de audio existente. Las referencias Spotify se conservan para
reconocer duplicados, pero no se usan como entradas de audio.

Jam tiene su propio controlador y servidor/cliente WebSocket, sin base de datos
ni cola personal duplicada. El anfitrión valida las acciones y conserva la cola
común en memoria. El puente de reproducción utiliza los contratos de audio y
fuentes; `beginJamPlayback`/`endJamPlayback` aíslan los eventos del reproductor
personal mientras dura el audio compartido. Al salir se conserva la cola personal
actual, incluidas las ediciones realizadas durante la sesión. El QR y la cámara
se crean únicamente cuando se activa la función correspondiente.

El relay progresivo de `sources/` usa loopback para decodificar audio localmente;
no se reutiliza como servidor Jam ni se comparte entre dispositivos. Jam abre
solo una interfaz IPv4 privada elegida y transmite metadatos públicos y estado,
nunca entradas extraídas, archivos, rutas locales o credenciales de proveedores.

## Persistencia y señales disponibles

SQLite conserva biblioteca, favoritos, playlists e historial. El historial guarda
la última reproducción de cada canción y consulta hasta 100 identificadores; no
aporta frecuencia, finalizaciones ni eventos de salto. Los gestos de omisión del
DJ son elecciones temporales de tarjetas, no estadísticas de reproducción.
Aceptar una tarjeta guarda un favorito y encola mediante los métodos existentes.

Los filtros del DJ se guardan en preferencias. `Track.genres` conserva únicamente
géneros explícitos de los datos; las canciones anteriores usan una lista vacía.
No se infieren géneros desde nombres ni se migra el esquema de la base de datos.
Las sesiones Jam, sus participantes, tokens y cola común permanecen en memoria.

## Motor de audio v1.1.0

`InnerTubeSource` busca en YouTube Music (canciones, álbumes, artistas, vídeos; continuación y recientes) y resuelve cada canción con `StreamOrchestrator` (endpoint `player`, cliente VISIONOS) a una URL de un proxy de bucle local (`AudioProxy`) que reproducen `AndroidMusicAudio`/Media3 o `RustMusicAudio` (Symphonia + CPAL); los archivos locales van directos al mismo motor. No hay reproductor web ni respaldo: si la resolución falla, se muestra el error de reproducción. yt-dlp solo descarga. Detalle en [youtube_music_audio_engine.md](youtube_music_audio_engine.md). El DJ (`lib/dj/ai_dj.dart`) guarda `track_vectors` y `taste_profile` en SQLite y no usa recomendaciones de YouTube; detalles en [dj.md](dj.md).

Consulta [diseño implementado](design_idea_implementation.md),
[DJ y sus señales](dj.md), [metadatos Spotify](spotify_metadata.md),
[Jam](jam.md) y [firma/CI](ci_signing.md).
