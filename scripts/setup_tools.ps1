[CmdletBinding()]
param(
    [string]$ToolDirectory = '',
    [string]$YtDlpVersion = '',
    [string]$DenoVersion = ''
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$ProgressPreference = 'SilentlyContinue'
if ([string]::IsNullOrWhiteSpace($ToolDirectory)) { $ToolDirectory = Join-Path $PSScriptRoot '..\tools\windows' }
$ToolDirectory = [IO.Path]::GetFullPath($ToolDirectory)
New-Item -ItemType Directory -Path $ToolDirectory -Force | Out-Null
$lockPath = Join-Path $ToolDirectory 'tools.lock.json'
$headers = @{ 'User-Agent' = 'Aurora-tool-setup'; 'Accept' = 'application/vnd.github+json' }

function Get-PinnedAsset([string]$Repository, [string]$Version, [string]$Pattern) {
    $endpoint = if ($Version -eq 'latest') { 'latest' } else { "tags/$Version" }
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/$endpoint" -Headers $headers -TimeoutSec 60
    $asset = @($release.assets | Where-Object { $_.name -match $Pattern })
    if ($asset.Count -ne 1) { throw "No se encuentra un único archivo para $Repository ($Pattern)." }
    # Use provider metadata or a checksum file published alongside this release.
    $expectedHash = $null
    if ($asset[0].digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $expectedHash = $Matches[1].ToLowerInvariant()
    } else {
        $checksumAssets = @($release.assets | Where-Object { $_.name -match '(?i)(SHA2-256SUMS|checksums\.sha256|sha256sum|\.sha256)$' })
        foreach ($checksumAsset in $checksumAssets) {
            $checksumText = (Invoke-WebRequest -Uri $checksumAsset.browser_download_url -Headers $headers).Content
            foreach ($line in ($checksumText -split "`n")) {
                if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and [IO.Path]::GetFileName($Matches[2]) -eq $asset[0].name) { $expectedHash = $Matches[1].ToLowerInvariant(); break }
                if ($checksumAsset.name.StartsWith($asset[0].name) -and $line.Trim() -match '^([0-9a-fA-F]{64})$') { $expectedHash = $Matches[1].ToLowerInvariant(); break }
            }
            if ($expectedHash) { break }
        }
    }
    if (-not $expectedHash) { throw "No hay SHA-256 publicado para $($asset[0].name). No se instalará sin verificación." }
    $pin = @{ repository = $Repository; version = $release.tag_name; name = $asset[0].name; url = $asset[0].browser_download_url; sha256 = $expectedHash }
    if ($Repository -eq 'yt-dlp/yt-dlp-nightly-builds') {
        if ($release.body -notmatch 'Generated from: https://github\.com/yt-dlp/yt-dlp/commit/([0-9a-f]{40})') { throw 'Nightly release is missing source provenance.' }
        $pin.sourceCommit = $Matches[1]
        $pin.checksumUrl = "https://github.com/$Repository/releases/download/$($release.tag_name)/SHA2-256SUMS"
    }
    return $pin
}

$defaultPins = Join-Path $PSScriptRoot 'windows_tools.lock.json'
$pinsFile = if (Test-Path -LiteralPath $lockPath) { $lockPath } else { $defaultPins }
if (-not (Test-Path -LiteralPath $pinsFile)) { throw 'Falta scripts/windows_tools.lock.json con versiones verificadas.' }
$pins = Get-Content -LiteralPath $pinsFile -Raw | ConvertFrom-Json
# Migrate an existing stable setup to the committed, verified nightly baseline.
if (-not $YtDlpVersion -and $pins.ytdlp.repository -ne 'yt-dlp/yt-dlp-nightly-builds') {
    $pins.ytdlp = (Get-Content -LiteralPath $defaultPins -Raw | ConvertFrom-Json).ytdlp
}
# Explicit versions (including latest) update only the requested tool.
if ($YtDlpVersion) { $pins.ytdlp = Get-PinnedAsset 'yt-dlp/yt-dlp-nightly-builds' $YtDlpVersion '^yt-dlp\.exe$' }
if ($DenoVersion) { $pins.deno = Get-PinnedAsset 'denoland/deno' $DenoVersion '^deno-x86_64-pc-windows-msvc\.zip$' }
# Aurora ya no usa FFmpeg: un tools.lock.json antiguo puede traerlo.
$pins.PSObject.Properties.Remove('ffmpeg')

