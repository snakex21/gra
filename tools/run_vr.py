"""Launch core Godot PCVR; no dependency install or system runtime modification."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulate", action="store_true", help="Desktop development preview; does not use a headset")
    parser.add_argument("--renderer", choices=("mobile", "gl_compatibility"), default="mobile")
    args = parser.parse_args()
    renderer = "gl_compatibility" if args.simulate else args.renderer
    command = [sys.executable, str(ROOT / "tools/run_local.py"), "godot", "--xr-mode",
               "off" if args.simulate else "on", "--rendering-method", renderer]
    if renderer == "mobile":
        command += ["--rendering-driver", "vulkan"]
    command += ["res://scenes/pc_vr.tscn"]
    if args.simulate:
        command += ["--", "--vr-sim"]
    return subprocess.run(command, cwd=ROOT).returncode


if __name__ == "__main__":
    sys.exit(main())
