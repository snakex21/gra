#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --editor --import
"$GODOT" --headless --path . --fixed-fps 60 --quit-after 1800 res://art/tests/test_art.tscn
