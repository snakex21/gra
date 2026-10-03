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

def export_edited_source():
    """Re-export hand edits without regenerating or overwriting the .blend."""
    import hashlib
    source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    manifest_path=ROOT/'assets/travelers_v3_manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    def hierarchy(ob):
        return [ob]+[desc for child in ob.children for desc in hierarchy(child)]
    for root_name,identifier in [('Traveler_v3','traveler'),('Mono_v3_Sleep','mono_sleep')]:
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
                if original.parent in remap:
                    cp.parent=remap[original.parent]
                    cp.matrix_local=original.matrix_local.copy()
                cp.hide_set(False);cp.hide_viewport=False;cp.hide_render=False
                if cp.type=='MESH':
                    bpy.context.view_layer.objects.active=cp
                    tri=cp.modifiers.new('Export triangles','TRIANGULATE')
                    bpy.ops.object.modifier_apply(modifier=tri.name)
                    if level:
                        dec=cp.modifiers.new('LOD reduction','DECIMATE');dec.ratio=ratio
                        bpy.ops.object.modifier_apply(modifier=dec.name)
                    cp.data.validate(verbose=False,clean_customdata=False)
            bpy.ops.object.select_all(action='DESELECT')
            for cp in copies: cp.select_set(True)
            path=OUT/(identifier+'_lod%d.glb'%level)
            bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
                export_materials='EXPORT',export_yup=True,export_normals=True,export_texcoords=True,
                export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
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

def mesh(name, verts, faces, tile):
    me = bpy.data.meshes.new(name)
    me.from_pydata([vec(v) for v in verts], [], faces)
    me.update()
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
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

FACE_PROFILE=[(.615,.043,.048,.003),(.632,.067,.067,-.006),(.653,.081,.078,-.003),
             (.678,.088,.087,0),(.710,.101,.091,.003),(.753,.116,.104,.009),
             (.790,.121,.108,.013),(.830,.118,.108,.013),(.861,.110,.104,.014),
             (.891,.079,.078,.014),(.912,.036,.036,.014),(.919,.004,.004,.014)]

def traveler_face_z(x,y):
    rx,rz,zc=[float(np.interp(y,[r[0] for r in FACE_PROFILE],[r[k] for r in FACE_PROFILE])) for k in [1,2,3]]
    sa=-math.sqrt(max(0,1-(x/max(rx,.001))**2))
    z=zc-rz*(-sa)**.64
    sculpt=.006*gaussian(x,y,0,.685,.031,.025)
    sculpt+=.011*gaussian(x,y,0,.773,.010,.031)
    sculpt+=.023*gaussian(x,y,0,.745,.015,.011)
    sculpt+=.007*gaussian(x,y,0,.721,.014,.008)
    for side in [-1,1]:
        sculpt+=.008*gaussian(x,y,side*.065,.763,.023,.023)
        sculpt+=.006*gaussian(x,y,side*.045,.817,.026,.013)
        sculpt-=.004*gaussian(x,y,side*.046,.792,.020,.010)
        sculpt+=.005*gaussian(x,y,side*.017,.742,.010,.008)
    return z-sculpt*max(0,-sa)**10

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
        rx,rz,zc=[float(np.interp(y,[r[0] for r in FACE_PROFILE],[r[k] for r in FACE_PROFILE])) for k in [1,2,3]]
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
        x=side*.045
        eye_z=traveler_face_z(x,.792)
        sclera=ellipsoid('Traveler inset sclera',(x,.792,0),(.0185,.0058,.0039),'eye_white',16,8)
        # A shallow conformal sclera follows the curvature of the cheek surface.
        for v in sclera.data.vertices:
            p=godot(v.co);v.co=vec((p.x,p.y,p.z+traveler_face_z(p.x,p.y)-.0004))
        parts.append(sclera)
        parts.append(ellipsoid('Traveler brown iris',(x,.792,eye_z-.0043),(.0057,.0054,.0006),'eye_dark',12,8))
        parts.append(ellipsoid('Traveler small eye glint',(x-.0014,.794,eye_z-.0050),(.0008,.0008,.0003),'eye_white',8,5))
        upper=[(x-.020,.791),(x-.009,.799),(x+.009,.798),(x+.020,.791)]
        lower=[(x-.020,.791),(x,.787),(x+.020,.791)]
        parts.append(facial_line('Traveler modeled upper eyelid',upper,.0021,'skin',6,4,offset=.0009))
        parts.append(facial_line('Traveler modeled lower eyelid',lower,.0016,'skin',6,4,offset=.0009))
        brow=[(x-side*.024,.817),(x,.822),(x+side*.025,.811)]
        parts.append(facial_line('Traveler fine tapered brow',brow,.0023,'hair',6,4,.25))
        parts.append(ellipsoid('Traveler nostril crease',(side*.012,.738,traveler_face_z(side*.012,.738)-.0004),(.003,.0013,.0016),'lips',10,6))
    upper=[(-.024,.704),(-.009,.707),(0,.705),(.009,.707),(.024,.704)]
    parts.append(facial_line('Traveler lip rim integrated with skin',upper,.0018,'skin',6,3,.5))
    parts.append(facial_line('Traveler lower lip soft volume',[(-.023,.701),(0,.699),(.023,.701)],.0020,'skin',6,4,.6))
    parts.append(facial_line('Traveler closed mouth crease',[(-.020,.703),(0,.702),(.020,.703)],.00075,'lips',5,3,.4,.0017))
    return parts

