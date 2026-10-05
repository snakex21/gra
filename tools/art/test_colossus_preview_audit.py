"""Regression checks for scoped loaded colossus evidence validation."""
import copy
import unittest
from verify_colossus_previews import audit_pair


def pair():
    def texture(name,digest):
        return {'source':'res://textures/colossi_material_finish/'+name,'width':2048,'height':2048,'format':17,'pixels_sha256':digest}
    material={'name':'','source':'res://materials/colossi_v3/atlas.tres','normal_scale':.6,'roughness':.85,'metallic':0,'roughness_texture_channel':0,'metallic_texture_channel':0,'textures':{'0':texture('atlas_2k.png','before'),'4':texture('atlas_normal.png','normal-before')}}
    before={'subject':'valus','lod':0,'variant':'before','semantics':[{'kind':'weak_point','state':0,'radius':1.1}],'pose':'rest',
            'meshes':[{'name':'Mesh_000','source':'res://body.glb::mesh','role':'sculpture','transform':[[1,0,0],[0,1,0],[0,0,1],[0,8,0]],
                       'surfaces':[{'vertices':3,'triangles':1,'array_sha256':'unchanged','material':material}]}]}
    after=copy.deepcopy(before);after['variant']='after'
    a=after['meshes'][0]['surfaces'][0]['material']
    a.update(source='res://materials/colossi_material_finish/atlas.tres',roughness=1,metallic=1,roughness_texture_channel=1,metallic_texture_channel=2)
    a['textures']={'0':texture('atlas_2k.png','after'),'4':texture('atlas_normal.png','normal-after'),'1':texture('atlas_orm.png','orm'),'2':texture('atlas_orm.png','orm')}
    return before,after


class AuditTest(unittest.TestCase):
    def test_scoped_material_change_passes(self): self.assertEqual(audit_pair(*pair())['changed_sculpture_bindings'],1)
    def test_geometry_drift_fails(self):
        b,a=pair();a['meshes'][0]['surfaces'][0]['array_sha256']='changed'
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_transform_drift_fails(self):
        b,a=pair();a['meshes'][0]['transform'][3][1]=0
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_normal_strength_drift_fails(self):
        b,a=pair();a['meshes'][0]['surfaces'][0]['material']['normal_scale']=1
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_texture_resolution_drift_fails(self):
        b,a=pair();a['meshes'][0]['surfaces'][0]['material']['textures']['0']['width']=1024
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_unchanged_albedo_fails(self):
        b,a=pair();a['meshes'][0]['surfaces'][0]['material']['textures']['0']['pixels_sha256']='before'
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_weakpoint_semantic_drift_fails(self):
        b,a=pair();a['semantics'][0]['state']=1
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_orm_swapped_channel_fails(self):
        b,a=pair();a['meshes'][0]['surfaces'][0]['material']['metallic_texture_channel']=1
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_wrong_scoped_material_fails(self):
        b,a=pair();a['meshes'][0]['surfaces'][0]['material']['source']='res://materials/unrelated.tres'
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_gameplay_visual_drift_fails(self):
        b,a=pair();g=copy.deepcopy(b['meshes'][0]);g['role']='gameplay_visual';b['meshes'].append(copy.deepcopy(g));a['meshes'].append(g)
        a['meshes'][1]['surfaces'][0]['material']['roughness']=.5
        with self.assertRaises(AssertionError): audit_pair(b,a)
    def test_swapped_variants_fail(self):
        b,a=pair()
        with self.assertRaises(AssertionError): audit_pair(a,b)

if __name__=='__main__': unittest.main()
