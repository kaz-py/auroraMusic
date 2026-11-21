[CmdletBinding()]
param([string]$EnvFile = '', [string]$Output = '')
# Genera dart_defines.json (ignorado por git) desde .env para `flutter build --dart-define-from-file`.
# Falla si falta una clave: una compilación sin AURORA_DISCORD_CLIENT_ID oculta Discord, y sin las
# de Last.fm desactiva el scrobbling, sin avisar.
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $EnvFile) { $EnvFile = Join-Path $project '.env' }
if (-not $Output) { $Output = Join-Path $project 'dart_defines.json' }
$required = 'AURORA_SUPABASE_URL','AURORA_SUPABASE_ANON_KEY','AURORA_LASTFM_API_KEY','AURORA_LASTFM_SECRET','AURORA_DISCORD_CLIENT_ID'
if (-not (Test-Path -LiteralPath $EnvFile)) { throw "No existe $EnvFile." }
$values = [ordered]@{}
foreach ($line in Get-Content -LiteralPath $EnvFile) {
    # Acepta «CLAVE=valor» y «CLAVE = valor» (con espacios) y comillas opcionales.
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $values[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
    }
}
$missing = $required | Where-Object { -not $values.Contains($_) -or [string]::IsNullOrWhiteSpace($values[$_]) }
if ($missing) { throw "Faltan en ${EnvFile}: $($missing -join ', ')" }
$selected = [ordered]@{}
foreach ($key in $required) { $selected[$key] = $values[$key] }
$selected | ConvertTo-Json | Set-Content -LiteralPath $Output -Encoding utf8
Write-Host "Escrito $Output con $($selected.Count) claves: $($required -join ', ')"