def traveler_hair():
    # Thin, irregular tapered clumps lie along the scalp; matte fibre response
    # replaces the old seven shiny sausage-shaped fringe tubes.
    hair_mat=mat.copy();hair_mat.name='Traveler_matte_hair_fibres'
    shader=hair_mat.node_tree.nodes.get('Principled BSDF')
    for link in list(shader.inputs['Roughness'].links): hair_mat.node_tree.links.remove(link)
    shader.inputs['Roughness'].default_value=.83
    for node in hair_mat.node_tree.nodes:
        if node.type=='NORMAL_MAP': node.inputs['Strength'].default_value=.15
    parts=[];verts=[];faces=[];nr=16;ns=40
    for j in range(nr+1):
        phi=.03+(math.pi*.90-.03)*j/nr
        for k in range(ns):
            a=math.tau*k/ns
            x=.129*math.sin(phi)*math.cos(a)
            y=.803+.125*math.cos(phi)
            z=.020+.118*math.sin(phi)*math.sin(a)
            verts.append((x,y,z))
    for j in range(nr):
        for k in range(ns):
            a=j*ns+k;b=j*ns+(k+1)%ns
            y=(verts[a][1]+verts[b][1])/2;z=(verts[a][2]+verts[b][2])/2
            if z<-.016 and y<.853+.007*math.cos(k*.8): continue
            faces.append((a,b,b+ns,a+ns))
    parts.append(mesh('Traveler natural irregular hair cap',verts,faces,'hair'))
    for i in range(14):
        a=.12+(math.pi-.24)*i/13;x=math.cos(a)*.122;z=math.sin(a)*.106+.019
        pts=[(x*.55,.915,z*.46),(x,.838,z+.004),(x*1.04,.763,z+.009),(x*.98,.696+(i%4)*.007,z)]
        parts.append(tube('Traveler flattened nape clump %02d'%i,pts,.012+(i%3)*.002,'hair',6,3,True,.22))
    for i in range(10):
        x=(i-4.5)*.022
        drift=.022+.012*math.sin(i*1.71)
        pts=[(x*.60-.014,.920-.001*(i%3),-.012),(x-.010,.883,-.090),
             (x+drift*.35,.858-(i%3)*.004,-.110),(x+drift,.840-(i%4)*.004,-.102)]
        parts.append(tube('Traveler uneven swept fringe %02d'%i,pts,.011+(i%3)*.0018,'hair',6,3,True,.20))
    for ob in parts: ob.data.materials[0]=hair_mat
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

TUNIC_PROFILE=[(-.32,.240,.165,.008),(-.25,.246,.166,.006),(-.15,.235,.155,0),
               (-.065,.199,.128,0),(.04,.215,.135,0),(.18,.236,.145,.002),(.32,.255,.146,.003),
               (.42,.251,.126,.003),(.477,.176,.089,0)]

