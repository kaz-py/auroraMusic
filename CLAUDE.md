# Aurora Music — guía para Claude

Rama de trabajo: **`rust-migration`** de `github.com/kaz-py/auroraMusic` (última
versión: `v1.6.0-beta.10`, `pubspec.yaml` 1.6.0-beta.10+29). No trabajar en ramas
antiguas (`rust-migration-1.4.0`, `integracion-1.5.0`) salvo petición expresa.

Lee también `AGENTS.md` (estilo, comandos, pruebas). Estado de la migración a Rust:
`MIGRATION_AUDIT.md` (lo hecho y medido) y `MIGRATION_PENDIENTES.md` (lista viva de lo
que falta, con motivo). Decisión del usuario (15/10/2026, revisada): el audio de
YouTube se resuelve por InnerTube `player` (cliente VISIONOS, como LIMusic) y suena en
el motor nativo a través de un proxy local. No hay reproductor web ni respaldo: si
falla, se muestra el error real.

## Qué es

Reproductor Flutter + Rust (Windows x64, Android ARM64, Linux x64) con cuatro temas
propios: Atelier (papel y tinta), Modern (cristal, por defecto), Brasa (oscuro con
brasa) y Slush (pegatinas). Diseño vigente en `docs/temas.md` (rediseño
1.6.0-beta.6). Funcionamiento de referencia: LIMusic (búsqueda de YouTube Music,
radio/autoplay, cola nativa), con la interfaz de Aurora. Cada tema se cambia solo en
sus archivos; respetar la zona segura en móvil.

## Arquitectura Flutter + Rust

- Puente: `flutter_rust_bridge` 2.13.0 (misma versión en `pubspec.yaml`,
  `rust/Cargo.toml` y `flutter_rust_bridge_codegen`). API en `rust/src/api/*.rs`
  (audio, cache, crash, database, dj, lyrics_align, media, playback, sources, voice) →
  Dart generado en `lib/bridge/`. Tras cambiar `rust/src/api/`, regenerar con
  `flutter_rust_bridge_codegen generate`. `rust_builder/` (cargokit) compila el crate
  con la app.
- Crates (`rust/crates/`):
  - `aurora_database`: SQLite de la biblioteca (sustituye a drift; el JSON de pistas pasa tal cual).
  - `aurora_ai_dj`: vectores, perfil de gustos y MMR del DJ (pruebas de oro contra la versión Dart).
  - `aurora_audio`: EQ paramétrico, barras de espectro y regla de fin de flujo.
  - `aurora_playback`: reproductor de escritorio (Symphonia + libopus → CPAL).
  - `aurora_cache`: poda LRU de cachés.
  - `aurora_sources`: analizadores de respuestas InnerTube (sin red).
  - `aurora_voice`: Whisper local (whisper.cpp) para comandos «Aurora…» y alineación de letras.
- Sigue en Dart: orquestador de streams, proxy local, cliente InnerTube con red
  (medido: portarlo no mejora la latencia), ejecutor de yt-dlp, Jam, sincronización,
  cola y `app_controller.dart`.

## Motor de audio (actual)

- Búsqueda: `lib/sources/innertube_source.dart` (InnerTube WEB_REMIX: canciones,
  álbumes, artistas, vídeos, continuación). No volver a la búsqueda por DOM.
- Resolución YouTube: `lib/sources/stream/`. `StreamOrchestrator` pide `player` con la
  tabla de `player_clients.dart` (hoy solo VISIONOS: URLs directas sin cifrado ni PO).
  Elige el audio (prefiere Opus 251), lo valida con una petición al final del archivo,
  marca los clientes fallidos con TTL y re-resuelve ante 403 o expiración. `AudioProxy`
  sirve `http://127.0.0.1:<puerto>/…` y pide al CDN trozos acotados de 4 MiB.
  `InnerTubeSource.resolve()` devuelve esa URL. Ante un fallo reintenta una vez y, si
  vuelve a fallar, lanza el error real.
