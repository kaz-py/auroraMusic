#!/usr/bin/env bash
# Mide la memoria de Aurora en Linux y separa lo propio del proceso (privado,
# anónimo) de lo compartido (bibliotecas) y de los búferes de GPU.
#
# El RSS que muestran top/htop/Monitor del sistema cuenta las páginas de las
# bibliotecas (equivale al «Working set» de Windows). La columna «Memoria» del
# Administrador de tareas es el working set PRIVADO: compárala con «Privada
# sucia», no con el RSS.
#
# Uso: scripts/linux/measure_memory.sh [pid|auto] [segundos]
#   pid|auto   proceso a medir (por defecto, el primer aurora_music)
#   segundos   si es > 0, muestrea cada segundo y da mín/máx antes del detalle
#   TOP=N      número de mapeos del desglose (15 por defecto)
set -uo pipefail

target="${1:-auto}"
seconds="${2:-0}"
top="${TOP:-15}"

if [[ "$target" == auto ]]; then
  pid="$(pgrep -x aurora_music | head -n1 || true)"
else
  pid="$target"
fi
if [[ -z "$pid" || ! -r "/proc/$pid/smaps_rollup" ]]; then
  echo "No encuentro Aurora (pid '${pid:-}'). Ábrela o pasa el PID." >&2
  exit 2
fi

# Valor en kB de un campo «Nombre:» de un archivo de /proc.
kb() { awk -v k="$1:" '$1 == k { print $2; found = 1; exit } END { if (!found) print 0 }' "$2"; }
mib() { awk -v v="${1:-0}" 'BEGIN { printf "%7.1f MiB", v / 1024 }'; }

# rss pss privada_sucia anonima
sample() {
  local r="/proc/$pid/smaps_rollup"
  echo "$(kb Rss "$r") $(kb Pss "$r") $(kb Private_Dirty "$r") $(kb Anonymous "$r")"
}

if ((seconds > 0)); then
  echo "Muestreo de $seconds s (PID $pid)…"
  min=() max=()
  for ((i = 0; i < seconds; i++)); do
    [[ -r "/proc/$pid/smaps_rollup" ]] || { echo "Aurora se cerró."; exit 1; }
    read -r -a v <<<"$(sample)"
    for j in 0 1 2 3; do
      ((${#min[@]} <= j || v[j] < min[j])) && min[j]=${v[j]}
      ((${#max[@]} <= j || v[j] > max[j])) && max[j]=${v[j]}
    done
    sleep 1
  done
  names=(RSS PSS Sucia Anónima)
  for j in 0 1 2 3; do
    printf '  %-8s mín %s  máx %s\n' "${names[j]}" "$(mib "${min[j]}")" "$(mib "${max[j]}")"
  done
  echo
fi

r="/proc/$pid/smaps_rollup"
s="/proc/$pid/status"
echo "Aurora PID $pid — $(date '+%F %T') — vivo desde $(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
printf '  RSS         %s  (top/htop/Monitor del sistema; en Windows, «Working set»)\n' "$(mib "$(kb Rss "$r")")"
printf '  PSS         %s  (RSS con lo compartido repartido entre procesos)\n' "$(mib "$(kb Pss "$r")")"
printf '  Privada sucia  %s  (en Windows, «Working set privado»: la columna del Administrador de tareas)\n' "$(mib "$(kb Private_Dirty "$r")")"
printf '  Privada limpia %s  (páginas de bibliotecas que solo usa Aurora; el sistema las puede descartar)\n' "$(mib "$(kb Private_Clean "$r")")"
printf '  Compartida  %s\n' "$(mib $(($(kb Shared_Clean "$r") + $(kb Shared_Dirty "$r"))))"
printf '  Anónima     %s\n' "$(mib "$(kb Anonymous "$r")")"
printf '  RssAnon %s · RssFile %s · RssShmem %s\n' "$(mib "$(kb RssAnon "$s")")" "$(mib "$(kb RssFile "$s")")" "$(mib "$(kb RssShmem "$s")")"
printf '  Swap        %s · Hilos %s\n' "$(mib "$(kb Swap "$r")")" "$(kb Threads "$s")"

maps="/proc/$pid/maps"
gl="$(grep -oE '[^/ ]*(d3d12|gallium|swrast|llvmpipe|LLVM|nvidia|radeonsi|iris|zink)[^/ ]*\.so[^/ ]*' "$maps" 2>/dev/null | sort -u | tr '\n' ' ')"
echo "  GL cargado: ${gl:-ninguno detectado}"
grep -q '/dev/dxg' "$maps" 2>/dev/null && echo "  Usa /dev/dxg: GPU de Windows a través de d3d12 (WSLg)"

echo
echo "Por categoría (RSS · privada):"
awk '
  /^[0-9a-f]+-[0-9a-f]+ / {
    name = (NF >= 6) ? $6 : "[anónimo]"
    for (i = 7; i <= NF; i++) name = name " " $i
    if (name ~ /\.so/) cat = "bibliotecas (.so)"
    else if (name == "[heap]") cat = "[heap] (malloc principal)"
    else if (name == "[anónimo]" || name ~ /^\[anon/) cat = "anónimo (arenas malloc, heap Dart, búferes)"
    else if (name ~ /dxg|\/dev\/dri|memfd|drm|nvidia|kgsl/) cat = "GPU / memoria compartida"
    else if (name ~ /stack/) cat = "pilas de hilos"
    else cat = "otros archivos"
    next
  }
  $1 == "Rss:" { rss[cat] += $2; rssn[name] += $2 }
  $1 == "Private_Clean:" || $1 == "Private_Dirty:" { priv[cat] += $2; privn[name] += $2 }
  END {
    for (c in rss) printf "%d\t%d\t%s\n", rss[c], priv[c], c > "/dev/stderr"
    for (n in rssn) if (rssn[n] > 0) printf "%d\t%d\t%s\n", rssn[n], privn[n], n
  }
' "/proc/$pid/smaps" 2> >(sort -rn | awk -F'\t' '{ printf "  %8.1f MiB · %8.1f MiB  %s\n", $1 / 1024, $2 / 1024, $3 }' >&2) |
  sort -rn | head -n "$top" >"${TMPDIR:-/tmp}/aurora_maps_$$"
sleep 0.2
echo
echo "Top $top mapeos por RSS (RSS · privada):"
awk -F'\t' '{ printf "  %8.1f MiB · %8.1f MiB  %s\n", $1 / 1024, $2 / 1024, $3 }' "${TMPDIR:-/tmp}/aurora_maps_$$"
rm -f "${TMPDIR:-/tmp}/aurora_maps_$$"