def tunic_point(y,a):
    rx,rz,zc=[float(np.interp(y,[r[0] for r in TUNIC_PROFILE],[r[k] for r in TUNIC_PROFILE])) for k in [1,2,3]]
    lower=max(0,min(1,(-y-.06)/.22))
    crease=.011*lower*math.sin(a*7+.4)+.004*math.sin(a*11+y*17)*math.exp(-((y+.025)/.18)**2)
    pull=.005*math.sin(a*6-y*19)*math.exp(-((y-.25)/.15)**2)
    return math.cos(a)*(rx+crease+pull),zc+math.sin(a)*(rz+crease+pull)

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
    verts=[];faces=[];sides=48;rows=27
    for j in range(rows):
        y=-.32+.797*j/(rows-1)
        for i in range(sides):
            a=math.tau*i/sides
            x,z=tunic_point(y,a)
            hem=.012*math.sin(a*5+.8)*(1-j/(rows-1))**14
            verts.append((x,y+hem,z))
    for j in range(rows-1):
        for i in range(sides):
            a=j*sides+i;b=j*sides+(i+1)%sides;faces.append((a,b,b+sides,a+sides))
    faces+=[tuple(reversed(range(sides))),tuple((rows-1)*sides+i for i in range(sides))]
    return mesh('Traveler gathered tunic folds under belt',verts,faces,'bluecloth')

# Traveler: editable rigid pieces in the existing two shoulder frames.
traveler = empty('Traveler_v3')
torso=[]
torso.append(gathered_tunic())
torso.append(loft('Visible linen collar',[(.43,.105,.082,0),(.47,.102,.080,0),(.51,.090,.074,0)],'linen',28,.02))
torso.append(loft('Neck tendon',[(.48,.068,.059,.004),(.525,.061,.056,.004),(.58,.055,.054,.006),(.64,.064,.058,.008)],'skin',28))
torso.append(loft('Double leather girdle',[(-.110,.224,.151,0),(-.075,.214,.140,0),(-.053,.210,.139,0)],'leather',36))
torso.append(ellipsoid('Oval hammered buckle',(0,-.077,-.150),(.035,.022,.008),'bronze',20,10))
torso.append(ellipsoid('Buckle inset',(0,-.077,-.158),(.023,.012,.002),'leather',18,8))
torso.append(tube('Buckle tongue',[(-.023,-.077,-.161),(.020,-.077,-.161)],.0025,'bronze',6,1))
for y in [-.28,.37,.42]:
    torso += fit_tunic_embroidery([tube('Front woven border',[(-.213,y,0),(-.12,y-.007,0),(0,y,0),(.12,y-.007,0),(.213,y,0)],.0023,'thread',6,4)])
torso += fit_tunic_embroidery(embroidered_diamonds('Chest original seed motif',[-.15,-.10,-.05,0,.05,.10,.15],.393,0,'thread',.60))
torso += fit_tunic_embroidery(embroidered_diamonds('Hem original salt lozenge',[-.175,-.105,-.035,.035,.105,.175],-.246,0,'thread',.9))
# Draped short mantle with real folds and an irregular soft edge.
verts=[];faces=[];nx=18;ny=22
for j in range(ny+1):
    t=j/ny;y=.441-.91*t
    width=.270*(1-.18*math.sin(math.pi*t)+.015*t)
    for i in range(nx+1):
        s=(i/nx)*2-1
        z=.132+.065*t+.015*math.cos(s*math.pi*4.7+.7*t)*(t*.75+.20)
        z+=-.036*s*s*(1-t)**4+.018*s*s*t+.009*math.sin(s*7+t*5)*t
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
    torso.append(ellipsoid('Shoulder clasp',(side*.181,.433,-.080),(.018,.014,.006),'bronze',16,8))
    # Soft body-side gussets close the armpit seam even with the existing
    # near-180-degree climbing shoulder pose. They remain under the sleeve head.
    torso.append(ellipsoid('Tailored shoulder gusset',(side*.256,.405,0),(.052,.049,.068),'bluecloth',16,8))
