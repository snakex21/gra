#!/usr/bin/env bash
# Long regression run of a boss fight: N full encounters played by the scripted bot
# (different brain seeds and starts; Quadratus alternates on foot / from Agro).
# Summary on stdout, details in tests/output/boss_soak.json / quadratus_soak.json.
#   tools/run_boss_soak.sh [runs] [first] [valus|quadratus]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --fixed-fps 60 --quit-after 100000000 res://tests/boss_soak.tscn -- --runs="${1:-50}" --from="${2:-1}" --boss="${3:-valus}"