- Motores, elegidos en `lib/main.dart`:
  - Android: `AndroidMusicAudio` (Media3, servicio).
  - Escritorio (Windows y Linux): `RustMusicAudio` (`lib/audio/rust_music_audio.dart` →
    `aurora_playback`), con EQ y espectro.
  - SoLoud y FFmpeg ya no existen en escritorio. FFmpeg solo queda en Android, dentro de
    `youtubedl-android`, para descargas y caché en MP3.
- `lib/audio/stream_guard.dart` impide que una URL de YouTube/googlevideo llegue al
  decodificador o a Media3 sin pasar por el proxy. Sigue en Dart a propósito.
- Android: `network_security_config.xml` permite texto claro solo a `127.0.0.1`.
- Comprobación manual del cliente: `dart run tool/probe_innertube_clients.dart <id>`.
- **Permitido** (decisión del usuario): InnerTube `player` imitando los clientes de la
  tabla y extraer URLs de audio para el proxy.
- **Prohibido**:
  - tokens PO/BotGuard;
  - descifrar firmas/`n`;
  - saltarse restricciones del sitio (p. ej. funciones de Premium);
  - que una URL de YouTube/googlevideo llegue al decodificador Rust o a Media3 sin el proxy.
- LIMusic es GPL: solo sirve de referencia de comportamiento; no copiar su código ni
  sus archivos de configuración.
- yt-dlp: solo para descargas explícitas (audio y vídeo) e importación de listas
  (`lib/sources/yt_dlp_source.dart`). En escritorio las descargas se guardan en Opus o
  M4A tal cual. En Linux, yt-dlp sale del `PATH` o de `tools/yt-dlp`.
- Detalle: `docs/youtube_music_audio_engine.md`, `docs/progressive_playback.md`.

## Módulos

- DJ: `lib/dj/` sobre `aurora_ai_dj`. IA propia y local: perfil de gustos y ranking
  por similitud + diversidad (MMR). **Permitido** (decisión del usuario, 17/10/2026):
  usar también como fuentes de candidatos las recomendaciones de YouTube
  (radio/relacionadas de InnerTube `next`, sin API key ni tokens PO) y los metadatos
  de Spotify emparejados a YouTube.
  - El perfil local manda en el ranking.
  - Todo candidato pasa por el filtro de coherencia de artista y la memoria anti-repetición.
  - Si YouTube falla, el DJ sigue con lo local.
  - La cola nunca termina y el DJ no se apaga solo.
- Last.fm (`lib/lastfm/`): **permitido** (decisión del usuario, 2026-10-24). Sirve para
  tres cosas: scrobbling opcional, candidatos del DJ (`track.getSimilar`/`artist.getSimilar`)
  y estadísticas del Perfil.
  - Cada usuario conecta su propia cuenta. Usuario y contraseña solo se usan para
    `auth.getMobileSession`.
  - Solo se guarda la clave de sesión, en almacenamiento seguro. Nunca la contraseña,
    y nada en logs.
  - Desactivado por defecto. Clave y secreto por
    `--dart-define=AURORA_LASTFM_API_KEY/AURORA_LASTFM_SECRET`; sin ellos queda apagado.
- Servicios en línea (Supabase): **apagados** con `kSupabaseEnabled = false` en
  `lib/core/feature_flags.dart` (ver `docs/servicios_en_linea.md`). Sin ellos funcionan
  la reproducción, la biblioteca, el DJ, las letras, la Jam por red local y la
  transferencia por QR. Cuando están encendidos:
  - Cuentas (`lib/account/`): correo + contraseña + usuario, sincronización LWW
    (SQL: `docs/accounts_supabase.sql`).
  - Amigos (`lib/friends/`): solo entre amigos aceptados, con RLS
    (SQL: `docs/friends_supabase.sql`).
  - Jam en línea (`docs/jam_supabase.sql`).
