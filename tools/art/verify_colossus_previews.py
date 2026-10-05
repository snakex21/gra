"""Fail closed on loaded geometry, gameplay visuals, source and matched CPU render drift."""
import argparse
import hashlib
import json
from pathlib import Path
from capture_colossus_previews import SUBJECTS, shots


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads(path.read_text())


def geometry(snapshot):
    return [{k:v for k,v in m.items() if k != 'surfaces'} | {
        'surfaces':[{k:v for k,v in s.items() if k!='material'} for s in m['surfaces']]}
        for m in snapshot['meshes']]


def audit_pair(before,after):
    assert before['subject']==after['subject'] and before['lod']==after['lod'],'Subject/LOD mismatch'
    assert before['variant']=='before' and after['variant']=='after','Swapped snapshots'
    assert geometry(before)==geometry(after),'Loaded geometry, topology, normals, UVs or transforms changed'
    assert before['semantics']==after['semantics'],'Weak-point positions, states or radii changed'
    assert before['pose']==after['pose'],'Pose input changed'
    changed=0
    for bm,am in zip(before['meshes'],after['meshes']):
        for bs,ass in zip(bm['surfaces'],am['surfaces']):
            b,a=bs['material'],ass['material']
            if bm['role']=='gameplay_visual':
                assert b==a,'Weak-point/gameplay visual material changed'
                continue
            assert b['source']=='res://materials/colossi_v3/atlas.tres'
            assert a['source']=='res://materials/colossi_material_finish/atlas.tres','Wrong scoped material'
            mutable={'source','textures','roughness','metallic','roughness_texture_channel','metallic_texture_channel'}
            assert {k:v for k,v in b.items() if k not in mutable}=={k:v for k,v in a.items() if k not in mutable},'Unapproved material scalar changed'
            assert a['roughness']==a['metallic']==1
            assert a['roughness_texture_channel']==1 and a['metallic_texture_channel']==2,'ORM channel mismatch'
            assert set(b['textures'])=={'0','4'} and set(a['textures'])=={'0','1','2','4'}
            assert a['textures']['1']==a['textures']['2'],'Packed ORM bindings differ'
            for channel,t in a['textures'].items():
                assert t['width']==t['height']==2048,'Unexpected atlas dimensions'
                assert t['source']=='res://textures/colossi_material_finish/'+{'0':'atlas_2k.png','4':'atlas_normal.png','1':'atlas_orm.png','2':'atlas_orm.png'}[channel]
            assert b['textures']['0']['pixels_sha256']!=a['textures']['0']['pixels_sha256'],'No loaded albedo change'
            changed+=1
    assert changed>0,'No changed production sculpture bindings'
    return {'meshes':len(before['meshes']),'triangles':sum(s['triangles'] for m in before['meshes'] for s in m['surfaces']),
            'changed_sculpture_bindings':changed,'geometry_and_pose_identical':True,'gameplay_visual_materials_identical':True,'weakpoint_semantics_identical':True,'scoped_material_contract_valid':True}


def verify_sources(snapshot):
    root=Path(snapshot['project_path'])
    for source,expected in snapshot['source_sha256s'].items():
        path=root/source.removeprefix('res://')
        assert path.is_file() and sha(path)==expected,f'Stale source: {path}'


def verify_imports(root):
    records=[]
    for p in sorted((root/'textures/colossi_material_finish').glob('*.png')):
        sidecar=p.with_suffix('.png.import')
        settings=sidecar.read_text()
        assert 'compress/mode=2' in settings and 'mipmaps/generate=true' in settings,'Missing VRAM compression/mips'
        assert ('compress/normal_map=1' if p.stem=='atlas_normal' else 'compress/normal_map=0') in settings,'Wrong normal import mode'
        expected=hashlib.md5(p.read_bytes()).hexdigest()
        cached=list((root/'.godot/imported').glob(p.name+'-*.md5'))
        assert cached and any('source_md5="'+expected+'"' in f.read_text() for f in cached),f'Stale texture import: {p}'
        records.append({'path':str(p.relative_to(root)),'sha256':sha(p),'import_sha256':sha(sidecar),'cache_matches_source':True})
    assert len(records)==3,'Wrong finish texture count'
    return records


def verify(output,require_renders=True):
    results,snapshots,renders={},[],[]
    after_root=Path(read(output/'scenes/valus_lod0_after.json')['project_path'])
    imports=verify_imports(after_root)
    for subject in SUBJECTS:
        for lod in range(3):
            name=f'{subject}_lod{lod}'
            before,after=(read(output/'scenes'/f'{name}_{v}.json') for v in ('before','after'))
            for snapshot in (before,after): verify_sources(snapshot)
            results[name]=audit_pair(before,after)
            for variant in ('before','after'):
                for extension in ('json','glb'):
                    p=output/'scenes'/f'{name}_{variant}.{extension}'
                    snapshots.append({'path':str(p.relative_to(output)),'sha256':sha(p),'bytes':p.stat().st_size})
    if require_renders:
        for subject,lod,view in shots():
            manifests=[]
            for variant in ('before','after'):
                p=output/'renders'/f'{subject}_lod{lod}_{view}_{variant}.png'
                m=read(p.with_suffix('.json'))
                assert sha(p)==m['output_sha256'],'Stale rendered image'
                assert sha(Path(m['source']))==m['source_sha256'],'Stale exported GLB'
                assert sha(Path(__file__).with_name('render_colossus_preview.py'))==m['renderer_sha256'],'Renderer changed'
                manifests.append(m)
                renders.append({'path':str(p.relative_to(output)),'sha256':sha(p),'bytes':p.stat().st_size})
            for key in ('subject','view','camera','lights','resolution','samples','seed','view_transform','renderer_sha256'):
                assert manifests[0][key]==manifests[1][key],f'Before/after renderer drift: {key}'
    result={'status':'PASS','scene_pairs':9,'render_pairs':len(renders)//2,'scenes':results,'snapshots':snapshots,'renders':renders,'after_imports':imports,
            'verification_scope':'Actual Godot-loaded production geometry, normals, UVs, transforms, weak-point semantics and active materials. Scoped sculpture PBR changes only. Identical camera/light/settings Blender Cycles CPU pairs. Not Godot GPU or runtime performance verification.'}
    (output/'verification.json').write_text(json.dumps(result,indent=2))
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--export-only',action='store_true');a=p.parse_args()
    r=verify(a.output.resolve(),not a.export_only)
    print('COLOSSUS_PREVIEW_VERIFY_OK',r['scene_pairs'],'scene pairs',r['render_pairs'],'render pairs')

if __name__=='__main__': main()
