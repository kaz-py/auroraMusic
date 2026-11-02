# Activa los hooks versionados de scripts/hooks (opt-in, por clon).
# Deshacer: git config --unset core.hooksPath
$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel).Trim()
Set-Location $root
git config core.hooksPath scripts/hooks
Write-Host 'core.hooksPath = scripts/hooks (guarda de interfaz activa en pre-commit)'