- Jam (`lib/jam/`, `docs/jam.md`): por defecto en red local con código QR. La cola de la
  Jam empieza vacía, sin sugerencias automáticas.
- Voz y letras (`lib/voice/`, `lib/lyrics/`): Whisper local en Windows y Linux; el audio
  no sale del equipo (`docs/voice_commands.md`, `docs/letras.md`).
- Importación (`lib/import/`, `docs/spotify_metadata.md`), artistas seguidos
  (`lib/follow/`), control remoto (`lib/remote/`) y plugin de Stream Deck
  (`streamdeck/`, `docs/stream_deck.md`).
- Discord (`lib/discord/`) y Duvet (`lib/core/duvet_presence.dart`): Rich Presence en
  Windows (named pipe) y Linux (socket Unix). Discord necesita `AURORA_DISCORD_CLIENT_ID`.
- Logo: `lib/ui/brand/aurora_logo.dart`.

## Comandos (PowerShell, Windows)

```powershell
$flutter = 'C:/flutter/flutter/bin/flutter.bat'
& $flutter pub get            # si falla por symlinks: scripts/prepare_windows_plugins.ps1
cargo build --release --manifest-path rust/Cargo.toml   # antes de flutter test (whisper.cpp: CMake + LLVM/LIBCLANG_PATH)
cargo test --manifest-path rust/Cargo.toml --workspace
& $flutter analyze
& $flutter test               # carga rust/target/release/rust_lib_aurora_music.dll (.so en Linux)
C:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe format lib test
& $flutter build apk --release
& $flutter build windows --release
```

Linux: compilar en Ubuntu/WSL con Flutter 3.38.8 para Linux, Rust y las dependencias
de apt del README (`libasound2-dev` para CPAL). Comando: `flutter build linux --release`,
que deja el paquete en `build/linux/x64/release/bundle`.

Instalación para usuarios: `scripts/linux/get.sh`, en una línea con curl. Instala las
bibliotecas y yt-dlp, comprueba el SHA-256 y elige la versión más alta. Detalle y
paquetes .deb en `docs/LINUX.md`.

En Linux no hay controles multimedia (audio_service/MPRIS) ni actualizador. La bandeja es
nativa (`linux/runner/tray_linux.cc`: GTK y libayatana-appindicator3 cargada con
`dlopen`) y usa el mismo canal `aurora/window` que Windows; sin bandeja, la X cierra.

## Reglas

- Nunca commitear ni imprimir claves, tokens, cookies, keystores ni `key.properties`.
  InnerTube se usa sin clave de API.
- `diseñoidea/`, `.agents/`, `skills-lock.json` y `DESIGN.md` son del usuario:
  no borrarlos ni incluirlos en commits salvo que lo pida.
- No hacer reset/clean/stash destructivo; puede haber trabajo sin confirmar.
- Mensajes de commit cortos en imperativo; `[skip ci]` si no debe correr CI.
  **Dar crédito a Claude como coautor**: cada commit (y cada PR) termina con la
  línea `Co-Authored-By: Claude <noreply@anthropic.com>` tras una línea en blanco.
- No afirmar reproducción real basándose solo en tests simulados.
- Al terminar o aplazar algo de la migración, actualizar `MIGRATION_PENDIENTES.md`.

## Consultas sobre el código (graphify)

Para cualquier pregunta sobre el código, su arquitectura o la relación entre
archivos, usa primero el skill `graphify` antes de recorrer el árbol con Grep/Read. El
grafo está en `graphify-out/` (ignorado por git) y ofrece consulta, camino y
explicación de nodos. Si falta o está viejo, regénralo con el skill (`--update` para
lo cambiado). Aplica también a los subagentes.

## Trabajo con subagentes

El agente principal orquesta: reparte tareas por áreas con dueños de archivos
claros (worktrees separados), integra, ejecuta analyze/test y builds, y hace el
commit final. Opus para motor/algoritmos; Sonnet para revisión, docs y builds.
