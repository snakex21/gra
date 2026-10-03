"""Download verified, pinned official CPU artefacts into the portable game folder."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data/ai"

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def download(artifact, path):
    if path.exists() and path.stat().st_size == artifact["bytes"] and digest(path) == artifact["sha256"]:
        return
    temporary = path.with_suffix(path.suffix + ".part")
    request = urllib.request.Request(artifact["url"], headers={"User-Agent": "ForbiddenLands-local-AI/1"})
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)
    if temporary.stat().st_size != artifact["bytes"] or digest(temporary) != artifact["sha256"]:
        raise RuntimeError("Size/SHA256 verification failed: " + path.name)
    temporary.replace(path)

def install(pin_name="pins.json"):
    BASE.mkdir(parents=True, exist_ok=True)
    os.environ["TEMP"] = os.environ["TMP"] = str(BASE)
    if pin_name not in ("pins.json", "pins_lfm.json", "pins_qwen35.json", "pins_qwen25.json"):
        raise ValueError("Unknown pinned candidate")
    pins = json.loads((ROOT / "tools/ai" / pin_name).read_text(encoding="utf-8"))
    archive = BASE / (pins["runtime"]["release"] + "-cpu.zip")
    print("Downloading pinned official CPU runtime and Q4 model; no progress polling.", flush=True)
    download(pins["runtime"], archive)
    runtime = BASE / pins["runtime"]["release"]
    runtime.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            target = (runtime / member.filename).resolve()
            if not target.is_relative_to(runtime.resolve()):
                raise RuntimeError("Archive entry escapes portable runtime directory")
            package.extract(member, runtime)
    model = BASE / pins["model"]["file"]
    download(pins["model"], model)
    for kind in ("runtime", "model"):
        url = pins[kind]["license_url"]
        with urllib.request.urlopen(url, timeout=30) as response:
            (BASE / (pin_name.removesuffix(".json") + "_" + kind + "_LICENSE.txt")).write_bytes(response.read(100000))
    (BASE / ("installed_" + pin_name)).write_text(json.dumps(pins, indent=2) + "\n", encoding="utf-8")
    print("Installed verified runtime:", runtime)
    print("Installed verified model:", model, model.stat().st_size, "bytes")
    return pins

if __name__ == "__main__":
    import sys
    install(sys.argv[1] if len(sys.argv) > 1 else "pins.json")
