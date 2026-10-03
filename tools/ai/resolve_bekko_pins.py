"""Maintainer-only resolution of official ONNX export and CPU wheels."""
import hashlib
import json
from pathlib import Path
import urllib.request
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data/ai"

def get(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()

def main():
    BASE.mkdir(parents=True, exist_ok=True)
    revision = "cf92c2f76214e764b9c4e3054125cdb146b0732e"
    size = "68" if len(sys.argv) > 1 and sys.argv[1] == "68" else "17"
    if size == "68":
        info = json.loads(get("https://huggingface.co/api/models/hotchpotch/bekko-system-one-v0-68m"))
        revision = info["sha"]
    repo = "hotchpotch/bekko-system-one-v0-" + size + "m"
    prefix = "https://huggingface.co/" + repo + "/resolve/" + revision + "/"
    pins = {"repo": repo, "revision": revision, "license": "UNASSIGNED: author has not finalized released-weight license", "reference_code_revision": "0fccbb8568b67d47745d820319fe9a4a04e7fa95", "files": [], "wheels": []}
    for name in ("manifest.json", "tokenizer.json", "tokenizer_config.json", "model.onnx"):
        url = prefix + "onnx_browser/" + name
        data = get(url)
        pins["files"].append({"file": name, "url": url, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        directory = BASE / ("bekko" + size)
        directory.mkdir(exist_ok=True)
        (directory / name).write_bytes(data)
    for package, version in (("onnxruntime", "1.30.0"), ("tokenizers", "0.22.2"), ("numpy", "2.3.3")):
        info = json.loads(get("https://pypi.org/pypi/" + package + "/" + version + "/json"))
        wheel = next(row for row in info["urls"] if ("cp313-cp313-win_amd64.whl" in row["filename"] or "cp39-abi3-win_amd64.whl" in row["filename"]))
        pins["wheels"].append({"package": package, "version": version, "file": wheel["filename"], "url": wheel["url"], "bytes": wheel["size"], "sha256": wheel["digests"]["sha256"], "license": {"onnxruntime": "MIT", "tokenizers": "Apache-2.0", "numpy": "BSD-3-Clause; bundled notices retained"}[package]})
    destination = "pins_bekko68.json" if size == "68" else "pins_bekko.json"
    (ROOT / "tools/ai" / destination).write_text(json.dumps(pins, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(pins, indent=2))

if __name__ == "__main__":
    main()
