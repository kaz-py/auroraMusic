#!/usr/bin/env bash
# Instala Aurora Music en Linux x86_64 con una línea (Debian/Ubuntu, Fedora,
# Arch y openSUSE):
#   curl -fsSL https://raw.githubusercontent.com/kaz-py/auroraMusic/rust-migration/scripts/linux/get.sh | bash
# 1. Instala las bibliotecas del sistema que falten con apt, dnf, pacman o
#    zypper (pide sudo solo para eso).
# 2. Descarga la versión más reciente con paquete de Linux (betas incluidas) y
#    comprueba su SHA-256 con el checksums.txt del release.
# 3. La instala para tu usuario en ~/.local con install.sh (sin root), con un
#    yt-dlp al día si tu distribución no lo trae.
# Versión concreta: ... | AURORA_VERSION=v1.6.0-beta.9 bash
# Desinstalar: bash ~/.local/share/aurora-music/install.sh --uninstall
set -euo pipefail

repo="kaz-py/auroraMusic"

say() { printf '==> %s\n' "$*"; }
warn() { printf 'Aviso: %s\n' "$*" >&2; }
die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

as_root() {
  if command -v sudo >/dev/null; then
    sudo "$@"
  elif command -v doas >/dev/null; then
    doas "$@"
  else
    return 1
  fi
}

installed() {
  case "$pm" in
    pacman) pacman -Q "$1" ;;
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed' ;;
    dnf | zypper) rpm -q --whatprovides "$1" ;;
  esac >/dev/null 2>&1
}

# Primera alternativa que existe en los repositorios (Ubuntu 24.04 renombró
# libasound2 y libgtk-3-0 con el sufijo t64).
resolve() {
  local alt alts
  IFS='|' read -ra alts <<<"$1"
  if [ "$pm" = apt ]; then
    for alt in "${alts[@]}"; do
      if apt-cache show "$alt" >/dev/null 2>&1; then
        echo "$alt"
        return
      fi
    done
  fi
  echo "${alts[0]}"
}

install_pkgs() {
  case "$pm" in
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    apt) as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
    dnf) as_root dnf install -y "$@" ;;
    zypper) as_root zypper --non-interactive install --no-recommends "$@" ;;
  esac
}

# Instala los que falten. "a|b" vale con cualquiera de las dos.
install_missing() {
  local item alt alts found missing=() pkgs=()
  for item in "$@"; do
    found=""
    IFS='|' read -ra alts <<<"$item"
    for alt in "${alts[@]}"; do
      if installed "$alt"; then
        found=1
        break
      fi
    done
    [ -n "$found" ] || missing+=("$item")
  done
  [ "${#missing[@]}" -gt 0 ] || return 0
  if ! command -v sudo >/dev/null && ! command -v doas >/dev/null; then
    warn "no hay sudo ni doas; instala como root: ${missing[*]}"
    return 0
  fi
  if [ "$pm" = apt ] && [ -z "$apt_updated" ]; then
    as_root apt-get update -qq || true
    apt_updated=1
  fi
  for item in "${missing[@]}"; do pkgs+=("$(resolve "$item")"); done
  say "Instalando con $pm: ${pkgs[*]}"
  install_pkgs "${pkgs[@]}"
}

# Comprueba "$tmp/$1" con la lista de sumas "$tmp/$2" (formato de sha256sum).
verify() {
  local hash file
  while read -r hash file; do
    if [ "$file" = "$1" ] || [ "$file" = "*$1" ]; then
      (cd "$tmp" && printf '%s  %s\n' "$hash" "$1" | sha256sum -c --quiet -)
      return
    fi
  done <"$tmp/$2"
  return 1
}

