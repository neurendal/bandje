#!/usr/bin/env bash
# Live end-to-end tests. Requires a DEBUG build (make app) and the permissions granted
# during the M0 probe. Usage: scripts/selftest.sh [static] [record] [long]
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tests/fixtures/nl_xander.wav ] || ./scripts/dev/make-fixtures.sh
exec python3 -I scripts/dev/selftest.py "$@"
