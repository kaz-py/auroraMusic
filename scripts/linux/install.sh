#!/usr/bin/env bash
# Instala Aurora Music para el usuario actual, sin root.
# Uso: install.sh [bundle_dir]   (por defecto, la carpeta de este script)
#      install.sh --uninstall
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

# Quita un directorio y sus padres vacíos hasta $HOME, para no dejar rastro.
prune_up() {
  local dir="$1"
  while [ "$dir" != "$HOME" ] && [ -d "$dir" ] && rmdir "$dir" 2>/dev/null; do
    dir="$(dirname "$dir")"
  done
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$dest"
  rm -f "$bin_link" "$desktop_file" "$icon_file"
  if compgen -G "$data_home/applications/*.desktop" >/dev/null; then
    refresh_menu
  else
    # Era la única aplicación: la caché la creó este instalador.
    rm -f "$data_home/applications/mimeinfo.cache"
  fi
  prune_up "$(dirname "$bin_link")"
  prune_up "$(dirname "$desktop_file")"
  prune_up "$(dirname "$icon_file")"
  prune_up "$data_home"
  echo "Aurora Music desinstalado."
  exit 0
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
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
fi
mkdir -p "$(dirname "$bin_link")" "$(dirname "$desktop_file")" "$(dirname "$icon_file")"
ln -sfn "$dest/aurora_music" "$bin_link"
while IFS= read -r line; do
  case "$line" in
    Exec=*) printf 'Exec=%s %%U\n' "$bin_link" ;;
    *) printf '%s\n' "$line" ;;
  esac
done <"$desktop_src" >"$desktop_file"
cp "$icon_src" "$icon_file"
refresh_menu
echo "Aurora Music instalado en $dest"

checker="$dest/check_bundle.sh"
[ -f "$checker" ] || checker="$here/check_bundle.sh"
missing="$(bash "$checker" "$dest" 2>&1 || true)"
if [ -n "$missing" ]; then
  echo "$missing"
  echo "Faltan bibliotecas del sistema. Instálalas con tu gestor de paquetes:"
  for lib in $(printf '%s\n' "$missing" | awk '/falta/ {print $NF}' | sort -u); do
    case "$lib" in
      libgtk-3.so.0) pkgs="libgtk-3-0|gtk3|gtk3" ;;
      libsecret-1.so.0) pkgs="libsecret-1-0|libsecret|libsecret" ;;
      libasound.so.2) pkgs="libasound2t64 (o libasound2)|alsa-lib|alsa-lib" ;;
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

for tool in ffmpeg yt-dlp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Aviso: $tool no está en el PATH; instálalo para usar todas las funciones."
  fi
done
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Aviso: añade ~/.local/bin a tu PATH para lanzar aurora-music desde la terminal." ;;
esac
