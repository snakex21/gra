"""Bounded core PCVR tests with simulated poses; runtime errors always fail."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCENES = ("pc_vr_rig", "pc_vr_scene")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--scene", action="append", choices=SCENES)
    parser.add_argument("--native", action="store_true", help="Actual Compatibility rendering without XR/HMD")
    args = parser.parse_args()
    runtime = ROOT / "tools" / "runtime"
    exe = args.godot or next(runtime.glob("Godot*_console.exe"), None)
    if exe is None:
        parser.error("Pass --godot or install portable Godot through tools/run_local.py")
    env = dict(os.environ)
    for key, directory in (("APPDATA", "engine_data"), ("LOCALAPPDATA", "engine_cache"),
                           ("XDG_DATA_HOME", "engine_data"), ("XDG_CACHE_HOME", "engine_cache"),
                           ("TEMP", "tmp"), ("TMP", "tmp"), ("TMPDIR", "tmp")):
        path = runtime / directory
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    output = ROOT / "tests" / "output"
    output.mkdir(exist_ok=True)
    failed = False
    mode = "compatibility" if args.native else "headless"
    scenes = args.scene or list(SCENES)
    if not args.native and args.scene is None:
        scenes = ["pc_vr_action_map", *scenes]
    for scene in scenes:
        prefix = output / f"{scene}.{mode}"
        command = [str(exe.resolve()), "--path", str(ROOT), "--xr-mode", "off", "--fixed-fps", "60",
                   "--log-file", str(Path(str(prefix) + ".engine.log"))]
        command += ["--rendering-method", "gl_compatibility"] if args.native else ["--headless"]
        if scene == "pc_vr_action_map":
            command += ["--script", "res://tools/vr/generate_action_map.gd", "--", "--verify-only"]
        else:
            command.append(f"res://tests/{scene}.tscn")
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=120)
            log = result.stdout + result.stderr
            Path(str(prefix) + ".strict.log").write_text(log, encoding="utf-8")
            marker = ("PC VR ACTION MAP: 147 checks, 0 failures" if scene == "pc_vr_action_map"
                      else f"{scene.upper()}: 0 failure(s)")
            ok = (result.returncode == 0 and marker in log
                  and not re.search(r"SCRIPT ERROR|^ERROR:|^FATAL:|ObjectDB instances leaked|Texture .* leaked", log, re.M))
            if not ok:
                print(log[-16000:])
        except subprocess.TimeoutExpired as exc:
            ok = False
            captured = (exc.stdout or b"") + (exc.stderr or b"")
            Path(str(prefix) + ".strict.log").write_text(captured.decode("utf-8", errors="replace"), encoding="utf-8")
            print(f"{scene}: timeout after120s")
        print(f"{scene} ({mode}): {'PASS' if ok else 'FAIL'}", flush=True)
        failed |= not ok
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
