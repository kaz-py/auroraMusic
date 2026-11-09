[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
# A build can launch Windows PowerShell from a PowerShell 7 parent. Resolve its
# own utility module explicitly instead of inheriting the parent's module path.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $project 'tools/windows'
$names = @('yt-dlp.exe','deno.exe','tools.lock.json','binaries.sha256.json','licenses','vosk')
$missing = @($names | Where-Object { -not (Test-Path -LiteralPath (Join-Path $source $_)) })
if ($missing.Count) {
    Write-Host 'Preparando las herramientas de Aurora con versiones y SHA-256 fijados...'
    & (Join-Path $PSScriptRoot 'setup_tools.ps1') -ToolDirectory $source
}
$hashes = Get-Content -LiteralPath (Join-Path $source 'binaries.sha256.json') -Raw | ConvertFrom-Json
foreach ($name in @('yt-dlp.exe','deno.exe')) {
    if ($hashes.$name -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash -ne $hashes.$name) {
        throw "Herramienta modificada o sin verificar: $name"
    }
}
$Destination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($name in $names) {
    $target = Join-Path $Destination $name
    if ($name -like '*.exe' -and (Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $hashes.$name) { continue }
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $Destination -Recurse -Force
}
Write-Host "Aurora: herramientas verificadas incluidas en $Destination"
