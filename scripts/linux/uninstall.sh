#!/usr/bin/env bash
# Desinstala Aurora Music instalada para tu usuario con install.sh o get.sh.
#
#   bash ~/.local/share/aurora-music/uninstall.sh [opciones]
#   curl -fsSL https://raw.githubusercontent.com/kaz-py/auroraMusic/rust-migration/scripts/linux/uninstall.sh | bash -s -- [opciones]
#
# Opciones:
#   --purge    borra también tus datos de Aurora: biblioteca, ajustes, letras,
#              registros, caché y la sesión guardada en el llavero. La música
#              descargada en la carpeta por defecto se conserva.
#   --yes      no pregunta antes de borrar (sin terminal hace falta).
#   --dry-run  enseña lo que haría y no toca nada.
#
# Solo borra lo que instaló Aurora. Comprueba cada ruta antes de tocarla, no
# sigue enlaces, no borra nada si algo no cuadra y nunca pide root. El paquete
# .deb se quita con «sudo apt remove aurora-music».
set -euo pipefail

app_id="com.aurora.aurora_music"

usage() {
  cat <<'EOF'
Uso: uninstall.sh [--purge] [--yes] [--dry-run]
  --purge    borra también tus datos de Aurora (biblioteca, ajustes, letras,
             registros, caché y la sesión del llavero); conserva la música
             descargada en la carpeta por defecto.
  --yes      no pregunta antes de borrar.
  --dry-run  enseña lo que haría y no toca nada.
EOF
}

purge=0
yes=0
dry=0
for arg in "$@"; do
  case "$arg" in
    --purge) purge=1 ;;
    --yes | -y) yes=1 ;;
    --dry-run | -n) dry=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Opción desconocida: %s\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}
warn() { printf 'Aviso: %s\n' "$*" >&2; }

[ "$(id -u)" -ne 0 ] ||
  die "no lo ejecutes como root ni con sudo: Aurora se instala para tu usuario."

home="${HOME:-}"
home="${home%/}"
case "$home" in
  /?*) ;;
  *) die "HOME no es una ruta absoluta válida." ;;
esac
[ -d "$home" ] || die "HOME ($home) no es una carpeta."
[ "$(cd "$home" && pwd -P)" != / ] || die "HOME no puede ser la raíz del sistema."

# Rutas XDG: solo valen si son absolutas (como pide la especificación).
xdg_dir() {
  local value="${1%/}"
  case "$value" in
    /?*) printf '%s' "$value" ;;
    *) printf '%s' "$2" ;;
  esac
}
data_home="$(xdg_dir "${XDG_DATA_HOME:-}" "$home/.local/share")"
cache_home="$(xdg_dir "${XDG_CACHE_HOME:-}" "$home/.cache")"

