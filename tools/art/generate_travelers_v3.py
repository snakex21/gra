"""Original travelers, authored as editable metre-scale Blender geometry.

Run: python tools/run_local.py blender --python tools/art/generate_travelers_v3.py
Optional final argument: -- --render (renders the source-file presentation).
No downloaded meshes, source-game assets, add-ons or external texture files.
Godot coordinates throughout: X right, Y up, -Z forward. The traveler origin is
the gameplay capsule centre; rigid arm origins exactly match PlayerVisual._arms.
"""
import bpy
import bmesh
import json
import math
import random
import sys
from pathlib import Path
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'models/characters/travelers_v3'
TEX = ROOT / 'textures/characters/travelers_v3'
SOURCE = ROOT / 'art/source/travelers_v3.blend'
SEED = 31907
random.seed(SEED)

def apply_surface_lod(ob,ratio):
    """Preserve cloth/skin attachment bands while reducing noncritical regions.

    Blender 4.3's collapse algorithm refuses edges touching exact zero-weight
    vertices. A temporary *mutable* group therefore locks protected vertices,
    unlike merely biasing their collapse cost. Verify coordinates/skin weights
    afterward and remove the non-bone group before glTF export.
    """
    if ob.data.shape_keys: return  # Small authored bow-hook/release topology stays exact.
    from collections import Counter
    thigh=ob.name.startswith('Traveler_Thigh_') and any(m.type=='ARMATURE' for m in ob.modifiers)
    if thigh:
        # Each thigh is only 388 triangles. Retain its waist, shared hem samples
        # and knee exactly; constrained collapse overshoots the hip silhouette.
        ob['lod_preserved_full_thigh_vertices']=len(ob.data.vertices)
        return
    guarded=ob.name.startswith(('Traveler_TunicSurface','Traveler_ArmSurface_'))
    keep=set();before={};lock=None
    if guarded:
        edges=Counter()
        for face in ob.data.polygons:
            ids=list(face.vertices)
            for a,b in zip(ids,ids[1:]+ids[:1]):edges[tuple(sorted((a,b)))]+=1
        keep={v for edge,count in edges.items() if count==1 for v in edge}
        upper_ids={g.index for g in ob.vertex_groups if g.name.startswith('SurfaceUpper_')}
        if ob.name.startswith('Traveler_TunicSurface'):
            keep.update(v.index for v in ob.data.vertices if any(g.group in upper_ids and g.weight>=.999999 for g in v.groups))
        # One complete neighbouring ring prevents new mixed-weight triangles
        # from spanning the protected all-Upper sleeve band.
        expanded=set(keep)
        for a,b in edges:
            if a in keep or b in keep:expanded.update((a,b))
        keep=expanded
        assert keep, 'No attachment boundary identified for '+ob.name
        def weights(v):return {ob.vertex_groups[g.group].name:float(g.weight) for g in v.groups if g.weight>1e-8}
        before={tuple(ob.data.vertices[i].co):weights(ob.data.vertices[i]) for i in keep}
        lock=ob.vertex_groups.new(name='__LOD_MUTABLE_EXPORT_ONLY')
        mutable=[v.index for v in ob.data.vertices if v.index not in keep]
        if mutable:lock.add(mutable,1.0,'REPLACE')
    dec=ob.modifiers.new('LOD reduction with attachment protection','DECIMATE')
    dec.ratio=max(ratio,.52) if ob.name.startswith('Traveler_TunicSurface') else (.07 if ratio<.2 and ob.name.startswith('Traveler_') and not ob.name.startswith('Traveler_ArmSurface_') else ratio)
    if lock:
        dec.vertex_group=lock.name;dec.vertex_group_factor=1.0;dec.invert_vertex_group=False
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.modifier_apply(modifier=dec.name)
    if lock:
        lock_after=ob.vertex_groups.get('__LOD_MUTABLE_EXPORT_ONLY')
        if lock_after: ob.vertex_groups.remove(lock_after)
        after={tuple(v.co):{ob.vertex_groups[g.group].name:float(g.weight) for g in v.groups if g.weight>1e-8} for v in ob.data.vertices}
        for co,weight in before.items():
            assert co in after, 'LOD moved/deleted protected attachment vertex in '+ob.name
            got=after[co]
            assert set(got)==set(weight) and all(abs(got[k]-weight[k])<1e-7 for k in weight), 'LOD changed protected skin weights in '+ob.name
        ob['lod_preserved_attachment_vertices']=len(before)

def validate_surface_influences(objects):
    """Godot receives at most two four-wide skin attribute sets; never truncate."""
    for ob in objects:
        if ob.type!='MESH' or not any(m.type=='ARMATURE' for m in ob.modifiers):continue
        for vertex in ob.data.vertices:
            assert all(math.isfinite(g.weight) and g.weight>=0 for g in vertex.groups), 'Invalid skin weight in '+ob.name
            weights=[g.weight for g in vertex.groups if g.weight>1e-8]
            assert len(weights)<=8, 'More than eight skin influences in '+ob.name
            assert abs(sum(weights)-1)<1e-5, 'Unnormalized skin weights in '+ob.name


def export_edited_source():
    """Re-export hand edits without regenerating or overwriting the .blend."""
    import hashlib
    source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    manifest_path=ROOT/'assets/travelers_v3_manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    def hierarchy(ob):
        return [ob]+[desc for child in ob.children if not child.get('source_display_only',False) for desc in hierarchy(child)]
    for root_name,identifier in [('Traveler_v3','traveler'),('Mono_v3_Sleep','mono_sleep')]:
        if '--traveler-only' in sys.argv and identifier!='traveler': continue
        root=bpy.data.objects.get(root_name)
        assert root, 'Missing editable source hierarchy '+root_name
        original_matrix=root.matrix_world.copy()
        root.matrix_world=__import__('mathutils').Matrix.Identity(4)
        bpy.context.view_layer.update()
        base_objects=hierarchy(root)
        records=[]
        for level,ratio in enumerate([1,.52,.12]):
            remap={};copies=[]
            for ob in base_objects:
                cp=ob.copy()
                if ob.type=='MESH': cp.data=ob.data.copy()
                bpy.context.scene.collection.objects.link(cp)
                cp.parent=None;cp.matrix_world=ob.matrix_world.copy()
                remap[ob]=cp;copies.append(cp)
            for original,cp in remap.items():
                for modifier in cp.modifiers:
                    if modifier.type=='ARMATURE' and modifier.object in remap: modifier.object=remap[modifier.object]
                if original.parent in remap:
                    cp.parent=remap[original.parent]
                    cp.matrix_local=original.matrix_local.copy()
                cp.hide_set(False);cp.hide_viewport=False;cp.hide_render=False
                if cp.type=='MESH':
                    bpy.context.view_layer.objects.active=cp
                    if not cp.data.shape_keys:
                        tri=cp.modifiers.new('Export triangles','TRIANGULATE')
                        bpy.ops.object.modifier_apply(modifier=tri.name)
                    if level:
                        apply_surface_lod(cp,ratio)
                    cp.data.validate(verbose=False,clean_customdata=False)
            bpy.ops.object.select_all(action='DESELECT')
            for cp in copies: cp.select_set(True)
            path=OUT/(identifier+'_lod%d.glb'%level)
            if identifier=='traveler':validate_surface_influences(copies)
            bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
                export_materials='EXPORT',export_yup=True,export_normals=True,export_texcoords=True,
                export_cameras=False,export_lights=False,export_animations=False,export_extras=True,export_influence_nb=8 if identifier=='traveler' else 4)
            points=[cp.matrix_world@v.co for cp in copies if cp.type=='MESH' for v in cp.data.vertices]
            points=[Vector((p.x,p.z,-p.y)) for p in points]
            records.append({'lod':level,'runtime':str(path.relative_to(ROOT)).replace('\\','/'),
                'triangles':sum(sum(len(p.vertices)-2 for p in cp.data.polygons) for cp in copies if cp.type=='MESH'),
                'vertices':sum(len(cp.data.vertices) for cp in copies if cp.type=='MESH'),
                'bytes':path.stat().st_size,'bounds_godot':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]})
            for cp in reversed(copies): bpy.data.objects.remove(cp,do_unlink=True)
        asset=next(a for a in manifest['assets'] if a['id']==identifier)
        asset['lods']=records
        asset['materials']=sorted({m.name for ob in base_objects if ob.type=='MESH' for m in ob.data.materials if m})
        asset['mesh_parts']=sum(ob.type=='MESH' for ob in base_objects)
        root.matrix_world=original_matrix
    manifest['last_export']='from edited source; .blend left untouched'
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash, 'Source export overwrote editable .blend'
    print('TRAVELERS_V3_EDITED_EXPORT_OK')

