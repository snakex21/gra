"""Manual optional local selector. Ctrl+C closes the native model too."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket
import time

from backend import Backend
from protocol import validate_request, validate_output

ADDRESS = ("127.0.0.1", 8766)


class DecisionHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def setup(self):
        super().setup()
        self.connection.settimeout(2.0)

    def log_message(self, *_):
        pass  # Numerical observations are not written to request logs.

    def reply(self, code, data):
        body = json.dumps(data, separators=(",", ":")).encode("utf-8")
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass  # Game timeout/cancel intentionally keeps its programmed fallback.

    def do_POST(self):
        if self.path != "/decision" or self.headers.get("Host") != "127.0.0.1:8766" or self.headers.get("Origin"):
            self.reply(403, {"error": "local endpoint only"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 1 <= length <= 4096 or self.headers.get("Transfer-Encoding") or self.headers.get_content_type() != "application/json":
                raise ValueError("Invalid body")
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValueError("Incomplete body")
            observation, allowed, generation = validate_request(json.loads(raw))
        except (ValueError, UnicodeError, socket.timeout):
            self.reply(400, {"error": "invalid observation"})
            return
        now = time.monotonic()
        if now < self.server.next_at:
            self.reply(429, {"error": "cooldown"})
            return
        self.server.next_at = now + 6.0
        try:
            intent, _metrics = self.server.backend.infer(observation, allowed)
            intent = validate_output(intent, allowed)
        except (OSError, ValueError, TimeoutError):
            self.reply(503, {"error": "fallback"})
            return
        self.reply(200, {"intent": intent, "generation": generation})


class DecisionServer(HTTPServer):
    request_queue_size = 2
    allow_reuse_address = False

    def __init__(self, backend):
        super().__init__(ADDRESS, DecisionHandler)
        self.backend = backend
        self.next_at = 0.0


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("bekko-research", "bekko68-research", "qwen35", "lfm", "qwen25"), required=True)
    args = parser.parse_args()
    if args.backend in ("bekko-research", "bekko68-research"):
        from bekko_backend import BekkoBackend
        model_backend = BekkoBackend("68" if args.backend == "bekko68-research" else "17")
    else:
        model_backend = Backend({"qwen35": "pins_qwen35.json", "lfm": "pins_lfm.json", "qwen25": "pins_qwen25.json"}[args.backend])
    # Bind the game's port before loading weights; do not replace another service.
    with DecisionServer(None) as server:
        with model_backend as backend:
            server.backend = backend
            print("Local tactics ready on 127.0.0.1:8766; " + args.backend + ", CPU 2 threads, context cap 512. Ctrl+C stops it.", flush=True)
            server.serve_forever(poll_interval=3600)  # Blocking select; no progress/status polling.


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
