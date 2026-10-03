"""Optional installed-model loopback transport smoke, bounded completion notifications."""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def main():
    env = dict(os.environ)
    base = ROOT / "data/ai"
    base.mkdir(parents=True, exist_ok=True)
    for key in ("TEMP", "TMP", "APPDATA", "LOCALAPPDATA", "HF_HOME", "XDG_CACHE_HOME"):
        env[key] = str(base)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    ready = threading.Event()
    lines = []
    process = subprocess.Popen([sys.executable, "tools/ai/run.py", "--backend", "bekko-research"], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    def notifications():
        for line in process.stdout:
            lines.append(line)
            if "Local tactics ready" in line:
                ready.set()
        ready.set()
    reader = threading.Thread(target=notifications, daemon=True)
    reader.start()
    try:
        if not ready.wait(20) or not any("Local tactics ready" in line for line in lines):
            raise RuntimeError("Local backend startup failed: " + "".join(lines))
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        payload = {"observation": {"health": 100, "threat": False, "leader_distance": 4, "ground_safe": True}, "allowed": ["follow", "hold"], "generation": 123}
        request = urllib.request.Request("http://127.0.0.1:8766/decision", data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}, method="POST")
        with opener.open(request, timeout=2) as response:
            answer = json.load(response)
        if set(answer) != {"intent", "generation"} or answer["generation"] != 123 or answer["intent"] not in payload["allowed"]:
            raise RuntimeError("Invalid live transport output")
        print("LIVE LOCAL DECISION: valid allowlisted reply and generation from actual CPU Choice head", answer)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        reader.join(timeout=5)
        process.stdout.close()

if __name__ == "__main__":
    main()
