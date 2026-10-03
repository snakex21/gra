"""Pinned, offline CPU llama.cpp child. No SDK, global cache or remote inference."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import urllib.request

from protocol import validate_output, validate_request

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data" / "ai"
PINS = json.loads((Path(__file__).parent / "pins.json").read_text(encoding="utf-8"))
BACKEND_URL = "http://127.0.0.1:8767/completion"
INFERENCE_TIMEOUT = 1.75


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def completion_payload(observation, allowed, source_model=""):
    # All interpolation has already passed the scalar/enum validator.
    validate_request({"observation": observation, "allowed": allowed, "generation": 0})
    rules = (
        "Choose one companion tactic. Output only its lowercase name. "
        "evade: immediate threat, unsafe ground, cliff, or low health. "
        "regroup: far from leader or path blocked. "
        "support: safe, enemy active, leader climbing, support available. "
        "hold: current intent hold and leader nearby. Otherwise follow. "
        "Use only allowed names."
    )
    prompt = ("<|im_start|>system\n" + rules + "<|im_end|>\n<|im_start|>user\n"
              + json.dumps({"observation": observation, "allowed": allowed}, separators=(",", ":"), sort_keys=True)
              + "<|im_end|>\n<|im_start|>assistant\n")
    if "Qwen3.5" in source_model:
        prompt += "<think>\n\n</think>\n\n"  # Explicit empty reasoning prefill; no thinking tokens budget.
    return {"prompt": prompt, "n_predict": 12, "temperature": 0, "seed": 17,
            "cache_prompt": True, "stream": False, "stop": ["<|im_end|>", "\n"],
            "grammar": "root ::= " + " | ".join(json.dumps(x) for x in allowed)}


class Backend:
    def __init__(self, pin_name="pins.json"):
        if pin_name not in ("pins.json", "pins_lfm.json", "pins_qwen35.json", "pins_qwen25.json"):
            raise ValueError("Unknown pinned candidate")
        self.pins = json.loads((Path(__file__).parent / pin_name).read_text(encoding="utf-8"))
        self.process = None
        self.reader = None
        self.ready = threading.Event()
        self.listening = False
        self.start_seconds = 0.0
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self.key = os.urandom(24).hex()

    def __enter__(self):
        BASE.mkdir(parents=True, exist_ok=True)
        runtime = BASE / self.pins["runtime"]["release"] / "llama-server.exe"
        model = BASE / self.pins["model"]["file"]
        if not runtime.is_file() or not model.is_file():
            raise RuntimeError("Install first: python tools/ai/install.py")
        # Ignore inherited runtime overrides, including tool/network options.
        env = {k: v for k, v in os.environ.items() if not k.startswith("LLAMA_")}
        for key in ("TEMP", "TMP", "APPDATA", "LOCALAPPDATA", "HF_HOME", "XDG_CACHE_HOME"):
            env[key] = str(BASE)
        command = [str(runtime), "--model", str(model), "--host", "127.0.0.1", "--port", "8767",
                   "--threads", "2", "--threads-batch", "2", "--ctx-size", "512", "--parallel", "1",
                   "--n-predict", "12", "--gpu-layers", "0", "--device", "none", "--batch-size", "128",
                   "--ubatch-size", "64", "--poll", "0", "--poll-batch", "0", "--prio", "-1",
                   "--cache-ram", "0", "--no-context-shift", "--no-webui", "--no-agent",
                   "--no-webui-mcp-proxy", "--no-slots", "--offline", "--no-mmproj", "--reasoning", "off", "--api-key", self.key,
                   "--log-colors", "off", "--threads-http", "1"]
        started = time.perf_counter()
        self.process = subprocess.Popen(command, cwd=BASE, env=env, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.reader = threading.Thread(target=self._read_notifications, daemon=True)
        self.reader.start()
        # Readiness and EOF are notifications from the child, never health polling.
        if not self.ready.wait(60) or not self.listening:
            self.stop()
            raise RuntimeError("Native model did not become ready; inspect data/ai/llama.log")
        self.start_seconds = time.perf_counter() - started
        return self

    def _read_notifications(self):
        with (BASE / "llama.log").open("w", encoding="utf-8") as log:
            for line in self.process.stdout:
                log.write(line)
                log.flush()
                if "listening on http://127.0.0.1:8767" in line:
                    self.listening = True
                    self.ready.set()
        self.ready.set()  # Early exit wakes startup immediately.

    def infer(self, observation, allowed):
        payload = completion_payload(observation, allowed, self.pins["model"]["repo"])
        # Render the checkpoint's own template, including any BOS/non-thinking prefill.
        template_request = urllib.request.Request("http://127.0.0.1:8767/apply-template",
            data=json.dumps({"messages": [{"role": "system", "content": "Choose one companion tactic. Output exactly one allowed lowercase name. "
                "Avoid immediate threat, cliffs, unsafe ground, or health below 20 first. Otherwise retain safe hold, "
                "support a climbing leader if available, regroup over 20 metres or blocked route, otherwise follow."},
                {"role": "user", "content": json.dumps({"observation": observation, "allowed": allowed}, separators=(",", ":"), sort_keys=True)}],
                "chat_template_kwargs": {"enable_thinking": False}}).encode("utf-8"),
            headers={"Content-Type": "application/json", "Authorization": "Bearer " + self.key}, method="POST")
        with self.opener.open(template_request, timeout=0.25) as response:
            rendered = json.loads(response.read(16385))
        prompt = rendered.get("prompt")
        if not isinstance(prompt, str) or len(prompt) > 4096:
            raise ValueError("Invalid native template")
        payload["prompt"] = prompt
        request = urllib.request.Request(BACKEND_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "Authorization": "Bearer " + self.key}, method="POST")
        started = time.perf_counter()
        with self.opener.open(request, timeout=INFERENCE_TIMEOUT) as response:
            body = response.read(65537)
        if len(body) > 65536:
            raise ValueError("Oversized native response")
        result = json.loads(body)
        if result.get("truncated") or result.get("stop_type") == "limit":
            raise ValueError("Bounded context/output exhausted")
        intent = validate_output(result.get("content"), allowed)
        return intent, {"wall_ms": round((time.perf_counter() - started) * 1000, 3),
                        "timings": result.get("timings", {})}

    def memory_mib(self):
        """One post-completion measurement, using native Windows peak/current counters."""
        if os.name != "nt":
            return {}
        import ctypes
        from ctypes import wintypes
        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [(name, ctypes.c_size_t) for name in (
                "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage",
                "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage", "PrivateUsage")]
        values = Counters()
        values.cb = ctypes.sizeof(values)
        query = ctypes.WinDLL("psapi").GetProcessMemoryInfo
        query.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        if not query(int(self.process._handle), ctypes.byref(values), values.cb):
            return {}
        return {"working_set_mib": round(values.WorkingSetSize / 1048576, 1),
                "peak_working_set_mib": round(values.PeakWorkingSetSize / 1048576, 1),
                "private_mib": round(values.PrivateUsage / 1048576, 1)}

    def stop(self):
        if self.process is not None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
            if self.reader is not None:
                self.reader.join(timeout=5)
            self.process.stdout.close()
            self.process = None

    def __exit__(self, *_):
        self.stop()
