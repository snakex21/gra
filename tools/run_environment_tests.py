"""Strict portable checks for biome blending and render-only groundcover."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCENES = ("environment_dressing", "landscape_v5")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--scene", action="append", choices=SCENES)
    parser.add_argument("--native", action="store_true", help="Render with Compatibility; requires a display")
    args = parser.parse_args()
    runtime = ROOT / "tools" / "runtime"
    exe = args.godot or next(runtime.glob("Godot*_console.exe"), None)
    if exe is None:
        parser.error("Pass --godot or install portable Godot with tools/run_local.py")
    env = dict(os.environ)
    for key, name in (("APPDATA", "engine_data"), ("LOCALAPPDATA", "engine_cache"),
                      ("XDG_DATA_HOME", "engine_data"), ("XDG_CACHE_HOME", "engine_cache"),
                      ("TEMP", "tmp"), ("TMP", "tmp"), ("TMPDIR", "tmp")):
        path = runtime / name
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    output = ROOT / "tests" / "output"
    output.mkdir(exist_ok=True)
    mode = "compatibility" if args.native else "headless"
    failed = False
    for scene in args.scene or SCENES:
        prefix = output / f"{scene}.{mode}"
        command = [str(exe.resolve()), "--path", str(ROOT), "--xr-mode", "off", "--fixed-fps", "60",
                   "--log-file", str(Path(str(prefix) + ".engine.log"))]
        command += ["--rendering-method", "gl_compatibility"] if args.native else ["--headless"]
        command.append(f"res://tests/{scene}.tscn")
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=180)
            log = result.stdout + result.stderr
            Path(str(prefix) + ".strict.log").write_text(log, encoding="utf-8")
            report_line = re.search(rf"^{scene.upper()}: (.+)$", log, re.M)
            report = json.loads(report_line.group(1)) if report_line else {}
            ok = (result.returncode == 0 and report.get("failures") == 0
                  and not re.search(r"SCRIPT ERROR|^ERROR:|^FATAL:|ObjectDB instances leaked|Texture .* leaked", log, re.M))
            if not ok:
                print(log[-16000:])
        except subprocess.TimeoutExpired as exc:
            ok = False
            captured = (exc.stdout or b"") + (exc.stderr or b"")
            Path(str(prefix) + ".strict.log").write_text(captured.decode("utf-8", errors="replace"), encoding="utf-8")
            print(f"{scene}: timed out (180 s)")
        except json.JSONDecodeError as exc:
            ok = False
            print(f"{scene}: invalid completion report: {exc}")
        print(f"{scene} ({mode}): {'PASS' if ok else 'FAIL'}", flush=True)
        failed |= not ok
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
