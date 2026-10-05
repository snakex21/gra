"""CPU-only authored architecture provenance, physical scale and map regressions.

Run: python tests/test_arena_architecture_assets.py [--report output.json]
No engine/display/GPU. Source texture budgets are not FPS or residency claims.
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
import generate_arena_architecture_materials as AUTHOR

EXPECTED = {"barba": (8., 6, 3), "kuromori": (8., 5, 3), "argus": (10., 5, 3), "gaius": (8., 4, 3), "dirge": (10., 5, 3), "celosia_cenobia": (8., 5, 3), "malus": (10., 5, 3), "phoenix": (10., 4, 3), "spider": (10., 5, 3), "dormin": (12., 4, 3)}
REPORT = {"scope": "CPU/source assets, not GPU memory, game screenshots or FPS", "textures": [], "materials": []}


class ArchitectureAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generated = dict(AUTHOR.outputs())

    def test_materials_use_physical_monumental_scale_and_existing_renderer(self):
        self.assertEqual(set(AUTHOR.CONFIG), set(EXPECTED))
        for kind, (tile, rows, columns) in EXPECTED.items():
            with self.subTest(arena=kind):
                cfg = AUTHOR.CONFIG[kind]
                self.assertEqual((cfg["tile"], cfg["rows"], cfg["columns"]), (tile, rows, columns))
                self.assertGreaterEqual(tile/rows, 1.3, "Domestic brick-sized course")
                self.assertGreaterEqual(tile/columns, 2.6, "Domestic brick-sized block")
                text = (AUTHOR.MATERIALS/f"{kind}.tres").read_text()
                self.assertEqual(text, AUTHOR.material_text(kind))
                self.assertIn('type="StandardMaterial3D"', text)
                self.assertEqual(len(re.findall(r'^\[ext_resource ', text, re.M)), 3)
                for slot in AUTHOR.SLOTS:
                    self.assertIn(f"res://textures/arena_architecture/{kind}_{slot}.png", text)
                for setting in ("uv1_triplanar = true", "uv1_world_triplanar = false",
                                "uv1_triplanar_sharpness = 6.0", "normal_enabled = true",
                                "roughness_texture_channel = 0", "texture_filter = 5"):
                    self.assertIn(setting, text)
                self.assertIn(f"uv1_scale = Vector3({1/tile:.9f}, {1/tile:.9f}, {1/tile:.9f})", text)
                self.assertNotRegex(text, r"(?:heightmap|transparency|emission|detail_enabled|grow_enabled)\s*=")
                self.assertNotIn("ShaderMaterial", text)
                REPORT["materials"].append({"arena": kind, "tile_metres": tile,
                    "average_block_width_metres": tile/columns,
                    "average_course_height_metres": tile/rows,
                    "normal_scale": cfg["normal"], "opaque": True, "geometry_displacement": False})

    def test_pngs_reproduce_byte_for_byte_and_stay_in_budget(self):
        self.assertEqual(len(self.generated), 30)
        total = 0
        hashes = {slot: set() for slot in AUTHOR.SLOTS}
        for name, generated in self.generated.items():
            with self.subTest(texture=name):
                path = AUTHOR.DEST/name
                data = path.read_bytes()
                self.assertEqual(data, generated)
                self.assertLessEqual(len(data), 480_000, "Unexpected single source PNG cost")
                im = Image.open(io.BytesIO(data))
                self.assertEqual(im.size, (512, 512))
                slot = path.stem.rsplit("_", 1)[1]
                self.assertEqual(im.mode, "L" if slot == "roughness" else "RGB")
                values = np.asarray(im, dtype=float)
                if slot == "albedo":
                    self.assertGreater(float(values.mean(axis=-1).std()), 5., "Flat albedo placeholder")
                    self.assertGreater(float(values.min()), 40.)
                    self.assertLess(float(values.max()), 230.)
                elif slot == "normal":
                    n = values/127.5-1
                    self.assertLess(float(np.abs(np.linalg.norm(n, axis=-1)-1).max()), .014)
                    self.assertGreater(float(n[..., 2].min()), 0.)
                    self.assertGreater(float(n[..., :2].std()), .10, "Normal map relief vanished")
                else:
                    self.assertGreater(float(values.std()), 3., "Flat roughness placeholder")
                    self.assertGreaterEqual(float(values.min()), 175.)
                    self.assertLessEqual(float(values.max()), 253.)
                AUTHOR.validate_import(path)
                sha = hashlib.sha256(data).hexdigest()
                hashes[slot].add(sha)
                total += len(data)
                REPORT["textures"].append({"file": path.relative_to(ROOT).as_posix(),
                    "sha256": sha, "bytes": len(data), "dimensions": list(im.size),
                    "mode": im.mode})
        custom = sum(len(data) for name, data in self.generated.items()
                     if name.split('_', 1)[0] in ('phoenix', 'spider', 'dormin'))
        self.assertLessEqual(custom, 2_200_000, "Custom architecture increment exceeded")
        self.assertLessEqual(total-custom, 5_600_000, "Prior seven budget regressed")
        self.assertLessEqual(total, AUTHOR.SOURCE_BUDGET_BYTES)
        REPORT["custom_three_source_png_bytes"] = custom
        remaining = ("gaius", "dirge", "celosia_cenobia", "malus")
        added = sum(len(data) for name, data in self.generated.items() if any(name.startswith(k+"_") for k in remaining))
        self.assertLessEqual(total-added-custom, 2_400_000, "Prior three budget regressed")
        self.assertLessEqual(added, 3_000_000, "Remaining four architecture budget exceeded")
        REPORT["remaining_four_source_png_bytes"] = added
        REPORT["prior_three_source_png_bytes"] = total-added-custom
        for slot, values in hashes.items():
            self.assertEqual(len(values), 10, f"Duplicated {slot} across arenas")
        REPORT["source_png_bytes"] = total
        REPORT["source_png_budget_bytes"] = AUTHOR.SOURCE_BUDGET_BYTES

    def test_periodic_fields_really_repeat_not_just_painted_borders(self):
        # Independent off-grid samples exercise continuous period invariance,
        # including unequal block/course identities and the carved collar.
        v, u = np.mgrid[:43, :47].astype(float)
        u, v = (u+.237)/47, (v+.713)/43
        for kind in EXPECTED:
            base = AUTHOR.surface_fields(kind, u, v)
            for du, dv in ((1, 0), (0, 1), (-2, 3)):
                other = AUTHOR.surface_fields(kind, u+du, v+dv)
                for slot, a, b in zip(("albedo", "physical_height", "roughness"), base, other):
                    with self.subTest(arena=kind, slot=slot, shift=(du, dv)):
                        np.testing.assert_allclose(a, b, rtol=0, atol=2e-9)

    def test_encoded_wrap_gradients_fit_interior_boundaries(self):
        measurements = {}
        for name in self.generated:
            values = np.asarray(Image.open(AUTHOR.DEST/name), dtype=float)
            seams = {}
            for axis, label in ((0, "y"), (1, "x")):
                wrap = float(np.abs(np.take(values, 0, axis)-np.take(values, -1, axis)).mean())
                delta = np.moveaxis(np.abs(np.diff(values, axis=axis)), axis, 0).reshape(511, -1).mean(axis=1)
                # Stone joints can be much sharper than the field average.
                # A seamless wrap must fit the actual interior distribution.
                self.assertLessEqual(wrap, max(3., float(delta.max())+.5), name+" "+label)
                seams[label] = {"wrap_mean_delta": wrap, "interior_mean_delta": float(delta.mean()),
                                "interior_p99_delta": float(np.quantile(delta, .99)),
                                "interior_max_delta": float(delta.max())}
            measurements[name] = seams
        REPORT["encoded_seam_measurements"] = measurements

    def test_rain_is_gravity_aligned_and_palettes_remain_distinct(self):
        averages, roughness = {}, {}
        for kind in EXPECTED:
            color = np.asarray(Image.open(AUTHOR.DEST/f"{kind}_albedo.png"), dtype=float)
            averages[kind] = color.mean(axis=(0, 1))
            roughness[kind] = float(np.asarray(Image.open(AUTHOR.DEST/f"{kind}_roughness.png"), dtype=float).mean()/255)
        self.assertGreater(averages["barba"][0]-averages["barba"][2], 42.)
        self.assertGreater(averages["kuromori"][1]-averages["kuromori"][0], 11.)
        self.assertGreater(averages["kuromori"][2]-averages["kuromori"][0], 10.)
        self.assertLess(averages["argus"][0]-averages["argus"][2], 23.)
        self.assertLess(roughness["kuromori"], roughness["barba"]-.04)
        self.assertLess(roughness["barba"], roughness["argus"]-.025)
        y, x = np.mgrid[:512, :512]/512
        rain = AUTHOR.periodic_noise(x, y, 43, 3, np.random.default_rng(917))
        self.assertGreater(np.abs(np.diff(rain, axis=1)).mean(), np.abs(np.diff(rain, axis=0)).mean()*8)
        REPORT["identity"] = {kind: {"mean_albedo_rgb": list(averages[kind]), "mean_roughness": roughness[kind]} for kind in EXPECTED}

    def test_remaining_palettes_pair_with_ground_and_keep_storm_dampness(self):
        kinds = ("gaius", "dirge", "celosia_cenobia", "malus")
        means, roughness = {}, {}
        for kind in kinds:
            rgb = np.asarray(Image.open(AUTHOR.DEST/f"{kind}_albedo.png"), dtype=float)
            ground = np.asarray(Image.open(ROOT/f"textures/arena_ground/{kind}_albedo.png"), dtype=float)
            means[kind] = rgb.mean(axis=(0, 1))
            roughness[kind] = np.asarray(Image.open(AUTHOR.DEST/f"{kind}_roughness.png"), dtype=float).mean()
            self.assertLess(float(np.linalg.norm(means[kind]-ground.mean(axis=(0, 1)))), 35., "Architecture palette no longer pairs with its arena ground")
        self.assertGreater(means["gaius"].mean(), means["malus"].mean()+40)
        self.assertGreater(means["dirge"][0]-means["dirge"][2], 65)
        self.assertGreater(means["celosia_cenobia"][0]-means["celosia_cenobia"][2], 65)
        self.assertGreater(means["malus"][2]-means["malus"][0], 30)
        self.assertLess(roughness["malus"], roughness["dirge"]-30)
        REPORT["remaining_four_identity"] = {kind: {"mean_albedo_rgb": means[kind].tolist(), "mean_roughness": float(roughness[kind]/255)} for kind in kinds}

    def test_previous_fifteen_ground_and_seven_architecture_sets_are_unchanged(self):
        baseline = json.loads((ROOT/"tests/fixtures/arena_custom_prior_assets.json").read_text())
        self.assertEqual(len(baseline['sha256']), 154)
        for path, expected in baseline['sha256'].items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected)
        REPORT['prior_custom_pass_files_preserved'] = len(baseline['sha256'])

    def test_custom_palettes_pair_with_ground_and_increment_stays_under_four_mb(self):
        means, ground_means, roughness = {}, {}, {}
        total = 0
        for kind in ('phoenix', 'spider', 'dormin'):
            means[kind] = np.asarray(Image.open(AUTHOR.DEST/f"{kind}_albedo.png"), dtype=float).mean(axis=(0, 1))
            ground_means[kind] = np.asarray(Image.open(ROOT/f"textures/arena_ground/{kind}_albedo.png"), dtype=float).mean(axis=(0, 1))
            roughness[kind] = np.asarray(Image.open(AUTHOR.DEST/f"{kind}_roughness.png"), dtype=float).mean()
            self.assertLess(float(np.linalg.norm(means[kind]-ground_means[kind])), 28.)
            for folder in ("arena_ground", "arena_architecture"):
                total += sum((ROOT/f"textures/{folder}/{kind}_{slot}.png").stat().st_size for slot in AUTHOR.SLOTS)
        self.assertLessEqual(total, 4_000_000)
        for colors in (means, ground_means):
            self.assertGreater(colors['phoenix'][0]-colors['phoenix'][2], 16.)
            self.assertGreater(colors['spider'][1]-colors['spider'][0], 10.)
            self.assertGreater(colors['dormin'].mean(), colors['spider'].mean()+55.)
            self.assertLess(abs(colors['dormin'][0]-colors['dormin'][2]), 15.)
        self.assertGreater(roughness['spider'], roughness['phoenix']+10.)
        REPORT['custom_six_sets_source_png_bytes'] = total

    def test_normal_derivatives_use_metres_and_wrapped_edges(self):
        x = np.arange(512)*2*np.pi/512
        h = np.broadcast_to(np.sin(x)[None, :]*.02, (512, 512))
        n8 = AUTHOR.normal_map(h, 8)/127.5-1
        n16 = AUTHOR.normal_map(h, 16)/127.5-1
        gradient = (2*np.pi/8)*np.cos(x)*.02
        expected = -gradient/np.sqrt(1+gradient*gradient)
        np.testing.assert_allclose(n8[0, :, 0], expected, atol=4e-7)
        np.testing.assert_allclose(n8[..., 1], 0., atol=1e-15)
        self.assertAlmostEqual(float(n8[0, 0, 0]/n16[0, 0, 0]), 2., delta=.001)
        np.testing.assert_allclose(AUTHOR.normal_map(np.zeros((512, 512)), 8),
                                   np.broadcast_to([127.5, 127.5, 255.], (512, 512, 3)))

    def test_manifest_covers_every_output_and_explains_limits(self):
        text = AUTHOR.MANIFEST.read_text()
        self.assertEqual(text, AUTHOR.manifest_text(self.generated))
        doc = json.loads(text)
        self.assertFalse(doc["geometry_displacement"])
        self.assertEqual(doc["dimensions"], [512, 512])
        self.assertEqual(doc["maps_per_arena"], list(AUTHOR.SLOTS))
        self.assertEqual(len(doc["textures"]), 30)
        self.assertIn("not GPU", doc["budget_scope"])
        self.assertIn("no external", doc["authoring"])
        self.assertEqual(doc["source_png_bytes"], sum(len(data) for data in self.generated.values()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args, remaining = parser.parse_known_args()
    result = unittest.main(argv=[sys.argv[0], *remaining], exit=False).result
    REPORT.update(status="PASS" if result.wasSuccessful() else "FAIL", tests_run=result.testsRun,
                  failures=len(result.failures), errors=len(result.errors))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(REPORT, indent=2)+"\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
