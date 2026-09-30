#!/usr/bin/env bash
# Runs the headless gameplay tests. Usage: tools/run_tests.sh [--only=<substring>]
# Set GODOT to the Godot 4.4+ binary if it is not on PATH as "godot".
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --fixed-fps 60 --quit-after 30000 res://tests/test_runner.tscn -- "$@"
