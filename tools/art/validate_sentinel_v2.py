"""Export and region-envelope validation for the original 17-part Sentinel v2."""
import json,struct,hashlib
from pathlib import Path
from validate_exports import read_glb
ROOT=Path(__file__).resolve().parents[2]
m=json.loads((ROOT/'assets/sentinel_v2_manifest.json').read_text())
old={a['id']:a for a in json.loads((ROOT/'assets/art_manifest.json').read_text())['assets'] if a['category']=='colossus'}
rows=[]
for a in m['assets']:
 p=ROOT/a['runtime'];counts=[read_glb(p.with_name(p.name.replace('_lod0',f'_lod{i}')),a['bounds_godot'] if i==0 else None) for i in range(3)]
 assert counts==a['lod_triangles'] and 0<counts[2]<=counts[1]<=counts[0]
 # Outer silhouette remains close to approved first-tranche collision-aligned shell.
 b=old[a['id']]['bounds_godot'];deviation=max(abs(f(v[i] for v in a['bounds_godot'])-f(v[i] for v in b)) for i in range(3) for f in [min,max])
 assert deviation<.15,(a['id'],deviation)
 rows.append({'id':a['id'],'lod_triangles':counts,'max_envelope_delta_m':deviation})
assert len(rows)==17
variants=[]
for a in m.get('optional_foot_variants',[]):
 p=ROOT/a['runtime'];counts=[read_glb(p.with_name(p.name.replace('_lod0',f'_lod{i}')),a['bounds_godot'] if i==0 else None) for i in range(3)]
 assert counts==a['lod_triangles'] and 0<counts[2]<=counts[1]<=counts[0]
 expected=[(-.85,.85),(-.4,.3),(-2.65,.95)]
 for i,(lo,hi) in enumerate(expected):
  assert abs(min(v[i] for v in a['bounds_godot'])-lo)<.001
  assert abs(max(v[i] for v in a['bounds_godot'])-hi)<.001
 variants.append({'id':a['id'],'lod_triangles':counts,'foot_size':[1.7,.7,3.6],'foot_center':[0,-.05,-.85]})
assert len(variants)==2
assert struct.unpack_from('>II',(ROOT/'textures/sentinel_v2/atlas_2k.png').read_bytes(),16)==(2048,2048)
result={'optional_foot_variants':variants,'segments':rows,'unique_triangles_by_lod':[sum(r['lod_triangles'][i] for r in rows) for i in range(3)],'texture_resolution':[2048,2048],'source':'art/source/sentinel_v2.blend','reference_height_metres':17,'notes':['Rigid joint-local mesh source with 10-ring capsule joint loops; no replacement skin rig.','Visual envelope comparison is against v1 art, not a claim of perfect collider matching at all moving poses.','Runtime adapter test separately verifies original skeleton identity, collision shapes, and 17 attachments.']}
(ROOT/'art/reports/v2/sentinel_budgets.json').write_text(json.dumps(result,indent=2)+'\n')
print('SENTINEL_V2_EXPORTS_OK',result['unique_triangles_by_lod'])