torso.append(tube('Cross-body woven cord',[(-.181,.443,-.092),(-.08,.253,-.163),(.05,.056,-.149),(.18,-.096,-.099)],.014,'scarf',10,6,False,.40))
torso.append(ellipsoid('Small belt pouch',(.184,-.150,.078),(.057,.073,.041),'leather',24,12))
torso.append(tube('Pouch seam',[(.138,-.146,.106),(.160,-.210,.113),(.207,-.211,.110),(.230,-.144,.092)],.003,'thread',6,5))
join_part('Traveler_Torso',torso,traveler)
join_part('Traveler_Head',face('Traveler','skin')+hair('Traveler'),traveler)

for index,side in enumerate([-1,1]):
    arm=empty('Arm_%d'%index,(side*.3,.4,0),traveler)
    upper=[loft('Linen sleeve draping folds',[(.005,.073,.064,0),(-.027,.074,.065,0),(-.054,.072,.064,0),
           (-.084,.077,.065,.001),(-.117,.072,.060,.002),(-.150,.068,.060,0),(-.182,.066,.058,0)],'linen',28,.055,.6),
           loft('Upper arm', [(-.160,.049,.045,0),(-.205,.046,.043,.001),(-.246,.040,.037,.002),(-.302,.037,.035,0)],'skin',24)]
    upper.append(ellipsoid('Rounded sleeve head',(0,-.018,0),(.073,.054,.068),'linen',16,8))
    upper.append(ellipsoid('Soft elbow contact',(0,-.285,0),(.037,.035,.034),'skin',16,8))
    upper.append(loop('Sleeve cuff',(0,-.178,0),.070,.061,'thread',.004))
    upper += embroidered_diamonds('Sleeve stitch',[-.04,0,.04],-.150,-.063,'bluecloth',.45)
    join_part('Traveler_UpperArm_%d'%index,upper,arm)
    fore=empty('Forearm_%d'%index,(0,-.285,0),arm)
    lower=[loft('Anatomical taper and forearm flexors',[(.023,.038,.036,0),(-.035,.043,.039,-.001),
           (-.084,.047,.038,-.002),(-.135,.042,.034,-.002),(-.195,.034,.028,-.001),(-.230,.029,.025,0),(-.280,.026,.024,0)],'skin',28),
           loft('Bound wrist wrap',[(-.230,.035,.031,0),(-.250,.035,.031,0),(-.280,.031,.028,0)],'leather',24)]
    lower.append(ellipsoid('Wrist to palm tendon',(0,-.276,0),(.028,.032,.025),'skin',16,8))
    for y in [-.239,-.256,-.272]: lower.append(loop('Wrist linen stitch',(0,y,0),.036,.031,'thread',.0017))
    join_part('Traveler_Forearm_%d'%index,lower,fore)
    wrist=empty('Wrist_%d'%index,(0,-.276,0),fore)
    join_part('Traveler_Hand_%d'%index,grip_hand('Traveler gripping hand %d'%index,side),wrist)
    empty('HandGrip_%d'%index,(0,-.050,-.037),wrist)
    leg=empty('Leg_%d'%index,(side*.118,-.188,0),traveler)
    thigh=[loft('Tapered trouser thigh',[(.03,.095,.099,0),(-.05,.095,.088,0),(-.20,.076,.070,0),(-.324,.067,.061,0)],'linen',28,.025)]
    join_part('Traveler_Thigh_%d'%index,thigh,leg)
    knee=empty('Knee_%d'%index,(0,-.325,0),leg)
    shin=[loft('Wrapped calf',[(.015,.066,.061,0),(-.070,.072,.063,.002),(-.205,.047,.046,0),(-.30,.042,.043,0)],'boots',28,.015)]
    for y in [-.065,-.120,-.175,-.23]:
        shin.append(loop('Boot bound strap',(0,y,0),.071 if y>-.13 else .055,.063 if y>-.13 else .052,'leather',.005))
    join_part('Traveler_Shin_%d'%index,shin,knee)
    ankle=empty('Ankle_%d'%index,(0,-.30,0),knee)
    foot=[ellipsoid('Leather toe and instep',(0,-.025,-.060),(.068,.058,.140),'boots',28,12),
          ellipsoid('Thick worn sole',(0,-.067,-.065),(.071,.019,.144),'leather',28,8)]
    foot.append(tube('Boot toe seam',[(-.053,-.040,-.138),(0,-.043,-.191),(.053,-.040,-.138)],.0027,'thread',7,5))
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
    for child in root.children: out += children(child)
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
            if original.parent in remap:
                cp.parent=remap[original.parent]
                cp.matrix_local=original.matrix_local.copy()
            cp.hide_set(False);cp.hide_viewport=False;cp.hide_render=False
            if cp.type=='MESH':
                bpy.context.view_layer.objects.active=cp
                tri=cp.modifiers.new('Export triangles','TRIANGULATE')
                bpy.ops.object.modifier_apply(modifier=tri.name)
                if level:
                    dec=cp.modifiers.new('LOD silhouette reduction','DECIMATE');dec.ratio=ratio
                    bpy.ops.object.modifier_apply(modifier=dec.name)
                cp.data.validate(verbose=False,clean_customdata=False)
        bpy.ops.object.select_all(action='DESELECT')
        for cp in copies: cp.select_set(True)
        path=OUT/(identifier+'_lod%d.glb'%level)
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
            export_materials='EXPORT',export_yup=True,export_normals=True,
            export_texcoords=True,export_cameras=False,export_lights=False,
            export_animations=False,export_extras=True,export_image_format='AUTO')
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

