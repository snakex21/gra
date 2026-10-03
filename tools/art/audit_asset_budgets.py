"""Read-only GLB/texture budget audit using the Python standard library.

Writes only assets/asset_budgets.json by default; no importer or app is launched.
The totals describe repository contents, not a simultaneous gameplay workload.
RGBA8 estimates are comparison units, not measured or promised GPU allocation.
"""
import argparse
import base64
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
TRAVELER_LIMITS = {0: 40000, 1: 22000, 2: 5000}
WEAPON_LIMITS = {0: 10000, 1: 5000, 2: 1800}
WEAPON_IDS = ["sword", "bow", "arrow", "scabbard", "quiver"]
LANDSCAPE_LIMITS = {0: 3000, 1: 1000, 2: 200}
LANDSCAPE_IDS = ["oak", "wind_tree", "pine", "dead_tree", "rock_shelf", "rock_split", "ruin_arch", "ruin_support", "ruin_parapet"]

def image_size(raw):
    if raw[:8] == b"\x89PNG\r\n\x1a\n" and len(raw) >= 26:
        w,h=struct.unpack_from(">II",raw,16)
        return {"width":w,"height":h,"format":"png","png_color_type":raw[25]}
    if raw[:2] == b"\xff\xd8":
        offset=2
        while offset+4<len(raw):
            if raw[offset]!=255:offset+=1;continue
            while offset<len(raw) and raw[offset]==255:offset+=1
            if offset>=len(raw):break
            kind=raw[offset];offset+=1
            if kind in [0xD8,0xD9] or 0xD0<=kind<=0xD7:continue
            size=struct.unpack_from(">H",raw,offset)[0]
            if kind in [0xC0,0xC1,0xC2,0xC3,0xC5,0xC6,0xC7,0xC9,0xCA,0xCB,0xCD,0xCE,0xCF]:
                h,w=struct.unpack_from(">HH",raw,offset+3)
                return {"width":w,"height":h,"format":"jpeg"}
            if size<2:break
            offset+=size
    if raw[:4]==b"RIFF" and raw[8:12]==b"WEBP":
        if raw[12:16]==b"VP8X" and len(raw)>=30:
            return {"width":1+int.from_bytes(raw[24:27],"little"),"height":1+int.from_bytes(raw[27:30],"little"),"format":"webp"}
    return {"width":None,"height":None,"format":"unknown"}

