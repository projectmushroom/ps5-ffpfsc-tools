#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n install.sh bin/ps5-ffpfsc bin/pack_ffpfsc.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh bin/ps5-ffpfsc bin/pack_ffpfsc.sh
else
  echo "shellcheck not found; skipped"
fi
