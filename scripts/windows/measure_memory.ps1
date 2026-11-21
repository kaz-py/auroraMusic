# Mide la memoria de Aurora en Windows con las mismas cifras que
# scripts/linux/measure_memory.sh, para comparar en igualdad de condiciones.
#
# «Working set privado» es la columna «Memoria» del Administrador de tareas;
# se compara con «Privada» del script de Linux, no con su RSS.
#
# Uso: scripts/windows/measure_memory.ps1 [-ProcessId <pid>] [-Seconds <n>]
param([int]$ProcessId = 0, [int]$Seconds = 0)

$proc = if ($ProcessId) {
  Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
} else {
  Get-Process aurora_music -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $proc) { Write-Error 'Aurora no está abierta.'; exit 2 }

function Get-AuroraSample {
  $proc.Refresh()
  # CIM y no Get-Counter: los nombres de los contadores cambian con el idioma.
  $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$($proc.Id)"
  [pscustomobject]@{
    PrivateWS = [double]$perf.WorkingSetPrivate
    WS        = [double]$proc.WorkingSet64
    Private   = [double]$proc.PrivateMemorySize64
  }
}

function Format-MiB([double]$bytes) { '{0,7:N1} MiB' -f ($bytes / 1MB) }

if ($Seconds -gt 0) {
  "Muestreo de $Seconds s (PID $($proc.Id))…"
  $samples = for ($i = 0; $i -lt $Seconds; $i++) { Get-AuroraSample; Start-Sleep -Seconds 1 }
  foreach ($name in 'PrivateWS', 'WS', 'Private') {
    $m = $samples | Measure-Object -Property $name -Minimum -Maximum
    '  {0,-10} mín {1}  máx {2}' -f $name, (Format-MiB $m.Minimum), (Format-MiB $m.Maximum)
  }
  ''
}

$s = Get-AuroraSample
$proc.Refresh()
"Aurora PID $($proc.Id) — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') — vivo desde $([int]((Get-Date) - $proc.StartTime).TotalSeconds) s"
'  Working set privado  {0}  (Administrador de tareas; comparar con «Privada sucia» de Linux)' -f (Format-MiB $s.PrivateWS)
'  Working set          {0}  (equivalente al RSS de Linux)' -f (Format-MiB $s.WS)
'    compartido         {0}' -f (Format-MiB ($s.WS - $s.PrivateWS))
'  Bytes privados       {0}  (memoria comprometida, incluida la recortada)' -f (Format-MiB $s.Private)
'  Pico working set     {0} · Hilos {1}' -f (Format-MiB $proc.PeakWorkingSet64), $proc.Threads.Count
