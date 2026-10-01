"""Original Saltward art kit. Run: blender -b --python tools/art/generate_art.py

No downloads, add-ons, paid tools, source-game assets, or image generation.
Blender 4.3+ / Python + NumPy bundled with Blender. All dimensions are metres.
Functions use Godot coordinates (X right, Y up, -Z forward); convert on creation.
"""
import bpy
import json
import math
import random
import hashlib
from pathlib import Path
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SEED = 7013
random.seed(SEED)
for folder in ['art/source', 'models/environment', 'models/colossus', 'textures/environment', 'assets']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for datablock in bpy.data.materials:
    bpy.data.materials.remove(datablock)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0

PALETTE = [
    ('grass', (0.34, 0.39, 0.22)), ('rock', (0.45, 0.45, 0.39)),
    ('ruin_stone', (0.65, 0.61, 0.48)), ('basalt', (0.24, 0.28, 0.27)),
    ('soil', (0.38, 0.32, 0.22)), ('sand', (0.71, 0.64, 0.46)),
    ('path', (0.51, 0.46, 0.34)), ('bark', (0.28, 0.29, 0.23)),
    ('leaf', (0.37, 0.42, 0.23)), ('dry_grass', (0.61, 0.53, 0.32)),
    ('fur', (0.43, 0.39, 0.29)), ('patina', (0.30, 0.45, 0.40)),
    ('dark', (0.13, 0.18, 0.19)), ('chalk', (0.75, 0.70, 0.56)),
    ('moss', (0.34, 0.37, 0.23)), ('worn_gold', (0.53, 0.44, 0.25)),
]
TILES = {name: i for i, (name, _) in enumerate(PALETTE)}


def texture_field(n, seed, kind):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:n, 0:n].astype(float) / n
    noise = np.zeros((n, n))
    for freq, amp in [(3, .08), (7, .04), (17, .018), (43, .009)]:
        grid = rng.uniform(-1, 1, (freq, freq))
        xx, yy = x*freq, y*freq
        xi, yi = xx.astype(int), yy.astype(int)
        fx, fy = xx-xi, yy-yi
        fx, fy = fx*fx*(3-2*fx), fy*fy*(3-2*fy)
        noise += amp * ((1-fy)*((1-fx)*grid[yi%freq,xi%freq]+fx*grid[yi%freq,(xi+1)%freq])+fy*((1-fx)*grid[(yi+1)%freq,xi%freq]+fx*grid[(yi+1)%freq,(xi+1)%freq]))
    noise += rng.normal(0, .006, (n, n))
    if kind in ['rock', 'ruin_stone', 'basalt', 'chalk']:
        noise -= .02 * (np.sin(x*math.pi*20 + np.sin(y*math.pi*4)) > .97)
    elif kind in ['fur', 'bark']:
        noise += .020 * np.sin(x*math.pi*70 + np.sin(y*math.pi*4))
    elif kind in ['grass', 'leaf', 'moss']:
        noise += rng.normal(0, .008, (n, n))
    return noise


def write_png(path, pixels):
    h, w = pixels.shape[:2]
    img = bpy.data.images.new(path.stem, width=w, height=h, alpha=True)
    rgba = np.ones((h, w, 4), dtype=np.float32)
    clipped = np.clip(pixels, 0, 1)
    if 'normal' in path.stem:
        img.colorspace_settings.name = 'Non-Color'
        rgba[:, :, :3] = clipped
    else:
        rgba[:, :, :3] = np.where(clipped <= .04045, clipped/12.92, ((clipped+.055)/1.055)**2.4)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = str(path)
    img.file_format = 'PNG'
    img.save()
    return img


