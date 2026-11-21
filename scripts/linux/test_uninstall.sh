#!/usr/bin/env bash
# Pruebas de scripts/linux/uninstall.sh (y de la delegacion de install.sh --uninstall).
# Autocontenido: cada caso usa un HOME temporal y un secret-tool falso.
# Codigo 0 si todo pasa; distinto de 0 si algo falla.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UN="$REPO/scripts/linux/uninstall.sh"
IN="$REPO/scripts/linux/install.sh"
ROOT="$(mktemp -d)"
ORIG_PATH="$PATH"
PIDS=()
EXTRA=()
PASS=0; FAIL=0; FAILED=()
APPID=com.aurora.aurora_music

cleanup() {
  for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
  for d in "${EXTRA[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
  rm -rf "$ROOT"
}
trap cleanup EXIT

CUR=""
n=0
new_case() { # nombre
  CUR="$1"; n=$((n+1))
  CASE="$ROOT/c$n"
  mkdir -p "$CASE/home" "$CASE/fake" "$CASE/cwd"
  cat >"$CASE/fake/secret-tool" <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
EOF
  printf '#!/bin/sh\nexit 0\n' >"$CASE/fake/update-desktop-database"
  chmod +x "$CASE/fake/"*
  export FAKE_LOG="$CASE/secret.log"
  export PATH="$CASE/fake:$ORIG_PATH"
  export HOME="$CASE/home"
  unset XDG_DATA_HOME XDG_CACHE_HOME
  OUT=""
  set_paths
  cd "$CASE/cwd"
}
set_paths() {
  DH="${XDG_DATA_HOME:-$HOME/.local/share}"
  CH="${XDG_CACHE_HOME:-$HOME/.cache}"
  APP="$DH/aurora-music"
  LINK="$HOME/.local/bin/aurora-music"
  DESK="$DH/applications/$APPID.desktop"
  ICON="$DH/icons/hicolor/256x256/apps/$APPID.png"
  DATA="$DH/$APPID"
  CACHE="$CH/$APPID"
}
pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); FAILED+=("$CUR: $1"); echo "FALLO [$CUR] $1"; [ -n "${OUT:-}" ] && echo "  salida: ${OUT:0:600}"; }
check() { # descripcion, comando...
  local d="$1"; shift
  if "$@"; then pass; else fail "$d"; fi
}
exists() { [ -e "$1" ] || [ -L "$1" ]; }
present() { check "deberia existir: $1" exists "$1"; }
absent() { if exists "$1"; then fail "deberia no existir: $1"; else pass; fi; }
rc_is() { if [ "$RC" -eq "$1" ]; then pass; else fail "codigo esperado $1, obtenido $RC"; fi; }
alive() { # pid vivo y no zombie
  [ -r "/proc/$1/stat" ] || return 1
  local st; st="$(sed 's/.*) //' "/proc/$1/stat" | cut -c1)"
  [ "$st" != Z ] && [ "$st" != X ]
}
run() { # args de uninstall.sh
  OUT="$(bash "$UN" "$@" </dev/null 2>&1)"; RC=$?
}
snap() { find "$HOME" -printf '%p %y %l %s\n' 2>/dev/null | sort; }

mkbundle() { # dir
  mkdir -p "$1/data/flutter_assets" "$1/lib"
  cp /usr/bin/sleep "$1/aurora_music"; chmod +x "$1/aurora_music"
  echo x >"$1/lib/libapp.so"
  echo a >"$1/data/flutter_assets/a.txt"
}
mkinstall() { # crea instalacion completa a mano
  mkbundle "$APP"
  mkdir -p "$HOME/.local/bin" "$(dirname "$DESK")" "$(dirname "$ICON")"
  ln -s "$APP/aurora_music" "$LINK"
  printf '[Desktop Entry]\nName=Aurora\nExec=%s %%U\n' "$HOME/.local/bin/aurora-music" >"$DESK"
  echo png >"$ICON"
}
mkdata() {
  mkdir -p "$DATA/logs" "$DATA/lyrics" "$DATA/downloads" "$CACHE"
  echo db >"$DATA/aurora.sqlite"; echo '{}' >"$DATA/shared_preferences.json"
  echo l >"$DATA/logs/a.log"; echo y >"$DATA/lyrics/x.lrc"; echo h >"$DATA/.oculto"
  echo song >"$DATA/downloads/song.mp3"
  echo c >"$CACHE/file"
}
launch() { # ejecutable -> LPID
  "$1" 1000 >/dev/null 2>&1 &
  LPID=$!; PIDS+=("$LPID")
  sleep 0.4
}
std_dirs_exist() {
  present "$HOME/.local/bin"; present "$HOME/.local/share/applications"; present "$HOME/.local/share"
}

