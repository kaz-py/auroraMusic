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
   PipeWire o PulseAudio, añade también el puente de ALSA para que se oiga el audio, y
   libayatana-appindicator para el icono de la bandeja.
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

Para desinstalar, ver «Desinstalar».

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

## Desinstalar

Si instalaste con el comando de una línea o con `install.sh`:

```bash
bash ~/.local/share/aurora-music/uninstall.sh
```

Si esa carpeta no trae `uninstall.sh` (instalaciones antiguas):

```bash
curl -fsSL https://raw.githubusercontent.com/kaz-py/auroraMusic/rust-migration/scripts/linux/uninstall.sh | bash
```

Antes de borrar, enseña la lista de lo que va a quitar y pide confirmación. Si Aurora
está abierta (también en la bandeja), la cierra primero.

- Por defecto quita solo la app, el comando `aurora-music`, la entrada del menú y el
  icono. Tu biblioteca, tus ajustes y tus descargas se quedan.
- `--purge` borra también tus datos (biblioteca, ajustes, letras, registros y caché de
  portadas) y la sesión guardada en el llavero. La música descargada en la carpeta por
  defecto se conserva, y las descargas que guardaste en otra carpeta no se tocan nunca.
- `--dry-run` muestra lo que borraría sin tocar nada. `--yes` no pregunta; con
  `curl … | bash` sin terminal hace falta. Las opciones van tras `bash -s --`, por
  ejemplo `curl … | bash -s -- --purge`.

Es seguro:
- Solo borra lo que reconoce como de Aurora: la carpeta de la app tiene que tener
  `aurora_music`, `data/flutter_assets` y `lib/libapp.so`; el comando tiene que
  apuntar a esa app y el menú tiene que tener su línea `Exec`. Lo demás lo deja y
  avisa.
- No sigue enlaces: si algo es un enlace, quita el enlace y no su destino.
- No borra carpetas estándar como `~/.local/bin`, aunque queden vacías.
- Si algo no cuadra, se detiene sin haber borrado nada.
- No usa `sudo` y no se puede ejecutar como root, así que no puede tocar archivos del
  sistema. Tampoco actúa si `XDG_DATA_HOME` o `XDG_CACHE_HOME` apuntan a una carpeta
  del sistema (`/usr`, `/etc`, `/opt`…).
- No desinstala yt-dlp ni las bibliotecas que instaló `get.sh`, porque otros programas
  pueden usarlas.

Con el paquete .deb: `sudo apt remove aurora-music`. Para borrar después tus datos,
usa `--purge` con el comando de `curl` de arriba.

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
- **Bandeja del sistema** (opcional): `libayatana-appindicator3` y un escritorio o una
  barra con bandeja StatusNotifierItem (KDE, Waybar, quickshell…). GNOME necesita la
  extensión AppIndicator. Sin ellas la app funciona igual y la X la cierra.

## Diferencias con Windows

Funciona igual que en Windows:

- Búsqueda y reproducción nativa con ecualizador.
- DJ y cola continua.
- Biblioteca y descargas.
- Cuenta y sincronización.
- Amigos.
- Last.fm.
- Jam.
- La bandeja del sistema y cerrar a la bandeja (ver «Bandeja y ventana»).

Discord muestra lo que escuchas si su app de escritorio está abierta, incluso en Flatpak
o Snap.

Duvet usa un socket local y busca `duvet-ipc` en `$XDG_RUNTIME_DIR`, `$TMPDIR` y
`/tmp`. Esas rutas no están confirmadas, porque no hay documentación pública de Duvet
para Linux.

En Linux no están disponibles:

- Los controles multimedia del sistema (MPRIS) y las teclas multimedia.
- El inicio automático con la sesión.
- Los enlaces `aurora://`. Para unirte a una Jam, escribe su código.
- El actualizador integrado y el actualizador de yt-dlp.

## Bandeja y ventana

Por defecto, cerrar con la X oculta la ventana y la música sigue: Aurora queda en la
bandeja del sistema. Para cerrarla del todo, usa «Salir» en el menú del icono. En
Ajustes → «Ventana y bandeja» puedes hacer que la X cierre la app.

El menú del icono muestra la canción que suena, «Mostrar Aurora», Pausa o Reproducir,
Siguiente, Anterior y Salir. En las barras que admiten el clic central, ese clic
también devuelve la ventana.

- La bandeja usa `libayatana-appindicator3`, que se carga al arrancar si está
  instalada. Si falta, o si el escritorio no tiene bandeja (no hay
  `org.kde.StatusNotifierWatcher` en el bus de sesión), la X cierra la app.
- Solo hay una instancia: abrir Aurora otra vez (desde el menú o con `aurora-music`)
  muestra la ventana que ya estaba, aunque esté en la bandeja. Con
  `AURORA_MULTI_INSTANCE=1` se puede abrir otra (útil para pruebas).
- Con la ventana oculta la app no dibuja nada: en pausa no gasta CPU y sonando solo
  gasta lo del audio.

## Consumo de recursos

Medido en Arch Linux (niri en Wayland, PipeWire, Mesa) con el tema Modern y la
ventana visible sin foco, 20 s por estado (CPU de `/proc/<pid>/stat`, memoria sucia
de `smaps_rollup`). «Antes» es la versión de `a5670ad`.

| Estado | CPU antes | CPU ahora | Memoria sucia antes | Memoria sucia ahora |
|---|---|---|---|---|
| Reposo | 0,6 % | 0,0 % | 108,5 MiB | 83,4 MiB |
| Sonando | 11,0 % | 3,8 % | 128,8 MiB | 93,5 MiB |
| En pausa | 10,1 % | 0,4 % | 123,6 MiB | 81,9 MiB |
| En la bandeja, sonando | — | 2,1 % | — | 104,6 MiB |
| En la bandeja, en pausa | — | 0,4 % | — | 86,7 MiB |

La RSS ronda los 390-405 MiB en los dos casos; casi toda es compartida (motor de
Flutter, Skia y bibliotecas del sistema).

Qué cambió:

- El fondo del tema Modern reiniciaba un fundido de 700 ms cada vez que llegaba la
  posición (5 veces por segundo) y la pantalla se redibujaba a unos 38 fps sin parar.
  Ahora solo se anima al cambiar de pista: sonando hay unos 5 fotogramas por segundo
  (Modern y Atelier) o 1 (Brasa y Slush), y en pausa ninguno.
- En pausa el motor se consulta 4 veces por segundo en vez de 30, y la interfaz no se
  reconstruye si nada cambió.
- La salida de audio se suspende tras 5 s sin sonar (PipeWire la pasa a `idle`) y
  vuelve al reproducir.
- Con la ventana oculta, una tarea de limpieza de memoria podía reintentarse en bucle
  y dejar un núcleo al 100 %. Ahora se ejecuta en cuanto no hay fotogramas.

Para medir: `scripts/linux/measure_memory.sh` (memoria) y, para los fotogramas,
`WAYLAND_DEBUG=client` contando las líneas `wl_surface.commit`.

## Problemas conocidos

- Probado en Arch Linux con niri (Wayland), PipeWire y una barra quickshell con
  bandeja: sonido real por `pipewire-alsa`, bandeja, instancia única y cierre. No se ha
  probado en un equipo físico con Ubuntu o Debian, X11 ni GNOME.
- Sin llavero activo, la app avisa de que no puede guardar la sesión y tendrás que
  iniciar sesión cada vez.
