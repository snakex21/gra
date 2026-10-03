"""Bounded real CPU fixture benchmark. No game and no downloads are launched."""
import json
import os
import platform
import statistics

from backend import Backend, BASE, PINS
from protocol import VOCABULARY

BASE_OBSERVATION = {"health": 100, "stamina": 1.0, "leader_distance": 4.0, "enemy_distance": -1,
                    "threat": False, "enemy_active": False, "leader_climbing": False,
                    "support_available": False, "near_cliff": False, "mounted": False,
                    "player_downed": False, "leader_downed": False, "ground_safe": True,
                    "navigation_blocked": False, "intent": "follow"}
FIXTURES = [
    ("travel", {}, "follow"),
    ("wait_order", {"intent": "hold"}, "hold"),
    ("help_climber", {"enemy_active": True, "enemy_distance": 8, "leader_climbing": True, "support_available": True}, "support"),
    ("incoming_attack", {"threat": True, "enemy_active": True, "enemy_distance": 3}, "evade"),
    ("edge", {"near_cliff": True}, "evade"),
    ("low_health", {"health": 15}, "evade"),
    ("lost_leader", {"leader_distance": 60}, "regroup"),
    ("blocked_path", {"navigation_blocked": True}, "regroup"),
    ("unsafe_ground", {"ground_safe": False}, "evade"),
    ("danger_over_support", {"threat": True, "enemy_active": True, "leader_climbing": True, "support_available": True}, "evade"),
]


def main():
    import sys
    pin_name = sys.argv[1] if len(sys.argv) > 1 else "pins.json"
    result = {"cpu": os.environ.get("PROCESSOR_IDENTIFIER", platform.processor()), "platform": platform.platform(),
              "threads": 2, "context": 512, "max_output_tokens": 12, "model": PINS["model"], "runtime": PINS["runtime"], "fixtures": []}
    with Backend(pin_name) as backend:
        result["model"] = backend.pins["model"]
        result["cold_start_seconds"] = round(backend.start_seconds, 3)
        for name, changes, expected in FIXTURES:
            observation = BASE_OBSERVATION | changes
            try:
                intent, metrics = backend.infer(observation, list(VOCABULARY))
                result["fixtures"].append({"name": name, "expected": expected, "actual": intent, **metrics})
            except (OSError, ValueError, TimeoutError) as exc:
                result["fixtures"].append({"name": name, "expected": expected, "actual": None, "error": str(exc)})
        result["memory"] = backend.memory_mib()
    rows = result["fixtures"]
    result["correct"] = sum(r["actual"] == r["expected"] for r in rows)
    result["valid"] = sum(r["actual"] in VOCABULARY for r in rows)
    times = sorted(r["wall_ms"] for r in rows if "wall_ms" in r)
    if times:
        result["median_ms"] = round(statistics.median(times), 3)
        result["maximum_ms"] = max(times)
    (BASE / ("benchmark_" + pin_name)).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("model", "runtime", "fixtures")}, indent=2))
    for row in rows:
        print(row["name"], row["actual"], "expected", row["expected"], row.get("wall_ms", row.get("error")))


if __name__ == "__main__":
    main()