# 1
new_case "1 opcion desconocida"
mkinstall; before="$(snap)"
run --bogus
rc_is 2; check "no borra nada" test "$before" = "$(snap)"
run --help; rc_is 0

# 2 HOME invalido
new_case "2 HOME vacio"
export HOME=""; run --yes; rc_is 1
new_case "2 HOME relativo"
mkdir -p "$CASE/cwd/rel"; export HOME="rel"; run --yes; rc_is 1
new_case "2 HOME /"
export HOME="/"; run --yes; rc_is 1

# 3
new_case "3 sin purge"
mkinstall; mkdata
run --yes
rc_is 0
absent "$APP"; absent "$LINK"; absent "$DESK"; absent "$ICON"
present "$DATA/aurora.sqlite"; present "$DATA/downloads/song.mp3"; present "$DATA/.oculto"; present "$CACHE/file"
absent "$FAKE_LOG"
std_dirs_exist

# 4a
new_case "4a app que no es Aurora (falta libapp.so)"
mkinstall; rm "$APP/lib/libapp.so"; before="$(snap)"
run --yes; rc_is 1
check "no borra nada" test "$before" = "$(snap)"
new_case "4a app sin ejecutable"
mkinstall; chmod -x "$APP/aurora_music"; before="$(snap)"
run --yes; rc_is 1; check "no borra nada" test "$before" = "$(snap)"
new_case "4a app sin flutter_assets"
mkinstall; rm -r "$APP/data/flutter_assets"; before="$(snap)"
run --yes; rc_is 1; check "no borra nada" test "$before" = "$(snap)"

# 4b
new_case "4b app enlace simbolico"
mkbundle "$CASE/real"
mkinstall; rm -rf "$APP"; ln -s "$CASE/real" "$APP"
run --yes; rc_is 0
absent "$APP"; present "$CASE/real/aurora_music"; present "$CASE/real/lib/libapp.so"; present "$CASE/real/data/flutter_assets/a.txt"
absent "$DESK"; absent "$ICON"

# 4c
new_case "4c comando es enlace a otra cosa"
mkinstall; echo o >"$CASE/otro"; rm "$LINK"; ln -s "$CASE/otro" "$LINK"
run --yes; rc_is 0
check "enlace ajeno intacto" test "$(readlink "$LINK")" = "$CASE/otro"
absent "$APP"; absent "$DESK"; absent "$ICON"
new_case "4c comando es archivo normal"
mkinstall; rm "$LINK"; echo normal >"$LINK"
run --yes; rc_is 0
check "archivo intacto" test "$(cat "$LINK")" = normal
absent "$APP"; absent "$DESK"; absent "$ICON"

# 4d
new_case "4d desktop ajeno"
mkinstall; printf '[Desktop Entry]\nExec=/usr/bin/otro %%U\n' >"$DESK"
run --yes; rc_is 0
present "$DESK"; check "contenido intacto" grep -q /usr/bin/otro "$DESK"
absent "$APP"; absent "$LINK"; absent "$ICON"

# 4e/f
new_case "4e/f carpetas estandar y ajenos"
mkinstall
echo x >"$HOME/.local/bin/otro"; echo y >"$(dirname "$DESK")/otro.desktop"
run --yes; rc_is 0
std_dirs_exist; present "$HOME/.local/bin/otro"; present "$(dirname "$DESK")/otro.desktop"
absent "$APP"; absent "$LINK"; absent "$DESK"; absent "$ICON"
new_case "4e carpetas estandar vacias tras desinstalar"
mkinstall; run --yes; rc_is 0; std_dirs_exist

