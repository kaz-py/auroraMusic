#!/usr/bin/env bash
# Comprueba que el bundle de Aurora no tiene bibliotecas sin resolver.
# Uso: check_bundle.sh <bundle_dir>
set -euo pipefail

bundle="${1:?Uso: check_bundle.sh <bundle_dir>}"
status=0

for file in "$bundle/aurora_music" "$bundle"/lib/*.so*; do
  [ -f "$file" ] || continue
  while read -r missing; do
    echo "$(basename "$file") → falta $missing"
    status=1
  done < <(ldd "$file" 2>/dev/null | awk '/not found/ {print $1}')
done

soloud="$bundle/lib/libflutter_soloud_plugin.so"
if [ -f "$soloud" ]; then
  if ! readelf -d "$soloud" | grep -Eq '\((RUNPATH|RPATH)\).*\[\$ORIGIN\]'; then
    echo "libflutter_soloud_plugin.so → RUNPATH distinto de [\$ORIGIN]"
    status=1
  fi
fi

exit "$status"
