"""Strict stage-16 checks: a Godot script error fails even if engine exits zero."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCENES = [
    "test_companion_policy", "test_companion_controller", "companion_settings",
    "companion_world", "companion_replay", "test_companion_controller_review",
    "auto_save", "climate_persistence", "main_layout",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--scene", action="append", choices=SCENES)
    args = parser.parse_args()
    runtime = ROOT / "tools" / "runtime"
    exe = args.godot or next(runtime.glob("Godot*_console.exe"), None)
    if exe is None:
        parser.error("Pass --godot or install portable Godot with tools/run_local.py")
    env = dict(os.environ)
    for variable, name in [("APPDATA", "engine_data"), ("LOCALAPPDATA", "engine_cache"),
                           ("XDG_DATA_HOME", "engine_data"), ("XDG_CACHE_HOME", "engine_cache"),
                           ("TEMP", "tmp"), ("TMP", "tmp"), ("TMPDIR", "tmp")]:
        path = runtime / name
        path.mkdir(parents=True, exist_ok=True)
        env[variable] = str(path)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    output = ROOT / "tests" / "output"
    output.mkdir(exist_ok=True)
    failed = False
    for scene in args.scene or SCENES:
        try:
            result = subprocess.run(
                [str(exe.resolve()), "--path", str(ROOT), "--headless", "--fixed-fps", "60",
                 "--log-file", str(output / f"{scene}.engine.log"), f"res://tests/{scene}.tscn"],
                cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=240,
            )
            log = result.stdout + result.stderr
            (output / f"{scene}.strict.log").write_text(log, encoding="utf-8")
            ok = result.returncode == 0 and not re.search(r"SCRIPT ERROR|^ERROR:|^FATAL:", log, re.M)
            if not ok:
                print(log[-12000:])
        except subprocess.TimeoutExpired:
            ok = False
            print(f"{scene}: timed out (240 s)")
        print(f"{scene}: {'PASS' if ok else 'FAIL'}", flush=True)
        failed |= not ok
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
