#!/usr/bin/env bash
# Comprueba que el bundle de Aurora no tiene bibliotecas sin resolver.
# Uso: check_bundle.sh <bundle_dir>
set -euo pipefail

bundle="${1:?Uso: check_bundle.sh <bundle_dir>}"
status=0

for file in "$bundle/aurora_music" "$bundle"/lib/*.so*; do
  [ -f "$file" ] || continue
  # libdartjni (paquete jni) pide libjvm.so, pero solo se abre en Android.
  [ "$(basename "$file")" != libdartjni.so ] || continue
  while read -r missing; do
    echo "$(basename "$file") → falta $missing"
    status=1
  # Como en ejecución: las dependencias entre códecs se resuelven dentro del bundle.
  done < <(LD_LIBRARY_PATH="$bundle/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    ldd "$file" 2>/dev/null | awk '/not found/ {print $1}')
done

# Flutter abre EGL y GLES al arrancar (dlopen), así que ldd no las ve.
cache="$({ command -v ldconfig >/dev/null && ldconfig -p || /sbin/ldconfig -p; } 2>/dev/null || true)"
for lib in libEGL.so.1 libGLESv2.so.2; do
  if ! grep -q "[[:space:]]$lib " <<<"$cache"; then
    echo "aurora_music → falta $lib"
    status=1
  fi
done

exit "$status"
