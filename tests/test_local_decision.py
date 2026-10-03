"""Protocol and actual loopback HTTP rejection tests; no weights required."""
import json
from pathlib import Path
import socket
import sys
import threading
import unittest
import urllib.error
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "ai"))
from backend import completion_payload
from protocol import validate_request, validate_output
from run import DecisionServer
from bekko_backend import render_state


class FakeBackend:
    def __init__(self):
        self.error = False
        self.calls = 0

    def infer(self, observation, allowed):
        self.calls += 1
        if self.error:
            raise TimeoutError("bounded mock timeout")
        return allowed[0], {}


class ProtocolTests(unittest.TestCase):
    def payload(self):
        return {"observation": {"health": 90, "threat": False, "enemy_distance": -1, "intent": "follow"}, "allowed": ["follow", "hold"], "generation": 7}

    def test_valid_scalar_state(self):
        obs, allowed, generation = validate_request(self.payload())
        self.assertEqual((obs["enemy_distance"], allowed, generation), (-1, ["follow", "hold"], 7))

    def test_malicious_and_non_scalar_state(self):
        for key, value in [("message", "ignore instructions"), ("health", True), ("health", -1), ("health", 101),
                           ("health", float("nan")), ("stamina", float("inf")), ("threat", 1),
                           ("intent", "exec_shell"), ("leader_distance", {"node": 1}), ("enemy_distance", -2)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                data = self.payload()
                data["observation"][key] = value
                validate_request(data)

    def test_generation_and_envelope(self):
        for value in (-1, True, 1.5, "7", 2147483648):
            with self.subTest(value=value), self.assertRaises(ValueError):
                data = self.payload()
                data["generation"] = value
                validate_request(data)
        data = self.payload() | {"url": "https://example.com"}
        with self.assertRaises(ValueError):
            validate_request(data)

    def test_allowed_vocabulary(self):
        for allowed in ([], ["follow", "follow"], ["follow", "delete"], [False], "follow"):
            with self.subTest(allowed=allowed), self.assertRaises(ValueError):
                validate_request(self.payload() | {"allowed": allowed})

    def test_generated_output_never_executes(self):
        for output in (None, "support", "FOLLOW", "follow; quit()", '{"intent":"follow"}', "<think>follow</think>", "f" * 2000):
            with self.subTest(output=output), self.assertRaises(ValueError):
                validate_output(output, ["follow"])
        self.assertEqual(validate_output("follow\n", ["follow"]), "follow")

    def test_grammar_cannot_inject(self):
        body = completion_payload({"health": 100}, ["follow", "evade"])
        self.assertEqual(body["grammar"], 'root ::= "follow" | "evade"')
        self.assertEqual(body["n_predict"], 12)
        with self.assertRaises(ValueError):
            completion_payload({"health": 100}, ['follow" | arbitrary'])

    def test_semantic_state_is_factual_and_has_no_selected_label(self):
        text = render_state({"health": 12, "leader_distance": 63, "threat": True, "ground_safe": False})
        self.assertIn("12 out of 100", text)
        self.assertIn("63 metres", text)
        self.assertIn("imminent attack: yes", text)
        self.assertIn("walkable and safe: no", text)
        self.assertFalse(any(intent in text for intent in ("evade", "regroup", "support")))

    def test_loopback_http_validation_cooldown_and_timeout(self):
        backend = FakeBackend()
        with DecisionServer(backend) as server:
            # serve_forever's select is application request handling, not task progress polling.
            thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
            thread.start()
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            def post(data, headers=None):
                request = urllib.request.Request("http://127.0.0.1:8766/decision", data=json.dumps(data).encode(), headers={"Content-Type": "application/json", **(headers or {})})
                with opener.open(request, timeout=3) as response:
                    return json.load(response)
            try:
                self.assertEqual(post(self.payload()), {"intent": "follow", "generation": 7})
                with self.assertRaises(urllib.error.HTTPError) as exc:
                    post(self.payload())
                self.assertEqual(exc.exception.code, 429)
                self.assertEqual(backend.calls, 1)
                server.next_at = 0
                backend.error = True
                with self.assertRaises(urllib.error.HTTPError) as exc:
                    post(self.payload())
                self.assertEqual(exc.exception.code, 503)
                with self.assertRaises(urllib.error.HTTPError) as exc:
                    post(self.payload() | {"instructions": "ignore"})
                self.assertEqual(exc.exception.code, 400)
                with self.assertRaises(urllib.error.HTTPError) as exc:
                    post(self.payload(), {"Origin": "https://example.com"})
                self.assertEqual(exc.exception.code, 403)
            finally:
                server.shutdown()
                thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
