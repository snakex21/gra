"""Portable Windows developer entry point; tools, logs and caches stay in the project."""
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "tools" / "runtime"
RUNTIME.mkdir(exist_ok=True)
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
os.environ["TEMP"] = os.environ["TMP"] = str(RUNTIME)
# Godot's engine-owned user/cache paths also stay local, including project runs.
# Only child processes see this environment; Windows/user configuration is untouched.
os.environ["APPDATA"] = str(RUNTIME / "engine_data")
os.environ["LOCALAPPDATA"] = str(RUNTIME / "engine_cache")
for key in ("APPDATA", "LOCALAPPDATA"):
    Path(os.environ[key]).mkdir(exist_ok=True)
(RUNTIME / "_sc_").touch(exist_ok=True)

if sys.argv[1] == "install-godot":
    archive = RUNTIME / "godot-4.6.3.zip"
    url = "https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_win64.exe.zip"
    urllib.request.urlretrieve(url, archive)
    with zipfile.ZipFile(archive) as z:
        z.extractall(RUNTIME)
    print("Godot 4.6.3 downloaded to", RUNTIME)
    sys.exit(0)

if sys.argv[1] == "blender":
    exe = Path("C:/Program Files/Blender Foundation/Blender 4.5/blender.exe")
    os.environ["BLENDER_USER_CONFIG"] = str(RUNTIME / "blender" / "config")
    os.environ["BLENDER_USER_SCRIPTS"] = str(RUNTIME / "blender" / "scripts")
    os.environ["BLENDER_USER_DATAFILES"] = str(RUNTIME / "blender" / "data")
    args = [str(exe), "--background", "--factory-startup", "--python-exit-code", "1", *sys.argv[2:]]
else:
    exe = next(RUNTIME.glob("Godot*_console.exe"), None)
    if exe is None:
        raise SystemExit("Missing portable Godot; run python tools/run_local.py install-godot")
    args = [str(exe), "--path", str(ROOT), "--log-file", str(ROOT / "tests" / "output" / f"godot-{os.getpid()}.log"), *sys.argv[2:]]
    (ROOT / "tests" / "output").mkdir(exist_ok=True)

result = subprocess.run(args, cwd=ROOT)
sys.exit(result.returncode)
