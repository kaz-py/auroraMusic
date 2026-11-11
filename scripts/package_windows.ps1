[CmdletBinding()]
param([string]$ReleaseDirectory = '', [string]$ToolDirectory = '', [string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $project 'build/windows/x64/runner/Release' }
if (-not $ToolDirectory) { $ToolDirectory = Join-Path $project 'tools/windows' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project 'dist' }
$ReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
$ToolDirectory = [IO.Path]::GetFullPath($ToolDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDirectory 'aurora_music.exe'))) { throw 'Compila primero: flutter build windows --release' }
$flutterConfig = Get-Content -LiteralPath (Join-Path $project 'windows/flutter/ephemeral/generated_config.cmake') -Raw
if ($flutterConfig -notmatch '(?m)^file\(TO_CMAKE_PATH "([^"]+)" FLUTTER_ROOT\)') { throw 'No se encuentra el SDK Flutter de esta compilación.' }
$flutterSdk = $Matches[1].Replace('\\','\')
$releaseEngine = Join-Path $flutterSdk 'bin/cache/artifacts/engine/windows-x64-release/flutter_windows.dll'
$bundledEngine = Join-Path $ReleaseDirectory 'flutter_windows.dll'
if (-not (Test-Path -LiteralPath $releaseEngine) -or (Get-FileHash -LiteralPath $bundledEngine -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $releaseEngine -Algorithm SHA256).Hash) {
    throw 'La DLL Flutter no corresponde a release. Recompila Windows --release sin compilar otra configuración en paralelo.'
}
$hashFile = Join-Path $ToolDirectory 'binaries.sha256.json'
if (-not (Test-Path -LiteralPath $hashFile)) { throw 'Ejecuta scripts/setup_tools.ps1 para generar los hashes verificados.' }
$hashes = Get-Content -LiteralPath $hashFile -Raw | ConvertFrom-Json
foreach ($name in 'yt-dlp.exe','deno.exe') {
    $binary = Join-Path $ToolDirectory $name
    if (-not (Test-Path -LiteralPath $binary) -or $hashes.$name -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hashes.$name) { throw "Herramienta modificada o sin verificar: $name" }
}
if (-not (Test-Path -LiteralPath (Join-Path $ToolDirectory 'licenses'))) { throw 'Faltan avisos de licencia de herramientas.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$id = [guid]::NewGuid().ToString('N').Substring(0,8)
$stage = Join-Path $OutputDirectory ('.staging-' + $id)
$package = Join-Path $stage 'Aurora-Windows'
New-Item -ItemType Directory -Path $package -Force | Out-Null
Get-ChildItem -LiteralPath $ReleaseDirectory -Force | Copy-Item -Destination $package -Recurse
$packageTools = Join-Path $package 'tools'
New-Item -ItemType Directory -Path $packageTools -Force | Out-Null
foreach ($name in 'yt-dlp.exe','deno.exe','tools.lock.json','binaries.sha256.json','licenses') {
    Copy-Item -LiteralPath (Join-Path $ToolDirectory $name) -Destination $packageTools -Recurse -Force
}
@'
# Aurora para Windows

Extrae todo el ZIP en una carpeta y ejecuta aurora_music.exe. Mantén data/, las DLL y tools/ junto al ejecutable. No requiere Python instalado: yt-dlp y Deno vienen incluidos.

Aurora detecta tools/ automáticamente. Si ya configuraste otra carpeta, selecciona la carpeta tools/ de este paquete en Ajustes. Importa archivos locales o busca canciones y enlaces públicos de YouTube.

Los datos de biblioteca y preferencias se guardan en el directorio de aplicación del usuario. El paquete no incluye cuentas ni sincronización remota. Para quitarlo, cierra Aurora y elimina la carpeta que extrajiste.

YouTube puede retirar videos o limitar temporalmente solicitudes. En ese caso, espera y vuelve a intentar; los archivos locales siguen disponibles. Este paquete no evita verificaciones de cuenta o restricciones del proveedor.

En Ajustes puedes importar voluntariamente un archivo Netscape con tus propias cookies de YouTube, obtenido después de verificar tu sesión en el navegador. Aurora guarda una copia local de esa sesión; puedes retirarla desde Ajustes. Las cookies son credenciales sensibles y no garantizan resolver un límite de solicitudes. Usa únicamente contenido al que tengas acceso.

tools/binaries.sha256.json y tools/tools.lock.json registran los hashes y versiones verificados de las herramientas. Sus avisos originales están en tools/licenses/. Conserva esos archivos al redistribuir.
'@ | Set-Content -LiteralPath (Join-Path $package 'README-INSTALACION.md') -Encoding utf8
$destination = Join-Path $OutputDirectory 'Aurora-Windows'
if (Test-Path -LiteralPath $destination) { $destination = Join-Path $OutputDirectory ('Aurora-Windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $id) }
foreach ($movePath in $package, $destination) {
    $resolvedMove = [IO.Path]::GetFullPath($movePath)
    if (-not $resolvedMove.StartsWith($OutputDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta de paquete fuera del directorio de distribución.' }
}
Move-Item -LiteralPath $package -Destination $destination
$zipPath = $destination + '.zip'
Compress-Archive -LiteralPath $destination -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($zipPath + '.sha256') -Value "$zipHash  $([IO.Path]::GetFileName($zipPath))" -Encoding ascii
# The empty staging directory is retained: existing packages are never deleted.
Write-Host "Paquete: $destination"
Write-Host "ZIP: $zipPath"
Write-Host "SHA-256: $zipHash"
