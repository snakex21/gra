#!/usr/bin/env bash
# Open only the isolated art scene. Original project main scene stays unchanged.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --editor --import > /tmp/gra-art-import.log 2>&1
exec "$GODOT" --path . --rendering-method gl_compatibility --resolution 1280x720 res://art/tests/environment_showcase.tscn -- "$@"