# 5
new_case "5 purge completa con downloads"
mkinstall; mkdata
run --purge --yes; rc_is 0
absent "$APP"; absent "$LINK"; absent "$DESK"; absent "$ICON"
absent "$DATA/aurora.sqlite"; absent "$DATA/shared_preferences.json"; absent "$DATA/logs"; absent "$DATA/lyrics"; absent "$DATA/.oculto"
present "$DATA/downloads/song.mp3"
check "datos solo con downloads" test "$(ls -A "$DATA")" = downloads
absent "$CACHE"
check "salida menciona downloads" bash -c '[[ "$1" == *"$2"* ]]' _ "$OUT" "$DATA/downloads"
check "secret-tool con argumentos exactos" test "$(cat "$FAKE_LOG" 2>/dev/null)" = "clear account com.aurora.aurora_music.secureStorage"

new_case "5b downloads vacia"
mkinstall; mkdata; rm "$DATA/downloads/song.mp3"
run --purge --yes; rc_is 0
absent "$DATA"; absent "$CACHE"

new_case "5c datos es enlace simbolico"
mkinstall; mkdir -p "$CASE/realdata/sub"; echo k >"$CASE/realdata/sub/f"; echo k >"$CASE/realdata/top"
ln -s "$CASE/realdata" "$DATA"
run --purge --yes; rc_is 0
absent "$DATA"; present "$CASE/realdata/top"; present "$CASE/realdata/sub/f"

new_case "5d solo datos, sin app"
mkdata
run --purge --yes; rc_is 0
absent "$DATA/aurora.sqlite"; absent "$CACHE"

new_case "5e enlaces internos hacia fuera"
mkinstall; mkdata; rm "$DATA/downloads/song.mp3"
mkdir -p "$CASE/fuera/d"; echo z >"$CASE/fuera/d/f"; echo z >"$CASE/fuera/file"
ln -s "$CASE/fuera/d" "$DATA/lnkdir"; ln -s "$CASE/fuera/file" "$DATA/lnkfile"
run --purge --yes; rc_is 0
absent "$DATA/lnkdir"; absent "$DATA/lnkfile"
present "$CASE/fuera/d/f"; present "$CASE/fuera/file"

# 6
for mode in "--dry-run" "--purge --dry-run"; do
  new_case "6 dry-run ($mode)"
  mkinstall; mkdata; launch "$APP/aurora_music"; pid=$LPID
  before="$(snap)"
  run $mode --yes
  rc_is 0
  check "no borra nada" test "$before" = "$(snap)"
  check "no mata procesos" alive "$pid"
  absent "$FAKE_LOG"
  check "imprime algo" test -n "$OUT"
  kill -9 "$pid" 2>/dev/null
done
new_case "6 dry-run -n sin --yes"
mkinstall; before="$(snap)"; run -n; rc_is 0; check "no borra" test "$before" = "$(snap)"

# 7
new_case "7 sin terminal ni --yes"
mkinstall; before="$(snap)"
OUT="$(setsid -w bash "$UN" </dev/null 2>&1)"; RC=$?
rc_is 1; check "no borra nada" test "$before" = "$(snap)"
new_case "7 sin terminal ni --yes con purge"
mkinstall; mkdata; before="$(snap)"
OUT="$(setsid -w bash "$UN" --purge </dev/null 2>&1)"; RC=$?
rc_is 1; check "no borra nada" test "$before" = "$(snap)"; absent "$FAKE_LOG"

# 8
new_case "8 nada que desinstalar"
before="$(snap)"
run --yes; rc_is 0; check "mensaje" test -n "$OUT"
check "no crea ni borra" test "$before" = "$(snap)"
run --purge --yes; rc_is 0; check "no crea ni borra (purge)" test "$before" = "$(snap)"

# 9
new_case "9 Aurora abierta desde la app"
mkinstall; launch "$APP/aurora_music"; pid=$LPID
check "proceso vivo antes" alive "$pid"
run --yes; rc_is 0
sleep 0.5
if alive "$pid"; then fail "el proceso sigue vivo"; else pass; fi
absent "$APP"; absent "$LINK"

# 10
new_case "10 purge con otra Aurora (otra ruta)"
mkinstall; mkdata
mkdir -p "$HOME/otra"; cp /usr/bin/sleep "$HOME/otra/aurora_music"
launch "$HOME/otra/aurora_music"; pid=$LPID
before="$(snap)"
run --purge --yes; rc_is 1
check "no borra nada" test "$before" = "$(snap)"
check "proceso sigue vivo" alive "$pid"
kill -9 "$pid" 2>/dev/null
new_case "10 sin purge ignora otro proceso"
mkinstall
mkdir -p "$HOME/otra"; cp /usr/bin/sleep "$HOME/otra/aurora_music"
launch "$HOME/otra/aurora_music"; pid=$LPID
run --yes; rc_is 0
absent "$APP"; check "otro proceso vivo" alive "$pid"
kill -9 "$pid" 2>/dev/null

