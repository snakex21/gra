#!/usr/bin/env bash
# Long regression run of the Sentinel fight: N full encounters played by the scripted bot
# (different brain seeds and starts). Summary on stdout, details in tests/output/boss_soak.json.
#   tools/run_boss_soak.sh [runs] [first]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --fixed-fps 60 --quit-after 100000000 res://tests/boss_soak.tscn -- --runs="${1:-50}" --from="${2:-1}"
