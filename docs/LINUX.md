# Aurora en Linux

Aurora funciona en Linux x64 (Ubuntu 22.04 o posterior, o una distribución equivalente).

## Instalar desde una versión publicada

Descarga desde [Releases](https://github.com/kaz-py/auroraMusic/releases) el paquete
que prefieras y `checksums.txt`. Comprueba la descarga:

```bash
sha256sum -c checksums.txt --ignore-missing
```

### Paquete .deb (Debian, Ubuntu y derivadas)

```bash
sudo apt install ./aurora-music_<versión>_amd64.deb
```

apt instala las dependencias. La app queda en `/opt/aurora-music`, se abre con
`aurora-music` y aparece en el menú de aplicaciones.

### Archivo tar.gz con install.sh (cualquier distribución)

```bash
tar -xzf Aurora-<versión>-linux-x64.tar.gz
bash Aurora-<versión>-linux-x64/install.sh
```

`install.sh` no necesita root. Copia la app a `~/.local/share/aurora-music`, crea
`~/.local/bin/aurora-music` y añade la entrada del menú y el icono. Después comprueba
las bibliotecas del sistema y, si falta alguna, dice qué paquete instalar con apt, dnf
o pacman. También avisa si falta `yt-dlp`.

Para desinstalar: `bash ~/.local/share/aurora-music/install.sh --uninstall`.

Bibliotecas del sistema que necesita la app:

```bash
sudo apt-get install libgtk-3-0 libsecret-1-0 libasound2
```

En Ubuntu 24.04, el paquete de audio se llama `libasound2t64`. Los códecs (FLAC, Opus,
Ogg, Vorbis) van incluidos en la app.

Si al abrir Aurora falta una biblioteca, la app muestra cuál es. Instálala, o usa el
.deb o `install.sh`, que comprueban las dependencias.

Para actualizar, repite estos pasos con la versión nueva. En Linux, Aurora no tiene
actualizador integrado.

## Compilar desde el código

```bash
sudo apt-get install clang cmake ninja-build pkg-config lld libgtk-3-dev liblzma-dev \
  libstdc++-12-dev libsecret-1-dev libasound2-dev
flutter pub get
flutter build linux --release
bash scripts/linux/check_bundle.sh build/linux/x64/release/bundle
```

El resultado queda en `build/linux/x64/release/bundle/`. Usa Flutter 3.38.8, la misma
versión que la CI.

Las cuentas, la Jam en línea, Last.fm y Discord necesitan claves al compilar. Guárdalas
en un archivo JSON fuera del repositorio y pásalo con
`--dart-define-from-file=<archivo>`. Usa estas variables: `AURORA_SUPABASE_URL`,
`AURORA_SUPABASE_ANON_KEY`, `AURORA_LASTFM_API_KEY`, `AURORA_LASTFM_SECRET` y
`AURORA_DISCORD_CLIENT_ID`. Nunca subas ese archivo a Git.

## Requisitos

- **Descargas**: usan `yt-dlp` del sistema (`sudo apt-get install yt-dlp`), o la
  carpeta que elijas en Ajustes. No hace falta ffmpeg: el audio se guarda tal como
  lo sirve YouTube (Opus o M4A) y la reproducción es nativa (Rust).
- **Llavero del sistema**: la sesión de tu cuenta y la de Last.fm se guardan con
  libsecret. Necesitas un llavero activo, como GNOME Keyring o KWallet.
- **Selector de archivos**: los diálogos para importar música y elegir carpetas usan
  `xdg-desktop-portal` (por ejemplo, `xdg-desktop-portal-gtk`).
- **Audio**: sale por ALSA. Con PipeWire instala `pipewire-alsa`; con PulseAudio, el
  plugin ALSA de PulseAudio.

## Diferencias con Windows

Funciona igual que en Windows:

- Búsqueda y reproducción nativa con ecualizador.
- DJ y cola continua.
- Biblioteca y descargas.
- Cuenta y sincronización.
- Amigos.
- Last.fm.
- Jam.

Discord muestra lo que escuchas si su app de escritorio está abierta, incluso en Flatpak
o Snap.

Duvet usa un socket local y busca `duvet-ipc` en `$XDG_RUNTIME_DIR`, `$TMPDIR` y
`/tmp`. Esas rutas no están confirmadas, porque no hay documentación pública de Duvet
para Linux.

En Linux no están disponibles:

- El reproductor de respaldo en WebView y la hoja «Revisar sitio». Si YouTube bloquea
  una canción, se muestra el error real.
- Los controles multimedia del sistema (MPRIS) y las teclas multimedia.
- La bandeja del sistema, cerrar a la bandeja y el inicio automático.
- Los enlaces `aurora://`. Para unirte a una Jam, escribe su código.
- El actualizador integrado y el actualizador de yt-dlp.

## Problemas conocidos

- No se ha probado el sonido en un equipo Linux real. La compilación se probó en WSL,
  que no tiene tarjeta de audio.
- Un test del proxy de audio (cliente que se va durante un vaciado pendiente) falla en
  Linux. Si una canción larga se corta, avísanos.
- Sin llavero activo, la app avisa de que no puede guardar la sesión y tendrás que
  iniciar sesión cada vez.
