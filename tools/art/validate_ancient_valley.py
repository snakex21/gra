"""Validate v2 exports without touching legacy manifests or gameplay."""
import json,struct,hashlib,subprocess
from pathlib import Path
from validate_exports import read_glb
ROOT=Path(__file__).resolve().parents[2]
m=json.loads((ROOT/'assets/ancient_valley_manifest.json').read_text())
records=[]
for a in m['assets']:
 p=ROOT/a['runtime'];ts=[read_glb(p.with_name(p.name.replace('_lod0',f'_lod{i}')),a['bounds_godot'] if i==0 else None) for i in range(3)]
 assert ts==a['lod_triangles'] and 0<ts[2]<=ts[1]<=ts[0],a['id']
 col=p.with_name(p.name.replace('_lod0','_collision'))
 ct=read_glb(col) if col.exists() else 0
 assert ct<=60,(a['id'],ct)
 records.append({'id':a['id'],'triangles':ts,'collision_triangles':ct,'collision':a['collision']})
assert len(records)==40
atlas=ROOT/'textures/ancient_valley/atlas_1k.png'
assert struct.unpack_from('>II',atlas.read_bytes(),16)==(1024,1024)
assert (ROOT/'art/source/ancient_valley_v2.blend').stat().st_size>100000
# Scope fence compares against the user's uploaded assets branch, not old gameplay.
for path in ['src','scenes','tests','project.godot']:
 assert not subprocess.check_output(['git','diff','origin/assets','--',path],cwd=ROOT),path
report={'assets':records,'asset_count':len(records),'lod_glbs':len(records)*3,'unique_triangles_by_lod':[sum(a['triangles'][i] for a in records) for i in range(3)],'shared_atlas':[1024,1024],'scope_fence':'src/scenes/tests/project.godot unchanged versus assets a838b5b','notes':['One mesh surface per GLB; no embedded per-model images.','Static hull sources <=60 triangles; openings use separate boxes.','No target-hardware FPS claim.']}
(ROOT/'art/reports/v2').mkdir(parents=True,exist_ok=True)
(ROOT/'art/reports/v2/export_budgets.json').write_text(json.dumps(report,indent=2)+'\n')
print('VALLEY_EXPORTS_OK',json.dumps({k:v for k,v in report.items() if k!='assets'}))
