"""Skinned core structural tests; intentionally not a substitute for motion review."""
import unittest,json,sys
from pathlib import Path
import numpy as np
from refine_character_materials import unpack
ROOT=Path(__file__).resolve().parents[2]

def array(d,b,index):
 a=d['accessors'][index];v=d['bufferViews'][a['bufferView']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
 n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];start=v.get('byteOffset',0)+a.get('byteOffset',0)
 assert not a.get('sparse') and 'byteStride' not in v
 return np.frombuffer(b,dtype=dtype,count=a['count']*n,offset=start).reshape(a['count'],n)
class SkinSource(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.d,cls.b=unpack((ROOT/'models/agro_skin/agro_lod0.glb').read_bytes())
  cls.primitives=cls.d['meshes'][0]['primitives'];core_names={'Agro neutral anatomical clay','Agro core black points','Agro detail muzzle','Agro core cream star'}
  pp=[];jj=[];ww=[];ii=[];offset=0;cls.all_weights=[];cls.all_joints=[];cls.total_triangles=0
  for primitive in cls.primitives:
   attrs=primitive['attributes'];positions=array(cls.d,cls.b,attrs['POSITION']);joints=array(cls.d,cls.b,attrs['JOINTS_0']);weights=array(cls.d,cls.b,attrs['WEIGHTS_0']);indices=array(cls.d,cls.b,primitive['indices']).ravel()
   cls.all_weights.extend(weights);cls.all_joints.extend(joints);cls.total_triangles+=len(indices)//3
   assert 'TEXCOORD_0' in attrs and 'TANGENT' in attrs,'Actual runtime normal maps require UVs and tangents'
   if cls.d['materials'][primitive['material']]['name'] in core_names:
    pp.append(positions);jj.append(joints);ww.append(weights);ii.append(indices+offset);offset+=len(positions)
  cls.pos=np.concatenate(pp);cls.j=np.concatenate(jj);cls.w=np.concatenate(ww);cls.indices=np.concatenate(ii)
  cls.all_weights=np.array(cls.all_weights);cls.all_joints=np.array(cls.all_joints)
  cls.m=json.loads((ROOT/'assets/agro_skin_manifest.json').read_text())
 def test_single_core_skin_named_public_bones(self):
  self.assertEqual(len(self.d['skins']),1);self.assertEqual(len(self.d['meshes']),1)
  self.assertEqual([self.d['nodes'][i]['name'] for i in self.d['skins'][0]['joints']],list(self.m['rest']))
 def test_finite_normalized_sparse_weights(self):
  self.assertTrue(np.isfinite(self.pos).all());self.assertTrue(np.isfinite(self.all_weights).all());self.assertTrue((self.all_weights>=0).all())
  self.assertTrue(np.allclose(self.all_weights.sum(axis=1),1,atol=1e-6));self.assertLessEqual(int((self.all_weights>1e-7).sum(axis=1).max()),4)
  self.assertTrue((self.all_joints<15).all())
 def test_bind_is_inverse_of_recorded_neutral(self):
  a=array(self.d,self.b,self.d['skins'][0]['inverseBindMatrices'])
  reference=json.loads((ROOT/'assets/agro_skin_neutral_reference.json').read_text())
  for n,name in enumerate(self.m['rest']):
   matrix=np.eye(4);matrix[:3,:]=np.array(reference['global_pose'][name]).T
   expected=np.linalg.inv(matrix)
   self.assertTrue(np.allclose(a[n].reshape(4,4).T,expected,atol=2e-6),name)
 def test_no_opposing_leg_influences(self):
  names=list(self.m['rest'])
  for joints,weights in zip(self.j,self.w):
   prefixes={names[int(j)].split('_')[0] for j,w in zip(joints,weights) if w>1e-7 and '_' in names[int(j)]}
   self.assertLessEqual(len(prefixes),1)
 def test_skin_trunk_at_saddle_stays_body_rigid(self):
  mask=(abs(self.pos[:,0])<.25)&(self.pos[:,1]>1.5)&(self.pos[:,2]>-.40)&(self.pos[:,2]<.35)
  self.assertGreater(mask.sum(),10)
  for joints,weights in zip(self.j[mask],self.w[mask]):self.assertAlmostEqual(float(weights[joints==0].sum()),1,places=6)
 def test_neutral_hind_root_has_no_lateral_cuff_overhang(self):
  # Regression for the visible rear-flank nub: measured silhouette vertices
  # formerly reached x=0.39 here, outside the torso envelope.
  mask=(self.pos[:,1]>1.34)&(self.pos[:,1]<1.42)&(self.pos[:,2]>.88)
  self.assertGreater(int(mask.sum()),10)
  self.assertLess(float(abs(self.pos[mask,0]).max()),.35)
 def test_core_is_connected_closed_surface(self):
  # glTF splits UV seams; weld position equivalence for topology check.
  _,idx=np.unique(np.round(self.pos,6),axis=0,return_inverse=True)
  triangles=idx[self.indices].reshape(-1,3)
  from collections import Counter
  edges=Counter(tuple(sorted((int(a),int(b)))) for t in triangles for a,b in zip(t,np.roll(t,-1)))
  self.assertTrue(all(n==2 for n in edges.values()))
  parent=list(range(int(idx.max())+1))
  def find(a):
   while parent[a]!=a:parent[a]=parent[parent[a]];a=parent[a]
   return a
  for a,b in edges:parent[find(a)]=find(b)
  self.assertEqual(len({find(a) for a in range(len(parent))}),1)
 def test_all_lods_match_manifest_and_bind_reference(self):
  reference=json.loads((ROOT/'assets/agro_skin_neutral_reference.json').read_text())
  counts=[]
  for lod in range(3):
   d,b=unpack((ROOT/f'models/agro_skin/agro_lod{lod}.glb').read_bytes());count=0
   self.assertEqual([d['nodes'][i]['name'] for i in d['skins'][0]['joints']],list(self.m['rest']))
   binds=array(d,b,d['skins'][0]['inverseBindMatrices'])
   for i,name in enumerate(self.m['rest']):
    mat=np.eye(4);mat[:3,:]=np.array(reference['global_pose'][name]).T
    self.assertTrue(np.allclose(mat@binds[i].reshape(4,4).T,np.eye(4),atol=2e-6))
   for primitive in d['meshes'][0]['primitives']:
    count+=len(array(d,b,primitive['indices']))//3
    at=primitive['attributes'];pos=array(d,b,at['POSITION']);w=array(d,b,at['WEIGHTS_0']);n=array(d,b,at['NORMAL']);t=array(d,b,at['TANGENT'])
    self.assertTrue(np.isfinite(pos).all() and np.isfinite(w).all() and np.isfinite(t).all())
    self.assertTrue(np.allclose(w.sum(axis=1),1,atol=1e-6))
    self.assertTrue(np.allclose(np.linalg.norm(n,axis=1),1,atol=1e-5))
    self.assertTrue(np.allclose(np.linalg.norm(t[:,:3],axis=1),1,atol=1e-4))
    # Blender glTF rounds tangent components to four decimals.
    self.assertLess(float(abs((t[:,:3]*n).sum(axis=1)).max()),2e-4)
    self.assertLess(float(abs(pos).max()),3)
   counts.append(count)
  self.assertEqual(counts,self.m['skin_triangle_counts'])
  self.assertEqual([counts[i]+[784,360,136][i] for i in range(3)],self.m['total_triangle_counts'])
  self.assertTrue(all(a<=b for a,b in zip(self.m['total_triangle_counts'],[9482,4347,1676])))
 def test_core_and_total_budget(self):
  self.assertLessEqual(len(self.indices)//3,6500)
  self.assertLessEqual(self.total_triangles+784,9482)
  self.assertFalse(self.d.get('animations'))
if __name__=='__main__':unittest.main()
