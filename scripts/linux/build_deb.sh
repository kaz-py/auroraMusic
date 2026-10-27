#!/usr/bin/env bash
# Crea el paquete .deb de Aurora Music.
# Uso: build_deb.sh <bundle_dir> <version> <out_dir>
set -euo pipefail

bundle="${1:?Uso: build_deb.sh <bundle_dir> <version> <out_dir>}"
version="${2:?Falta la versión}"
out="${3:?Falta la carpeta de salida}"
app_id="com.aurora.aurora_music"
packaging="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../linux/packaging" && pwd)"

root="$(mktemp -d)"
chmod 755 "$root"
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/opt/aurora-music" "$root/usr/bin" "$root/usr/share/applications" \
  "$root/usr/share/icons/hicolor/256x256/apps" "$root/DEBIAN"
# Solo el bundle: el tar.gz trae además install.sh y compañía en la misma carpeta.
cp -a "$bundle/aurora_music" "$bundle/lib" "$bundle/data" "$root/opt/aurora-music/"
ln -s /opt/aurora-music/aurora_music "$root/usr/bin/aurora-music"
install -m 644 "$packaging/$app_id.desktop" "$root/usr/share/applications/"
install -m 644 "$packaging/$app_id.png" "$root/usr/share/icons/hicolor/256x256/apps/"

cat >"$root/DEBIAN/control" <<EOF
Package: aurora-music
Version: $version
Architecture: amd64
Maintainer: Aurora <noreply@users.noreply.github.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libsecret-1-0, libasound2 | libasound2t64, ffmpeg
Recommends: yt-dlp, gnome-keyring | kwalletmanager, xdg-desktop-portal-gtk | xdg-desktop-portal, pipewire-alsa | pulseaudio
Description: Reproductor de música Aurora
EOF

mkdir -p "$out"
dpkg-deb --build --root-owner-group "$root" "$out/aurora-music_${version}_amd64.deb"
