"""Real bounded CPU Choice probes, including paired changes in safety state."""
import ctypes
from ctypes import wintypes
import json
import os
import platform
import statistics

from benchmark import BASE_OBSERVATION, FIXTURES
from backend import BASE
from bekko_backend import BekkoBackend
from protocol import VOCABULARY

def memory():
    if os.name != "nt":
        return {}
    class Counters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [(name, ctypes.c_size_t) for name in (
            "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage", "PrivateUsage")]
    values = Counters()
    values.cb = ctypes.sizeof(values)
    query = ctypes.WinDLL("psapi").GetProcessMemoryInfo
    query.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    ctypes.windll.kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    if not query(ctypes.windll.kernel32.GetCurrentProcess(), ctypes.byref(values), values.cb):
        return {}
    return {"peak_working_set_mib": round(values.PeakWorkingSetSize / 1048576, 1), "private_mib": round(values.PrivateUsage / 1048576, 1)}

def main():
    import sys
    size = "68" if len(sys.argv) > 1 and sys.argv[1] == "68" else "17"
    result = {"cpu": os.environ.get("PROCESSOR_IDENTIFIER", platform.processor()), "threads": 2, "context_cap": 512, "fixtures": []}
    result["model"] = "bekko" + size
    with BekkoBackend(size) as backend:
        result["cold_start_seconds"] = round(backend.start_seconds, 3)
        result["runtime"] = backend.versions
        for name, changes, expected in FIXTURES:
            intent, metrics = backend.infer(BASE_OBSERVATION | changes, list(VOCABULARY))
            result["fixtures"].append({"name": name, "expected": expected, "actual": intent, **metrics})
        pairs = [("cliff", {"near_cliff": False}, {"near_cliff": True}),
                 ("threat", {"threat": False}, {"threat": True}),
                 ("ground", {"ground_safe": True}, {"ground_safe": False}),
                 ("health", {"health": 80}, {"health": 12})]
        result["contrast_pairs"] = []
        for name, safe, danger in pairs:
            a, am = backend.infer(BASE_OBSERVATION | safe, list(VOCABULARY))
            b, bm = backend.infer(BASE_OBSERVATION | danger, list(VOCABULARY))
            result["contrast_pairs"].append({"name": name, "safe": a, "danger": b, "responds_to_change": a != b, "danger_evades": b == "evade", "safe_wall_ms": am["wall_ms"], "danger_wall_ms": bm["wall_ms"]})
        result["memory"] = memory()
    rows = result["fixtures"]
    result["strict_correct"] = sum(r["actual"] == r["expected"] for r in rows)
    # Near a safe idle leader, holding is also an acceptable style choice.
    result["acceptable"] = sum(r["actual"] == r["expected"] or (r["name"] == "travel" and r["actual"] == "hold") for r in rows)
    result["valid"] = sum(r["actual"] in VOCABULARY for r in rows)
    result["median_ms"] = round(statistics.median(r["wall_ms"] for r in rows), 3)
    result["maximum_ms"] = max(r["wall_ms"] for r in rows)
    result["danger_pairs_correct"] = sum(p["danger_evades"] for p in result["contrast_pairs"])
    (BASE / ("benchmark_bekko" + size + ".json")).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("fixtures", "contrast_pairs")}, indent=2))
    for row in rows:
        print(row["name"], row["actual"], "expected", row["expected"], row["wall_ms"])
    print("Contrast pairs:", result["contrast_pairs"])

if __name__ == "__main__":
    main()
