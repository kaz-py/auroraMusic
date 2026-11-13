# Aurora Music — guía para Claude

Lee también `AGENTS.md` (estilo, comandos) y `DESIGN.md` (estética). Este archivo
manda sobre `RETOMAR_AURORA.md` cuando se contradicen. Decisión del usuario
(15/10/2026, revisada): el audio de YouTube se resuelve por InnerTube `player`
(cliente VISIONOS, como LIMusic) y suena en el motor nativo a través de un proxy
local. No hay reproductor web ni respaldo: si falla, se muestra el error real.

## Qué es

Reproductor Flutter (Windows + Android + Linux) con cuatro temas propios: Atelier
(papel y tinta), Modern (cristal), Brasa (oscuro con brasa) y Slush (pegatinas).
Su diseño vigente está en `docs/temas.md` y en los prototipos de
`Aurora-prototipos/<tema>/DISENO.md` (rediseño 1.6.0-beta.6). Funcionamiento de
referencia: LIMusic (búsqueda de YouTube Music, radio/autoplay, cola nativa), con
la interfaz de Aurora. Cada tema se cambia solo en sus archivos; respetar la
zona segura en móvil.

## Motor de audio (actual)

- Búsqueda: `lib/sources/innertube_source.dart` (InnerTube WEB_REMIX: canciones,
  álbumes, artistas, vídeos, continuación). No volver a la búsqueda por DOM.
- Resolución YouTube: `lib/sources/stream/` — `StreamOrchestrator` pide `player`
  con la tabla de clientes de `player_clients.dart` (VISIONOS: URLs directas sin
  cifrado ni PO), elige audio, valida con una petición al final del archivo,
  marca clientes fallidos con TTL y re-resuelve ante 403/expiración.
  `AudioProxy` sirve `http://127.0.0.1:<puerto>/…` y pide al CDN trozos acotados
  de 4 MiB. `InnerTubeSource.resolve()` devuelve esa URL; ante un fallo reintenta
  una vez la resolución nativa y, si vuelve a fallar, lanza el error real.
- Motores: Android `AndroidMusicAudio` (Media3, servicio), escritorio `RustMusicAudio`
  (`rust/crates/aurora_playback`: Symphonia + CPAL) con EQ/espectro, elegidos en
  `main.dart`. `lib/audio/stream_guard.dart` impide que
  una URL de YouTube/googlevideo llegue al decodificador/Media3 sin pasar por el proxy.
- Android: `network_security_config.xml` permite texto claro solo a `127.0.0.1`.
- Comprobación manual del cliente: `dart run tool/probe_innertube_clients.dart <id>`.
- **Permitido** (decisión del usuario): InnerTube `player` imitando clientes de la
  tabla y extraer URLs de audio para el proxy.
- **Prohibido**: tokens PO/BotGuard, descifrar firmas/`n`, saltarse restricciones
  del sitio (p. ej. funciones de Premium), y que una URL de YouTube/googlevideo
  llegue a FFmpeg/Media3 sin el proxy. LIMusic es GPL: solo referencia de
  comportamiento, no copiar su código ni sus archivos de configuración.
- yt-dlp: solo descargas explícitas (audio y vídeo) e importación de listas.
- DJ: `lib/dj/` — IA propia y local: base de datos vectorial (drift/SQLite) con
  embeddings de pistas y perfil de gustos del usuario; ranking por similitud +
  diversidad (MMR). **Permitido** (decisión del usuario, 17/10/2026): usar también
  las recomendaciones de YouTube (radio/relacionadas de InnerTube `next`, sin API key
  ni tokens PO) y metadatos de Spotify emparejados a YouTube como fuentes de
  candidatos. El perfil local manda en el ranking; todo candidato pasa por el filtro
  de coherencia de artista y la memoria anti-repetición, y si YouTube falla el DJ
  sigue con lo local. La cola nunca termina y el DJ no se apaga solo.
- Last.fm (`lib/lastfm/`): **permitido** (decisión del usuario, 2026-10-24; sustituye
  a la integración anterior de scrobbling) como scrobbling opcional donde cada usuario
  conecta su propia cuenta (usuario y contraseña solo para `auth.getMobileSession`; se
  guarda únicamente la clave de sesión en almacenamiento seguro; nunca la contraseña ni
  nada en logs; desactivado por defecto) y como fuente de candidatos del DJ
  (`track.getSimilar`/`artist.getSimilar`) y estadísticas del Perfil. La clave y el
  secreto de la app van por `--dart-define=AURORA_LASTFM_API_KEY/AURORA_LASTFM_SECRET`;
  sin ellos la función queda desactivada.
- Cuentas (`lib/account/`, decisión del usuario 2026-10-24): Supabase con correo +
  contraseña + usuario, sesión en almacenamiento seguro, avatar genérico hasta subir foto
  (la foto anterior se borra del bucket `avatars`). Sincroniza me gusta, playlists,
  historial y perfil de gustos (LWW por `updated_at`). SQL: `docs/accounts_supabase.sql`.
- Amigos (`lib/friends/`): solicitudes por usuario y canciones compartidas a una bandeja
  en tiempo real; RLS solo entre amigos aceptados. SQL: `docs/friends_supabase.sql`.
- Discord (`lib/discord/`): Rich Presence solo en Windows por named pipe
  (`AURORA_DISCORD_CLIENT_ID`). Tema por defecto: Modern. Logo: `lib/ui/brand/aurora_logo.dart`.
- Detalle: `docs/youtube_music_audio_engine.md`.

## Comandos (PowerShell, Windows)

```powershell
$flutter = 'C:/flutter/flutter/bin/flutter.bat'
& $flutter pub get            # si falla por symlinks: scripts/prepare_windows_plugins.ps1
& $flutter analyze
& $flutter test
C:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe format lib test
& $flutter build apk --release
& $flutter build windows --release
```

Linux (en Ubuntu/WSL, con Flutter 3.38.8 para Linux y las dependencias de apt
del README): `flutter build linux --release` → `build/linux/x64/release/bundle`.
En Linux no hay audio_service/MPRIS, bandeja ni actualizador; yt-dlp sale
del `PATH` o de la carpeta de Ajustes; Discord y Duvet usan socket Unix.

## Reglas

- Nunca commitear ni imprimir claves, tokens, cookies, keystores ni `key.properties`.
  InnerTube se usa sin clave de API.
- `diseñoidea/`, `.agents/`, `skills-lock.json` y `DESIGN.md` son del usuario:
  no borrarlos ni incluirlos en commits salvo que lo pida.
- No hacer reset/clean/stash destructivo; hay trabajo sin confirmar.
- Mensajes de commit cortos en imperativo; `[skip ci]` si no debe correr CI.
  **Dar crédito a Claude como coautor**: cada commit (y cada PR) termina con la
  línea `Co-Authored-By: Claude <noreply@anthropic.com>` tras una línea en blanco.
- No afirmar reproducción real basándose solo en tests simulados.

## Consultas sobre el código (graphify)

Para cualquier pregunta sobre el código, su arquitectura o la relación entre
archivos, usa primero el skill `graphify` (grafo en `graphify-out/`: consulta,
camino y explicación de nodos) antes de recorrer el árbol con Grep/Read. Si el
grafo falta o está viejo, regénralo con el skill. Aplica también a los
subagentes. Estado del trabajo pendiente: `CONTINUAR.md`.

## Trabajo con subagentes

El agente principal orquesta: reparte tareas por áreas con dueños de archivos
claros (worktrees separados), integra, ejecuta analyze/test y builds, y hace el
commit final. Opus para motor/algoritmos; Sonnet para revisión, docs y builds.