# 11
new_case "11 XDG absoluto"
export XDG_DATA_HOME="$HOME/xdg/data"; export XDG_CACHE_HOME="$HOME/xdg/cache"; set_paths
mkinstall; mkdata
run --purge --yes; rc_is 0
absent "$APP"; absent "$DESK"; absent "$ICON"; absent "$LINK"
absent "$DATA/aurora.sqlite"; absent "$CACHE"
new_case "11 XDG_DATA_HOME relativo se ignora"
mkinstall
mkdir -p "$CASE/cwd/rel"; mkbundle "$CASE/cwd/rel/aurora-music"
export XDG_DATA_HOME="rel"
run --yes; rc_is 0
absent "$APP"; present "$CASE/cwd/rel/aurora-music/aurora_music"; absent "$LINK"

# 12
new_case "12 install.sh --uninstall --yes"
mkinstall; mkdata; cp "$UN" "$APP/uninstall.sh"
OUT="$(bash "$IN" --uninstall --yes </dev/null 2>&1)"; RC=$?
rc_is 0
absent "$APP"; absent "$LINK"; absent "$DESK"; absent "$ICON"
present "$DATA/aurora.sqlite"; present "$CACHE/file"; absent "$FAKE_LOG"
new_case "12 install.sh --uninstall --dry-run"
mkinstall; before="$(snap)"
OUT="$(bash "$IN" --uninstall --dry-run </dev/null 2>&1)"; RC=$?
rc_is 0; check "no borra" test "$before" = "$(snap)"
new_case "12 install.sh deja uninstall.sh y funciona"
mkbundle "$CASE/bundle"
OUT="$(bash "$IN" "$CASE/bundle" </dev/null 2>&1)"; RC=$?
rc_is 0
present "$APP/uninstall.sh"; present "$LINK"; present "$DESK"; present "$ICON"
check "Exec exacto" grep -qxF "Exec=$HOME/.local/bin/aurora-music %U" "$DESK"
mkdata
OUT="$(bash "$APP/uninstall.sh" --yes </dev/null 2>&1)"; RC=$?
rc_is 0
absent "$APP"; absent "$LINK"; absent "$DESK"; absent "$ICON"; present "$DATA/aurora.sqlite"

# 13
new_case "13 install.sh no reemplaza carpeta ajena"
mkbundle "$CASE/bundle"
mkdir -p "$APP"; echo mio >"$APP/dato.txt"
OUT="$(bash "$IN" "$CASE/bundle" </dev/null 2>&1)"; RC=$?
rc_is 1
check "carpeta intacta" test "$(ls -A "$APP")" = dato.txt
check "contenido intacto" test "$(cat "$APP/dato.txt")" = mio

# 14 XDG apuntando a carpetas del sistema (no se crea nada fuera del HOME temporal)
for var_val in "XDG_DATA_HOME=/usr/share" "XDG_CACHE_HOME=/etc"; do
  for opts in "--yes" "--purge --yes" "--dry-run"; do
    new_case "14 $var_val $opts"
    mkinstall; mkdata; before="$(snap)"
    export "$var_val"
    run $opts
    rc_is 1
    check "HOME temporal intacto" test "$before" = "$(snap)"
  done
done
new_case "14 XDG_DATA_HOME=/usr/share/ (barra final)"
mkinstall; before="$(snap)"; export XDG_DATA_HOME=/usr/share/
run --yes; rc_is 1; check "HOME temporal intacto" test "$before" = "$(snap)"
new_case "14 carpeta bajo /var no es del sistema"
VT="$(mktemp -d /var/tmp/aurora-test.XXXXXX 2>/dev/null)"
if [ -n "$VT" ]; then
  EXTRA+=("$VT")
  export XDG_DATA_HOME="$VT/data"; export XDG_CACHE_HOME="$VT/cache"; set_paths
  mkinstall; mkdata
  run --purge --yes; rc_is 0
  absent "$APP"; absent "$DATA/aurora.sqlite"; absent "$CACHE"
fi

echo
echo "Pasados: $PASS  Fallidos: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'FALLO: %s\n' "${FAILED[@]}"
  exit 1
fi
exit 0
