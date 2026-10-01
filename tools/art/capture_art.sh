#!/usr/bin/env bash
# Real viewport capture. Never substitutes headless output or a Blender render.
# Run under your desktop display, or: xvfb-run -a tools/art/capture_art.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
mkdir -p art/tests/output
printf '# Review evidence, not runtime assets.\n' > art/tests/output/.gdignore
"$GODOT" --headless --path . --editor --import > art/tests/output/import.log 2>&1
ARGS=(--path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 res://art/tests/environment_showcase.tscn -- --capture-art)
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
	exec xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" "${ARGS[@]}"
fi
if [[ -z "${DISPLAY:-}" ]]; then
	echo "A rendering display is required. Start this from a desktop terminal, or install/run xvfb-run. Headless cannot provide screenshots." >&2
	exit 2
fi
exec "$GODOT" "${ARGS[@]}"
