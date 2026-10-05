"""Carry measured runtime dielectric specular through Godot's GLB export.
Only JSON scalar transport. Geometry, image bytes and renderer remain unchanged.
"""
import json,struct,hashlib,math
from pathlib import Path

def complete(path):
 path=Path(path);snap=path.with_suffix('.json');record=json.loads(snap.read_text());values={}
 assert record['material_mode']=='production'
 for mesh in record['meshes']:
  for surface in mesh['surfaces']:
   m=surface['material'];name=m['export_name'];spec=m['metallic_specular']
   assert isinstance(spec,(float,int)) and math.isfinite(spec) and 0<=spec<=.5
   if name in values:assert abs(values[name]-spec)<1e-7
   values[name]=spec
 raw=path.read_bytes();size,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
 doc=json.loads(raw[20:20+size]);binary=raw[20+size:];assert struct.unpack_from('<II',binary)==(len(binary)-8,0x004e4942)
 changes=[]
 for mat in doc.get('materials',[]):
  name=mat.get('name');assert name in values, 'Unmeasured exported material '+str(name)
  spec=values[name]
  if abs(spec-.5)<1e-7:continue
  mat.setdefault('extensions',{})['KHR_materials_specular']={'specularFactor':2*spec}
  changes.append({'material':name,'runtime_specular':spec,'transport_factor':2*spec})
 if changes:
  used=doc.setdefault('extensionsUsed',[])
  if 'KHR_materials_specular' not in used:used.append('KHR_materials_specular')
  j=json.dumps(doc,separators=(',',':'),allow_nan=False).encode();j+=b' '*(-len(j)%4)
  path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(j)+len(binary))+struct.pack('<II',len(j),kind)+j+binary)
 sha=lambda b:hashlib.sha256(b).hexdigest()
 proof={'snapshot_sha256':sha(snap.read_bytes()),'before_sha256':sha(raw),'after_sha256':sha(path.read_bytes()),'binary_sha256':sha(binary),'changes':changes,'scope':'Actual measured scalar only; no binary geometry/image or renderer changes'}
 path.with_suffix('.specular-transport.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
if __name__=='__main__':
 import sys
 for path in sys.argv[1:]:print(json.dumps(complete(path)))
