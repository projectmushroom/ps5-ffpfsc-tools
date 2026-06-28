#!/usr/bin/env bash
set -euo pipefail

ROOT="${PS5_ROOT:-$HOME/ps5}"
BIN_DIR="${PS5_BIN_DIR:-$HOME/.local/bin}"
SKILL_DIR="${PS5_SKILL_DIR:-$HOME/.codex/skills/ps5-ffpfsc}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$ROOT" "$ROOT/scratch" "$ROOT/logs" "$BIN_DIR" "$HOME/Downloads/ps5/out"

if [ ! -x "$ROOT/.venv/bin/python" ]; then
  python3 -m venv "$ROOT/.venv"
fi

"$ROOT/.venv/bin/pip" install --upgrade pip
"$ROOT/.venv/bin/pip" install -U "mkpfs"

ln -sf "$REPO_DIR/bin/ps5-ffpfsc" "$BIN_DIR/ps5-ffpfsc"
ln -sf "$REPO_DIR/bin/pack_ffpfsc.sh" "$BIN_DIR/pack_ffpfsc.sh"

if [ -d "$REPO_DIR/skills/ps5-ffpfsc" ]; then
  mkdir -p "$(dirname "$SKILL_DIR")"
  rm -rf "$SKILL_DIR"
  cp -R "$REPO_DIR/skills/ps5-ffpfsc" "$SKILL_DIR"
fi

echo "Installed PS5 FFPFSC tools"
echo "  root:    $ROOT"
echo "  command: $BIN_DIR/ps5-ffpfsc"
echo "  skill:   $SKILL_DIR"
echo "  mkpfs:   $("$ROOT/.venv/bin/python" -m mkpfs -V)"
echo
echo "Make sure $BIN_DIR is on PATH, then run:"
echo "  ps5-ffpfsc status"
