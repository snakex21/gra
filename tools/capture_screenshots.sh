#!/usr/bin/env bash
# Runs the real sandbox with a scripted autopilot and saves screenshots to tests/output/.
# "tools/capture_screenshots.sh agro" runs the Agro scene instead (tests/output/agro_*.png).
# Works without a GPU (Mesa llvmpipe) through xvfb-run if no display is available.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
SCENE=res://tests/capture_demo.tscn
if [[ "${1:-}" == "agro" ]]; then
	SCENE=res://tests/capture_agro.tscn
fi
ARGS=(--rendering-method gl_compatibility --fixed-fps 60 --quit-after 8000 --resolution 1280x720 "$SCENE")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
	exec xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" "${ARGS[@]}"
fi
exec "$GODOT" "${ARGS[@]}"
