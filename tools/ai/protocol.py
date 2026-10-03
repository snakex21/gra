"""Small numerical observations only. No player text, names, conversation or tools."""
import math

VOCABULARY = ("follow", "hold", "support", "evade", "regroup")
NUMBERS = {"health": (0, 100), "stamina": (0, 1), "leader_distance": (0, 10000), "enemy_distance": (-1, 10000)}
BOOLEANS = {"threat", "enemy_active", "leader_climbing", "support_available", "near_cliff", "mounted", "player_downed", "leader_downed", "ground_safe", "navigation_blocked"}

def validate_request(data):
    if not isinstance(data, dict) or set(data) != {"observation", "allowed", "generation"}:
        raise ValueError("Invalid request fields")
    generation = data["generation"]
    if type(generation) is not int or generation < 0 or generation > 2147483647:
        raise ValueError("Invalid generation")
    allowed = data["allowed"]
    if not isinstance(allowed, list) or not 1 <= len(allowed) <= 5 or any(type(x) is not str or x not in VOCABULARY for x in allowed) or len(set(allowed)) != len(allowed):
        raise ValueError("Invalid allowed intents")
    observation = data["observation"]
    if not isinstance(observation, dict) or not observation or len(observation) > len(NUMBERS) + len(BOOLEANS) + 1:
        raise ValueError("Invalid observation")
    for key, value in observation.items():
        if key in NUMBERS:
            low, high = NUMBERS[key]
            if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
                raise ValueError("Invalid numeric observation")
        elif key in BOOLEANS:
            if type(value) is not bool:
                raise ValueError("Invalid boolean observation")
        elif key == "intent":
            if type(value) is not str or value not in VOCABULARY:
                raise ValueError("Invalid current intent")
        else:
            raise ValueError("Unknown observation field")
    return observation, allowed, generation

def validate_output(content, allowed):
    if type(content) is not str or len(content) > 32 or content.strip() not in allowed or content.strip() not in VOCABULARY:
        raise ValueError("Model returned invalid intent")
    return content.strip()
