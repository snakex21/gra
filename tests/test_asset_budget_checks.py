"""CI budget guards reject real threshold breaches without editing any assets."""
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "tools/art/audit_asset_budgets.py"
SPEC = importlib.util.spec_from_file_location("asset_budget_audit", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def allowed_records():
    records = []
    for lod, limit in AUDIT.TRAVELER_LIMITS.items():
        records.append({"path": "models/characters/travelers_v3/traveler_lod%d.glb" % lod,
                        "triangles_node_instances": limit, "images": []})
    for name in AUDIT.WEAPON_IDS:
        for lod, limit in AUDIT.WEAPON_LIMITS.items():
            records.append({"path": "models/weapons_v4/%s_lod%d.glb" % (name, lod),
                            "triangles_node_instances": limit, "images": []})
    return records


class BudgetChecks(unittest.TestCase):
    def test_exact_triangle_and_texture_limits_pass(self):
        textures = [{"path": "textures/characters/travelers_v3/albedo.png", "width": 2048, "height": 2048},
                    {"path": "textures/weapons_v4/albedo.png", "width": 512, "height": 512}]
        self.assertEqual(AUDIT.check_budgets(allowed_records(), textures)["violations"], [])

    def test_each_triangle_limit_rejects_one_extra_triangle(self):
        for index in range(len(allowed_records())):
            records = allowed_records()
            records[index]["triangles_node_instances"] += 1
            violations = AUDIT.check_budgets(records, [])["violations"]
            self.assertEqual(len(violations), 1)
            self.assertEqual(violations[0]["rule"], "triangle_budget")

    def test_oversized_embedded_weapon_texture_rejected(self):
        records = allowed_records()
        records[3]["images"] = [{"index": 0, "width": 513, "height": 512}]
        violations = AUDIT.check_budgets(records, [])["violations"]
        self.assertEqual(violations[0]["rule"], "texture_dimension_budget")

    def test_missing_model_and_unknown_dimensions_rejected(self):
        records = allowed_records()[1:]
        violations = AUDIT.check_budgets(records, [{"path": "textures/test.png", "width": None, "height": None}])["violations"]
        self.assertEqual({v["rule"] for v in violations}, {"required_model", "known_texture_dimensions"})


if __name__ == "__main__":
    unittest.main()
