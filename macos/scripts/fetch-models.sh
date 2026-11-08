#!/usr/bin/env bash
# Downloads the Voz and Who model files to ~/Music/Bandje/.models (outside the app).
# The app itself never downloads; it only loads from this folder.
# Idempotent: files that already match size and checksum are skipped.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="${BANDJE_MODELS_DIR:-$HOME/Music/Bandje/.models}"
mkdir -p "$ROOT"
exec python3 -I scripts/dev/fetch_models.py "$ROOT"
