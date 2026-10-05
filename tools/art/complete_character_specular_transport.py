"""Lossless JSON-only transport of actual Godot dielectric specular to glTF.
Godot 4.6.3 exports no KHR_materials_specular. Read measured runtime material
values from the adjacent snapshot; preserve the binary geometry/image chunk.
No authoring values, texture edits, renderer override or speculative defaults.
"""
import hashlib,json,struct,math
from pathlib import Path

TRANSPORT_NAMES=frozenset(('Traveler_skin_restrained_specular','Traveler_matte_hair_fibres','agro_mane_tail_fibres'))

def sha(raw):return hashlib.sha256(raw).hexdigest()
def complete(path):
    path=Path(path);snap=path.with_suffix('.json');source=snap.read_bytes();record=json.loads(source)
    values={}
    for mesh in record['meshes']:
        for surface in mesh['surfaces']:
            m=surface['material'];name=m['name']
            if name not in TRANSPORT_NAMES:continue
            value=m['metallic_specular']
            assert isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value) and 0<=value<=.5, 'Unrepresentable measured specular'
            if name in values:assert abs(values[name]-value)<1e-7
            values[name]=value
    raw=path.read_bytes();n,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
    assert raw[:4]==b'glTF' and struct.unpack_from('<I',raw,4)[0]==2 and struct.unpack_from('<I',raw,8)[0]==len(raw)
    doc=json.loads(raw[20:20+n]);binary=raw[20+n:];changes=[]
    assert struct.unpack_from('<II',binary,0)==(len(binary)-8,0x004e4942), 'Expected one binary chunk'
    exported_names={m.get('name','') for m in doc.get('materials',[])}
    assert not any(name!=base and name.startswith(base) for name in exported_names for base in TRANSPORT_NAMES), 'Unmapped exported specular material alias'
    expected={m['name'] for m in doc.get('materials',[]) if m.get('name') in TRANSPORT_NAMES}
    assert expected==set(values), 'Missing or extra runtime specular measurements'
    for m in doc.get('materials',[]):
        if m.get('name') not in values:continue
        value=values[m['name']]
        extensions=m.setdefault('extensions',{})
        assert set(extensions.get('KHR_materials_specular',{})) <= {'specularFactor'}, 'Unsupported unmeasured specular extension fields'
        extensions['KHR_materials_specular']={'specularFactor':2*value}
        changes.append({'material':m['name'],'godot_metallic_specular':value,'gltf_specularFactor':2*value})
    if changes:
        used=doc.setdefault('extensionsUsed',[])
        if 'KHR_materials_specular' not in used:used.append('KHR_materials_specular')
        j=json.dumps(doc,separators=(',',':'),allow_nan=False).encode();j+=b' '*(-len(j)%4)
        out=struct.pack('<4sII',b'glTF',2,20+len(j)+len(binary))+struct.pack('<II',len(j),kind)+j+binary
        path.write_bytes(out)
    else:out=raw
    proof={'scope':'JSON-only scalar transport from measured loaded Godot material; binary geometry/textures untouched','snapshot_sha256':sha(source),'before_sha256':sha(raw),'after_sha256':sha(out),'binary_chunk_sha256':sha(binary),'changes':changes}
    path.with_suffix('.specular-transport.json').write_text(json.dumps(proof,indent=2)+'\n')
    return proof
if __name__=='__main__':
    import sys
    for arg in sys.argv[1:]:print(json.dumps(complete(arg)))
