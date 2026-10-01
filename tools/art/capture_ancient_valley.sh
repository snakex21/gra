#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --editor --path . --import
"$GODOT" --path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 res://art/tests/ancient_valley.tscn -- --capture-valley
