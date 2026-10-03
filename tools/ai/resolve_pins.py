"""Maintainer utility: resolve official artefacts once, never during game startup."""
from pathlib import Path
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "ForbiddenLands-local-AI/1"}), timeout=60) as response:
        return json.load(response)

if __name__ == "__main__":
    release = fetch("https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/b11010")
    asset = next(item for item in release["assets"] if item["name"] == "llama-b11010-bin-win-cpu-x64.zip")
    import sys
    repo = sys.argv[1] if len(sys.argv) > 1 else "ggml-org/Qwen3.5-0.8B-GGUF"
    model = fetch("https://huggingface.co/api/models/" + repo + "?blobs=true")
    suffix = sys.argv[3] if len(sys.argv) > 3 else ("q4_0.gguf" if repo.startswith("ggml-org/Qwen3.5") else "q4_k_m.gguf")
    gguf = next(item for item in model["siblings"] if item["rfilename"].lower().endswith(suffix))
    pins = {"runtime": {"release": "b11010", "url": asset["browser_download_url"], "sha256": asset["digest"].removeprefix("sha256:"), "bytes": asset["size"], "license": "MIT", "license_url": "https://raw.githubusercontent.com/ggml-org/llama.cpp/" + release["tag_name"] + "/LICENSE"}, "model": {"repo": repo, "revision": model["sha"], "file": gguf["rfilename"], "url": "https://huggingface.co/" + repo + "/resolve/" + model["sha"] + "/" + gguf["rfilename"], "sha256": gguf["lfs"]["sha256"], "bytes": gguf["size"], "license": "Apache-2.0", "license_url": "https://huggingface.co/" + repo + "/resolve/" + model["sha"] + "/LICENSE", "model_card_url": "https://huggingface.co/" + repo}}
    if repo.startswith("LiquidAI/"):
        pins["model"]["license"] = "Liquid AI LFM Open License 1.0"
    if repo.startswith("ggml-org/Qwen3.5"):
        original = fetch("https://huggingface.co/api/models/Qwen/Qwen3.5-0.8B")
        pins["model"]["license_url"] = "https://huggingface.co/Qwen/Qwen3.5-0.8B/resolve/" + original["sha"] + "/LICENSE"
        pins["model"]["source_model"] = "Qwen/Qwen3.5-0.8B"
    destination = sys.argv[2] if len(sys.argv) > 2 else "tools/ai/pins.json"
    (ROOT / destination).write_text(json.dumps(pins, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(pins, indent=2))