# Nunca dentro de carpetas del sistema, aunque XDG apunte allí por error.
for dir in "$data_home" "$cache_home"; do
  case "$dir/" in
    /usr/* | /etc/* | /opt/* | /bin/* | /sbin/* | /lib/* | /lib32/* | /lib64/* | /boot/* | /srv/* | /sys/* | /proc/* | /dev/*)
      die "$dir es una carpeta del sistema; Aurora nunca se instala ahí. No se borró nada."
      ;;
  esac
done

app_dir="$data_home/aurora-music"
bin_link="$home/.local/bin/aurora-music"
desktop_file="$data_home/applications/$app_id.desktop"
icon_file="$data_home/icons/hicolor/256x256/apps/$app_id.png"
data_dir="$data_home/$app_id"
cache_dir="$cache_home/$app_id"

looks_like_aurora() {
  [ -f "$1/aurora_music" ] && [ ! -L "$1/aurora_music" ] && [ -x "$1/aurora_music" ] &&
    [ -d "$1/data/flutter_assets" ] && [ -f "$1/lib/libapp.so" ]
}

remove=()
reasons=()
kept=()
plan() {
  remove+=("$1")
  reasons+=("$2")
}
keep() { kept+=("$1"); }

# --- Qué hay instalado --------------------------------------------------------
app_is_aurora=0
if [ -L "$app_dir" ]; then
  plan "$app_dir" "enlace a $(readlink "$app_dir"); se quita el enlace, no su destino"
elif [ -d "$app_dir" ]; then
  looks_like_aurora "$app_dir" ||
    die "$app_dir no parece una instalación de Aurora (falta aurora_music, data/flutter_assets o lib/libapp.so). No se borró nada."
  app_is_aurora=1
  plan "$app_dir" "la aplicación"
elif [ -e "$app_dir" ]; then
  die "$app_dir existe pero no es una carpeta. No se borró nada."
fi

if [ -L "$bin_link" ]; then
  if [ "$(readlink "$bin_link")" = "$app_dir/aurora_music" ]; then
    plan "$bin_link" "el comando aurora-music"
  else
    keep "$bin_link (apunta a $(readlink "$bin_link"), no lo creó Aurora)"
  fi
elif [ -e "$bin_link" ]; then
  keep "$bin_link (no es el enlace que crea Aurora)"
fi

if [ -f "$desktop_file" ] && [ ! -L "$desktop_file" ] &&
  grep -qxF "Exec=$bin_link %U" "$desktop_file"; then
  plan "$desktop_file" "la entrada del menú"
elif [ -e "$desktop_file" ] || [ -L "$desktop_file" ]; then
  keep "$desktop_file (no la creó install.sh)"
fi

if [ -f "$icon_file" ] && [ ! -L "$icon_file" ]; then
  plan "$icon_file" "el icono"
elif [ -e "$icon_file" ] || [ -L "$icon_file" ]; then
  keep "$icon_file (no es un archivo normal)"
fi

keep_downloads=0
if [ "$purge" = 1 ]; then
  if [ -L "$data_dir" ]; then
    plan "$data_dir" "enlace a tus datos; se quita el enlace, no su destino"
  elif [ -d "$data_dir" ]; then
    shopt -s nullglob dotglob
    for entry in "$data_dir"/*; do
      if [ "${entry##*/}" = downloads ] && [ -d "$entry" ] && [ ! -L "$entry" ] &&
        [ -n "$(find "$entry" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        keep_downloads=1
        keep "$entry (tu música descargada)"
        continue
      fi
      if [ "${entry##*/}" = downloads ]; then
        plan "$entry" "carpeta de descargas vacía"
      else
        plan "$entry" "datos de Aurora"
      fi
    done
    shopt -u nullglob dotglob
  fi
  if [ -L "$cache_dir" ]; then
    plan "$cache_dir" "enlace a la caché; se quita el enlace, no su destino"
  elif [ -d "$cache_dir" ]; then
    plan "$cache_dir" "caché de portadas"
  fi
fi

# --- Procesos de Aurora abiertos ---------------------------------------------
# Solo procesos de este usuario. Se cierran los de esta instalación; con
# --purge, si hay otra Aurora abierta con este HOME (el .deb o una compilación),
# se aborta para no borrarle los datos mientras los usa.
same_home() {
  local env_file="/proc/$1/environ"
  [ -r "$env_file" ] || return 0
  tr '\0' '\n' <"$env_file" 2>/dev/null | grep -qxF -e "HOME=$home" -e "HOME=$home/"
}
ours=()
others=()
for proc in /proc/[0-9]*; do
  [ -O "$proc" ] || continue
  exe="$(readlink "$proc/exe" 2>/dev/null)" || continue
  exe="${exe% (deleted)}"
  case "$exe" in */aurora_music) ;; *) continue ;; esac
  pid="${proc#/proc/}"
  if [ "$exe" = "$app_dir/aurora_music" ]; then
    ours+=("$pid")
  elif [ "$purge" = 1 ] && same_home "$pid"; then
    others+=("$pid ($exe)")
  fi
done
if [ "${#others[@]}" -gt 0 ]; then
  die "hay otra Aurora abierta que usa tus datos: ${others[*]}. Ciérrala (bandeja → Salir) y repite. No se borró nada."
fi

# --- Plan ---------------------------------------------------------------------
deb_note=""
if [ -x /opt/aurora-music/aurora_music ]; then
  deb_note="También está instalado el paquete del sistema (/opt/aurora-music). Quítalo con: sudo apt remove aurora-music"
fi

