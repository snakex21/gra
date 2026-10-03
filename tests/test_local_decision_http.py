"""Real Godot HTTP timeout/rejection harness with bounded completion wait."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import argparse
import os
from pathlib import Path
import subprocess
import threading
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        generation = data["generation"]
        if generation == 104:
            threading.Event().wait(3.0)  # Intentional silent server tests actual client timeout.
        answer = {"intent": "support" if generation == 102 else "follow", "generation": 102 if generation == 103 else generation}
        encoded = json.dumps(answer).encode()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
        except (BrokenPipeError, ConnectionResetError):
            pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", ""))
    args = parser.parse_args()
    portable = ROOT / "tests/output/local_decision"
    portable.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for key in ("TEMP", "TMP", "TMPDIR", "APPDATA", "LOCALAPPDATA", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"):
        env[key] = str(portable)
    command = [args.godot] if args.godot else [sys.executable, "tools/run_local.py", "godot"]
    command += ["--headless", "--path", ".", "tests/test_local_decision.tscn"]
    with ThreadingHTTPServer(("127.0.0.1", 8766), Handler) as server:
        server.daemon_threads = True
        serving = threading.Thread(target=server.serve_forever, daemon=True)
        serving.start()
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, timeout=35, capture_output=True, text=True, encoding="utf-8", errors="replace")
        finally:
            server.shutdown()
            serving.join(timeout=3)
    output = result.stdout + result.stderr
    print(output, end="")
    bad = any(marker in output for marker in ("SCRIPT ERROR:", "Parse Error:", "ERROR:", "ObjectDB instances leaked"))
    passed = "LOCAL DECISION: 40 checks, 0 failures" in output
    raise SystemExit(result.returncode if result.returncode else (1 if bad or not passed else 0))

if __name__ == "__main__":
    main()
