#!/usr/bin/env bash
# Instala Aurora Music para el usuario actual, sin root.
# Uso: install.sh [bundle_dir]   (por defecto, la carpeta de este script)
#      install.sh --uninstall [--purge] [--yes] [--dry-run]   (ver uninstall.sh)
set -euo pipefail

app_id="com.aurora.aurora_music"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data_home/aurora-music"
bin_link="$HOME/.local/bin/aurora-music"
desktop_file="$data_home/applications/$app_id.desktop"
icon_file="$data_home/icons/hicolor/256x256/apps/$app_id.png"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

refresh_menu() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$data_home/applications" || true
  fi
}

# La desinstalación vive en uninstall.sh: comprueba cada ruta antes de borrarla.
if [ "${1:-}" = "--uninstall" ]; then
  shift
  if [ ! -f "$here/uninstall.sh" ]; then
    echo "Falta uninstall.sh junto a install.sh. Desinstala con:" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/kaz-py/auroraMusic/rust-migration/scripts/linux/uninstall.sh | bash" >&2
    exit 1
  fi
  exec bash "$here/uninstall.sh" "$@"
fi

src="$(cd "${1:-$here}" && pwd)"
if [ ! -x "$src/aurora_music" ]; then
  echo "No encuentro $src/aurora_music. Pasa la carpeta del bundle como argumento." >&2
  exit 1
fi

find_asset() {
  local name="$1"
  for candidate in "$src/$name" "$here/$name" "$here/../../linux/packaging/$name"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "No encuentro $name." >&2
  return 1
}
desktop_src="$(find_asset "$app_id.desktop")"
icon_src="$(find_asset "$app_id.png")"

if [ "$src" != "$dest" ]; then
  # Solo se reemplaza una instalación anterior de Aurora, nunca otra carpeta.
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    if [ ! -f "$dest/aurora_music" ] || [ ! -d "$dest/data/flutter_assets" ] ||
      [ ! -f "$dest/lib/libapp.so" ]; then
      echo "$dest existe y no parece una instalación de Aurora; no la reemplazo. Muévela y repite." >&2
      exit 1
    fi
    rm -rf --one-file-system "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
fi
# Los scripts van con la app para poder desinstalarla después
# (el tar.gz ya los trae; una compilación local, no).
for script in install.sh uninstall.sh check_bundle.sh; do
  if [ -f "$here/$script" ] && [ ! -e "$dest/$script" ]; then
    install -m 755 "$here/$script" "$dest/$script"
  fi
done
mkdir -p "$(dirname "$bin_link")" "$(dirname "$desktop_file")" "$(dirname "$icon_file")"
ln -sfn "$dest/aurora_music" "$bin_link"
while IFS= read -r line; do
  case "$line" in
    Exec=*) printf 'Exec=%s %%U\n' "$bin_link" ;;
    *) printf '%s\n' "$line" ;;
  esac
done <"$desktop_src" >"$desktop_file"
install -m 644 "$icon_src" "$icon_file"
refresh_menu
echo "Aurora Music instalado en $dest"

checker="$dest/check_bundle.sh"
[ -f "$checker" ] || checker="$here/check_bundle.sh"
missing="$(bash "$checker" "$dest" 2>&1 || true)"
[ -z "$missing" ] || echo "$missing"
libs="$(printf '%s\n' "$missing" | awk '/falta/ {print $NF}' | sort -u)"
if [ -n "$libs" ]; then
  echo "Faltan bibliotecas del sistema. Instálalas con tu gestor de paquetes:"
  for lib in $libs; do
    case "$lib" in
      libgtk-3.so.0) pkgs="libgtk-3-0|gtk3|gtk3" ;;
      libsecret-1.so.0) pkgs="libsecret-1-0|libsecret|libsecret" ;;
      libasound.so.2) pkgs="libasound2t64 (o libasound2)|alsa-lib|alsa-lib" ;;
      libEGL.so.1) pkgs="libegl1 libegl-mesa0|libglvnd-egl mesa-libEGL|libglvnd mesa" ;;
      libGLESv2.so.2) pkgs="libgles2|libglvnd-gles|libglvnd" ;;
      *) pkgs="" ;;
    esac
    if [ -n "$pkgs" ]; then
      IFS='|' read -r apt_pkg dnf_pkg pacman_pkg <<<"$pkgs"
      echo "  $lib: sudo apt install $apt_pkg | sudo dnf install $dnf_pkg | sudo pacman -S $pacman_pkg"
    else
      echo "  $lib: busca el paquete que la contiene en tu distribución."
    fi
  done
fi

# Aurora usa primero tools/yt-dlp junto a su ejecutable (lo pone get.sh).
if [ ! -x "$dest/tools/yt-dlp" ] && ! command -v yt-dlp >/dev/null 2>&1; then
  echo "Aviso: yt-dlp no está en el PATH; instálalo para usar todas las funciones."
fi
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Aviso: añade ~/.local/bin a tu PATH para lanzar aurora-music desde la terminal." ;;
esac
