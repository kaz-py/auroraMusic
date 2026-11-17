# Aurora en Linux

Aurora funciona en Linux x64 (Ubuntu 22.04 o posterior, Debian, Fedora, Arch, openSUSE o
una distribución equivalente).

## Instalar con una línea (recomendado)

```bash
curl -fsSL https://raw.githubusercontent.com/kaz-py/auroraMusic/rust-migration/scripts/linux/get.sh | bash
```

Ejecútalo con tu usuario, sin `sudo`. El script:

1. Instala las bibliotecas que falten con apt, dnf, pacman o zypper: GTK 3, libsecret,
   ALSA, EGL y GLES. Pide la contraseña de `sudo` solo para eso. Si el escritorio usa
   PipeWire o PulseAudio, añade también el puente de ALSA para que se oiga el audio.
2. Descarga la versión más reciente que tenga paquete de Linux (las beta incluidas) y
   comprueba su SHA-256 con el `checksums.txt` del release.
3. Instala `yt-dlp`: en Arch y Fedora, el paquete del sistema; en el resto, el binario
   oficial dentro de la app (`tools/yt-dlp`), porque el de apt suele estar desfasado.
4. Instala la app para tu usuario con `install.sh` (ver más abajo).

Para instalar una versión concreta:
`curl -fsSL <misma URL> | AURORA_VERSION=v1.6.0-beta.9 bash`. Para actualizar, repite el
comando.

Probado en WSL con Arch, Ubuntu 24.04 y Fedora 44, partiendo de imágenes limpias.
openSUSE no está probado.

## Instalar a mano desde una versión publicada

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

Bibliotecas del sistema que necesita la app (Debian y Ubuntu):

```bash
sudo apt-get install libgtk-3-0 libsecret-1-0 libasound2 libegl1 libgles2 libegl-mesa0
```

En Ubuntu 24.04, los paquetes se llaman `libasound2t64` y `libgtk-3-0t64`. Flutter
carga EGL y GLES al arrancar; sin ellas, la app se cierra con
`Couldn't open libGLESv2.so.2`. Los códecs (FLAC, Opus, Ogg, Vorbis) van incluidos en la
app.

Si al abrir Aurora falta una biblioteca, la app muestra cuál es. Instálala, o usa el
.deb o `install.sh`, que comprueban las dependencias.

Para actualizar, repite el comando de una línea o estos pasos con la versión nueva. En
Linux, Aurora no tiene actualizador integrado.

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
