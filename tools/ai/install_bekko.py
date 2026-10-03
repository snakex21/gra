"""Pinned local research ONNX installation; the weights have no assigned licence."""
import json
import os
from pathlib import Path
import subprocess
import sys

from install import BASE, ROOT, download

def main():
    if sys.version_info[:2] != (3, 13) or sys.platform != "win32":
        raise RuntimeError("Pinned wheels require Windows x64 Python 3.13; do not fall back to profile installs")
    BASE.mkdir(parents=True, exist_ok=True)
    size = "68" if len(sys.argv) > 1 and sys.argv[1] == "68" else "17"
    pin_name = "pins_bekko68.json" if size == "68" else "pins_bekko.json"
    pins = json.loads((ROOT / "tools/ai" / pin_name).read_text(encoding="utf-8"))
    model_dir = BASE / ("bekko" + size)
    model_dir.mkdir(exist_ok=True)
    wheels = BASE / "wheels"
    wheels.mkdir(exist_ok=True)
    print("Installing pinned Bekko ONNX CPU research runtime inside data/ai; weight licence unassigned.", flush=True)
    for item in pins["files"]:
        download(item, model_dir / item["file"])
    local_wheels = []
    for item in pins["wheels"]:
        wheel = wheels / item["file"]
        download(item, wheel)
        local_wheels.append(str(wheel))
    env = {key: value for key, value in os.environ.items() if not key.startswith("PIP_")}
    for key in ("TEMP", "TMP", "APPDATA", "LOCALAPPDATA", "PIP_CACHE_DIR", "XDG_CACHE_HOME", "HF_HOME"):
        env[key] = str(BASE)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    subprocess.run([sys.executable, "-m", "pip", "--isolated", "install", "--target", str(BASE / "python"), "--no-deps", "--no-index", "--no-cache-dir", "--disable-pip-version-check", "--upgrade", *local_wheels], env=env, cwd=BASE, timeout=120, check=True)
    (BASE / ("installed_bekko" + size + ".json")).write_text(json.dumps(pins, indent=2) + "\n", encoding="utf-8")
    print("Pinned ONNX research runtime installed; no Torch, training or profile cache.")

if __name__ == "__main__":
    main()