main() {
  [ "$(id -u)" -ne 0 ] || die "ejecútalo con tu usuario, sin sudo: Aurora se instala en tu carpeta personal y el script pide sudo solo para las bibliotecas."
  [ "$(uname -m)" = x86_64 ] || die "solo hay paquete para Linux x86_64; este equipo es $(uname -m)."
  local tool
  for tool in curl tar sha256sum; do
    command -v "$tool" >/dev/null || die "falta $tool; instálalo y vuelve a intentarlo."
  done

  # GTK 3 (ventana), libsecret (llavero de la sesión), ALSA (audio) y EGL/GLES
  # con su controlador Mesa: Flutter los abre al arrancar y ldd no los ve.
  # En dnf y zypper se piden por biblioteca, sin depender de nombres.
  local libs=() bridges=() extras=() ytdlp_pkg=""
  # install.sh usa awk, que falta en imágenes mínimas de Fedora y openSUSE.
  local sonames=('libgtk-3.so.0()(64bit)' 'libsecret-1.so.0()(64bit)' 'libasound.so.2()(64bit)'
    'libEGL.so.1()(64bit)' 'libGLESv2.so.2()(64bit)' 'libEGL_mesa.so.0()(64bit)' /usr/bin/awk)
  pm="" apt_updated=""
  if command -v pacman >/dev/null; then
    pm=pacman ytdlp_pkg=yt-dlp
    libs=(gtk3 libsecret alsa-lib libglvnd mesa)
    bridges=(pipewire-alsa pulseaudio-alsa)
  elif command -v apt-get >/dev/null; then
    pm=apt
    libs=("libgtk-3-0t64|libgtk-3-0" libsecret-1-0 "libasound2t64|libasound2" libegl1 libgles2 libegl-mesa0)
    bridges=(pipewire-alsa libasound2-plugins)
  elif command -v dnf >/dev/null; then
    pm=dnf ytdlp_pkg=yt-dlp libs=("${sonames[@]}")
    bridges=(pipewire-alsa alsa-plugins-pulseaudio)
  elif command -v zypper >/dev/null; then
    pm=zypper libs=("${sonames[@]}")
    bridges=(pipewire-alsa alsa-plugins-pulse)
  fi

  if [ -z "$pm" ]; then
    warn "no reconozco el gestor de paquetes; instala GTK 3, libsecret, ALSA, EGL y GLES por tu cuenta."
  else
    if ! install_missing "${libs[@]}"; then
      if [ "$pm" = pacman ]; then
        warn "pacman no pudo instalarlas; actualiza el sistema (sudo pacman -Syu) y repite."
      else
        warn "$pm no pudo instalar las bibliotecas; al final se indica cuáles faltan."
      fi
    fi
    # El puente de ALSA saca el sonido por el servidor de audio del escritorio.
    if command -v pipewire >/dev/null; then
      extras+=("${bridges[0]}")
    elif command -v pulseaudio >/dev/null; then
      extras+=("${bridges[1]}")
    fi
    [ -z "$ytdlp_pkg" ] || extras+=("$ytdlp_pkg")
    if [ "${#extras[@]}" -gt 0 ] && ! install_missing "${extras[@]}"; then
      warn "no se pudo instalar: ${extras[*]}"
    fi
  fi

  local url
  if [ -n "${AURORA_VERSION:-}" ]; then
    local version="${AURORA_VERSION#v}"
    url="https://github.com/$repo/releases/download/v$version/Aurora-$version-linux-x64.tar.gz"
  else
    # La API no ordena por versión (beta.9 sale antes que beta.10): se elige la
    # mayor con sort -V; con «~» una beta queda antes que su versión final.
    url="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=100" |
      grep -o '"browser_download_url": *"[^"]*/Aurora-[^"/]*-linux-x64\.tar\.gz"' |
      sed -E 's#.*"(https:[^"]*/Aurora-([^"/]*)-linux-x64\.tar\.gz)"$#\2 \1#; s#^([0-9.]+)-#\1~#' |
      sort -V -k1,1 | tail -n 1 | cut -d' ' -f2)"
    [ -n "$url" ] || die "no encuentro ningún release de $repo con paquete de Linux."
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  local name="${url##*/}"
  say "Descargando $name"
  curl -fL --progress-bar -o "$tmp/$name" "$url" || die "no se pudo descargar $url"
  curl -fsSL -o "$tmp/checksums.txt" "${url%/*}/checksums.txt" ||
    die "el release no tiene checksums.txt; no instalo algo sin verificar."
  verify "$name" checksums.txt ||
    die "el SHA-256 de $name no coincide con checksums.txt (o no aparece en él)."
  tar -xzf "$tmp/$name" -C "$tmp"
  local bundle="$tmp/${name%.tar.gz}"
  [ -x "$bundle/aurora_music" ] || die "$name no tiene el formato esperado."

  # Aurora busca primero tools/yt-dlp junto a su ejecutable: así no depende
  # del PATH de la sesión gráfica. Sin paquete al día, va el binario oficial.
  if [ -z "$ytdlp_pkg" ] || ! command -v yt-dlp >/dev/null; then
    say "Descargando yt-dlp oficial"
    local yt="https://github.com/yt-dlp/yt-dlp/releases/latest/download"
    if curl -fL --progress-bar -o "$tmp/yt-dlp_linux" "$yt/yt-dlp_linux" &&
      curl -fsSL -o "$tmp/SHA2-256SUMS" "$yt/SHA2-256SUMS" &&
      verify yt-dlp_linux SHA2-256SUMS; then
      install -D -m 755 "$tmp/yt-dlp_linux" "$bundle/tools/yt-dlp"
    else
      warn "no se pudo descargar yt-dlp; sin él no funcionan las fuentes de YouTube."
    fi
  fi

  bash "$bundle/install.sh" "$bundle"
  say "Listo: abre Aurora Music desde el menú de aplicaciones o con aurora-music."
}

main "$@"