atlas = np.zeros((1024, 1024, 3))
for i, (name, color) in enumerate(PALETTE):
    field = texture_field(256, SEED+i, name)
    # Interior is wrapped into a 4px gutter; UVs never cross a tile boundary.
    for c in range(3):
        atlas[(i//4)*256:(i//4+1)*256, (i%4)*256:(i%4+1)*256, c] = np.clip(color[c]+field, .035, .92)
atlas_img = write_png(ROOT/'textures/environment/saltward_atlas_albedo.png', atlas)
for name in ['grass', 'soil', 'rock', 'sand', 'path', 'ruin_stone']:
    idx = TILES[name]
    field = texture_field(512, SEED+idx, name)
    rgb = np.array(PALETTE[idx][1])[None, None, :] + field[:, :, None]
    write_png(ROOT/f'textures/environment/{name}_albedo.png', rgb)
    gy, gx = np.gradient(field)
    normal = np.stack((-gx*7, -gy*7, np.ones_like(field)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    write_png(ROOT/f'textures/environment/{name}_normal.png', normal*.5+.5)

mat = bpy.data.materials.new('Saltward_SharedAtlas')
mat.use_nodes = True
nodes = mat.node_tree.nodes
bsdf = nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value = .92
tex = nodes.new('ShaderNodeTexImage')
tex.image = atlas_img
mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])


def vec(p):
    return Vector((p[0], -p[2], p[1]))


def mesh_object(name, verts, faces, tile='rock'):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([vec(v) for v in verts], [], faces)
    mesh.update()
    # Orient closed pieces consistently before exporting to a backface-culling renderer.
    import bmesh
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj['atlas_tile'] = TILES[tile]
    obj.data.materials.append(mat)
    uv_project(obj, tile)
    return obj


def uv_project(obj, tile):
    uv = obj.data.uv_layers.new(name='UVMap') if not obj.data.uv_layers else obj.data.uv_layers[0]
    idx = TILES[tile]
    for poly in obj.data.polygons:
        axis = max(range(3), key=lambda a: abs(poly.normal[a]))
        ax = [a for a in range(3) if a != axis]
        # Face-local projection: readable texture scale and padded atlas UVs.
        coords = [obj.data.vertices[obj.data.loops[li].vertex_index].co for li in poly.loop_indices]
        lo = [min(c[a] for c in coords) for a in ax]
        hi = [max(c[a] for c in coords) for a in ax]
        for li, co in zip(poly.loop_indices, coords):
            u, v = [(co[a]-l)/max(h-l, .001) for a, l, h in zip(ax, lo, hi)]
            uv.data[li].uv = ((idx % 4 + .03 + u*.94)/4, (idx//4 + .03 + v*.94)/4)


def block(name, pos, size, tile='ruin_stone', bevel=.06, rot=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=vec(pos))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.rotation_euler.z = -rot
    if bevel:
        mod = ob.modifiers.new('Editable chipped arris', 'BEVEL')
        mod.width = min(bevel, min(size)*.20)
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.data.materials.append(mat)
    uv_project(ob, tile)
    return ob


def rings(name, radii, ys, center=(0,0,0), tile='rock', sides=12, seed=0, irregular=.0):
    rng = random.Random(seed)
    verts = []
    factors = [1+rng.uniform(-irregular, irregular) for _ in range(sides)]
    for r, y in zip(radii, ys):
        rx, rz = r if isinstance(r, tuple) else (r, r)
        for j in range(sides):
            a = j*math.tau/sides
            verts.append((center[0]+math.cos(a)*rx*factors[j], center[1]+y, center[2]+math.sin(a)*rz*factors[j]))
    faces = [tuple(reversed(range(sides))), tuple((len(ys)-1)*sides+j for j in range(sides))]
    for i in range(len(ys)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    return mesh_object(name, verts, faces, tile)


def rock(name, size, seed, tile='rock', subdivisions=3, loc=(0,0,0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1)
    ob=bpy.context.object; ob.name=name
    rng=random.Random(seed)
    for v in ob.data.vertices:
        x,y,z=v.co
        fac=1+.045*math.sin(x*5+seed)+.035*math.cos(y*4+seed*.3)
        v.co=(x*size[0]*.5*fac, y*size[2]*.5*fac, max(0, (min(z,.89)+.70)*size[1]/1.59)*fac)
    ob.location=vec(loc)
    ob.data.update()
    ob.data.materials.append(mat)
    uv_project(ob,tile)
    return ob


def branch(name, a, b, r1, r2, tile='bark', sides=7):
    av,bv=Vector(a),Vector(b)
    axis=(bv-av).normalized()
    u=axis.cross(Vector((0,0,1))).normalized()
    if u.length < .1: u=axis.cross(Vector((1,0,0))).normalized()
    v=axis.cross(u).normalized()
    verts=[]
    for p,r in [(av,r1),(bv,r2)]:
        for i in range(sides):
            verts.append(tuple(p+(math.cos(i*math.tau/sides)*u+math.sin(i*math.tau/sides)*v)*r))
    faces=[tuple(reversed(range(sides))),tuple(sides+i for i in range(sides))]
    faces += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    return mesh_object(name,verts,faces,tile)


def blade(name, base, height, width, angle, tile, bend=.2):
    u=Vector((math.cos(angle),0,math.sin(angle)))
    b=Vector(base)
    p=b+Vector((0,height*.55,0))+u*bend*.3
    t=b+Vector((0,height,0))+u*bend
    verts=[tuple(b-u*width*.5),tuple(b+u*width*.5),tuple(p+u*width*.24),tuple(p-u*width*.24),tuple(t)]
    # Opaque double-sided Godot material: no duplicate faces or alpha overdraw.
    return mesh_object(name,verts,[(0,1,2,3),(3,2,4)],tile)


assets=[]
manifest=[]


def finish_asset(name, obs, folder='environment', lod=True, collision='hull', category='environment'):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    bpy.ops.object.join()
    base=bpy.context.object; base.name=name+'_LOD0'
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    # Remove duplicate material slots from joining while preserving a single atlas.
    base.data.materials.clear();base.data.materials.append(mat)
    for p in base.data.polygons:p.material_index=0
    tri=base.modifiers.new('Runtime triangles','TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tri.name)
    base['metres']=True; base['original_design']='Saltward / generated in repository'
    base['source_seed']=SEED
    variants=[base]
    tris=[]
    for i,ratio in enumerate([1,.48,.18] if lod else [1]):
        ob=base
        if i:
            ob=base.copy();ob.data=base.data.copy();bpy.context.collection.objects.link(ob)
            ob.name=name+f'_LOD{i}';variants.append(ob)
            bpy.context.view_layer.objects.active=ob
            mod=ob.modifiers.new(f'LOD{i} reduction','DECIMATE');mod.ratio=ratio
            bpy.ops.object.modifier_apply(modifier=mod.name)
        ob.data.validate(verbose=False, clean_customdata=False)
        ob.data.update()
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
        path=ROOT/f'models/{folder}/{name}_lod{i}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
            export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,
            export_cameras=False,export_lights=False,export_animations=False)
        tris.append(sum(len(p.vertices)-2 for p in ob.data.polygons))
        ob.hide_set(i>0)
    bbox=[[v[0], v[2], -v[1]] for v in base.bound_box]
    record={'id':name,'category':category,'runtime':f'models/{folder}/{name}_lod0.glb',
            'lod_triangles':tris,'material':'Saltward_SharedAtlas','collision':collision,
            'license':'CC0-1.0','provenance':'Original deterministic procedural geometry; tools/art/generate_art.py',
            'bounds_godot':bbox}
    # Collision sources are intentionally very coarse, separate from visual geometry.
    if collision=='hull':
        import bmesh
        bm=bmesh.new()
        for vertex in base.data.vertices:bm.verts.new(vertex.co)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.001)
        result=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
        bmesh.ops.delete(bm,geom=list(set(result['geom_interior']) | set(result['geom_unused'])),context='VERTS')
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
        mesh=bpy.data.meshes.new(name+'_COL');bm.to_mesh(mesh);bm.free()
        col=bpy.data.objects.new(name+'_COL',mesh);bpy.context.collection.objects.link(col)
        bpy.context.view_layer.objects.active=col
        dec=col.modifiers.new('Collision simplification','DECIMATE');dec.ratio=min(1,48/max(1,len(mesh.polygons)))
        bpy.ops.object.modifier_apply(modifier=dec.name)
        col.data.validate(verbose=False, clean_customdata=False)
        col.data.update()
        bpy.ops.object.select_all(action='DESELECT');col.select_set(True)
        path=ROOT/f'models/{folder}/{name}_collision.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_animations=False)
        record['collision_triangles']=sum(len(p.vertices)-2 for p in col.data.polygons)
        col.hide_set(True);variants.append(col)
    assets.append((name,variants))
    manifest.append(record)
    return base


# 5 rock silhouettes + a tall fractured cliff. No per-rock materials.
for i,size in enumerate([(2.2,1.4,1.7),(1.7,2.1,1.4),(3.4,1.2,2.3),(4.8,3.4,3.8),(7.5,5.4,4.9)]):
    finish_asset(f'rock_{i+1:02d}',[rock('eroded stone',size,80+i)],category='rock')
cliff=[]
for i in range(5):
    x=(i-2)*3.8; h=[12,17,20,16,11][i]
    slab = rings('layered escarpment',[(3.5,4.3),(3.4,4.0),(2.9,3.7),(3.1,3.7),(2.65,3.2)],[0,h*.16,h*.52,h*.74,h],center=(x,0,random.uniform(-1,1)),tile='rock',sides=9,seed=92+i,irregular=.16)
    for vertex in slab.data.vertices:
        height_fraction = vertex.co.z/h
        vertex.co.z += height_fraction**2*(.7*math.sin(vertex.co.x*.93)+.65*math.cos(vertex.co.y*.7))
        vertex.co.x += height_fraction*math.sin(i*1.5)*1.1
    slab.data.update()
    uv_project(slab,'rock')
    cliff.append(slab)
finish_asset('cliff_buttress',cliff,category='cliff')

# Modular ruins. Grid 1 m; column footprint 2x2 m, wall 4 m, arch clear width 6 m.
col=[block('plinth',(0,.20,0),(2.3,.4,2.3)),block('step',(0,.53,0),(1.9,.26,1.9))]
col += [rings('tapered shaft',[.79,.76,.65,.63],[.65,1,6.7,7],tile='ruin_stone',sides=12)]
for y in [1.05,3.3,6.6]: col.append(rings('collar',[.80,.80],[y,y+.18],tile='chalk',sides=12))
col += [block('capital',(0,7.17,0),(1.9,.34,1.9)),block('abacus',(0,7.50,0),(2.2,.32,2.2))]
finish_asset('ruin_column',col,collision='hull',category='ruin')
wall=[]
for row in range(5):
    for j in range(3):
        x=(j-1)*1.3 + (.15 if row%2 else 0)
        wall.append(block('ashlar',(x,.50+row*.97,0),(1.26,.93,1.05),bevel=.045))
wall.append(block('coping',(0,5.02,0),(4.05,.23,1.25)))
finish_asset('ruin_wall',wall,category='ruin')
arch=[]
for x in [-3.75,3.75]:
    arch += [block('pier',(x,2.2,0),(1.50,4.4,1.75)),block('pier base',(x,.25,0),(1.85,.5,2)),block('spring',(x,4.25,0),(1.85,.38,2))]
for j in range(13):
    a=j*math.pi/13; b=(j+1)*math.pi/13
    # Wedge voussoirs in XY plane with tiny intentional joints.
    a+=.009;b-=.009
    v=[]
    for z in [-.85,.85]:
        for r,t in [(3,a),(4.5,a),(4.5,b),(3,b)]:v.append((math.cos(t)*r,4.4+math.sin(t)*r,z))
    arch.append(mesh_object('voussoir',v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'chalk' if j==6 else 'ruin_stone'))
finish_asset('ruin_arch',arch,collision='arch_boxes',category='ruin')
stairs=[]
for i in range(8):stairs.append(block('tread',(0,(i+1)*.17,-i*.5),(4.0,(i+1)*.34,.54),bevel=.025))
finish_asset('ruin_stairs',stairs,collision='stair_ramp',category='ruin')
rubble=[]
for i in range(13):
    a=random.uniform(0,math.tau);r=random.uniform(.2,2.5)
    rubble.append(block('fallen ashlar',(math.cos(a)*r,.25+random.uniform(0,.6),math.sin(a)*r),(random.uniform(.4,1.1),random.uniform(.3,.7),random.uniform(.4,1.0)),rot=a))
finish_asset('ruin_rubble',rubble,category='ruin')
finish_asset('road_slab',[block('flagstone',(0,.075,0),(2,.15,2),'path',.07)],collision='none',category='road')

# Opaque blade vegetation: very small meshes, no textures with alpha, no shadows.
for name,tile,height,count in [('grass_tuft','grass',.75,11),('grass_dry','dry_grass',.9,9),('grass_low','leaf',.38,7)]:
    obs=[]
    for i in range(count):
        a=random.uniform(0,math.tau)
        obs.append(blade('blade',(random.uniform(-.28,.28),0,random.uniform(-.28,.28)),height*random.uniform(.5,1.15),.1,a,tile,random.uniform(.08,.35)))
    finish_asset(name,obs,collision='none',category='vegetation')
for name,scale in [('shrub_salt',1.0),('plant_spear',.65)]:
    obs=[]
    for i in range(9):
        a=i*math.tau/9
        tip=(math.cos(a)*scale*.65,scale*random.uniform(.6,1.2),math.sin(a)*scale*.65)
        obs.append(branch('stem',(0,0,0),tip,.035,.012))
        for j in range(3):
            p=tuple(Vector(tip)*(j+1)/4)
            obs.append(blade('leaf',p,scale*.35,.18,a+1.0,'leaf',.25))
    finish_asset(name,obs,collision='none',category='vegetation')
for name,scale,seed in [('tree_windward',1.0,44),('tree_juniper',.70,57)]:
    rng=random.Random(seed)
    obs=[branch('leaning trunk',(0,0,0),(.7*scale,5.3*scale,.3*scale),.45*scale,.14*scale)]
    for i in range(9):
        a=i*math.tau/9
        start=(.3*scale,(2.5+i*.22)*scale,0)
        end=(math.cos(a)*rng.uniform(1.8,3.2)*scale+.7*scale,(4.2+rng.uniform(.0,2.0))*scale,math.sin(a)*rng.uniform(1.8,3)*scale)
        obs.append(branch('bough',start,end,.18*scale,.05*scale))
        obs.append(rock('opaque leaf cluster',(2.6*scale,1.25*scale,2.2*scale),seed+i,'leaf',subdivisions=1,loc=end))
    finish_asset(name,obs,collision='trunk',category='tree')

# Separate rigid visual parts at EXACT existing joint origins. No skeleton or skin changes.
# Match baseline b615585 PARTS, using the same box/capsule silhouettes and regions.
parts=[
 ('hips','fur',(4.2,1.6,2.6),(0,.2,0)),('spine','fur',(3.4,2.4,2.4),(0,1.1,0)),
 ('chest','stone',(5,2.8,3),(0,1.4,0)),('chest','fur',(4.4,2.9,.5),(0,1.2,1.6)),
 ('neck','fur',(.8,2.2),(0,.6,.1)),('head','stone',(2,2.2,2.2),(0,1.1,0)),
 ('head','fur',(1.9,.4,2),(0,2.3,.1)),('head','fur',(1.8,1.8,.4),(0,1.1,1.2)),
 ('upper_arm_l','fur',(.8,4.6),(0,-2,0)),('forearm_l','fur',(.7,4.4),(0,-2,0)),
 ('forearm_l','armor',(.5,2.6,1.3),(.75,-2,0)),('hand_l','stone',(1.3,1.8,1.1),(0,-.9,0)),
 ('thigh_l','fur',(1,4.4),(0,-1.9,0)),('shin_l','fur',(.85,4),(0,-1.7,0)),
 ('shin_l','armor',(1.3,2.8,.45),(0,-1.7,-.85)),('foot_l','stone',(1.7,.7,2.8),(0,-.05,-.45))]
for p in list(parts):
    if p[0].endswith('_l'): parts.append((p[0][:-2]+'_r',p[1],p[2],(-p[3][0],p[3][1],p[3][2])))
by_bone={}
for bone,kind,size,center in parts:
    obs=by_bone.setdefault(bone,[])
    tile={'fur':'fur','stone':'ruin_stone','armor':'basalt'}[kind]
    if len(size)==3:
        obs.append(block(kind,center,size,tile,.075))
        if kind=='fur':
            # Overlapping short shallow tufts, maximum 8cm from collider skin.
            sx,sy,sz=size
            for face in [-1,1]:
                for row in range(max(1,int(sy/.36))):
                    for col in range(max(1,int(sx/.32))):
                        x=center[0]-sx*.5+.16+col*.32
                        y=center[1]+sy*.5-row*.36
                        z=center[2]+face*(sz*.5+.012)
                        obs.append(mesh_object('short fur ridge',[(x-.14,y,z),(x+.14,y,z),(x+.08,y-.34,z+face*.04),(x,y-.44,z+face*.075),(x-.09,y-.32,z+face*.04)],[(0,1,2,3,4)],'fur'))
        else:
            sx,sy,sz=size
            # Narrow inset-looking seams and original salt-worn turquoise inlays.
            for x in [-sx*.28,sx*.28]:
                obs.append(block('inlay',(center[0]+x,center[1],center[2]-sz*.5-.012),(.045,sy*.65,.018),'patina',0))
    else:
        r,h=size
        rings_y=[-h*.5,-h*.5+r*.30,-h*.5+r,h*.5-r,h*.5-r*.30,h*.5]
        radii=[r*.06,r*.70,r,r,r*.70,r*.06]
        obs.append(rings('fur capsule',radii,rings_y,center,'fur',sides=16))
        for row in range(max(1,int((h-2*r)/.40))):
            yy=center[1]-h*.5+r+row*.40
            for j in range(14):
                a=j*math.tau/14
                vertices=[]
                for da,dy,dr in [(-.12,.28,.015),(.12,.28,.015),(.09,-.03,.04),(0,-.17,.08),(-.09,-.03,.04)]:
                    vertices.append((center[0]+math.cos(a+da)*(r+dr),yy+dy,center[2]+math.sin(a+da)*(r+dr)))
                obs.append(mesh_object('fur ridge',vertices,[(0,1,2,3,4)],'fur'))

# Distinct blind mask and carved rib work; no horns, weapons, insignia or copied motifs.
by_bone['head'] += [block('blind brow',(0,1.5,-1.145),(1.5,.18,.08),'basalt',.015),block('salt seam',(0,1.0,-1.15),(.13,.65,.09),'patina',.015)]
for x in [-.52,0,.52]:by_bone['head'].append(block('weather slit',(x,.38,-1.15),(.16,.28,.07),'dark',.015))
for y in [.55,1.18,1.81,2.44]:
    by_bone['chest'].append(block('chest carving',(0,y,-1.535),(4.6,.085,.045),'basalt',.015))
by_bone['chest'].append(block('heart seam',(0,1.45,-1.57),(.13,2.05,.055),'patina',.01))
for bone,obs in by_bone.items():
    finish_asset('sentinel_'+bone,obs,folder='colossus',collision='existing_segment',category='colossus')

# Editable source has two scenes: an environment catalogue and a correctly posed
# joint-reference hierarchy. These empties are NOT a replacement gameplay rig.
rest = [
 ('hips','',(0,8,0)),('spine','hips',(0,1,0)),('chest','spine',(0,2.2,0)),
 ('neck','chest',(0,2.8,0)),('head','neck',(0,1,0)),
 ('upper_arm_l','chest',(2.9,2.3,0)),('forearm_l','upper_arm_l',(0,-4.2,0)),('hand_l','forearm_l',(0,-4.2,0)),
 ('upper_arm_r','chest',(-2.9,2.3,0)),('forearm_r','upper_arm_r',(0,-4.2,0)),('hand_r','forearm_r',(0,-4.2,0)),
 ('thigh_l','hips',(1.3,-.4,0)),('shin_l','thigh_l',(0,-3.8,0)),('foot_l','shin_l',(0,-3.4,0)),
 ('thigh_r','hips',(-1.3,-.4,0)),('shin_r','thigh_r',(0,-3.8,0)),('foot_r','shin_r',(0,-3.4,0))]
source_scene=bpy.context.scene
source_scene.name='01_Environment_Catalogue'
sentinel_scene=bpy.data.scenes.new('02_Sentinel_Rest_Reference')
sentinel_scene.unit_settings.system='METRIC'
refs={}
for bone,parent,offset in rest:
    ref=bpy.data.objects.new('reference_joint_'+bone,None)
    sentinel_scene.collection.objects.link(ref)
    ref.empty_display_type='PLAIN_AXES';ref.empty_display_size=.4
    if parent:ref.parent=refs[parent]
    ref.location=vec(offset);refs[bone]=ref
for idx,(name,variants) in enumerate(assets):
    for ob in variants:
        if name.startswith('sentinel_'):
            for collection in list(ob.users_collection):collection.objects.unlink(ob)
            sentinel_scene.collection.objects.link(ob)
            ob.parent=refs[name.removeprefix('sentinel_')]
            ob.location=(0,0,0)
            ob.hide_viewport=not ob.name.endswith('LOD0')
        else:
            ob.location=vec(((idx%6)*17,0,(idx//6)*24))
            ob.hide_viewport=not ob.name.endswith('LOD0')
source_scene['pipeline']='Saltward original art kit: tools/art/generate_art.py'
source_scene['coordinates']='X right, Blender Z up; GLB exports Godot Y up, -Z forward'
source_scene['seed']=SEED
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/saltward_kit.blend'),compress=True)
(ROOT/'assets/art_manifest.json').write_text(json.dumps({'pack':'Saltward / original art prototype','seed':SEED,'source':'art/source/saltward_kit.blend','atlas_resolution':[1024,1024],'assets':manifest},indent=2)+'\n')
contract={'baseline_commit':'b6155855fa4153ab5610ec02e591b9d622e1fbf3','source':'src/colossus/greybox/greybox_humanoid.gd','source_sha256':hashlib.sha256((ROOT/'src/colossus/greybox/greybox_humanoid.gd').read_bytes()).hexdigest(),'unit':'metre','up':'+Y','forward':'-Z','left':'+X','body_height':17,'rest_joints':[{'bone':b,'parent':p,'offset':o} for b,p,o in rest],'parts':[{'bone':b,'kind':k,'size':s,'center':c} for b,k,s,c in parts]}
(ROOT/'assets/colossus_visual_contract.json').write_text(json.dumps(contract,indent=2)+'\n')
(ROOT/'environment/prefabs').mkdir(parents=True,exist_ok=True)
for a in manifest:
    if a['category']=='colossus':continue
    (ROOT/f"environment/prefabs/{a['id']}.tscn").write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://art/scripts/art_asset.gd" id="1"]\n\n[node name="'+a['id']+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+a['id']+'"\ncollidable = '+str(a['collision']!='none').lower()+'\ncollision_kind = "'+a['collision']+'"\n')
print('ART_GENERATION_OK assets='+str(len(manifest)))
