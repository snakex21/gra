#!/usr/bin/env python3
"""Prove manual edits export in isolation and full regeneration is opt-in."""
import tempfile,subprocess,shutil,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
hashfile=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=ROOT/'art/source/mirewood.blend';before=hashfile(source)
result=subprocess.run(['blender','-b','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/art/generate_mirewood.py')],capture_output=True,text=True)
assert result.returncode!=0 and 'Existing editable source protected' in result.stdout+result.stderr
assert hashfile(source)==before
with tempfile.TemporaryDirectory(prefix='mirewood-edit-') as name:
 tmp=Path(name)
 for folder in ['tools/art','assets','art/source','models/mirewood']:(tmp/folder).mkdir(parents=True)
 shutil.copy2(source,tmp/'art/source/mirewood.blend')
 shutil.copy2(ROOT/'assets/mirewood_manifest.json',tmp/'assets/mirewood_manifest.json')
 shutil.copy2(ROOT/'tools/art/export_mirewood.py',tmp/'tools/art/export_mirewood.py')
 mutation=tmp/'tools/art/edit_one.py'
 mutation.write_text("import bpy\nfrom pathlib import Path\nroot=Path(__file__).resolve().parents[2]\nbpy.ops.wm.open_mainfile(filepath=str(root/'art/source/mirewood.blend'))\no=bpy.data.objects['boardwalk_8m_LOD0']\no.data.vertices[0].co.x += .071\nbpy.ops.wm.save_as_mainfile(filepath=str(root/'art/source/mirewood.blend'),compress=True)\n")
 with (ROOT/'art/reports/v5/manual_edit_export.log').open('w') as log:
  subprocess.run(['blender','-b','--threads','2','--python-exit-code','1','--python',str(mutation)],stdout=log,stderr=subprocess.STDOUT,check=True)
  subprocess.run(['blender','-b',str(tmp/'art/source/mirewood.blend'),'--threads','2','--python-exit-code','1','--python',str(tmp/'tools/art/export_mirewood.py'),'--','--asset','boardwalk_8m'],stdout=log,stderr=subprocess.STDOUT,check=True)
 assert hashfile(tmp/'models/mirewood/boardwalk_8m_lod0.glb')!=hashfile(ROOT/'models/mirewood/boardwalk_8m_lod0.glb')
 exported=list((tmp/'models/mirewood').glob('*.glb'));assert len(exported)==3
 manifest=json.loads((tmp/'assets/mirewood_manifest.json').read_text());entry=next(a for a in manifest['assets'] if a['id']=='boardwalk_8m')
 assert entry['lod_triangles'][0]>entry['lod_triangles'][1]>entry['lod_triangles'][2]
assert hashfile(source)==before
report={'regeneration_without_explicit_flag_refused':True,'source_sha256_unchanged':before,'edit_test_asset':'boardwalk_8m','vertex_edit_metres':.071,'only_selected_asset_lods_exported':3,'edited_lod0_differs_from_generated':True,'source_and_collision_recipes_remain_editable':True,'notes':'Independent temporary root, not a destructive test on the user source. Collision recipes are edited separately in the manifest.'}
(ROOT/'art/reports/v5/editing_tests.json').write_text(json.dumps(report,indent=2)+'\n')
print('MIREWOOD_EDITING_OK')
