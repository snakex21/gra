#!/usr/bin/env bash
# Run only once the asset exporter has completed. Import and capture are serial.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
export XDG_DATA_HOME="${STONEWATER_XDG_DATA_HOME:-/tmp/gra-stonewater-data}"
export XDG_CONFIG_HOME="${STONEWATER_XDG_CONFIG_HOME:-/tmp/gra-stonewater-config}"
export XDG_CACHE_HOME="${STONEWATER_XDG_CACHE_HOME:-/tmp/gra-stonewater-cache}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
mkdir -p art/reports/v3 art/screenshots/v3
if [[ "${SKIP_IMPORT:-0}" != "1" ]]; then
  "$GODOT" --headless --editor --path . --import 2>&1 | tee art/reports/v3/import.log
fi
"$GODOT" --headless --path . --script art/scripts/stonewater_review.gd --check-only \
  2>&1 | tee art/reports/v3/review_compile.log
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo 'A rendering display is required; --headless cannot produce viewport screenshots.' >&2
  exit 2
fi
export STONEWATER_CAPTURE_STARTED_NS="$(date +%s%N)"
"$GODOT" --path . --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 1280x720 res://art/tests/stonewater.tscn -- --capture-stonewater \
  2>&1 | tee art/reports/v3/capture.log
python3 - <<'PY'
from pathlib import Path
import json
import os
started = int(os.environ["STONEWATER_CAPTURE_STARTED_NS"])
report_path = Path("art/reports/v3/render_costs.json")
assert report_path.stat().st_mtime_ns >= started, "Stale render report"
assert "STONEWATER_CAPTURE_OK views=8" in Path("art/reports/v3/capture.log").read_text()
report = json.loads(Path('art/reports/v3/render_costs.json').read_text())
assert len(report['views']) == 8
for view in report['views']:
    p = Path('art/screenshots/v3') / (view['view'] + '.png')
    assert p.is_file() and p.stat().st_size > 10240, p
    assert p.stat().st_mtime_ns >= started, ("Stale screenshot", p)
    assert view['draw_calls'] > 0 and view['primitives'] > 0, view
print('STONEWATER_CAPTURE_VALIDATED', len(report['views']), 'actual viewport PNGs')
PY