if '--export-source' in sys.argv:
    export_edited_source()
    sys.exit(0)
for folder in (OUT, TEX, ROOT/'assets', ROOT/'data/captures'):
    folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.name = 'Travelers_v3_Original_Studio'
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

PALETTE = [
    ('linen', (.66,.625,.55), .94, 0), ('bluecloth', (.29,.34,.35), .94, 0),
    ('cloak', (.19,.225,.225), .96, 0), ('skin', (.67,.515,.427), .76, 0),
    ('mono_skin', (.82,.69,.57), .70, 0), ('hair', (.10,.071,.048), .59, 0),
    ('boots', (.18,.115,.076), .74, 0), ('leather', (.34,.23,.14), .75, 0),
    ('bronze', (.59,.46,.26), .52, .55), ('thread', (.77,.71,.54), .91, 0),
    ('ivory', (.79,.75,.65), .94, 0), ('mono_trim', (.34,.44,.46), .90, 0),
    ('eye_white', (.83,.80,.72), .48, 0), ('eye_dark', (.056,.063,.053), .42, 0),
    ('lips', (.45,.27,.22), .73, 0), ('scarf', (.47,.42,.33), .93, 0),
]
TILES = {row[0]: i for i, row in enumerate(PALETTE)}

def vec(p):
    return Vector((p[0], -p[2], p[1]))

def godot(p):
    return Vector((p[0], p[2], -p[1]))

def image_png(name, rgb, color=True):
    h,w = rgb.shape[:2]
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    rgba = np.ones((h,w,4), dtype=np.float32)
    rgb = np.clip(rgb,0,1)
    if color:
        rgb = np.where(rgb <= .04045, rgb/12.92, ((rgb+.055)/1.055)**2.4)
    rgba[:,:,:3] = rgb
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = str(TEX / (name+'.png'))
    img.file_format = 'PNG'
    img.save()
    return img