def mip_rgba_bytes(w,h):
    total=0
    while True:
        total+=w*h*4
        if w==1 and h==1:return total
        w=max(1,w//2);h=max(1,h//2)

def load_glb(path):
    raw=path.read_bytes()
    magic,version,size=struct.unpack_from("<4sII",raw)
    if magic!=b"glTF" or version!=2 or size!=len(raw):raise ValueError("Invalid GLB header")
    offset=12;doc=None;blob=b""
    while offset+8<=len(raw):
        n,kind=struct.unpack_from("<I4s",raw,offset);offset+=8
        data=raw[offset:offset+n];offset+=n
        if kind==b"JSON":doc=json.loads(data)
        elif kind==b"BIN\0":blob=data
    if doc is None:raise ValueError("Missing GLB JSON")
    return doc,blob,len(raw)

def import_options(path):
    if not path.exists():return None
    result={}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if "=" not in line:continue
        key,value=line.split("=",1)
        if key in ["compress/mode","compress/high_quality","compress/normal_map","mipmaps/generate","process/size_limit","meshes/generate_lods","meshes/create_shadow_meshes","meshes/light_baking","materials/extract","gltf/embedded_image_handling"]:
            result[key]=value.strip()
    return result

def inspect_glb(path):
    doc,blob,file_bytes=load_glb(path)
    relative=path.relative_to(ROOT).as_posix()
    match=re.search(r"(?:_|-)lod([0-9]+)(?:\.|_|$)",path.name,re.I)
    lod=int(match.group(1)) if match else None
    refs=Counter(n["mesh"] for n in doc.get("nodes",[]) if "mesh" in n)
    triangles=0;instance_triangles=0;surfaces=0;vertices=0;morph_targets=0;used_views=set()
    def track(index):
        accessor=doc["accessors"][index]
        if "bufferView" in accessor:used_views.add(accessor["bufferView"])
        if "sparse" in accessor:
            for block in ["indices","values"]:used_views.add(accessor["sparse"][block]["bufferView"])
    for index,mesh in enumerate(doc.get("meshes",[])):
        for primitive in mesh.get("primitives",[]):
            mode=primitive.get("mode",4)
            count=doc["accessors"][primitive.get("indices",primitive["attributes"]["POSITION"])]["count"]
            tris=count//3 if mode==4 else max(0,count-2) if mode in [5,6] else 0
            triangles+=tris;instance_triangles+=tris*refs[index]
            surfaces+=refs[index]
            vertices+=doc["accessors"][primitive["attributes"]["POSITION"]]["count"]
            morph_targets=max(morph_targets,len(primitive.get("targets",[])))
            if "indices" in primitive:track(primitive["indices"])
            for acc in primitive["attributes"].values():track(acc)
            for target in primitive.get("targets",[]):
                for acc in target.values():track(acc)
    images=[]
    for index,image in enumerate(doc.get("images",[])):
        external=None
        if "bufferView" in image:
            view=doc["bufferViews"][image["bufferView"]]
            start=view.get("byteOffset",0);data=blob[start:start+view["byteLength"]]
        elif image.get("uri","").startswith("data:"):
            data=base64.b64decode(image["uri"].split(",",1)[1])
        elif "uri" in image:
            external=(path.parent/image["uri"]).resolve()
            data=external.read_bytes()
        else:continue
        dims=image_size(data)
        images.append({"index":index,"name":image.get("name",image.get("uri",str(index))),"sha256":hashlib.sha256(data).hexdigest(),
            "encoded_bytes":len(data),"external":external.relative_to(ROOT).as_posix() if external else None,**dims,
            "rgba8_base_equivalent_bytes":dims["width"]*dims["height"]*4 if dims["width"] else None,
            "rgba8_mips_equivalent_bytes":mip_rgba_bytes(dims["width"],dims["height"]) if dims["width"] else None})
    materials=doc.get("materials",[])
    return {"path":relative,"pack":path.parent.relative_to(ROOT/"models").as_posix(),"lod":lod,"file_bytes":file_bytes,
        "meshes":len(doc.get("meshes",[])),"mesh_node_instances":sum(refs.values()),"triangles_unique_meshes":triangles,"triangles_node_instances":instance_triangles,
        "position_vertices_across_surfaces":vertices,"material_surfaces_node_instances":surfaces,"material_count":len(materials),
        "transparent_materials":sum(m.get("alphaMode","OPAQUE")=="BLEND" for m in materials),
        "double_sided_materials":sum(bool(m.get("doubleSided")) for m in materials),"max_morph_targets":morph_targets,
        "geometry_buffer_view_bytes":sum(doc["bufferViews"][index]["byteLength"] for index in used_views),"images":images,
        "import_options":import_options(Path(str(path)+".import"))}

def totals(records):
    images=[image for item in records for image in item["images"]]
    unique={image["sha256"]:image for image in images}
    return {"glb_files":len(records),"file_bytes":sum(r["file_bytes"] for r in records),
        "triangles_by_lod":{str(lod):sum(r["triangles_node_instances"] for r in records if r["lod"]==lod) for lod in [0,1,2,None]},
        "surfaces_by_lod":{str(lod):sum(r["material_surfaces_node_instances"] for r in records if r["lod"]==lod) for lod in [0,1,2,None]},
        "geometry_buffer_view_bytes":sum(r["geometry_buffer_view_bytes"] for r in records),
        "image_references":len(images),"unique_encoded_image_contents":len(unique),
        "image_encoded_bytes_sum":sum(i["encoded_bytes"] for i in images),"image_encoded_bytes_unique":sum(i["encoded_bytes"] for i in unique.values()),
        "rgba8_mips_equivalent_bytes_sum":sum(i["rgba8_mips_equivalent_bytes"] or 0 for i in images),
        "rgba8_mips_equivalent_bytes_unique":sum(i["rgba8_mips_equivalent_bytes"] or 0 for i in unique.values())}

def check_budgets(records, texture_imports):
    violations=[]
    indexed={r["path"]:r for r in records}
    expected={"models/characters/travelers_v3/traveler_lod%d.glb"%lod:limit for lod,limit in TRAVELER_LIMITS.items()}
    expected.update({"models/weapons_v4/%s_lod%d.glb"%(name,lod):limit for name in WEAPON_IDS for lod,limit in WEAPON_LIMITS.items()})
    expected.update({"models/landscape_v5/%s_lod%d.glb"%(name,lod):limit for name in LANDSCAPE_IDS for lod,limit in LANDSCAPE_LIMITS.items()})
    for path,limit in expected.items():
        record=indexed.get(path)
        if record is None:
            violations.append({"path":path,"rule":"required_model","actual":"missing"})
        elif record["triangles_node_instances"]>limit:
            violations.append({"path":path,"rule":"triangle_budget","actual":record["triangles_node_instances"],"maximum":limit})
        if record is not None and "/landscape_v5/" in path:
            if record["images"]:
                violations.append({"path":path,"rule":"shared_atlas_only","actual":len(record["images"]),"maximum":0})
            if record.get("material_surfaces_node_instances", 1)>1 or record.get("transparent_materials", 0)>0:
                violations.append({"path":path,"rule":"single_opaque_surface","actual":record.get("material_surfaces_node_instances", 1)})
    image_entries=[{"path":r["path"]+"#image"+str(i["index"]),**i} for r in records for i in r["images"]]
    image_entries+=texture_imports
    for image in image_entries:
        path=image["path"]
        limit=512 if "/weapons_v4/" in path else 1024 if "/landscape_v5/" in path else 2048
        w,h=image.get("width"),image.get("height")
        if w is None or h is None:
            violations.append({"path":path,"rule":"known_texture_dimensions","actual":"unknown"})
        elif w>limit or h>limit:
            violations.append({"path":path,"rule":"texture_dimension_budget","actual":[w,h],"maximum":limit})
    return {"traveler_triangles_by_lod":TRAVELER_LIMITS,"weapon_triangles_per_model_by_lod":WEAPON_LIMITS,
        "landscape_triangles_per_model_by_lod":LANDSCAPE_LIMITS,"landscape_texture_maximum_dimension":1024,
        "texture_maximum_dimension":2048,"weapon_texture_maximum_dimension":512,"violations":violations}

def runtime_summary():
    path=ROOT/"tests/output/texture_budgets.json"
    if not path.exists():return None
    report=json.loads(path.read_text(encoding="utf-8"))
    groups=report.get("identical_glb_payloads_with_different_texture_rids",[])
    return {"report":path.relative_to(ROOT).as_posix(),
        **{key:report.get(key) for key in ["renderer","display_server","failures","authored_textures_count","compressed_image_payload_bytes",
            "rgba8_full_mipmap_comparison_bytes","image_formats","rendered_material_count","texture_memory_counter_before","texture_memory_counter_after","scope"]},
        "duplicate_glb_payload_groups":len(groups),
        "duplicate_glb_payload_extra_bytes_in_selected_models":sum((g["distinct_gpu_texture_rids"]-1)*g["payload_bytes_per_rid"] for g in groups)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",default="assets/asset_budgets.json")
    parser.add_argument("--check-budgets",action="store_true",help="Exit nonzero for missing/over-budget traveler, weapons, landscape or textures")
    args=parser.parse_args()
    destination=(ROOT/args.output).resolve()
    if ROOT not in destination.parents:raise SystemExit("Output must remain in the game folder")
    records=[];errors=[]
    for path in sorted((ROOT/"models").rglob("*.glb")):
        try:records.append(inspect_glb(path))
        except Exception as exc:errors.append({"path":path.relative_to(ROOT).as_posix(),"error":str(exc)})
    packs={name:totals([r for r in records if r["pack"]==name]) for name in sorted({r["pack"] for r in records})}
    texture_imports=[]
    for folder in [ROOT/"models",ROOT/"textures"]:
        for path in sorted(folder.rglob("*.png.import")):
            source=Path(str(path)[:-7]);raw=source.read_bytes() if source.exists() else b""
            texture_imports.append({"path":source.relative_to(ROOT).as_posix(),"file_bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest(),**image_size(raw),"options":import_options(path)})
    dupes=defaultdict(list);image_details={}
    for record in records:
        for image in record["images"]:
            dupes[image["sha256"]].append(record["path"]+"#"+str(image["index"]))
            image_details[image["sha256"]]=image
    duplicate_images=[{"sha256":sha,"references":paths,"copies":len(paths),"image":image_details[sha]} for sha,paths in dupes.items() if len(paths)>1]
    duplicate_images.sort(key=lambda r:(r["copies"]-1)*r["image"]["encoded_bytes"],reverse=True)
    option_counts={"compress/mode":dict(Counter((r["options"] or {}).get("compress/mode","missing") for r in texture_imports)),
        "mipmaps/generate":dict(Counter((r["options"] or {}).get("mipmaps/generate","missing") for r in texture_imports))}
    budgets=check_budgets(records,texture_imports)
    result={"scope":"Repository inventory; not simultaneous residency, measured VRAM, draw-call counters or an FPS benchmark",
        "method":"GLB v2 JSON/binary metadata, embedded image signatures/dimensions/SHA256, indexed geometry and Godot import sidecars; Python standard library only",
        "texture_estimate_note":"RGBA8 full-mipmap equivalent is a comparison unit. Actual GPU allocation depends on channels, import compression, samplers and resource sharing. Identical SHA256 does not prove engine deduplication.",
        "totals":totals(records),"packs":packs,"texture_import_option_counts":option_counts,"budget_checks":budgets,"runtime_texture_test":runtime_summary(),
        "largest_lod0_geometry":sorted([r for r in records if r["lod"]==0],key=lambda r:r["triangles_node_instances"],reverse=True)[:20],
        "duplicate_image_contents":duplicate_images,"texture_imports":texture_imports,"assets":records,"errors":errors}
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print("ASSET_BUDGET_AUDIT",len(records),"GLB;",len(errors),"errors;",len(texture_imports),"texture imports")
    print("TOTALS",json.dumps(result["totals"]))
    print("TEXTURE_IMPORTS",json.dumps(option_counts))
    print("BUDGET_CHECKS", "violations=",len(budgets["violations"]),"enforced=",args.check_budgets)
    if result["runtime_texture_test"]:print("RUNTIME_TEXTURE_TEST",json.dumps(result["runtime_texture_test"]))
    for violation in budgets["violations"]:print("BUDGET_VIOLATION",json.dumps(violation))
    for name,value in sorted(packs.items(),key=lambda pair:pair[1]["file_bytes"],reverse=True)[:12]:
        print("PACK",name,json.dumps(value))
    for record in result["largest_lod0_geometry"][:10]:
        print("GEOMETRY",record["path"],record["triangles_node_instances"],"tri;",record["material_surfaces_node_instances"],"surfaces")
    print("REPORT",destination)
    return bool(errors or (args.check_budgets and budgets["violations"]))

if __name__=="__main__":raise SystemExit(main())
