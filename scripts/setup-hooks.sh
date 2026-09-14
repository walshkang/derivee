#!/usr/bin/env bash
set -e

# ==============================================================================
# Dérivée Local Hooks Setup Script
# Configures Git to route hooks through .githooks/ in version control.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "🔧 Configuring Git core.hooksPath -> .githooks..."
git config core.hooksPath .githooks

chmod +x .githooks/pre-commit
chmod +x scripts/verify-ux.sh
chmod +x scripts/setup-hooks.sh

echo "✅ Local Ergonomic Bouncer hooks activated successfully."
