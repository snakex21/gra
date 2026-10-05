"""Texture invariants for the isolated finish; no renderer required."""
import unittest
import numpy as np
from PIL import Image
import refine_colossus_materials as m

class FinishTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.arrays,cls.records=m.generate()
        cls.base={name:np.array(Image.open(m.ROOT/'textures/colossi_v3'/name).convert('RGB')) for name in ('atlas_2k.png','atlas_normal.png')}
    def test_control_eyes_teeth_and_unselected_tiles_exact(self):
        for tile in set(range(16))-set(m.TILES):
            for name in self.base:
                np.testing.assert_array_equal(self.arrays[name][m.tile_slice(tile)],self.base[name][m.tile_slice(tile)])
    def test_real_detail_not_uniform_recolor(self):
        for tile in m.TILES:
            sl=m.tile_slice(tile);delta=self.arrays['atlas_2k.png'][sl].astype(float)-self.base['atlas_2k.png'][sl]
            self.assertGreater(delta.std(),3)
            self.assertGreater(np.abs(delta).mean(),2)
            self.assertLess(np.max(np.abs(delta.mean(axis=(0,1)))),3)
            self.assertFalse(np.array_equal(self.arrays['atlas_normal.png'][sl],self.base['atlas_normal.png'][sl]))
    def test_only_fittings_metallic(self):
        for tile in range(16):
            value=self.arrays['atlas_orm.png'][m.tile_slice(tile)][:,:,2]
            if tile in (11,13):self.assertGreater(value.max(),0)
            else:self.assertEqual(int(value.max()),0)
    def test_same_texture_resolution_and_opaque_rgb(self):
        for a in self.arrays.values():
            self.assertEqual(a.shape,(2048,2048,3));self.assertEqual(a.dtype,np.uint8)
    def test_normals_finite_normalized(self):
        n=self.arrays['atlas_normal.png'].astype(float)/255*2-1
        self.assertLess(np.max(np.abs(np.linalg.norm(n,axis=-1)-1)),.025)
        self.assertGreater(n[:,:,2].min(),.80)
    def test_reproducible_committed_payload(self):
        for name,a in self.arrays.items():
            self.assertEqual(m.encoded(a),(m.ROOT/'textures/colossi_material_finish'/name).read_bytes())
    def test_float_blur_has_no_posterization(self):
        a=np.random.default_rng(1).normal(size=(100,100));v=m.blur(a,12)
        self.assertGreater(len(np.unique(v)),9900)
    def test_tile_orientation(self):
        self.assertEqual(m.tile_slice(0),(slice(1536,2048),slice(0,512)))
        self.assertEqual(m.tile_slice(15),(slice(0,512),slice(1536,2048)))
    def test_allowlist_and_readonly_mesh_binding(self):
        s=(m.ROOT/'src/colossus/colossus_art_v3.gd').read_text()
        self.assertIn('FINISHED_PROFILES := [&"valus", &"gaius", &"pelagia"]',s)
        self.assertNotIn('surface_set_material',s)
        self.assertIn('mesh.material_override = material',s)
        self.assertIn('_add_lods(wool, id + "_grip", seg, material)',s)
if __name__=='__main__':unittest.main()
