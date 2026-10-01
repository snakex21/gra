#!/usr/bin/env bash
# Deterministically rebuild original editable meshes, explicit GLBs and textures.
set -euo pipefail
cd "$(dirname "$0")/../.."
BLENDER="${BLENDER:-blender}"
"$BLENDER" --background --python-exit-code 1 --python tools/art/generate_art.py
"${GODOT:-godot}" --headless --path . --editor --import
python3 tools/art/validate_exports.py