records=[export_character(traveler,'traveler'),export_character(mono,'mono_sleep')]
manifest={'pack':'Travelers v3 / original interpretation','seed':SEED,'unit':'metre','up':'+Y','forward':'-Z',
          'source':'art/source/travelers_v3.blend','generator':'tools/art/generate_travelers_v3.py',
          'texture_resolution':[1024,1024],'textures':[str(TEX.relative_to(ROOT)).replace('\\','/')+'/'+n+'.png' for n in ['travelers_v3_albedo','travelers_v3_normal','travelers_v3_orm']],
          'license':'CC0-1.0 for newly authored geometry and textures','provenance':'Original repository-authored parametric meshes; no imported third-party or game content',
          'traveler_contract':{'origin':'PlayerCharacter capsule centre','arm_pivots':[[-.3,.4,0],[.3,.4,0]],'rig':'rigid part hierarchy; existing PlayerVisual controls shoulder raise and orientation',
                 'attachment_nodes':['Arm_0','Arm_1','Forearm_0','Forearm_1','Wrist_0','Wrist_1','HandGrip_0','HandGrip_1','Leg_0','Leg_1','Knee_0','Knee_1','Ankle_0','Ankle_1'],
                 'wrist_local':[0,-.276,0],'hand_grip_wrist_local':[0,-.050,-.037],
                 'hand_grip_forearm_local':[0,-.326,-.037],'upper_arm_length':.285,'forearm_to_wrist_length':.276,'forearm_to_grip_length':math.sqrt(.326**2+.037**2),
                 'weapon_axis':'local -Y, socket rotation identity','previous_lod0_triangles':35614},
          'mono_contract':{'pose':'supine; closed eyes; hands over gown','head':'+Z','face':'+Y','altar_contact_y':.014,'origin':'body centre projected to altar plane'},'assets':records}
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
scene.render.engine='CYCLES';scene.cycles.samples=40;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene['authoring_notes']='Original travelers. Export origins in manifest. Source meshes remain editable, rigid hierarchies retained; all dimensions metres.'
scene['export_lod_triangles']=[r['lods'][0]['triangles'] for r in records]
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
if '--render' in sys.argv:
    scene.render.filepath=str(ROOT/'data/captures/travelers_v3_blender.png')
    bpy.ops.render.render(write_still=True)
print('TRAVELERS_V3_OK',[(r['id'],[lod['triangles'] for lod in r['lods']]) for r in records])