# Shared PBR atlas with actual weave, subtle pores and strand grain. No alpha
# hair cards: the silhouettes are geometry and work with depth/shadows normally.
n = 256
yy,xx = np.mgrid[0:n,0:n].astype(float)
atlas = np.zeros((1024,1024,3))
normal = np.zeros_like(atlas)
orm = np.zeros_like(atlas)
for i,(name,color,rough,metal) in enumerate(PALETTE):
    rng = np.random.default_rng(SEED+i)
    soft = .008*np.sin(xx*.034+yy*.051)+.007*np.cos(xx*.070-yy*.025)
    field = soft+rng.normal(0,.003,(n,n))
    if name in ('linen','bluecloth','cloak','thread','ivory','mono_trim','scarf'):
        field += .014*np.sin(xx*math.pi/2)*np.sin(yy*math.pi/2)
        field += .006*np.sin(xx*.20+np.sin(yy*.037))
    elif name == 'hair':
        field += .012*np.sin(xx*.65+np.sin(yy*.07))
    elif name in ('boots','leather'):
        field += rng.normal(0,.009,(n,n))+.011*np.sin(xx*.024)*np.cos(yy*.047)
    elif 'skin' in name:
        field *= .40
    rgb = np.array(color)[None,None,:]+field[:,:,None]
    sy,sx = (i//4)*n,(i%4)*n
    atlas[sy:sy+n,sx:sx+n] = rgb
    gy,gx = np.gradient(field)
    norm = np.stack((-gx*3,-gy*3,np.ones_like(field)),axis=-1)
    norm /= np.linalg.norm(norm,axis=-1,keepdims=True)
    normal[sy:sy+n,sx:sx+n] = norm*.5+.5
    orm[sy:sy+n,sx:sx+n] = np.stack((np.ones_like(field),np.clip(rough+field,0,1),np.full_like(field,metal)),axis=-1)
albedo_img = image_png('travelers_v3_albedo', atlas)
normal_img = image_png('travelers_v3_normal', normal, False)
orm_img = image_png('travelers_v3_orm', orm, False)
mat = bpy.data.materials.new('Travelers_v3_Woven_PBR_Atlas')
mat.use_nodes = True
mat.diffuse_color = (.55,.48,.38,1)
nodes = mat.node_tree.nodes
bsdf = nodes.get('Principled BSDF')
base = nodes.new('ShaderNodeTexImage'); base.image = albedo_img
orm_tex = nodes.new('ShaderNodeTexImage'); orm_tex.image = orm_img
split = nodes.new('ShaderNodeSeparateColor')
norm_tex = nodes.new('ShaderNodeTexImage'); norm_tex.image = normal_img
norm_node = nodes.new('ShaderNodeNormalMap')
norm_node.inputs['Strength'].default_value = .38
links = mat.node_tree.links
links.new(base.outputs['Color'],bsdf.inputs['Base Color'])
links.new(orm_tex.outputs['Color'],split.inputs['Color'])
links.new(split.outputs['Green'],bsdf.inputs['Roughness'])
links.new(split.outputs['Blue'],bsdf.inputs['Metallic'])
links.new(norm_tex.outputs['Color'],norm_node.inputs['Color'])
links.new(norm_node.outputs['Normal'],bsdf.inputs['Normal'])
mat.use_backface_culling = False
skin_mat=mat.copy();skin_mat.name='Traveler_skin_restrained_specular'
skin_shader=skin_mat.node_tree.nodes.get('Principled BSDF')
skin_shader.inputs['Specular IOR Level'].default_value=.24

def mesh(name, verts, faces, tile):
    me = bpy.data.meshes.new(name)
    me.from_pydata([vec(v) for v in verts], [], faces)
    me.update()
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    ob.data.materials.append(skin_mat if tile=='skin' else mat)
    ob['palette_tile'] = tile
    uv = me.uv_layers.new(name='UVMap')
    idx = TILES[tile]
    # Continuous projection across each curved object, with a tile gutter.
    coords = [v.co for v in me.vertices]
    lo = [min(p[a] for p in coords) for a in range(3)]
    hi = [max(p[a] for p in coords) for a in range(3)]
    for poly in me.polygons:
        axis = max(range(3), key=lambda a: abs(poly.normal[a]))
        axes = [a for a in range(3) if a != axis]
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            u,v = [(p[a]-lo[a])/max(.001,hi[a]-lo[a]) for a in axes]
            uv.data[li].uv = ((idx%4+.025+u*.95)/4,(idx//4+.025+v*.95)/4)
        poly.use_smooth = True
    return ob

def ellipsoid(name, center, radii, tile, segments=24, rings=12):
    verts = [(center[0],center[1]-radii[1],center[2])]
    for j in range(1,rings):
        lat = -math.pi/2+math.pi*j/rings
        for k in range(segments):
            a = math.tau*k/segments
            verts.append((center[0]+radii[0]*math.cos(lat)*math.cos(a),
                          center[1]+radii[1]*math.sin(lat),
                          center[2]+radii[2]*math.cos(lat)*math.sin(a)))
    top = len(verts); verts.append((center[0],center[1]+radii[1],center[2]))
    faces = []
    for k in range(segments): faces.append((0,1+(k+1)%segments,1+k))
    for j in range(rings-2):
        for k in range(segments):
            a = 1+j*segments+k; b = 1+j*segments+(k+1)%segments
            faces.append((a,b,b+segments,a+segments))
    for k in range(segments): faces.append((top,1+(rings-2)*segments+k,1+(rings-2)*segments+(k+1)%segments))
    return mesh(name,verts,faces,tile)

def loft(name, rows, tile, sides=32, folds=0, phase=0):
    # rows are (height, width radius, depth radius, depth centre).
    verts = []
    for y,rx,rz,zc in rows:
        for i in range(sides):
            a = math.tau*i/sides
            f = 1+folds*math.sin(a*8+phase+y*3)
            verts.append((math.cos(a)*rx*f,y,zc+math.sin(a)*rz*f))
    faces = [tuple(reversed(range(sides))),tuple((len(rows)-1)*sides+i for i in range(sides))]
    for j in range(len(rows)-1):
        for i in range(sides):
            a=j*sides+i;b=j*sides+(i+1)%sides
            faces.append((a,b,b+sides,a+sides))
    return mesh(name,verts,faces,tile)

def sampled(points, subdivisions=5):
    p = [Vector(v) for v in points]
    if len(p) < 3: return p
    out=[]
    for i in range(len(p)-1):
        p0,p1,p2,p3 = p[max(0,i-1)],p[i],p[i+1],p[min(len(p)-1,i+2)]
        for j in range(subdivisions):
            t=j/subdivisions
            out.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
    out.append(p[-1])
    return out

def tube(name, points, radius, tile, sides=8, subdivisions=4, taper=False, flatten=1):
    pp = sampled(points,subdivisions)
    verts=[]
    for i,p in enumerate(pp):
        tangent = pp[min(len(pp)-1,i+1)]-pp[max(0,i-1)]
        tangent.normalize()
        u = tangent.cross(Vector((0,0,1)))
        if u.length < .1: u=tangent.cross(Vector((1,0,0)))
        u.normalize();v=tangent.cross(u).normalized()
        t=i/max(1,len(pp)-1)
        rr=radius*(.30+.70*math.sin(math.pi*(.06+.88*t))**.35) if taper else radius
        if taper and i==len(pp)-1: rr=radius*.04
        for j in range(sides):
            a=math.tau*j/sides
            verts.append(tuple(p+u*math.cos(a)*rr+v*math.sin(a)*rr*flatten))
    faces=[tuple(reversed(range(sides))),tuple((len(pp)-1)*sides+i for i in range(sides))]
    for i in range(len(pp)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    return mesh(name,verts,faces,tile)

def loop(name, center, rx, rz, tile, radius=.0035, y=None):
    points=[]
    for i in range(25):
        a=math.tau*i/24
        points.append((center[0]+math.cos(a)*rx,center[1] if y is None else y,center[2]+math.sin(a)*rz))
    return tube(name,points,radius,tile,sides=6,subdivisions=1)

def empty(name, pos=(0,0,0), parent=None):
    ob=bpy.data.objects.new(name,None)
    scene.collection.objects.link(ob)
    ob.empty_display_type='PLAIN_AXES';ob.empty_display_size=.055
    ob.location=vec(pos)
    ob.parent=parent
    return ob

def join_part(name, objects, parent):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    ob=bpy.context.object;ob.name=name
    scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    ob.parent=parent;ob.location=(0,0,0)
    ob['original_design']='Travelers v3: original geometry, repository generator'
    return ob

def face(name, skin, sleeping=False, female=False):
    if name=='Traveler': return traveler_face()
    width=.94 if female else 1.0
    rows=[(.626,.054,.063,.003),(.643,.073,.078,-.004),(.67,.089,.089,0),
          (.709,.104,.098,.002),(.756,.119,.108,.005),(.802,.122,.108,.010),
          (.845,.117,.109,.010),(.880,.096,.091,.010),(.911,.046,.045,.012),(.919,.005,.005,.012)]
    rows=[(y,rx*width,rz,zc) for y,rx,rz,zc in rows]
    parts=[loft(name+' sculpted jaw and cheek planes',rows,skin,sides=40)]
    for side in [-1,1]:
        parts.append(ellipsoid(name+' ear', (side*.119*width,.759,.015),(.019,.031,.017),skin,16,10))
        parts.append(ellipsoid(name+' ear fold',(side*.130*width,.761,-.0005),(.004,.018,.008),'lips',12,8))
    # Nose has a connected bridge, alar lobes and a tapered tip, no box proxy.
    parts.append(loft(name+' nose bridge',[(.731,.010,.004,-.116),(.740,.023,.017,-.122),
                      (.752,.017,.021,-.124),(.775,.010,.012,-.109),(.808,.006,.003,-.103)],skin,sides=20))
    for side in [-1,1]:
        parts.append(ellipsoid(name+' nostril wing',(side*.015,.740,-.120),(.008,.006,.010),skin,16,8))
        parts.append(ellipsoid(name+' nostril shadow',(side*.013,.736,-.130),(.004,.002,.0025),'lips',12,6))
    for side in [-1,1]:
        x=side*.051*width
        if sleeping:
            points=[(x-side*.022,.790,-.097),(x,.786,-.108),(x+side*.022,.792,-.095)]
            parts.append(tube(name+' closed eyelid',points,.0018,'hair',6,5))
            parts.append(tube(name+' upper lid volume',[(p[0],p[1]+.004,p[2]+.001) for p in points],.003,skin,6,4))
        else:
            parts.append(ellipsoid(name+' eye white',(x,.791,-.099),(.023,.0095,.008),'eye_white',20,10))
            parts.append(ellipsoid(name+' iris',(x,.791,-.108),(.008,.008,.0025),'eye_dark',18,10))
            parts.append(ellipsoid(name+' iris catchlight',(x-.002,.794,-.1105),(.0018,.0018,.0008),'eye_white',10,6))
            for s in [-1,1]:
                pts=[(x-.024,.791,-.097),(x,.791+s*.010,-.108),(x+.024,.791,-.096)]
                parts.append(tube(name+' eyelid',pts,.0028,skin,6,5))
        brow=[(x-side*.025,.823,-.101),(x,.829,-.106),(x+side*.028,.819,-.092)]
        parts.append(tube(name+' tapered brow',brow,.0035,'hair',7,5,True,.65))
    lipline=[(-.026,.704,-.097),(-.009,.707,-.106),(0,.705,-.109),(.009,.707,-.106),(.026,.704,-.097)]
    parts.append(tube(name+' soft upper lip',lipline,.0034,'lips',7,4,True,.65))
    parts.append(tube(name+' lower lip',[(-.024,.700,-.098),(0,.697,-.107),(.024,.700,-.098)],.0033,'lips',7,5,True,.6))
    return parts

def hair(name, long=False):
    if name=='Traveler': return traveler_hair()
    parts=[]
    # Scalp envelope with an open front below the irregular hairline.
    verts=[];faces=[];nr=12;ns=40
    for j in range(nr+1):
        phi=.12+(math.pi*.91-.12)*j/nr
        for k in range(ns):
            a=math.tau*k/ns
            verts.append((.131*math.sin(phi)*math.cos(a),.803+.126*math.cos(phi),.018+.121*math.sin(phi)*math.sin(a)))
    for j in range(nr):
        for k in range(ns):
            a=j*ns+k;b=j*ns+(k+1)%ns
            c=(verts[a][1]+verts[b][1])/2;z=(verts[a][2]+verts[b][2])/2
            if z < -.020 and c < .838+.007*math.cos(k*.7): continue
            faces.append((a,b,b+ns,a+ns))
    parts.append(mesh(name+' open face scalp',verts,faces,'hair'))
    count=26 if long else 18
    for i in range(count):
        a=.10+(math.pi-.2)*i/(count-1)
        x=math.cos(a)*.12;z=math.sin(a)*.106+.022
        if long:
            pts=[(x*.48,.910,z*.45),(x*.90,.823,z),
                 (x*1.16,.683,z+.01),(x*1.45,.521,z+.004),(x*1.80,.343,z-.015)]
            radius=.018+(.004 if i%3==0 else 0)
        else:
            pts=[(x*.5,.911,z*.50),(x,.833,z+.007),
                 (x*1.06,.739,z+.018),(x*1.0,.683+(i%3)*.013,z+.002)]
            radius=.020
        parts.append(tube(name+' layered back lock %02d'%i,pts,radius,'hair',9,5,True,.45))
        if i%2==0:
            pts2=[(p[0]+.003,p[1],p[2]+.006) for p in pts]
            parts.append(tube(name+' strand highlight %02d'%i,pts2,.0016,'leather',5,3,True,.55))
    # Broad swept fringe, kept above brows rather than hiding the modeled eyes.
    for i in range(7):
        x=(i-3)*.026
        pts=[(x*.6-.025,.916,-.021),(x-.020,.874,-.096),
             (x+.017,.845-(i%2)*.009,-.111),(x+.024,.836+(i%3)*.005,-.097)]
        parts.append(tube(name+' swept fringe %02d'%i,pts,.020,'hair',9,5,True,.4))
    return parts

def hand(name, side, skin, y=-.280):
    parts=[ellipsoid(name+' palm',(0,y-.026,0),(.035,.050,.022),skin,20,10)]
    for i,x in enumerate([-.024,-.008,.008,.024]):
        length=[.056,.067,.063,.048][i]
        parts.append(tube(name+' finger %d'%i,[(x,y-.059,-.004),(x,y-.059-length*.5,-.012),
                         (x,y-.059-length,-.009)],.008,skin,8,4,True,.85))
    parts.append(tube(name+' thumb',[(side*.028,y-.017,-.004),(side*.049,y-.040,-.013),
                     (side*.046,y-.064,-.019)],.010,skin,8,5,True))
    return parts

def embroidered_diamonds(name, xs, y, z, tile, scale=1):
    parts=[]
    for x in xs:
        pts=[(x,y+.026*scale,z),(x+.020*scale,y,z-.001),(x,y-.026*scale,z),
             (x-.020*scale,y,z-.001),(x,y+.026*scale,z)]
        parts.append(tube(name+' double weft',pts,.0022*scale,tile,5,1))
        # Submillimetre stitches do not benefit from full facial sphere density.
        segments,rings=(10,6) if name.startswith('Mono') else (8,4)
        parts.append(ellipsoid(name+' seed stitch',(x,y,z-.002),(.003,.005,.0025),tile,segments,rings))
    return parts

def gaussian(x,y,cx,cy,sx,sy):
    return math.exp(-((x-cx)/sx)**2-((y-cy)/sy)**2)

# Anatomical landmarks in metres, deliberately stronger plane changes than the
# former smooth egg. Keep local coordinates; rig/attachment frames are invariant.
FACE_PROFILE=[(.615,.036,.042,-.013),(.632,.055,.062,-.009),(.653,.074,.075,-.001),
             (.678,.087,.082,.006),(.710,.098,.092,.008),(.753,.111,.103,.010),
             (.790,.114,.104,.014),(.830,.112,.103,.017),(.861,.106,.100,.020),
             (.891,.077,.077,.019),(.912,.035,.035,.018),(.919,.004,.004,.018)]

def profile_value(y, profile, k):
    # Cubic Hermite interpolation avoids horizontal rings from piecewise-linear
    # cheek and jaw radii. Values remain in the authored landmark envelope.
    i=max(0,min(len(profile)-2,int(np.searchsorted([r[0] for r in profile],y))-1))
    p0,p1=profile[i],profile[i+1];h=p1[0]-p0[0];t=max(0,min(1,(y-p0[0])/h))
    a=profile[max(0,i-1)];b=profile[min(len(profile)-1,i+2)]
    m0=(p1[k]-a[k])/(p1[0]-a[0]);m1=(b[k]-p0[k])/(b[0]-p0[0])
    return (2*t**3-3*t*t+1)*p0[k]+(t**3-2*t*t+t)*h*m0+(-2*t**3+3*t*t)*p1[k]+(t**3-t*t)*h*m1

def traveler_face_z(x,y):
    rx,rz,zc=[profile_value(y,FACE_PROFILE,k) for k in [1,2,3]]
    sa=-math.sqrt(max(0,1-(x/max(rx,.001))**2))
    z=zc-rz*(-sa)**.78
    # Chin pad, mouth barrel, philtrum, nasal bridge and alar cartilages.
    sculpt=.004*gaussian(x,y,0,.642,.035,.020)
    sculpt+=.008*gaussian(x,y,0,.701,.030,.021)
    sculpt+=.0025*gaussian(x,y,0,.716,.027,.017)
    sculpt+=.0028*gaussian(x,y,0,.707,.027,.0035)
    sculpt+=.0038*gaussian(x,y,0,.698,.025,.0040)
    sculpt-=.0005*gaussian(x,y,0,.672,.030,.012)
    sculpt+=.016*gaussian(x,y,0,.775,.013,.038)
    sculpt+=.022*gaussian(x,y,0,.745,.018,.013)
    sculpt+=.005*gaussian(x,y,0,.721,.011,.010)
    for side in [-1,1]:
        sculpt+=.004*gaussian(x,y,side*.069,.763,.034,.030)
        sculpt-=.002*gaussian(x,y,side*.068,.712,.032,.037)
        sculpt+=.012*gaussian(x,y,side*.045,.816,.028,.012)
        sculpt-=.007*gaussian(x,y,side*.040,.791,.025,.017)
        sculpt+=.010*gaussian(x,y,side*.017,.740,.011,.008)
    return z-sculpt*max(0,-sa)**5

def facial_line(name,xy,r,tile,sides=6,subdiv=3,flatten=1,offset=.0008):
    # Keep eyelids, philtrum and lip rims on the sculpt in a side profile too.
    pts=[(x,y,traveler_face_z(x,y)-offset) for x,y in xy]
    return tube(name,pts,r,tile,sides,subdiv,True,flatten)

def traveler_face():
    # A single continuous sculpt carries forehead, brow sockets, nose, cheek,
    # philtrum and chin. The same surface positions all small facial details.
    yy=[.615,.628,.640,.653,.670,.685,.696,.702,.710,.720,.728,.735,.740,.745,
        .750,.755,.761,.770,.780,.788,.796,.805,.814,.824,.835,.847,.859,.874,.891,.907,.919]
    angles=[math.pi*i/12 for i in range(12)]+[math.pi+math.pi*i/32 for i in range(32)]
    sides=len(angles);verts=[];faces=[]
    for y in yy:
        rx,rz,zc=[profile_value(y,FACE_PROFILE,k) for k in [1,2,3]]
        for a in angles:
            ca,sa=math.cos(a),math.sin(a)
            x=rx*ca;z=zc+rz*sa
            if sa<0: z=traveler_face_z(x,y)
            verts.append((x,float(y),z))
    for j in range(len(yy)-1):
        for i in range(sides):
            a=j*sides+i;b=j*sides+(i+1)%sides;faces.append((a,b,b+sides,a+sides))
    faces+=[tuple(reversed(range(sides))),tuple((len(yy)-1)*sides+i for i in range(sides))]
    parts=[mesh('Traveler continuous facial sculpt',verts,faces,'skin')]
    for side in [-1,1]:
        parts.append(ellipsoid('Traveler shaped ear',(side*.121,.765,.019),(.014,.027,.012),'skin',16,10))
        parts.append(tube('Traveler ear helix',[(side*.131,.743,.014),(side*.134,.771,.009),(side*.126,.789,.009)],.0024,'skin',6,3))
        x=side*.040
        cy=.791
        # Eyeball volume is visible through an asymmetrical lid aperture. Lids
        # form a skin annulus blending into the socket, not pasted-on outlines.
        center_z=traveler_face_z(x,cy)+.009
        def aperture(a):
            u=math.cos(a);v=math.sin(a)
            return .0185*u, (.0054 if v>0 else .0048)*v + side*.0012*u
        def globe_z(dx,dy):
            return center_z-.014*math.sqrt(max(.02,1-(dx/.022)**2-(dy/.016)**2))
        vv=[(x,cy,globe_z(0,0))];ff=[];ns=32
        for j in range(1,5):
            for k in range(ns):
                dx,dy=aperture(math.tau*k/ns);dx*=j/4;dy*=j/4
                vv.append((x+dx,cy+dy,globe_z(dx,dy)))
        for k in range(ns):ff.append((0,1+k,1+(k+1)%ns))
        for j in range(3):
            for k in range(ns):
                a=1+j*ns+k;b=1+j*ns+(k+1)%ns;ff.append((a,b,b+ns,a+ns))
        parts.append(mesh('Traveler spherical sclera under lids',vv,ff,'eye_white'))
        vv=[];ff=[]
        for j in range(4):
            t=j/3
            for k in range(ns):
                a=math.tau*k/ns;dx,dy=aperture(a)
                ox=.028*math.cos(a);oy=(.019 if math.sin(a)>0 else .014)*math.sin(a)
                px=x+dx*(1-t)+ox*t;py=cy+dy*(1-t)+oy*t
                inner=globe_z(dx,dy)-.0008
                outer=traveler_face_z(px,py)-.0001
                z=inner*(1-t)+outer*t-.0014*max(0,math.sin(a))*math.sin(math.pi*t)
                vv.append((px,py,z))
        for j in range(3):
            for k in range(ns):
                a=j*ns+k;b=j*ns+(k+1)%ns;ff.append((a,b,b+ns,a+ns))
        parts.append(mesh('Traveler orbital eyelid planes and socket transition',vv,ff,'skin'))
        iris=ellipsoid('Traveler iris partially covered by upper eyelid',(x,cy,globe_z(0,0)-.0005),(.0062,.0060,.0006),'eye_dark',16,8)
        for vertex in iris.data.vertices:
            p=godot(vertex.co);dx=p.x-x
            aperture_height=math.sqrt(max(0,1-(dx/.0185)**2))
            lo=cy-.0048*aperture_height+side*.0012*(dx/.0185)
            hi=cy+.0054*aperture_height+side*.0012*(dx/.0185)
            vertex.co=vec((p.x,max(lo+.0002,min(hi-.0002,p.y)),p.z))
        parts.append(iris)
        parts.append(ellipsoid('Traveler restrained corneal glint',(x-.0018,cy+.002,globe_z(0,0)-.0012),(.0006,.0006,.00025),'eye_white',8,5))
        brow=[(x-side*.023,.812),(x,.815),(x+side*.024,.809)]
        parts.append(facial_line('Traveler fine tapered brow',brow,.0014,'hair',6,4,.25))
        parts.append(ellipsoid('Traveler nostril crease',(side*.012,.738,traveler_face_z(side*.012,.738)-.0004),(.003,.0013,.0016),'lips',10,6))
    parts.append(facial_line('Traveler integrated closed mouth opening',[(-.030,.703),(-.010,.704),(0,.7025),(.010,.704),(.029,.703)],.0005,'lips',5,3,.3,.0012))
    return parts

def traveler_hair():
    # Single close-fitting scalp surface with irregular swept relief. The major
    # masses are continuous, not separated plates. Only fine tips leave the cap.
    hair_mat=mat.copy();hair_mat.name='Traveler_matte_hair_fibres'
    shader=hair_mat.node_tree.nodes.get('Principled BSDF')
    for link in list(shader.inputs['Roughness'].links):hair_mat.node_tree.links.remove(link)
    shader.inputs['Roughness'].default_value=.9
    shader.inputs['Specular IOR Level'].default_value=.16
    for node in hair_mat.node_tree.nodes:
        if node.type=='NORMAL_MAP':node.inputs['Strength'].default_value=.22
    vv=[];ff=[];nr=20;ns=64
    def cap_point(t,a):
        front=max(0,-math.sin(a))**2
        limit=2.45-.35*abs(math.cos(a))-1.27*front
        limit+=.055*math.sin(5*a+.7)+.035*math.sin(9*a+1.3)
        phi=.02+(limit-.02)*t
        sweep=a+.22*math.sin(phi)*front
        # Shallow, unequal primary masses, supported continuously by the scalp.
        relief=.0022*math.sin(7*a+2.6*phi)+.0012*math.sin(17*a+5*phi)
        relief*=math.sin(phi)**.8
        y=.802+.123*math.cos(phi)
        sy=max(.615,min(.919,.802+.117*math.cos(phi)))
        rx,rz,zc=[profile_value(sy,FACE_PROFILE,k) for k in (1,2,3)]
        bx=rx*math.cos(sweep)
        bz=traveler_face_z(bx,sy) if math.sin(sweep)<0 else zc+rz*math.sin(sweep)
        # Fit to the actual authored skull, not a different generic ellipsoid.
        # Positive clearance everywhere prevents skin islands through the cap.
        offset=(.0065+relief)*math.sin(phi)
        return (bx+offset*math.cos(sweep),y,bz+offset*math.sin(sweep))

    for j in range(nr+1):
        for k in range(ns):vv.append(cap_point(j/nr,math.tau*k/ns))
    for j in range(nr):
        for k in range(ns):
            a=j*ns+k;b=j*ns+(k+1)%ns;ff.append((a,b,b+ns,a+ns))
    crown=len(vv);vv.append((0,.925,.018))
    for k in range(ns):ff.append((crown,(k+1)%ns,k))
    parts=[mesh('Traveler unified swept scalp and shallow hair clusters',vv,ff,'hair')]
    # Layered clusters ride directly on the cap with millimetre relief. No
    # detached plates or full-depth seams; unequal flows retain swept identity.
    for group,(angle,width,end) in enumerate([(3.78,.14,1.025),(4.08,.17,1.04),(4.43,.20,1.03),(4.86,.14,1.018),(5.18,.17,1.035)]):
        pv=[];pf=[];steps=12;cross=7
        for j in range(steps):
            t=j/(steps-1);ct=.18+(end-.18)*t
            ca=angle-.19+.27*t+.04*math.sin(math.pi*t)
            taper=(.58+.42*math.sin(math.pi*t))*(1-.65*t**7)
            for k in range(cross):
                u=(k-(cross-1)/2)/((cross-1)/2)
                a=ca+u*width*taper
                point=Vector(cap_point(ct,a))
                outward=Vector((math.cos(a),.30*(1-t),math.sin(a))).normalized()
                relief=(.0005+.002*(1-u*u)*math.sin(math.pi*t))*(1-.85*t**9)
                pv.append(tuple(point+outward*relief))
        for j in range(steps-1):
            for k in range(cross-1):
                a=j*cross+k;pf.append((a,a+1,a+cross+1,a+cross))
        parts.append(mesh('Traveler shallow swept hair cluster %02d'%group,pv,pf,'hair'))
    # Sparse short ends: roots overlap the cap and never float above forehead.
    for i,a in enumerate([3.62,4.02,4.38,4.82,5.17,5.51,.2,2.8]):
        start=cap_point(.88,a);mid=cap_point(.98,a+.018);end=cap_point(1.03,a+.027)
        end=(end[0]*1.003,end[1]-.005-(i%3)*.002,end[2])
        parts.append(tube('Traveler fine overlapping hair tip %02d'%i,[start,mid,end],.0045+(i%2)*.001,'hair',6,3,True,.30))
    for ob in parts:ob.data.materials[0]=hair_mat
    return parts

def grip_hand(name, side):
    # Closed neutral grip: each curled finger wraps the vertical hilt axis,
    # leaving a 26mm channel centred at Wrist-local (0,-.050,-.037).
    parts=[loft(name+' metacarpal palm',[(.004,.025,.021,0),(-.018,.034,.023,-.002),
            (-.043,.036,.022,-.002),(-.068,.031,.019,-.001),(-.084,.017,.013,0)],'skin',24)]
    for i,y in enumerate([-.027,-.043,-.059,-.073]):
        r=[.0072,.0077,.0072,.0060][i]
        pts=[(side*.025,y,-.004),(side*.039,y-.002,-.025),(side*.026,y-.003,-.060),
             (side*.001,y-.004,-.064),(-side*.017,y-.002,-.044)]
        parts.append(tube(name+' curled finger %d'%i,pts,r,'skin',7,3,False,.85))
        parts.append(ellipsoid(name+' knuckle %d'%i,(side*.026,y,-.021),(.009,r*.93,.010),'skin',8,5))
    parts.append(tube(name+' opposed thumb',[(side*.025,-.009,-.006),(side*.038,-.022,-.036),
                  (side*.019,-.031,-.058),(-side*.003,-.034,-.057)],.0080,'skin',7,4,True,.83))
    return parts

TUNIC_PROFILE=[(-.32,.201,.134,0),(-.23,.200,.132,0),(-.13,.176,.117,0),
               (-.07,.165,.108,0),(0,.157,.102,0),(.10,.169,.107,0),(.23,.184,.113,0),
               (.35,.190,.117,0),(.43,.190,.102,0),(.455,.177,.089,0),(.475,.137,.075,0),(.492,.085,.068,0)]

def tunic_point(y,a):
    rx,rz,zc=[float(np.interp(y,[r[0] for r in TUNIC_PROFILE],[r[k] for r in TUNIC_PROFILE])) for k in [1,2,3]]
    gather=max(0,min(1,(-y-.07)/.25))
    fold=gather*.007*(math.sin(a*7+.2)+.4*math.sin(a*11))
    front=max(0,-math.sin(a))**4
    fold+=.004*front*math.sin(28*y+5*math.cos(a))*math.exp(-((y-.05)/.14)**2)
    x=(rx+fold)*math.cos(a);z=zc+(rz+fold)*math.sin(a)
    # Unequal cloth compression lines from armhole towards the waist. These
    # terminate in the fabric instead of forming circumferential rubber rings.
    tension=math.exp(-((y-.15)/.16)**4)*front
    for side in [-1,1]:
        line=side*(.072+.32*y)
        z+=.006*tension*math.exp(-((x-line)/.013)**2)
        z-=.003*tension*math.exp(-((x-line-side*.019)/.019)**2)
    # Keep gathered cloth below the actual narrowed leather-belt envelope.
    if -.12<=y<=-.045:
        brx=.79*float(np.interp(y,[-.110,-.075,-.053],[.224,.214,.210]))-.003
        brz=.79*float(np.interp(y,[-.110,-.075,-.053],[.151,.140,.139]))-.003
        q=math.sqrt((x/brx)**2+(z/brz)**2)
        if q>1:x/=q;z/=q
    return x,z

def fit_tunic_embroidery(parts):
    # Ornament follows the gathered surface instead of floating on a flat plane
    # or disappearing under deeper skirt folds. Preserve its actual thickness.
    for ob in parts:
        for v in ob.data.vertices:
            p=godot(v.co)
            samples=[tunic_point(p.y,math.pi+math.pi*i/80) for i in range(81)]
            z=float(np.interp(p.x,[s[0] for s in samples],[s[1] for s in samples]))
            v.co=vec((p.x,p.y,z+p.z-.0035))
        ob.data.update()
    return parts

def gathered_tunic():
    verts=[];faces=[];sides=64;rows=41
    for j in range(rows):
        y=-.32+.797*j/(rows-1)
        for i in range(sides):
            a=math.tau*i/sides
            x,z=tunic_point(y,a)
            hem=(.007*math.sin(a*3+.8)+.005*math.cos(a*2+.3))*(1-j/(rows-1))**14
            verts.append((x,y+hem,z))
    for j in range(rows-1):
        for i in range(sides):
            a=j*sides+i;b=j*sides+(i+1)%sides;faces.append((a,b,b+sides,a+sides))
    faces+=[tuple(reversed(range(sides))),tuple((rows-1)*sides+i for i in range(sides))]
    return mesh('Traveler gathered tunic folds under belt',verts,faces,'bluecloth')

# Independent cosmetic skin follows the immutable gameplay joint hierarchy.
exec(compile((Path(__file__).with_name('traveler_body_surface.py')).read_text(), 'traveler_body_surface.py', 'exec'))
traveler = empty('Traveler_v3')
surface_rig=build_surface_rig(traveler)
continuous_garment(traveler,surface_rig)
for index,side in enumerate([-1,1]): continuous_arm(index,side,surface_rig)
torso=[]
torso.append(loft('Visible linen collar',[(.465,.095,.077,0),(.487,.091,.074,0),(.505,.086,.070,0)],'linen',40,0))
torso.append(loft('Neck tendon',[(.49,.074,.061,.010),(.525,.064,.054,.015),(.550,.058,.050,.018),(.58,.060,.052,.018)],'skin',28))
torso.append(loft('Double leather girdle',[(-.110,.224,.151,0),(-.075,.214,.140,0),(-.053,.210,.139,0)],'leather',36))
torso.append(ellipsoid('Oval hammered buckle',(0,-.077,-.150),(.035,.022,.008),'bronze',20,10))
torso.append(ellipsoid('Buckle inset',(0,-.077,-.158),(.023,.012,.002),'leather',18,8))
torso.append(tube('Buckle tongue',[(-.023,-.077,-.161),(.020,-.077,-.161)],.0025,'bronze',6,1))
for y in [-.28,.37,.42]:
    torso += fit_tunic_embroidery([tube('Front woven border',[(-.185,y,0),(-.10,y-.007,0),(0,y,0),(.10,y-.007,0),(.185,y,0)],.0023,'thread',6,4)])
torso += fit_tunic_embroidery(embroidered_diamonds('Chest original seed motif',[-.135,-.09,-.045,0,.045,.09,.135],.393,0,'thread',.60))
torso += fit_tunic_embroidery(embroidered_diamonds('Hem original salt lozenge',[-.175,-.105,-.035,.035,.105,.175],-.246,0,'thread',.9))
# Draped short mantle with real folds and an irregular soft edge.
verts=[];faces=[];nx=18;ny=22
for j in range(ny+1):
    t=j/ny;y=.441-.85*t
    width=.150+.060*math.sin(min(1,t/.30)*math.pi/2)+.008*t
    for i in range(nx+1):
        s=(i/nx)*2-1
        z=.132+.065*t+.015*math.cos(s*math.pi*4.7+.7*t)*(t*.75+.20)
        z+=-.036*s*s*(1-t)**4+.018*s*s*t+.009*math.sin(s*7+t*5)*t
        top_y=.441-.070*s*s
        top_rx,top_rz=[float(np.interp(top_y,[r[0] for r in TUNIC_PROFILE],[r[k] for r in TUNIC_PROFILE])) for k in [1,2]]
        attached_z=top_rz*math.sqrt(max(.02,1-(s*.150/top_rx)**2))+.006
        old_top=.132+.003*math.cos(s*math.pi*4.7)-.036*s*s
        z+=(attached_z-old_top)*(1-t)**6
        hem=(.018*math.sin(s*7.3)+.014*s)*(t**7)
        verts.append((s*width,y-.070*s*s*(1-t)**4-.015*math.cos(s*math.pi*4.7+.7*t)*t+hem,z))
for j in range(ny):
    for i in range(nx):
        a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
front_count=len(verts)
verts += [(x,y,z+.0025) for x,y,z in verts]
faces += [tuple(front_count+i for i in reversed(f)) for f in list(faces)]
outline=list(range(nx+1))+[j*(nx+1)+nx for j in range(1,ny+1)]+[ny*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(ny-1,0,-1)]
for i,a in enumerate(outline):
    b=outline[(i+1)%len(outline)];faces.append((a,b,b+front_count,a+front_count))
torso.append(mesh('Traveler gravity draped wool mantle with cloth thickness',verts,faces,'cloak'))
torso.append(tube('Mantle hem',[verts[ny*(nx+1)+i] for i in range(nx+1)],.005,'thread',6,1))
for side in [-1,1]:
    torso.append(tube('Mantle bound side',[verts[j*(nx+1)+(0 if side<0 else nx)] for j in range(ny+1)],.004,'leather',6,1))
    torso.append(ellipsoid('Shoulder clasp',(side*.152,.445,-.060),(.016,.012,.005),'bronze',16,8))
    # The rotating sleeve head overlaps the tunic edge. No fixed spherical
    # body-side joint pad: those read as doll shoulders in neutral/climb views.
cord=[]
for x,y in [(-.152,.445),(-.13,.37),(-.08,.253),(-.015,.15),(.05,.056),(.11,-.02),(.17,-.096)]:
    rx,rz=[float(np.interp(y,[r[0] for r in TUNIC_PROFILE],[r[k] for r in TUNIC_PROFILE])) for k in [1,2]]
    cord.append((x,y,-rz*math.sqrt(max(.05,1-(x/rx)**2))-.010))
torso.append(tube('Cross-body woven cord',cord,.010,'scarf',10,5,False,.40))
torso.append(ellipsoid('Small belt pouch',(.184,-.150,.078),(.057,.073,.041),'leather',24,12))
torso.append(tube('Pouch seam',[(.138,-.146,.106),(.160,-.210,.113),(.207,-.211,.110),(.230,-.144,.092)],.003,'thread',6,5))
for ob in torso:
    if any(label in ob.name for label in ['girdle','buckle','Buckle','belt pouch','Pouch seam']):
        for vertex in ob.data.vertices:
            p=godot(vertex.co);vertex.co=vec((p.x*.79,p.y,p.z*.79))
torso_surface=join_part('Traveler_Torso',torso,traveler)
torso_weights=[]
for vertex in torso_surface.data.vertices:
    p=godot(vertex.co)
    alpha=surface_torso_alpha(p.x,p.y,p.z)
    if p.z>.04:
        attachment_y=.441-.070*min(1,(abs(p.x)/.150)**2)
        fade=max(0,min(1,(p.y-(attachment_y-.12))/.12))
        alpha*=fade*fade*(3-2*fade)
    mask=surface_axilla_mask(p.x,p.y,p.z)
    if p.z>.04:mask*=fade
    index=0 if p.x<0 else 1
    weights=axilla_weights(index,shoulder_weights(index,alpha),mask,surface_fold_mask(p.x,p.y,p.z)*(fade if p.z>.04 else 1),p.z<0)
    # Front hem ornament follows its cloth; the separate mantle remains body-driven.
    torso_weights.append(lower_cloth_weights(p.x,p.y,p.z,weights) if p.z<.04 else weights)
bind_surface(torso_surface,surface_rig,torso_weights)
head_parts=face('Traveler','skin')+hair('Traveler')
for ob in head_parts:
    for vertex in ob.data.vertices:
        p=godot(vertex.co)
        vertex.co=vec((p.x*.82,.535+(p.y-.615)*.81,p.z*.87))
join_part('Traveler_Head',head_parts,traveler)

for index,side in enumerate([-1,1]):
    arm=empty('Arm_%d'%index,(side*.3,.4,0),traveler)
    upper=[loft('Linen sleeve draping folds',[(.005,.073,.064,0),(-.027,.074,.065,0),(-.054,.072,.064,0),
           (-.084,.077,.065,.001),(-.117,.072,.060,.002),(-.150,.068,.060,0),(-.182,.066,.058,0)],'linen',28,.055,.6),
           loft('Upper arm', [(-.160,.049,.045,0),(-.205,.046,.043,.001),(-.246,.040,.037,.002),(-.302,.037,.035,0)],'skin',24)]
    upper.append(ellipsoid('Rounded sleeve head',(0,-.018,0),(.070,.037,.065),'linen',16,8))
    upper.append(ellipsoid('Soft elbow contact',(0,-.285,0),(.037,.035,.034),'skin',16,8))
    upper.append(loop('Sleeve cuff',(0,-.178,0),.070,.061,'thread',.004))
    upper += embroidered_diamonds('Sleeve stitch',[-.04,0,.04],-.150,-.063,'bluecloth',.45)
    for ob in upper: bpy.data.objects.remove(ob,do_unlink=True)
    empty('Traveler_UpperArm_%d'%index,parent=arm)
    fore=empty('Forearm_%d'%index,(0,-.285,0),arm)
    lower=[loft('Anatomical taper and forearm flexors',[(.023,.038,.036,0),(-.035,.043,.039,-.001),
           (-.084,.047,.038,-.002),(-.135,.042,.034,-.002),(-.195,.034,.028,-.001),(-.230,.029,.025,0),(-.280,.026,.024,0)],'skin',28),
           loft('Bound wrist wrap',[(-.230,.035,.031,0),(-.250,.035,.031,0),(-.280,.031,.028,0)],'leather',24)]
    lower.append(ellipsoid('Wrist to palm tendon',(0,-.276,0),(.028,.032,.025),'skin',16,8))
    for y in [-.239,-.256,-.272]: lower.append(loop('Wrist linen stitch',(0,y,0),.036,.031,'thread',.0017))
    # Preserve bound wrist accessories on original forearm; continuous skin replaces flesh.
    for ob in [lower[0],lower[2]]: bpy.data.objects.remove(ob,do_unlink=True)
    lower=[ob for n,ob in enumerate(lower) if n not in [0,2]]
    join_part('Traveler_Forearm_%d'%index,lower,fore)
    wrist=empty('Wrist_%d'%index,(0,-.276,0),fore)
    join_part('Traveler_Hand_%d'%index,grip_hand('Traveler gripping hand %d'%index,side),wrist)
    empty('HandGrip_%d'%index,(0,-.050,-.037),wrist)
    if index == 1:
        import importlib.util
        spec=importlib.util.spec_from_file_location('archery_draw_hand',ROOT/'tools/art/archery_draw_hand.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        module.build_archery_hand(globals(),wrist)
    leg=empty('Leg_%d'%index,(side*.118,-.188,0),traveler)
    thigh=[loft('Tapered trouser thigh',trouser_rows(),'linen',28,.025)]
    # Trouser waist stays with the pelvis; knee end follows its unchanged hip.
    # Mesh reparenting is visual only. Leg/Knee/Ankle joint paths stay intact.
    thigh_surface=join_part('Traveler_Thigh_%d'%index,thigh,traveler)
    thigh_weights=[]
    for vertex in thigh_surface.data.vertices:
        p=godot(vertex.co)+Vector((side*.118,-.188,0))
        vertex.co=vec(p)
        thigh_weights.append(lower_cloth_weights(p.x,p.y,p.z,{'SurfaceBody':1}))
    bind_surface(thigh_surface,surface_rig,thigh_weights)
    knee=empty('Knee_%d'%index,(0,-.325,0),leg)
    shin=[loft('Wrapped calf',[(.015,.066,.061,0),(-.070,.072,.063,.002),(-.205,.047,.046,0),(-.30,.042,.043,0)],'boots',28,.015)]
    for y in [-.065,-.120,-.175,-.23]:
        rx=float(np.interp(y,[-.30,-.205,-.070,.015],[.042,.047,.072,.066]))
        rz=float(np.interp(y,[-.30,-.205,-.070,.015],[.043,.046,.063,.061]))
        shin.append(loop('Boot fitted bound strap',(0,y,0),rx+.002,rz+.002,'leather',.003))
    join_part('Traveler_Shin_%d'%index,shin,knee)
    ankle=empty('Ankle_%d'%index,(0,-.30,0),knee)
    foot=anatomical_boot()
    join_part('Traveler_Foot_%d'%index,foot,ankle)

# Mono: a dignified sleeping pose, hands resting together over her gown. The
# full dress, fingers, eyelids and long hair are modeled; no body proxy is shown.
mono = empty('Mono_v3_Sleep')
mono_parts=[]
mono_parts.append(loft('Mono softly gathered gown',[(-.866,.268,.145,.018),(-.80,.279,.147,.015),(-.60,.258,.141,.009),
                   (-.38,.235,.129,0),(-.18,.194,.121,0),(-.03,.172,.116,0),(.14,.190,.122,0),(.31,.212,.127,0),(.425,.202,.111,0),(.470,.118,.079,0)],'ivory',48,.055))
mono_parts.append(loft('Mono neck',[(.46,.058,.052,0),(.55,.054,.048,.005),(.65,.057,.048,.008)],'mono_skin',24))
for y,rx,rz in [(-.855,.273,.150),(-.814,.280,.154),(-.037,.175,.122),(.44,.122,.083)]:
    mono_parts.append(loop('Mono gown bound edge',(0,y,0),rx,rz,'mono_trim',.004))
mono_parts += embroidered_diamonds('Mono neckline seed motif',[-.070,-.035,0,.035,.070],.412,-.112,'mono_trim',.5)
mono_parts += embroidered_diamonds('Mono embroidered hem',[-.21,-.15,-.09,-.03,.03,.09,.15,.21],-.777,-.147,'mono_trim',.75)
# Paired vertical ornamental bands, quietly following the drape.
for side in [-1,1]:
    mono_parts.append(tube('Mono gown running stitch',[(side*.060,.32,-.129),(side*.073,.10,-.126),
                      (side*.087,-.14,-.125),(side*.123,-.43,-.145),(side*.171,-.74,-.157)],.003,'mono_trim',7,7))
    mono_parts.append(tube('Mono long loose sleeve',[(side*.214,.393,0),(side*.242,.235,-.035),(side*.190,.089,-.094),(side*.106,.013,-.165)],.066,'ivory',20,7,False,.84))
    mono_parts.append(tube('Mono cuff binding',[(side*.092,.035,-.163),(side*.121,.009,-.173),(side*.118,-.012,-.177)],.006,'mono_trim',8,5))
    # Each resting hand is sculpted along the abdomen rather than hanging down.
    mono_parts.append(ellipsoid('Mono resting palm',(side*.077,-.021,-.182),(.047,.024,.022),'mono_skin',24,12))
    for i in range(4):
        x=side*(.079-i*.010)
        mono_parts.append(tube('Mono relaxed finger',[(x,-.029,-.194),(x-side*.016,-.047,-.199),(x-side*.032,-.057,-.192)],.0063,'mono_skin',8,5,True))
    mono_parts.append(tube('Mono relaxed thumb',[(side*.080,-.002,-.179),(side*.054,-.011,-.195),(side*.041,-.024,-.194)],.008,'mono_skin',8,5,True))
    mono_parts.append(ellipsoid('Mono slipper below gown hem',(side*.089,-.916,.038),(.049,.072,.052),'ivory',24,10))
mono_parts += face('Mono','mono_skin',True,True)
mono_parts += hair('Mono',True)
mono_mesh=join_part('Mono_Sleep_Detailed',mono_parts,mono)
for v in mono_mesh.data.vertices:
    p=godot(v.co)
    # Lie supine: head +Z, face +Y, altar contact around Y=0. A minimum contact
    # height softly spreads the longest locks over the support instead of clipping.
    v.co=vec((p.x,max(.014,-p.z+.16),p.y))
mono_mesh.data.update()

def children(root):
    out=[root]
    for child in root.children:
        if not child.get('source_display_only',False): out += children(child)
    return out

def export_character(root, identifier):
    records=[]
    base_objects=children(root)
    base_meshes=[o for o in base_objects if o.type=='MESH']
    for level,ratio in enumerate([1,.52,.12]):
        remap={};copies=[]
        for ob in base_objects:
            cp=ob.copy()
            if ob.type=='MESH': cp.data=ob.data.copy()
            scene.collection.objects.link(cp)
            cp.parent=None;cp.matrix_world=ob.matrix_world.copy()
            remap[ob]=cp;copies.append(cp)
        for original,cp in remap.items():
            for modifier in cp.modifiers:
                if modifier.type=='ARMATURE' and modifier.object in remap: modifier.object=remap[modifier.object]
            if original.parent in remap:
                cp.parent=remap[original.parent]
                cp.matrix_local=original.matrix_local.copy()
            cp.hide_set(False);cp.hide_viewport=False;cp.hide_render=False
            if cp.type=='MESH':
                bpy.context.view_layer.objects.active=cp
                if not cp.data.shape_keys:
                    tri=cp.modifiers.new('Export triangles','TRIANGULATE')
                    bpy.ops.object.modifier_apply(modifier=tri.name)
                if level:
                    apply_surface_lod(cp,ratio)
                cp.data.validate(verbose=False,clean_customdata=False)
        bpy.ops.object.select_all(action='DESELECT')
        for cp in copies: cp.select_set(True)
        path=OUT/(identifier+'_lod%d.glb'%level)
        if identifier=='traveler':validate_surface_influences(copies)
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
            export_materials='EXPORT',export_yup=True,export_normals=True,
            export_texcoords=True,export_cameras=False,export_lights=False,
            export_animations=False,export_extras=True,export_image_format='AUTO',export_influence_nb=8 if identifier=='traveler' else 4)
        triangles=sum(sum(len(p.vertices)-2 for p in cp.data.polygons) for cp in copies if cp.type=='MESH')
        vertices=sum(len(cp.data.vertices) for cp in copies if cp.type=='MESH')
        points=[]
        for cp in copies:
            if cp.type=='MESH': points += [godot(cp.matrix_world@v.co) for v in cp.data.vertices]
        bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
        records.append({'lod':level,'runtime':str(path.relative_to(ROOT)).replace('\\','/'),'triangles':triangles,'vertices':vertices,'bytes':path.stat().st_size,'bounds_godot':bounds})
        for cp in reversed(copies): bpy.data.objects.remove(cp,do_unlink=True)
    return {'id':identifier,'lods':records,'material':mat.name,
            'materials':sorted({m.name for ob in base_meshes for m in ob.data.materials if m}),
            'mesh_parts':len(base_meshes),'colliders':'none; preserve existing gameplay capsule/anchors',
            'parts':[ob.name for ob in base_objects],'original_design':True,'source':'art/source/travelers_v3.blend'}

if '--traveler-only' in sys.argv:
    previous=json.loads((ROOT/'assets/travelers_v3_manifest.json').read_text())
    mono_record=next(a for a in previous['assets'] if a['id']=='mono_sleep')
else:
    mono_record=export_character(mono,'mono_sleep')
records=[export_character(traveler,'traveler'),mono_record]
manifest={'pack':'Travelers v3 / original interpretation','seed':SEED,'unit':'metre','up':'+Y','forward':'-Z',
          'source':'art/source/travelers_v3.blend','generator':'tools/art/generate_travelers_v3.py',
          'texture_resolution':[1024,1024],'textures':[str(TEX.relative_to(ROOT)).replace('\\','/')+'/'+n+'.png' for n in ['travelers_v3_albedo','travelers_v3_normal','travelers_v3_orm']],
          'license':'CC0-1.0 for newly authored geometry and textures','provenance':'Original repository-authored parametric meshes; no imported third-party or game content',
          'traveler_contract':{'origin':'PlayerCharacter capsule centre','arm_pivots':[[-.3,.4,0],[.3,.4,0]],'rig':'Original rigid gameplay anchors preserved; independent cosmetic skin with ten local axillary corrective bones driven after equipment IK by TravelerSurfacePose',
                 'attachment_nodes':['Arm_0','Arm_1','Forearm_0','Forearm_1','Wrist_0','Wrist_1','HandGrip_0','HandGrip_1','Leg_0','Leg_1','Knee_0','Knee_1','Ankle_0','Ankle_1'],
                 'wrist_local':[0,-.276,0],'hand_grip_wrist_local':[0,-.050,-.037],
                 'hand_grip_forearm_local':[0,-.326,-.037],'upper_arm_length':.285,'forearm_to_wrist_length':.276,'forearm_to_grip_length':math.sqrt(.326**2+.037**2),
                 'weapon_axis':'local -Y, socket rotation identity','previous_lod0_triangles':35614},
          'mono_contract':{'pose':'supine; closed eyes; hands over gown','head':'+Z','face':'+Y','altar_contact_y':.014,'origin':'body centre projected to altar plane'},'assets':records}
rest_positions={'SurfaceBody':[0,0,0]}
helper_centers={}
for i,side in enumerate([-1,1]):
    rest_positions['SurfaceLeg_%d'%i]=[side*.118,-.188,0]
    rest_positions['SurfaceUpper_%d'%i]=[side*.210,.405,0]
    rest_positions['SurfaceLower_%d'%i]=[side*(.210+COSMETIC_UPPER_LENGTH),.405,0]
    rest_positions['SurfaceWrist_%d'%i]=[side*(.210+COSMETIC_UPPER_LENGTH+COSMETIC_LOWER_LENGTH),.405,0]
corrective_bones={}
for i,side in enumerate([-1,1]):
    entries=[('SurfaceAxillaBody_%d'%i,'SurfaceBody',[side*.008,-.012,0],[side*.004,.075,0])]
    for view,z in [('Front',-.040),('Back',.032)]:
        for kind,base in [('Body','SurfaceBody'),('Upper','SurfaceUpper_%d'%i)]:
            entries.append(('SurfaceFold%s%s_%d'%(view,kind,i),base,[0,0,0],[0,0,z]))
    for name,base,down,up in entries:
        rest_positions[name]=list(rest_positions[base])
        corrective_bones[name]={'base':base,'side':i,'down':down,'up':up}
manifest['surface_rig_contract']={
    'version':5,'corrective_bones':corrective_bones,'binding_pose':'T','rest_positions':rest_positions,'helper_centers':helper_centers,
    'rigid_wrist_rest':{'SurfaceWrist_0':[-.300,-.161,0],'SurfaceWrist_1':[.300,-.161,0]},
    'rigid_leg_rest':{'SurfaceLeg_0':[-.118,-.188,0],'SurfaceLeg_1':[.118,-.188,0]},
    'wrist_bind_axes':{'SurfaceWrist_0':[-1,0,0],'SurfaceWrist_1':[1,0,0]},
    'centre_correction_enabled':False,
    'max_visual_stretch':1.20,
    'scope':'Cosmetic skeleton reads immutable old rigid arms and wrists. Gameplay anchors and controller unchanged.',
}
manifest['geometry_finish']={'scope':'Traveler original visual garment/limb/foot topology and cosmetic skin; original rigid gameplay joint names/transforms, grips and colliders preserved. TravelerArt gains a visual-only driver.',
    'authoring':'Original repository-authored geometry; no downloaded meshes, no AI-generated images',
    'runtime_specular_import':'art/scripts/traveler_visual_import.gd',
    'skin_specular':.24,'hair_specular':.16,
    'triangle_limits':[40000,22000,5000],
    'gpu_performance_measured':False}
(ROOT/'assets/travelers_v3_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')

# An editable, lit presentation scene lives only in the new source file. Export
# geometry keeps its zero-origin contract and never includes these studio props.
traveler.location=vec((-.65,.895,0))
mono.location=vec((.55,.62,0))
def plain_material(name,color):
    m=bpy.data.materials.new(name);m.use_nodes=True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.91
    return m
stone=plain_material('Studio limestone',(.28,.31,.29))
floor=plain_material('Studio ground',(.13,.16,.17))
def studio_box(name,p,size,material,bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1,location=vec(p))
    ob=bpy.context.object;ob.name=name;ob.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(material)
    mod=ob.modifiers.new('soft worn edge','BEVEL');mod.width=bevel;mod.segments=3
    ob.modifiers.new('weighted normals','WEIGHTED_NORMAL')
    return ob
studio_box('Presentation floor',(0,-.08,0),(200,.1,200),floor)
studio_box('Original altar plinth',(.55,.29,0),(.78,.56,2.05),stone)
studio_box('Original altar cap',(.55,.59,0),(.91,.06,2.13),stone,.018)
for x in [-.37,.37]:
    studio_box('Altar restrained channel',(.55+x,.41,0),(.025,.21,1.70),floor,.005)
def area(name,p,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=vec(p)
    ob.rotation_euler=(vec((0,.8,0))-ob.location).to_track_quat('-Z','Y').to_euler()
area('Large soft daylight',(1.8,4.0,-3.5),420,4,(1,.90,.77))
area('Cool stone fill',(-3,2.4,-1),230,3,(.73,.85,1))
area('Hair edge light',(1,3.4,3),500,3,(1,.88,.67))
world=bpy.data.worlds.new('Travelers studio atmosphere');scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.11,.15,.18,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
data=bpy.data.cameras.new('Travelers presentation camera');camera=bpy.data.objects.new('Travelers presentation camera',data)
scene.collection.objects.link(camera)
camera.location=vec((2.9,2.35,-4.4))
camera.rotation_euler=(vec((.04,.94,0))-camera.location).to_track_quat('-Z','Y').to_euler()
data.type='ORTHO';data.ortho_scale=3.5;scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=40;scene.cycles.use_denoising=False
scene.render.resolution_x=1600;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene['authoring_notes']='Original travelers. Cosmetic skin uses T bind; gameplay rigid hierarchies retained. Studio_T hand/wrap views share original mesh data and are excluded from export. Origins and dual-rig contract in manifest; metres. CPU rendering, denoising disabled for portable support.'
setup_authoring_bind_display(traveler,surface_rig)
scene['export_lod_triangles']=[r['lods'][0]['triangles'] for r in records]
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
if '--render' in sys.argv:
    scene.render.filepath=str(ROOT/'data/captures/travelers_v3_blender.png')
    bpy.ops.render.render(write_still=True)
print('TRAVELERS_V3_OK',[(r['id'],[lod['triangles'] for lod in r['lods']]) for r in records])
