"""CPU-only arena texture provenance, import, seams and budget regressions.

Run: python tests/test_arena_ground_assets.py [--report output.json]
Does not import Godot, render a frame or infer GPU residency/FPS from file sizes.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import generate_arena_ground_materials as AUTHOR

EXPECTED_TILES = {"valus": 14, "hydrus": 12, "basaran": 16, "phalanx": 24,
                  "quadratus": 14, "phaedra": 12, "avion": 14,
                  "barba": 16, "pelagia": 14, "argus": 20, "kuromori": 18, "gaius": 18, "dirge": 22, "celosia_cenobia": 12, "malus": 16, "phoenix": 16, "spider": 14, "dormin": 20}
NEW_ARENAS = ("barba", "pelagia", "argus", "kuromori")
SLOTS = ("albedo", "normal", "roughness")
REPORT = {"scope": "CPU-generated/source-image measurements; not GPU memory or FPS",
          "textures": [], "materials": [], "legacy_assets_preserved": 0}


class ArenaGroundAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generated = dict(AUTHOR.outputs())

    def test_all_eighteen_materials_are_explicit_and_reproducible(self):
        self.assertEqual(set(AUTHOR.CONFIG), set(EXPECTED_TILES))
        self.assertEqual(len(self.generated), 54)
        for arena, tile in EXPECTED_TILES.items():
            with self.subTest(arena=arena):
                self.assertEqual(AUTHOR.CONFIG[arena]["tile"], tile)
                text = (AUTHOR.MATERIALS / (arena + ".tres")).read_text()
                self.assertEqual(text, AUTHOR.material_text(arena))
                self.assertEqual(len(re.findall(r'^\[ext_resource ', text, re.M)), 3)
                self.assertIn('type="StandardMaterial3D"', text)
                for slot in SLOTS:
                    self.assertIn(f'res://textures/arena_ground/{arena}_{slot}.png', text)
                for setting in ("uv1_triplanar = true", "uv1_world_triplanar = false",
                                "normal_enabled = true", "roughness_texture_channel = 0",
                                "texture_filter = 5"):
                    self.assertIn(setting, text)
                self.assertNotRegex(text, r"(?:heightmap_enabled|transparency)\s*=")
                REPORT["materials"].append({"arena": arena, "tile_metres": tile,
                                             "maps": 3, "opaque": True,
                                             "geometry_displacement": False})

    def test_original_four_surface_assets_remain_byte_identical(self):
        baseline = json.loads((ROOT / "tests/fixtures/arena_ground_original_assets.json").read_text())
        self.assertEqual(baseline["source_commit"], "33851a305eeaed6a3371bff74df8feafd8a25ea9")
        self.assertEqual(len(baseline["sha256"]), 16)
        for path, expected in baseline["sha256"].items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected)
        REPORT["legacy_assets_preserved"] = len(baseline["sha256"])

    def test_previous_seven_surfaces_and_import_settings_remain_byte_identical(self):
        baseline = json.loads((ROOT / "tests/fixtures/arena_ground_seven_assets.json").read_text())
        self.assertEqual(baseline["source_commit"], "7f0e8d3a36eba49af936b06a5e74ab732dd754e0")
        self.assertEqual(len(baseline["sha256"]), 49)
        for path, expected in baseline["sha256"].items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected)
        REPORT["previous_seven_assets_preserved"] = len(baseline["sha256"])

    def test_new_surface_palettes_and_dampness_are_distinct(self):
        averages = {}
        roughness = {}
        for arena in NEW_ARENAS:
            color = np.asarray(Image.open(AUTHOR.DEST / f"{arena}_albedo.png"), dtype=float)
            averages[arena] = color.mean(axis=(0, 1))
            roughness[arena] = np.asarray(Image.open(AUTHOR.DEST / f"{arena}_roughness.png"), dtype=float).mean()
        # These semantic relationships keep the new set from degenerating into
        # recolored generic dirt or three equally dry surfaces during reauthoring.
        self.assertGreater(averages["barba"][0]-averages["barba"][2], 30)
        self.assertGreater(averages["pelagia"][1]-averages["pelagia"][0], 12)
        self.assertGreater(averages["pelagia"][1]-averages["pelagia"][2], 15)
        self.assertLess(averages["argus"][0]-averages["argus"][2], 28)
        self.assertGreater(averages["kuromori"][2]-averages["kuromori"][0], 6)
        self.assertGreater(averages["kuromori"][1]-averages["kuromori"][0], 6)
        self.assertLess(roughness["pelagia"], roughness["barba"]-20)
        self.assertLess(roughness["barba"], roughness["argus"]-5)
        REPORT["new_surface_identity"] = {
            arena: {"mean_albedo_rgb": averages[arena].tolist(),
                    "mean_roughness": float(roughness[arena]/255)} for arena in NEW_ARENAS}

    def test_remaining_four_have_distinct_structures_and_palettes(self):
        kinds = ("gaius", "dirge", "celosia_cenobia", "malus")
        means, reliefs = {}, {}
        for kind in kinds:
            color, normal, rough = AUTHOR.remaining_texture(kind)
            means[kind] = np.asarray(color).mean(axis=(0, 1))
            reliefs[kind] = float(np.asarray(normal)[..., :2].std())
            self.assertGreater(float(np.asarray(color).mean(axis=-1).std()), 5.)
            self.assertGreater(float(np.asarray(rough).std()), 1.)
            self.assertGreater(reliefs[kind], 1., "Flat relief placeholder")
        self.assertGreater(means["gaius"][2], means["gaius"][0]+4)
        self.assertGreater(means["dirge"][0], means["dirge"][2]+90)
        self.assertGreater(means["celosia_cenobia"][0], means["celosia_cenobia"][2]+65)
        self.assertGreater(means["malus"][2], means["malus"][0]+35)
        self.assertGreater(means["gaius"].mean(), means["malus"].mean()+35)
        self.assertGreater(reliefs["gaius"], reliefs["dirge"]*2)
        REPORT["remaining_four_identity"] = {kind: {
            "mean_albedo_rgb": means[kind].tolist(), "normal_xy_std": reliefs[kind]
        } for kind in kinds}

    def test_texture_content_import_seams_and_budget(self):
        total_bytes = 0
        hashes = {slot: set() for slot in SLOTS}
        for name, generated in self.generated.items():
            with self.subTest(texture=name):
                path = AUTHOR.DEST / name
                data = path.read_bytes()
                self.assertEqual(data, generated, "Generator output differs from committed asset")
                self.assertLessEqual(len(data), 900_000, "Unexpected 512px source texture cost")
                total_bytes += len(data)
                im = Image.open(io.BytesIO(data))
                self.assertEqual(im.size, (512, 512))
                slot = path.stem.rsplit("_", 1)[1]
                self.assertEqual(im.mode, "L" if slot == "roughness" else "RGB")
                values = np.asarray(im, dtype=float)
                self.assertGreater(float(values.std()), .25, "Flat/placeholder map")
                seams = {}
                for axis, label in ((0, "y"), (1, "x")):
                    wrap = float(np.abs(np.take(values, 0, axis) - np.take(values, -1, axis)).mean())
                    deltas = np.abs(np.diff(values, axis=axis))
                    boundary_means = np.moveaxis(deltas, axis, 0).reshape(511, -1).mean(axis=1)
                    # A periodic fracture may cross the border at a steeper point
                    # than the global average. Compare it with the full interior
                    # boundary distribution, allowing half a quantization level.
                    self.assertLessEqual(wrap, max(3., float(boundary_means.max()) + .5),
                                         f"{label}-edge discontinuity exceeds all interior boundaries")
                    seams[label] = {"wrap_mean_delta": wrap,
                                    "adjacent_mean_delta": float(boundary_means.mean()),
                                    "adjacent_p99_delta": float(np.quantile(boundary_means, .99)),
                                    "adjacent_max_delta": float(boundary_means.max())}
                if slot == "normal":
                    normals = values / 127.5 - 1
                    self.assertLess(float(np.abs(np.linalg.norm(normals, axis=-1) - 1).max()), .014)
                    self.assertGreaterEqual(float(normals[..., 2].min()), 0)
                elif slot == "roughness":
                    self.assertGreaterEqual(float(values.min()), 168)
                    self.assertLessEqual(float(values.max()), 253)
                sidecar = Path(str(path) + ".import").read_text()
                for setting in ('importer="texture"', 'type="CompressedTexture2D"',
                                "compress/mode=2", "mipmaps/generate=true",
                                "process/normal_map_invert_y=false"):
                    self.assertIn(setting, sidecar)
                self.assertIn("compress/normal_map=" + ("1" if slot == "normal" else "0"), sidecar)
                sha = hashlib.sha256(data).hexdigest()
                hashes[slot].add(sha)
                REPORT["textures"].append({"file": str(path.relative_to(ROOT)), "bytes": len(data),
                                            "sha256": sha, "dimensions": list(im.size), "mode": im.mode,
                                            "seam_deltas": seams})
        for slot in SLOTS:
            self.assertEqual(len(hashes[slot]), 18, "Arenas accidentally reuse an identical source map")
        custom = sum(len(data) for name, data in self.generated.items()
                     if name.split('_', 1)[0] in ('phoenix', 'spider', 'dormin'))
        self.assertLessEqual(custom, 1_800_000, "Custom ground increment exceeded")
        self.assertLessEqual(total_bytes-custom, 12_000_000, "Prior fifteen budget regressed")
        self.assertLessEqual(total_bytes, 13_800_000)
        REPORT["custom_three_source_png_bytes"] = custom
        remaining = ("gaius", "dirge", "celosia_cenobia", "malus")
        added = sum(len(data) for name, data in self.generated.items() if any(name.startswith(k+"_") for k in remaining))
        self.assertLessEqual(total_bytes-added-custom, 9_000_000, "Prior eleven budget regressed")
        self.assertLessEqual(added, 3_000_000, "Remaining four ground budget exceeded")
        REPORT["remaining_four_source_png_bytes"] = added
        REPORT["prior_eleven_source_png_bytes"] = total_bytes-added-custom
        REPORT["source_png_bytes"] = total_bytes
        REPORT["new_four_arenas_source_png_bytes"] = sum(
            row["bytes"] for row in REPORT["textures"]
            if Path(row["file"]).stem.split("_", 1)[0] in NEW_ARENAS)
        self.assertLessEqual(REPORT["new_four_arenas_source_png_bytes"], 3_000_000)
        REPORT["unique_source_maps"] = {slot: len(values) for slot, values in hashes.items()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args, remaining = parser.parse_known_args()
    result = unittest.main(argv=[sys.argv[0], *remaining], exit=False).result
    REPORT["status"] = "PASS" if result.wasSuccessful() else "FAIL"
    REPORT["tests_run"] = result.testsRun
    REPORT["failures"] = len(result.failures)
    REPORT["errors"] = len(result.errors)
    if args.report:
        args.report.write_text(json.dumps(REPORT, indent=2) + "\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
