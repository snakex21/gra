"""Capture exact Godot runtime adapters; render matched before/after CPU evidence.

The baseline is read only and must be a clean checkout at --baseline-commit.
Both checkouts must already have been imported with Godot --headless --editor --import.
"""
from pathlib import Path
import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
from complete_character_specular_transport import complete as complete_specular
import subprocess

BASELINE = '0837f3539e37136ec6956642e44fc11b12e13496'
SUBJECTS = ('traveler_idle','traveler_walk','traveler_climb','agro_stand','rider')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def shots():
    out = []
    for lod in range(3):
        for subject,view in [('traveler_idle','traveler_whole'),('agro_stand','agro_whole'),('rider','rider_whole')]:
            out.append((subject,lod,view))
    for subject,view in [('traveler_idle','traveler_face'),('traveler_idle','traveler_cloth'),('agro_stand','agro_face'),('agro_stand','agro_tack'),('traveler_walk','traveler_whole'),('traveler_climb','traveler_climb')]:
        out.append((subject,0,view))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--baseline-root',type=Path,required=True)
    parser.add_argument('--baseline-commit',default=BASELINE)
    parser.add_argument('--after-root',type=Path,help='Optional independent imported copy for after export; its tracked source assets must match this worktree')
    parser.add_argument('--variant',choices=('before','after','both'),default='both')
    parser.add_argument('--export-only',action='store_true')
    parser.add_argument('--render-only',action='store_true')
    parser.add_argument('--width',type=int,default=960)
    parser.add_argument('--samples',type=int,default=24)
    parser.add_argument('--threads',type=int,default=4)
    parser.add_argument('--jobs',type=int,default=2)
    parser.add_argument('--geometry-review',action='store_true',help='Also render neutral front/side face, front body and gameplay-distance geometry views')
    parser.add_argument('--quick',action='store_true',help='LOD0 whole/close crops for material review')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    base,out = args.baseline_root.resolve(),args.output.resolve()
    after_root = args.after_root.resolve() if args.after_root else root
    for folder in ('source','scenes','raw-scenes','renders','logs','runtime/data','runtime/config','runtime/cache'):
        (out/folder).mkdir(parents=True,exist_ok=True)
    env = dict(os.environ)
    for kind in ('DATA','CONFIG','CACHE'): env['XDG_'+kind+'_HOME'] = str(out/'runtime'/kind.lower())
    def git(*cmd,cwd=root): return subprocess.check_output(['git',*cmd],cwd=cwd).decode().strip()
    def run(cmd,log,marker):
        with log.open('w') as stream:
            subprocess.run(cmd,cwd=root,env=env,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=1200)
        text = log.read_text()
        assert marker in text and 'SCRIPT ERROR:' not in text and 'ERROR:' not in text, log
        print('DONE',log.name,flush=True)
    variants = ('before','after') if args.variant=='both' else (args.variant,)
    if not args.render_only:
        assert git('rev-parse','HEAD',cwd=base)==args.baseline_commit
        assert not git('status','--porcelain','--untracked-files=no',cwd=base),'Baseline tracked files changed'
        for variant in variants:
            run(['godot','--headless','--path',str(base if variant=='before' else after_root),'--log-file',str(out/'logs'/f'export_{variant}_engine.log'),'--script',str(root/'tools/art/export_character_preview.gd'),'--',str(out/'scenes'),variant,args.baseline_commit],out/'logs'/f'export_{variant}.log','CHARACTER_EXPORT_OK')
            for path in sorted((out/'scenes').glob('*_'+variant+'.glb')):
                shutil.copyfile(path,out/'raw-scenes'/path.name)
                complete_specular(path)
        provenance = {'baseline_commit':args.baseline_commit,'baseline_root':str(base),'changed_root':str(root),
                      'capture_after_root':str(after_root),'changed_head':git('rev-parse','HEAD'),'changed_status':git('status','--porcelain').splitlines(),
                      'tools':{p.name:sha(p) for p in sorted((root/'tools/art').glob('*character*preview*')) if p.is_file()},
                      'specular_transport_sha256':sha(root/'tools/art/complete_character_specular_transport.py'),
                      'renderer':'Blender Cycles CPU; no GPU verification'}
        (out/'source/capture_provenance.json').write_text(json.dumps(provenance,indent=2))
    if args.export_only: return
    selected_shots=shots()+([('traveler_idle',0,v) for v in ('traveler_face_front','traveler_face_side','traveler_front','traveler_gameplay')] if args.geometry_review else [])
    selection = [s for s in selected_shots if not args.quick or s[1]==0 and s[0] not in ('traveler_climb','traveler_walk')]
    def render(task):
        subject,lod,view,variant = task
        name = f'{subject}_lod{lod}_{view}_{variant}'
        run(['blender','--background','--python-exit-code','1','--threads',str(args.threads),'--python',str(root/'tools/art/render_character_preview.py'),'--',str(out/'scenes'/f'{subject}_lod{lod}_{variant}.glb'),str(out/'renders'/f'{name}.png'),'--view',view,'--width',str(args.width),'--samples',str(args.samples)],out/'logs'/f'render_{name}.log','CHARACTER_RENDER_OK')
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(render,[(*s,v) for s in selection for v in variants]))

if __name__=='__main__': main()
