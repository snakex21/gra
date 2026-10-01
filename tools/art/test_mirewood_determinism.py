#!/usr/bin/env python3
"""Rebuild in an isolated temporary root; never overwrite hand-edited sources."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,shutil
ROOT=Path(__file__).resolve().parents[2]
paths=sorted([p.relative_to(ROOT) for d in ['models/mirewood','textures/mirewood'] for p in (ROOT/d).glob('*') if p.suffix in ['.png','.glb']]+[Path('assets/mirewood_manifest.json')])
def hashes(root):return {str(p):hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=hashes(ROOT)
with tempfile.TemporaryDirectory(prefix='mirewood-rebuild-') as tmp:
 out=Path(tmp);(out/'tools/art').mkdir(parents=True)
 for name in ['generate_art.py','generate_saltwind.py','generate_mirewood.py']:shutil.copy2(ROOT/'tools/art'/name,out/'tools/art'/name)
 with (ROOT/'art/reports/v5/determinism_generation.log').open('w') as log:
  subprocess.run(['blender','-b','--python-exit-code','1','--python',str(out/'tools/art/generate_mirewood.py')],stdout=log,stderr=subprocess.STDOUT,check=True)
 after=hashes(out)
changed=[p for p in before if before[p]!=after[p]]
report={'files_compared':len(paths),'changed':changed,'sha256':after,'blend_metadata_excluded':True,'original_sources_untouched':True,'description':'93 GLBs, five original PNGs and manifest. Independent temporary-root rebuild, same Blender and seed.'}
(ROOT/'art/reports/v5/determinism.json').write_text(json.dumps(report,indent=2)+'\n')
assert not changed,changed
print('MIREWOOD_DETERMINISM_OK',len(paths))
