#!/usr/bin/env bash
# Comprueba en Linux la cadena de audio de YouTube de Aurora y el estado de
# los procesos. Se ejecuta desde la raíz del repositorio con el SDK de Dart
# (o Flutter) en el PATH. Usa la red real.
#
# Uso: scripts/linux/verify_playback.sh [segundos_de_muestreo]
#   1. Cadena: resuelve y arranca 5 pistas seguidas por el orquestador y el
#      proxy local, forzando la salida por un relé que anota cada destino
#      (prueba que el «player» y googlevideo salen por la ruta de proxy).
#   2. Si hay https_proxy/http_proxy/all_proxy, repite la prueba por TU proxy
#      y compara la IP de salida (api.ipify.org) por la ruta y en directo.
#   3. Procesos: yt-dlp/deno zombis (fallo) o huérfanos (aviso).
#   4. Si Aurora está abierta, muestrea RAM y CPU mientras cambias canciones.
set -uo pipefail

seconds="${1:-30}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
status=0

if command -v dart >/dev/null 2>&1; then
  dart_cmd=(dart)
elif command -v flutter >/dev/null 2>&1; then
  # El Dart que trae el SDK de Flutter (bin/cache/dart-sdk).
  flutter_bin="$(dirname "$(readlink -f "$(command -v flutter)")")"
  dart_cmd=("$flutter_bin/cache/dart-sdk/bin/dart")
else
  echo "Falta dart o flutter en el PATH." >&2
  exit 2
fi

echo "== 1. Cadena de reproducción por el relé de prueba"
"${dart_cmd[@]}" run tool/verify_stream_chain.dart --relay || status=1

if [[ -n "${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}}}" ]]; then
  echo
  echo "== 2. Cadena por el proxy configurado en el entorno"
  "${dart_cmd[@]}" run tool/verify_stream_chain.dart --check-ip || status=1
  echo "(Si «route» y «direct» dan la misma IP, el proxy no se está usando."
  echo " Un proxy socks5:// o socks5h:// no lo admite Aurora: verás el aviso en «route».)"
fi

echo
echo "== 3. Procesos yt-dlp / deno"
procs="$(ps -eo pid=,ppid=,stat=,etime=,comm= 2>/dev/null | awk '$5 ~ /^(yt-dlp|deno)$/')"
if [[ -z "$procs" ]]; then
  echo "Ninguno en ejecución."
else
  echo "  PID  PPID STAT  TIEMPO COMANDO"
  echo "$procs"
  if awk '$3 ~ /^Z/' <<<"$procs" | grep -q .; then
    echo "FALLO: hay procesos zombis."
    status=1
  fi
  while read -r pid ppid _; do
    parent="$(ps -o comm= -p "$ppid" 2>/dev/null || true)"
    if [[ "$ppid" == 1 || "$parent" == systemd ]]; then
      echo "AVISO: $pid quedó huérfano (padre $ppid $parent)."
    fi
  done <<<"$procs"
fi

echo
echo "== 4. RAM y CPU de Aurora"
pid="$(pgrep -x aurora_music | head -n1 || true)"
if [[ -z "$pid" ]]; then
  echo "Aurora no está abierta: se omite. Ábrela y vuelve a ejecutar el script."
else
  echo "Aurora (PID $pid): muestreo de ${seconds} s. Cambia de canción varias veces ahora."
  min_rss=0 max_rss=0 max_cpu=0 sum_cpu=0 n=0
  prev_ticks="" prev_t=""
  hz="$(getconf CLK_TCK)"
  for ((i = 0; i < seconds; i++)); do
    [[ -r "/proc/$pid/stat" ]] || { echo "Aurora se cerró."; break; }
    rss_kb="$(awk '/^VmRSS/ {print $2}' "/proc/$pid/status")"
    # utime + stime (campos 14 y 15) tras el nombre entre paréntesis.
    ticks="$(sed 's/^.*) //' "/proc/$pid/stat" | awk '{print $12 + $13}')"
    t="$(date +%s.%N)"
    if [[ -n "$prev_ticks" ]]; then
      cpu="$(awk -v a="$prev_ticks" -v b="$ticks" -v ta="$prev_t" -v tb="$t" -v hz="$hz" \
        'BEGIN { printf "%.1f", (b - a) / hz / (tb - ta) * 100 }')"
      sum_cpu="$(awk -v s="$sum_cpu" -v c="$cpu" 'BEGIN { print s + c }')"
      max_cpu="$(awk -v m="$max_cpu" -v c="$cpu" 'BEGIN { print (c > m ? c : m) }')"
      n=$((n + 1))
    fi
    ((min_rss == 0 || rss_kb < min_rss)) && min_rss=$rss_kb
    ((rss_kb > max_rss)) && max_rss=$rss_kb
    prev_ticks=$ticks prev_t=$t
    sleep 1
  done
  if ((n > 0)); then
    echo "RSS: mín $((min_rss / 1024)) MiB, máx $((max_rss / 1024)) MiB (subida $(((max_rss - min_rss) / 1024)) MiB)"
    echo "CPU: media $(awk -v s="$sum_cpu" -v n="$n" 'BEGIN { printf "%.1f", s / n }')%, pico ${max_cpu}%"
  fi
  children="$(pgrep -P "$pid" -l || true)"
  echo "Procesos hijos de Aurora ahora: ${children:-ninguno}"
fi

echo
if ((status == 0)); then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO"; fi
exit "$status"
