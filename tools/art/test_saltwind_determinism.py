#!/usr/bin/env python3
"""Explicitly regenerate original kit and compare all runtime/source data contracts.
This overwrites authored edits. Run only on the unedited procedural kit.
.blend metadata is not required to be byte-identical between saves.
"""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
paths=sorted(list((ROOT/'models/saltwind').glob('*.glb'))+list((ROOT/'textures/saltwind').glob('*.png'))+[ROOT/'assets/saltwind_manifest.json'])
def snapshot():return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
before=snapshot()
with (ROOT/'art/reports/v4/determinism_generation.log').open('w') as log:
 subprocess.run(['blender','-b','--python-exit-code','1','--python','tools/art/generate_saltwind.py'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
after=snapshot();changed=[p for p in before if before[p]!=after[p]]
report={'files_compared':len(paths),'changed':changed,'sha256':after,'blend_metadata_excluded':True,'description':'96 GLBs, five original PNGs and manifest, same Blender/NumPy version and seed'}
(ROOT/'art/reports/v4/determinism.json').write_text(json.dumps(report,indent=2)+'\n')
assert not changed,changed
print('SALTWIND_DETERMINISM_OK',len(paths),'byte-identical generated contracts')
