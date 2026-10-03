#!/usr/bin/env bash
# Long regression run of the whole game: N new games played start to finish by GameBot
# (beam, ride, campaign fights, back to the temple). Details in tests/output/game_soak.json.
#   tools/run_game_soak.sh [runs] [first]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --fixed-fps 60 --quit-after 100000000 res://tests/game_soak.tscn -- --runs="${1:-10}" --from="${2:-1}"