if [ "${#remove[@]}" -eq 0 ]; then
  echo "No hay nada de Aurora que desinstalar para tu usuario."
  for item in "${kept[@]}"; do echo "  Se deja: $item"; done
  [ -z "$deb_note" ] || echo "$deb_note"
  exit 0
fi

echo "Se borrará:"
for i in "${!remove[@]}"; do
  printf '  %s  (%s)\n' "${remove[$i]}" "${reasons[$i]}"
done
if [ "${#kept[@]}" -gt 0 ]; then
  echo "Se deja:"
  for item in "${kept[@]}"; do echo "  $item"; done
fi
if [ "$purge" = 1 ]; then
  echo "También se borrará la sesión de Aurora guardada en el llavero."
else
  echo "Tus datos (biblioteca, ajustes y descargas) se conservan. Para borrarlos: --purge."
fi
if [ "${#ours[@]}" -gt 0 ]; then
  echo "Aurora está abierta (pid ${ours[*]}): se cerrará antes de borrar."
fi

if [ "$dry" = 1 ]; then
  echo "Prueba (--dry-run): no se ha tocado nada."
  exit 0
fi

if [ "$yes" != 1 ]; then
  # Con «curl | bash» la entrada es el script: se pregunta por la terminal.
  if ! (: </dev/tty) 2>/dev/null; then
    die "no hay terminal para confirmar. Repite con --yes. No se borró nada."
  fi
  printf '¿Continuar? [s/N] ' >&2
  answer=""
  read -r answer </dev/tty || true
  case "$answer" in
    s | S | si | Si | SI | sí | Sí | SÍ | y | Y | yes | Yes) ;;
    *)
      echo "Cancelado: no se borró nada."
      exit 1
      ;;
  esac
fi

# --- Cerrar Aurora --------------------------------------------------------------
if [ "${#ours[@]}" -gt 0 ]; then
  for pid in "${ours[@]}"; do
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || continue
    [ "${exe% (deleted)}" = "$app_dir/aurora_music" ] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done
  alive=0
  for _ in $(seq 1 50); do
    alive=0
    for pid in "${ours[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then alive=1; fi
    done
    [ "$alive" = 0 ] && break
    sleep 0.2
  done
  [ "$alive" = 0 ] ||
    die "Aurora (pid ${ours[*]}) no se cerró en 10 s. Ciérrala (bandeja → Salir) y repite. No se borró nada."
fi

# --- Borrar -------------------------------------------------------------------
# La carpeta de la app se vuelve a comprobar justo antes: pudo cambiar mientras
# se esperaba la confirmación.
if [ "$app_is_aurora" = 1 ] && { [ -L "$app_dir" ] || ! looks_like_aurora "$app_dir"; }; then
  die "$app_dir cambió durante la desinstalación. No se borró nada."
fi
for path in "${remove[@]}"; do
  if [ -L "$path" ] || [ ! -d "$path" ]; then
    rm -f -- "$path"
  else
    rm -rf --one-file-system -- "$path"
  fi
done
if [ "$purge" = 1 ] && [ "$keep_downloads" = 0 ] && [ -d "$data_dir" ] && [ ! -L "$data_dir" ]; then
  rmdir -- "$data_dir" 2>/dev/null || true
fi
if command -v update-desktop-database >/dev/null 2>&1 && [ -d "$data_home/applications" ]; then
  update-desktop-database "$data_home/applications" 2>/dev/null || true
fi

if [ "$purge" = 1 ]; then
  if command -v secret-tool >/dev/null 2>&1; then
    secret-tool clear account "$app_id.secureStorage" 2>/dev/null ||
      warn "no se pudo borrar la sesión del llavero; búscala como «$app_id» en Seahorse o KWallet."
  else
    warn "falta secret-tool: si iniciaste sesión, borra la entrada «$app_id» del llavero (Seahorse o KWallet)."
  fi
fi

echo "Aurora Music desinstalado."
if [ "$keep_downloads" = 1 ]; then
  echo "Tu música descargada sigue en $data_dir/downloads."
fi
if [ "$purge" = 1 ]; then
  echo "Las descargas guardadas en otra carpeta elegida en Ajustes no se tocan."
fi
[ -z "$deb_note" ] || echo "$deb_note"
