#!/bin/sh
# Activa los hooks versionados de scripts/hooks (opt-in, por clon).
# Deshacer: git config --unset core.hooksPath
set -e
root=$(git rev-parse --show-toplevel)
cd "$root"
chmod +x scripts/hooks/pre-commit 2>/dev/null || true
git config core.hooksPath scripts/hooks
echo "core.hooksPath = scripts/hooks (guarda de interfaz activa en pre-commit)"