$staging = Join-Path $ToolDirectory ('.staging-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    foreach ($tool in 'ytdlp', 'deno') {
        $pin = $pins.$tool
        if ($pin.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "Hash inválido para $tool." }
        if ($pin.url -notmatch '^https://github\.com/(yt-dlp/yt-dlp-nightly-builds|denoland/deno)/releases/download/') { throw 'URL de herramientas no autorizada.' }
        $download = Join-Path $staging ([IO.Path]::GetFileName($pin.name))
        Write-Host "Descargando $tool ($($pin.version)); verificando SHA-256 oficial."
        Invoke-WebRequest -Uri $pin.url -OutFile $download -Headers $headers -TimeoutSec 600
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pin.sha256.ToLowerInvariant()) { throw "SHA-256 incorrecto: $tool. No se instalará." }
        if ($tool -ne 'ytdlp') { Expand-Archive -LiteralPath $download -DestinationPath (Join-Path $staging $tool) }
    }
    $binaries = @{
        'yt-dlp.exe' = Join-Path $staging $pins.ytdlp.name
        'deno.exe' = (Get-ChildItem -LiteralPath (Join-Path $staging 'deno') -Filter deno.exe -Recurse | Select-Object -First 1).FullName
    }
    foreach ($name in $binaries.Keys) {
        if (-not $binaries[$name] -or -not (Test-Path -LiteralPath $binaries[$name])) { throw "Falta el binario $name." }
    }
    $licenses = Join-Path $staging 'licenses'
    New-Item -ItemType Directory -Path $licenses | Out-Null
    if ($pins.ytdlp.sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Nightly yt-dlp source commit is missing or invalid.' }
    $licenseSources = @{
        'yt-dlp-LICENSE.txt' = "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$($pins.ytdlp.sourceCommit)/LICENSE"
        'yt-dlp-THIRD_PARTY_LICENSES.txt' = "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$($pins.ytdlp.sourceCommit)/THIRD_PARTY_LICENSES.txt"
        'deno-LICENSE.md' = "https://raw.githubusercontent.com/denoland/deno/$($pins.deno.version)/LICENSE.md"
    }
    foreach ($notice in $licenseSources.Keys) {
        Invoke-WebRequest -Uri $licenseSources[$notice] -OutFile (Join-Path $licenses $notice) -Headers $headers -TimeoutSec 60
    }
    $binaryHashes = @{}
    foreach ($name in $binaries.Keys) {
        Copy-Item -LiteralPath $binaries[$name] -Destination (Join-Path $ToolDirectory $name) -Force
        $binaryHashes[$name] = (Get-FileHash -LiteralPath $binaries[$name] -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $binaryHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ToolDirectory 'binaries.sha256.json') -Encoding utf8
    # A rejected download must leave the installed versions' lock unchanged.
    $pins | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath -Encoding utf8
    Copy-Item -LiteralPath $licenses -Destination $ToolDirectory -Recurse -Force
    $licenseSources | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ToolDirectory 'licenses/sources.json') -Encoding utf8
    Write-Host "Herramientas verificadas instaladas en $ToolDirectory; la compilación las incluye automáticamente."
    Write-Host 'tools.lock.json fija las versiones y hashes. Conserva los avisos de licencia de los binarios al redistribuir.'
} finally {
    $resolvedStaging = [IO.Path]::GetFullPath($staging)
    if (-not $resolvedStaging.StartsWith($ToolDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta temporal fuera del directorio de herramientas.' }
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
}
