#!/usr/bin/env bash
# Runs the real sandbox with a scripted autopilot and saves screenshots to tests/output/.
# "tools/capture_screenshots.sh agro" runs the Agro scene instead (tests/output/agro_*.png),
# "tools/capture_screenshots.sh boss" the Valus fight (tests/output/boss_*.png),
# "tools/capture_screenshots.sh quadratus" the Quadratus fight (tests/output/quadratus_*.png;
# ON_FOOT=1 without Agro), "gaius" the Gaius fight (tests/output/gaius_*.png), "game" the valley, the beam and the ride (tests/output/game_*.png), "art" fixed views of both arenas with the art pack
# (tests/output/art_*.png). NO_ART=1 shows the greybox scenes.
# Works without a GPU (Mesa llvmpipe) through xvfb-run if no display is available.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
SCENE=res://tests/capture_demo.tscn
if [[ "${1:-}" == "agro" ]]; then
	SCENE=res://tests/capture_agro.tscn
elif [[ "${1:-}" == "boss" ]]; then
	SCENE=res://tests/capture_valus.tscn
elif [[ "${1:-}" == "quadratus" ]]; then
	SCENE=res://tests/capture_quadratus.tscn
elif [[ "${1:-}" == "gaius" ]]; then
	SCENE=res://tests/capture_gaius.tscn
elif [[ "${1:-}" == "characters" ]]; then
	SCENE=res://tests/capture_characters.tscn
elif [[ "${1:-}" == "game" ]]; then
	SCENE=res://tests/capture_game.tscn
elif [[ "${1:-}" == "art" ]]; then
	SCENE=res://tests/capture_art.tscn
fi
ARGS=(--rendering-method gl_compatibility --fixed-fps 60 --quit-after 60000 --resolution 1280x720 "$SCENE")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
	exec xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" "${ARGS[@]}"
fi
exec "$GODOT" "${ARGS[@]}"
