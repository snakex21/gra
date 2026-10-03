"""Bounded CPU Choice inference for the author's official shared-prefix ONNX.

Rendering follows hotchpotch/bekko-system-one browser/core.js and decision.js,
MIT reference revision 0fccbb8568b67d47745d820319fe9a4a04e7fa95. This is a local
research adapter: the model author has not assigned a released-weight licence.
"""
import json
import os
from pathlib import Path
import sys
import time

from protocol import validate_request, validate_output

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data/ai"
DESCRIPTIONS = {
    "follow": "Accompany the leader, walking behind them during travel.",
    "hold": "Wait in the current safe place near the leader.",
    "support": "Assist the climbing leader with a bow against the active enemy.",
    "evade": "Move away from immediate danger and retreat to safe ground.",
    "regroup": "Rejoin the faraway leader or recover from a blocked route."
}
INSTRUCTION = "Which companion tactic best fits the observed game state? Avoid immediate danger, cliffs, unsafe ground, or health below 20 first. Otherwise retain safe hold, help a climbing leader if possible, rejoin a leader over 20 metres away or recover a blocked route, or accompany the leader."

def render_state(observation):
    """Fixed factual rendering only: no inferred intent, decision label or answer cache."""
    flags = {"threat": "The companion faces an imminent attack", "enemy_active": "An enemy encounter is active",
             "leader_climbing": "The leader is climbing", "support_available": "The companion can assist with a bow",
             "near_cliff": "The companion is near a cliff edge", "mounted": "The companion is mounted",
             "player_downed": "The companion is downed", "leader_downed": "The leader is downed",
             "ground_safe": "Ground under the companion is walkable and safe", "navigation_blocked": "The route is blocked"}
    lines = []
    for key, value in observation.items():
        if key in flags:
            lines.append(flags[key] + ": " + ("yes" if value else "no") + ".")
        elif key == "health":
            lines.append("Companion health: " + str(value) + " out of 100.")
        elif key == "stamina":
            lines.append("Companion stamina: " + str(value) + " out of 1.")
        elif key == "leader_distance":
            lines.append("Leader distance: " + str(value) + " metres.")
        elif key == "enemy_distance":
            lines.append("Enemy distance: " + ("no enemy observed" if value < 0 else str(value) + " metres") + ".")
        elif key == "intent":
            lines.append("Current companion tactic: " + value + ".")
    return " ".join(lines)


def token_rows(tokenizer, manifest, observation, allowed):
    validate_request({"observation": observation, "allowed": allowed, "generation": 0})
    encode = lambda text: tokenizer.encode(text, add_special_tokens=False).ids
    max_query = min(448, manifest["query_length"])
    instruction, state = encode(INSTRUCTION), encode(json.dumps({"game_state": render_state(observation)}, ensure_ascii=False, separators=(",", ":")))
    im, sm, newline = encode("Instruction: "), encode("State: "), encode("\n")
    budget = max_query - 2 - len(im) - len(sm) - len(newline)
    ni, ns = min(len(instruction), (budget + 1) // 2), min(len(state), budget // 2)
    ni += min(len(instruction) - ni, budget - ni - ns)
    ns += min(len(state) - ns, budget - ni - ns)
    if ni != len(instruction) or ns != len(state):
        raise ValueError("Observation would truncate; keep programmed fallback")
    prefix = [manifest["cls_token_id"], *im, *instruction, *newline, *sm, *state, manifest["sep_token_id"]]
    documents = []
    for name in allowed:
        tokens = encode("Candidate: " + name + ": " + DESCRIPTIONS[name])
        if len(tokens) >= 64:
            raise ValueError("Candidate exceeds bounded branch")
        documents.append([*tokens, manifest["sep_token_id"]])
    return prefix, documents


class BekkoBackend:
    def __init__(self, size="17"):
        if size not in ("17", "68"):
            raise ValueError("Unknown pinned research model")
        self.size = size

    def __enter__(self):
        started = time.perf_counter()
        sys.dont_write_bytecode = True
        sys.path.insert(0, str(BASE / "python"))
        os.environ["TOKENIZERS_PARALLELISM"] = "false"
        os.environ["HF_HUB_OFFLINE"] = "1"
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
        if ort.__version__ != "1.30.0" or np.__version__ != "2.3.3" or not Path(ort.__file__).resolve().is_relative_to((BASE / "python").resolve()):
            raise RuntimeError("Use the pinned portable ONNX runtime; no global/profile fallback")
        self.np = np
        directory = BASE / ("bekko" + self.size)
        self.manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        self.tokenizer = Tokenizer.from_file(str(directory / "tokenizer.json"))
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        options.add_session_config_entry("session.intra_op.allow_spinning", "0")
        options.add_session_config_entry("session.inter_op.allow_spinning", "0")
        options.enable_mem_pattern = False
        options.log_severity_level = 3
        self.session = ort.InferenceSession(str(directory / "model.onnx"), options, providers=["CPUExecutionProvider"])
        self.start_seconds = time.perf_counter() - started
        self.versions = {"onnxruntime": ort.__version__, "numpy": np.__version__}
        return self

    def infer(self, observation, allowed):
        started = time.perf_counter()
        validate_request({"observation": observation, "allowed": allowed, "generation": 0})
        if len(allowed) == 1:
            return allowed[0], {"wall_ms": 0.0, "probabilities": {allowed[0]: 1.0}, "prefix_tokens": 0, "branch_tokens": 0}
        prefix, documents = token_rows(self.tokenizer, self.manifest, observation, allowed)
        np = self.np
        width = max(map(len, documents))
        doc_ids = np.full((len(documents), width), self.manifest["pad_token_id"], dtype=np.int64)
        doc_mask = np.zeros(doc_ids.shape, dtype=np.bool_)
        for row, tokens in enumerate(documents):
            doc_ids[row, :len(tokens)] = tokens
            doc_mask[row, :len(tokens)] = True
        prefix_ids = np.array([prefix], dtype=np.int64)
        feeds = {"prefix_ids": prefix_ids, "prefix_mask": np.ones(prefix_ids.shape, dtype=np.bool_),
                 "doc_ids": doc_ids, "doc_mask": doc_mask, "owners": np.zeros(len(documents), dtype=np.int64)}
        raw = self.session.run(["logits"], feeds)[0]
        if raw.shape != (len(documents), len(self.manifest["tasks"])) or not np.all(np.isfinite(raw)):
            raise ValueError("Invalid Choice logits")
        logits = raw[:, self.manifest["tasks"].index("choice")]
        probabilities = np.exp(logits - np.max(logits))
        probabilities /= probabilities.sum()
        intent = validate_output(allowed[int(np.argmax(probabilities))], allowed)
        return intent, {"wall_ms": round((time.perf_counter() - started) * 1000, 3), "prefix_tokens": len(prefix),
                        "branch_tokens": width, "probabilities": dict(zip(allowed, map(float, probabilities)))}

    def __exit__(self, *_):
        self.session = None
