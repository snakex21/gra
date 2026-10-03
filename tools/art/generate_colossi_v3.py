"""Original carved guardian visuals fitted to the current rigid gameplay envelopes.

Run through tools/run_local.py blender --python tools/art/generate_colossi_v3.py.
The source keeps editable rings, feather/tuft islands and ornaments. No physics,
animation or third-party geometry is exported. Each existing bone gets three LODs.
"""
from pathlib import Path
import json
import math
import random
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SEED = 330721
CONTRACT = json.loads((ROOT / "assets/colossi_v3_contracts.json").read_text())
for folder in ("models/colossi_v3", "textures/colossi_v3", "materials/colossi_v3", "art/source", "art/reports/colossi_v3"):
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.preferences.filepaths.save_version = 0

# family, stone tile, fur tile, ornament tile, unique mask/profile, crest extent
PROFILES = {
    "valus": ("humanoid", 0, 6, 10, "ox", .14),
    "gaius": ("humanoid", 2, 7, 11, "visor", .22),
    "barba": ("humanoid", 1, 6, 10, "sage", .08),
    "argus": ("humanoid", 3, 8, 11, "cyclops", .10),
    "malus": ("humanoid", 3, 8, 12, "temple", .14),
    "saru": ("humanoid", 4, 7, 10, "ape", .10),
    "quadratus": ("quadruped", 4, 6, 10, "ram", .19),
    "phaedra": ("quadruped", 1, 8, 13, "horse", .13),
    "basaran": ("quadruped", 3, 7, 12, "tortoise", .12),
    "pelagia": ("quadruped", 5, 8, 13, "amphibian", .15),
    "celosia": ("quadruped", 4, 6, 11, "lion", .12),
    "cenobia": ("quadruped", 5, 8, 12, "boar", .14),
    "hydrus": ("serpent", 5, 8, 13, "eel", .09),
    "dirge": ("serpent", 4, 7, 11, "shark", .12),
    "phalanx": ("serpent", 1, 7, 10, "whale", .10),
    "kuromori": ("reptile", 2, 8, 13, "lizard", .09),
    "avion": ("bird", 3, 8, 13, "raptor", .11),
    "devil": ("bird", 3, 8, 12, "bat", .16),
    "phoenix": ("bird", 4, 6, 11, "phoenix", .17),
    "spider": ("insect", 3, 8, 13, "spider", .07),
    "worm": ("worm", 4, 6, 11, "maw", .11),
}
COLORS = [( .45,.47,.40), (.69,.66,.55), (.34,.42,.31), (.22,.27,.29),
          (.60,.49,.33), (.34,.45,.46), (.34,.26,.18), (.47,.39,.26),
          (.21,.25,.23), (.075,.10,.105), (.63,.61,.48), (.66,.47,.23),
          (.40,.27,.23), (.32,.56,.53), (.87,.68,.25), (.43,.70,.68)]

def make_atlas():
    n=2048; pixels=np.ones((n,n,4), dtype=np.float32);normals=np.ones_like(pixels)
    yy,xx=np.mgrid[0:512,0:512]/512
    for i,color in enumerate(COLORS):
        rng=np.random.default_rng(SEED+i)
        field=rng.normal(0,.008,(512,512))
        for freq,amplitude in [(3,.07),(9,.035),(27,.017),(73,.008)]:
            grid=rng.uniform(-1,1,(freq+1,freq+1));gx=xx*freq;gy=yy*freq
            ix=gx.astype(int);iy=gy.astype(int);fx=gx-ix;fy=gy-iy
            fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
            field+=amplitude*((1-fy)*((1-fx)*grid[iy,ix]+fx*grid[iy,ix+1])+fy*((1-fx)*grid[iy+1,ix]+fx*grid[iy+1,ix+1]))
        if i in (6,7,8):
            field+=.035*np.sin(xx*math.tau*72+np.sin(yy*math.tau*9))
            field-=.02*(np.sin(xx*math.tau*31+yy*3)>.8)
        else:
            for crack in range(7):
                start=rng.uniform(.05,.85);end=min(1,start+rng.uniform(.09,.3))
                line=rng.uniform(.08,.92)+rng.uniform(-.7,.7)*(yy-.5)+.008*np.sin(yy*27+crack)
                field-=.075*((np.abs(xx-line)<.003)*(yy>start)*(yy<end))
        rgb=np.clip(np.asarray(color)[None,None,:]+field[:,:,None],0,1)
        rgb=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
        pixels[(i//4)*512:(i//4+1)*512,(i%4)*512:(i%4+1)*512,:3]=rgb
        dy,dx=np.gradient(field);normal=np.stack((-dx*5,dy*5,np.ones_like(field)),axis=-1)
        normal/=np.linalg.norm(normal,axis=-1)[:,:,None]
        normals[(i//4)*512:(i//4+1)*512,(i%4)*512:(i%4+1)*512,:3]=normal*.5+.5
    image=bpy.data.images.new("ColossiV3_carved_stone_wool_2k",width=n,height=n,alpha=True)
    image.pixels.foreach_set(pixels.ravel()); image.filepath_raw=str(ROOT/"textures/colossi_v3/atlas_2k.png")
    image.file_format="PNG";image.save()
    mat=bpy.data.materials.new("ColossiV3_shared_atlas");mat.use_nodes=True
    tex=mat.node_tree.nodes.new("ShaderNodeTexImage");tex.image=image
    bsdf=mat.node_tree.nodes.get("Principled BSDF");bsdf.inputs["Roughness"].default_value=.85
    mat.node_tree.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"])
    normal_image=bpy.data.images.new('ColossiV3_surface_normal',width=n,height=n,alpha=True)
    normal_image.colorspace_settings.name='Non-Color';normal_image.pixels.foreach_set(normals.ravel())
    normal_image.filepath_raw=str(ROOT/'textures/colossi_v3/atlas_normal.png');normal_image.file_format='PNG';normal_image.save()
    normal_tex=mat.node_tree.nodes.new('ShaderNodeTexImage');normal_tex.image=normal_image
    normal_node=mat.node_tree.nodes.new('ShaderNodeNormalMap');normal_node.inputs['Strength'].default_value=.6
    mat.node_tree.links.new(normal_tex.outputs['Color'],normal_node.inputs['Color']);mat.node_tree.links.new(normal_node.outputs['Normal'],bsdf.inputs['Normal'])
    return image,mat

IMAGE,MATERIAL=make_atlas()
(ROOT/"materials/colossi_v3/atlas.tres").write_text('''[gd_resource type="StandardMaterial3D" load_steps=3 format=3]
[ext_resource type="Texture2D" path="res://textures/colossi_v3/atlas_2k.png" id="1"]
[ext_resource type="Texture2D" path="res://textures/colossi_v3/atlas_normal.png" id="2"]
[resource]
albedo_texture = ExtResource("1")
roughness = 0.85
texture_filter = 4
normal_enabled = true
normal_texture = ExtResource("2")
normal_scale = 0.6
''')

def convert(v): return Vector((v[0],-v[2],v[1]))

class Sculpt:
    def __init__(self): self.vertices=[];self.faces=[];self.tiles=[];self.smooth=[]
    def add(self,verts,faces,tile,smooth=False):
        start=len(self.vertices);self.vertices.extend(verts)
        self.faces.extend([tuple(start+i for i in f) for f in faces]);self.tiles.extend([tile]*len(faces));self.smooth.extend([smooth]*len(faces))
    def mass(self,center,size,tile,role="limb",seed=0):
        rng=random.Random(SEED+seed); sx,sy,sz=size
        rings=10; sides=28
        if min(size)<.4 and max(size)>min(size)*6:
            # Preserve a thin climbing sheet's complete readable support envelope.
            self.bevel_box(center,size,tile,.018);return
        profile=[.56,.75,.91,.98,1,1,.98,.90,.74,.53]
        if role in ("torso","body","shell"):profile=[.72,.85,.96,1,1,1,.99,.93,.82,.65]
        if role=="head":profile=[.60,.77,.91,.99,1,1,.98,.96,.85,.72]
        vertices=[]
        for k in range(rings):
            y=(-.5+k/(rings-1))*sy; r=profile[k]
            for j in range(sides):
                a=j*math.tau/sides; exponent=.53 if role in ("torso","body","shell") else .69
                x=math.copysign(abs(math.cos(a))**exponent,math.cos(a))*sx*.5*r
                z=math.copysign(abs(math.sin(a))**exponent,math.sin(a))*sz*.5*r
                weather=1+.015*math.sin(j*2.2+k*1.3+seed)
                vertices.append((center[0]+x*weather,center[1]+y,center[2]+z*weather))
        faces=[tuple(reversed(range(sides))),tuple((rings-1)*sides+j for j in range(sides))]
        for k in range(rings-1):
            for j in range(sides):
                a=k*sides+j;b=k*sides+(j+1)%sides;faces.append((a,b,b+sides,a+sides))
        self.add(vertices,faces,tile,True)
    def bevel_box(self,at,size,tile,inset=.07):
        # Superellipse rings produce a bevelled slab with chipped corners.
        sx,sy,sz=size; sides=12; vv=[]
        for y,r in [(-.5,.88),(-.42,1),(.42,1),(.5,.88)]:
            for j in range(sides):
                a=math.tau*(j+.5)/sides
                x=math.copysign(abs(math.cos(a))**.22,math.cos(a))*sx*.5*r
                z=math.copysign(abs(math.sin(a))**.22,math.sin(a))*sz*.5*r
                vv.append((at[0]+x,at[1]+y*sy,at[2]+z))
        ff=[tuple(reversed(range(sides))),tuple(3*sides+j for j in range(sides))]
        for k in range(3):
            for j in range(sides):
                a=k*sides+j;b=k*sides+(j+1)%sides;ff.append((a,b,b+sides,a+sides))
        self.add(vv,ff,tile,False)
    def tube(self,points,radii,tile,sides=10):
        pp=[Vector(p) for p in points];vv=[]
        for i,p in enumerate(pp):
            direction=(pp[min(i+1,len(pp)-1)]-pp[max(0,i-1)]).normalized()
            right=direction.cross(Vector((0,1,0)))
            if right.length<.05:right=direction.cross(Vector((1,0,0)))
            right.normalize();up=right.cross(direction).normalized()
            for j in range(sides):
                q=p+(right*math.cos(j*math.tau/sides)+up*math.sin(j*math.tau/sides))*radii[i];vv.append(tuple(q))
        ff=[tuple(reversed(range(sides))),tuple((len(pp)-1)*sides+j for j in range(sides))]
        for i in range(len(pp)-1):
            for j in range(sides):
                a=i*sides+j;b=i*sides+(j+1)%sides;ff.append((a,b,b+sides,a+sides))
        self.add(vv,ff,tile,True)
    def panel(self,vv,tile):
        # Closed thin feathers and membranes remain visible from both sides.
        # A single downward polygon would vanish from the rider's top-down view.
        normal=(Vector(vv[1])-Vector(vv[0])).cross(Vector(vv[2])-Vector(vv[0])).normalized()
        front=[tuple(Vector(v)+normal*.008) for v in vv]
        back=[tuple(Vector(v)-normal*.008) for v in vv]
        n=len(vv);faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
        for j in range(n):faces.append((j,(j+1)%n,(j+1)%n+n,j+n))
        self.add(front+back,faces,tile,False)
    def fur(self,at,size,tile,seed):
        rng=random.Random(SEED+seed);sx,sy,sz=size
        # Scattered solid tapered locks on every broad visible face, not flat cards.
        count=min(220,max(35,int((sx*sy+sy*sz+sz*sx)*6)))
        for k in range(count):
            axis=k%3;sign=1 if k%2 else -1
            q=list(at);q[axis]+=sign*size[axis]*.496
            others=[a for a in range(3) if a!=axis]
            q[others[0]]+=rng.uniform(-.43,.43)*size[others[0]]
            q[others[1]]+=rng.uniform(-.42,.42)*size[others[1]]
            w=min(.16,max(.035,min(size)*.10));h=rng.uniform(.12,.25)*min(1.4,max(size))
            tip=q.copy();tip[axis]+=sign*min(.075,min(size)*.08);tip[2 if axis==1 else 1]-=h
            vv=[]
            for dx,dy in [(-w,0),(0,w),(w,0),(0,-w)]:
                v=q.copy();v[others[0]]+=dx;v[others[1]]+=dy;vv.append(v)
            vv.append(tip);self.add(vv,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],tile,False)
    def object(self,name):
        mesh=bpy.data.meshes.new(name);mesh.from_pydata([convert(v) for v in self.vertices],[],self.faces);mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        mesh.materials.append(MATERIAL)
        uv=mesh.uv_layers.new(name="CarvedAtlas")
        for p,tile,smooth in zip(mesh.polygons,self.tiles,self.smooth):
            p.use_smooth=smooth
            axis=max(range(3),key=lambda a:abs(p.normal[a]));other=[a for a in range(3) if a!=axis]
            for li in p.loop_indices:
                v=mesh.vertices[mesh.loops[li].vertex_index].co
                u=(v[other[0]]*.37)%1;w=(v[other[1]]*.37)%1
                uv.data[li].uv=((tile%4+.035+u*.93)/4,(tile//4+.035+w*.93)/4)
        ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
        return ob

def role_for(bone,part):
    s=part['size'];at=part['at']
    if "wing" in bone:return "wing"
    if "head" in bone or bone=="crown":return "head"
    if bone=="body" and at[2]<-1.9 and s[2]<2:return "head"
    if "foot" in bone or "hand" in bone:return "foot"
    if "leg" in bone or "arm" in bone or "thigh" in bone or "shin" in bone or bone.endswith(("_up","_low")):return "limb"
    if bone.startswith("s") and bone[1:].isdigit():return "serpent"
    if bone in ("body","torso","back","chest","body0","body1","body2","base"):return "torso"
    if "sword" in bone:return "weapon"
    return "body"

def ornament(sc,at,size,tile,variant):
    sx,sy,sz=size; x,y,z=at
    if min(size)<.4:return
    # Carved shoulder/torso bands and incomplete chevrons follow the curved surface.
    for row in [-.23,.23]:
        pts=[(x+sx*u,y+sy*row,z-sz*(.49-.04*abs(u)*2)) for u in [-.35,-.18,0,.18,.35]]
        sc.tube(pts,[min(.055,sy*.025)]*5,tile,6)
    for side in [-1,1]:
        sc.tube([(x+sx*side*.29,y-sy*.1,z-sz*.493),(x+sx*side*.17,y+sy*.04,z-sz*.50),(x+sx*side*.29,y+sy*.17,z-sz*.493)], [min(.043,sy*.018)]*3,tile,6)

def head_details(sc,at,size,profile,front_override=None,top_override=None):
    family,stone,fur,accent,mask,crest=profile; sx,sy,sz=size;x,y,z=at
    front=z-sz*.50 if front_override is None else front_override
    if mask=='maw':
        top=y+sy*.49 if top_override is None else top_override
        sc.mass((x,top,z),(sx*.65,sy*.025,sz*.65),9,'body')
        for j in range(18):
            a=j*math.tau/18
            sc.tube([(x+math.cos(a)*sx*.43,top-.05,z+math.sin(a)*sz*.43),(x+math.cos(a)*sx*.29,top+.13,z+math.sin(a)*sz*.29)],[min(sx,sz)*.04,.008],accent,9)
        return
    # A physically broad mask changes cheek, brow, jaw and crown, not just a badge.
    eye_y=y+sy*.10
    if mask=="cyclops":
        sc.mass((x,y+sy*.12,front-.02),(sx*.64,sy*.30,sz*.12),9,"head")
        sc.mass((x,y+sy*.12,front-.08),(sx*.24,sy*.08,sz*.035),15,"head")
    else:
        for side in [-1,1]:
            sc.mass((x+side*sx*.22,eye_y,front-.014),(sx*.22,sy*.15,sz*.10),9,"head")
            sc.mass((x+side*sx*.23,eye_y,front-.052),(sx*.09,sy*.05,sz*.035),14 if mask in ("ram","shark","lion","phoenix") else 15,"head")
            sc.tube([(x+side*sx*.08,y+sy*.26,front-.02),(x+side*sx*.30,y+sy*.22,front-.03),(x+side*sx*.42,y+sy*.11,front+.01)],[sy*.05,sy*.065,sy*.03],accent,8)
    sc.mass((x,y-sy*.2,front+sz*.04),(sx*.58,sy*.35,sz*.17),stone,"head")
    sc.tube([(x,y-sy*.28,front-.04),(x,y+sy*.08,front-.08),(x,y+sy*.35,front+.03)],[sx*.026,sx*.040,sx*.014],accent,8)
    if mask in ("ox","ram","tortoise","amphibian","bat","boar"):
        for side in [-1,1]:
            if mask=="ram":
                pts=[(x+side*sx*.38,y+sy*.30,z),(x+side*sx*.53,y+sy*.39,z-sz*.1),(x+side*sx*.55,y+sy*.05,z-sz*.22),(x+side*sx*.37,y-sy*.05,z-sz*.30)]
            elif mask=="boar":
                pts=[(x+side*sx*.32,y-sy*.28,front),(x+side*sx*.45,y-sy*.06,front-sz*.06),(x+side*sx*.42,y+sy*.10,front)]
            else:
                pts=[(x+side*sx*.33,y+sy*.25,z),(x+side*sx*.50,y+sy*.50,z),(x+side*sx*(.65+crest),y+sy*(.70+crest),z-sz*.05)]
            sc.tube(pts,[sx*.10,sx*.07,sx*.006] if len(pts)==3 else [sx*.12,sx*.09,sx*.05,sx*.008],accent,12)
    if mask in ("sage","ape","lion"):
        for j in range(11):
            xx=x+(j-5)*sx*.062; length=(.23 if mask=="sage" else .12)*sy*(1+.2*math.cos(j))
            sc.tube([(xx,y-sy*.22,front+.03),(xx,y-sy*.38,front+.02),(xx,y-sy*.45-length,front+.09)],[sx*.047,sx*.035,.005],fur,8)
    if mask in ("raptor","phoenix","horse","shark","eel"):
        sc.tube([(x,y-sy*.06,front+.12),(x,y-sy*.15,front-sz*.09),(x,y-sy*.25,front-sz*.18)],[sx*.14,sx*.10,.004],accent,10)
    if mask in ("visor","temple","phoenix","horse"):
        sc.tube([(x,y+sy*.31,z),(x,y+sy*.5,z),(x,y+sy*(.5+crest),z-sz*.08)],[sx*.18,sx*.10,.009],accent,10)

def wing(sc,part,profile,seed):
    at=part['at'];sx,sy,sz=part['size'];x,y,z=at
    family,stone,fur,accent,mask,crest=profile
    # Broad overlapping rigid feathers/membrane ribs follow each existing wing bone.
    if mask in ("bat","whale"):
        origin=(x-sx*.48 if x>0 else x+sx*.48,y,z-sz*.35)
        ribs=[]
        for j in range(6):
            u=-.48+j*.96/5;end=(x+sx*u,y+sy*.2,z+sz*(.40 if j%2==0 else .25))
            sc.tube([origin,(x+sx*u,y+sy*.4,z-sz*.44),end],[min(.085,sx*.02),min(.055,sx*.014),.008],accent,8)
            ribs.append(end)
        for j in range(5):
            middle=((ribs[j][0]+ribs[j+1][0])/2,y-sy*.1,z+sz*.12)
            sc.panel([origin,ribs[j],middle,ribs[j+1]],stone)
    else:
        sc.tube([(x-sx*.48,y,z-sz*.35),(x,y,z-sz*.42),(x+sx*.48,y,z-sz*.28)],[max(.04,sy*.4)]*3,stone,12)
        count=max(8,int(sx*2.6))
        for j in range(count):
            xx=x+sx*(-.48+j/max(1,count-1)); width=sx/count*.62
            back=z+sz*(.43+.05*math.sin(j*1.4+seed))
            sc.panel([(xx-width*.35,y+sy*.34,z-sz*.46),(xx+width*.35,y+sy*.34,z-sz*.46),(xx+width,y+sy*.18,z+sz*.15),(xx+width*.65,y+sy*.12,back-.10),(xx,y+sy*.09,back),(xx-width*.65,y+sy*.12,back-.10),(xx-width,y+sy*.18,z+sz*.15)],fur if j%4 else accent)
            sc.tube([(xx,y+sy*.37,z-sz*.4),(xx,y+sy*.23,back-.08)],[.018,.007],accent,5)

def build_segment(kind,segment):
    profile=PROFILES[kind];family,stone,fur,accent,mask,crest=profile
    sc=Sculpt();bone=segment['bone'];main=None
    for index,part in enumerate(segment['parts']):
        at=part['at'];size=part['size'];role=role_for(bone,part)
        tile=fur if part['kind']==0 else accent if part['kind']==2 else stone
        if kind=='pelagia' and size[0]<1.4 and size[1]<.7 and size[2]<1.4:
            tile=10  # Existing bow control teeth remain conspicuously pale.
        seed=sum(ord(ch) for ch in kind+bone)+index*71
        if role=='wing':wing(sc,part,profile,seed);continue
        if role=='weapon':sc.bevel_box(at,size,tile);ornament(sc,at,size,accent,seed);continue
        sc.mass(at,size,tile,role,seed)
        if part['kind']==0:sc.fur(at,size,fur,seed)
        elif max(size)>.8:ornament(sc,at,size,accent,seed)
        if role=='head':
            priority=(100000 if part['kind']!=0 else 0)+math.prod(size)
            if main is None or priority>main[0]:main=(priority,at,size)
        if bone=='back' and kind=='pelagia' and at[2]<-5 and size[0]>3:
            main=(100000+math.prod(size),at,size)
        if family in ('serpent','reptile') and role in ('serpent','torso') and part['kind']!=0:
            sx,sy,sz=size;x,y,z=at
            for j in range(7):
                zz=z+sz*(-.40+j*.8/6)
                sc.tube([(x-sx*.45,y+sy*.24,zz),(x,y+sy*.5,zz),(x+sx*.45,y+sy*.24,zz)],[min(.065,sy*.04)]*3,accent,7)
        if family=='insect' and role=='limb':
            sx,sy,sz=size;x,y,z=at
            for zz in [-.3,0,.3]:sc.mass((x,y,z+sz*zz),(sx*.95,sy*1.02,min(sz*.15,sy*1.5)),accent,'limb',seed)
    if main:
        front_override=min(p['at'][2]-p['size'][2]*.5 for p in segment['parts'])-.025 if mask=='sage' else None
        top_override=max(p['at'][1]+p['size'][1]*.5 for p in segment['parts'])+.035 if mask=='maw' else None
        head_details(sc,main[1],main[2],profile,front_override,top_override)
    # Distinct carapaces and visible anatomy inside the same fight envelopes.
    if segment['parts'] and bone in ('body','back','body0','base'):
        p=max(segment['parts'],key=lambda p:math.prod(p['size']));sx,sy,sz=p['size'];x,y,z=p['at']
        if mask=='tortoise':
            for j in range(3):
                sc.mass((x,y+sy*.3,z+sz*(j-1)*.25),(sx*.88,sy*.36,sz*.34),stone,'shell',j)
                sc.tube([(x-sx*.32,y+sy*.4,z+sz*(j-1)*.25),(x,y+sy*.5,z+sz*(j-1)*.25),(x+sx*.32,y+sy*.4,z+sz*(j-1)*.25)],[sy*.025]*3,accent)
        if mask=='spider':
            for j in range(3):sc.mass((x,y,z+sz*(j-1)*.26),(sx*(.81 if j==0 else .9),sy*.98,sz*.44),stone,'shell',j)
            for j in range(6):sc.mass((x+sx*(j-2.5)*.10,y+sy*.05,z-sz*.49),(sx*.075,sy*.15,sz*.035),15,'head')
        if mask in ('lion','boar'):
            # Separate quadruped silhouettes despite sharing the paired gameplay box.
            for side in [-1,1]:
                sc.mass((x+side*sx*.42,y+sy*.0,z-sz*.30),(sx*.26,sy*.95,sz*.32),accent,'shell')
            if mask=='lion':sc.fur((x,y,z-sz*.35),(sx*.93,sy*.94,sz*.22),fur,77)
        if mask=='maw':
            for j in range(18):
                a=j*math.tau/18;sc.tube([(x+math.cos(a)*sx*.38,y+sy*.48,z+math.sin(a)*sz*.38),(x+math.cos(a)*sx*.27,y+sy*.51,z+math.sin(a)*sz*.27)],[min(sx,sz)*.035,.005],accent,8)
    return sc

manifest=[];totals={};source_refs={}

def export_segment(kind,segment,sc,asset_id,collection,root,variant='base'):
    base=sc.object(asset_id+'_EDITABLE')
    for cc in list(base.users_collection):cc.objects.unlink(base)
    collection.objects.link(base)
    basis=Matrix(segment['basis']).transposed();C=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
    pose=(C@basis@C.inverted()).to_4x4();pose.translation=convert(segment['at'])
    source=base.copy();source.data=base.data.copy();collection.objects.link(source)
    source.name=asset_id+'_SCULPT_RINGS';source.parent=root;source.matrix_local=pose
    source.hide_render=True;source.hide_viewport=True
    base.name=asset_id+'_LOD0';bpy.context.view_layer.objects.active=base;base.select_set(True)
    tri=base.modifiers.new('Export triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
    lods=[]
    for level,ratio in enumerate((1,.42,.15)):
        ob=base
        if level:
            ob=base.copy();ob.data=base.data.copy();collection.objects.link(ob);ob.name=asset_id+f'_LOD{level}'
            bpy.context.view_layer.objects.active=ob
            dec=ob.modifiers.new('Preserve silhouette LOD','DECIMATE');dec.ratio=ratio;bpy.ops.object.modifier_apply(modifier=dec.name)
        ob.data.validate(verbose=False,clean_customdata=False);ob.data.update()
        bpy.ops.object.select_all(action='DESELECT');ob.hide_set(False);ob.hide_render=False;ob.hide_viewport=False;ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(ROOT/f'models/colossi_v3/{asset_id}_lod{level}.glb'),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,export_animations=False,export_cameras=False,export_lights=False)
        triangles=sum(len(poly.vertices)-2 for poly in ob.data.polygons);lods.append(triangles);totals[kind][level]+=triangles
        ob.parent=root;ob.matrix_local=pose;ob.hide_render=level>0 or variant=='grip';ob.hide_viewport=level>0 or variant=='grip'
    bounds=[[v[0],v[2],-v[1]] for v in base.bound_box]
    manifest.append({'id':asset_id,'kind':kind,'bone':segment['bone'],'variant':variant,'lod_triangles':lods,'bounds_godot':bounds,'collision':'none','material':'materials/colossi_v3/atlas.tres'})

for kind,contract in CONTRACT.items():
    collection=bpy.data.collections.new(kind.upper()+" — editable rigid sculptures")
    bpy.context.scene.collection.children.link(collection)
    root=bpy.data.objects.new(kind.upper()+"_rig_reference",None);collection.objects.link(root)
    root['family']=PROFILES[kind][0];root['mask']=PROFILES[kind][4];root['visual_only']=True
    source_refs[kind]=root;totals[kind]=[0,0,0]
    for segment in contract['segments']:
        if not segment['parts']:continue
        asset_id=kind+'_'+segment['bone'].replace('-','m')
        export_segment(kind,segment,build_segment(kind,segment),asset_id,collection,root)
        # New wool is shown only after the game's existing physical patch unlocks.
        # This covers paired armour backs, Spider's lowered route and bat/phoenix backs.
        missing=[]
        for patch in segment['patches']:
            represented=any(p['kind']==0 and sum((p['at'][a]-patch['at'][a])**2+(p['size'][a]-patch['size'][a])**2 for a in range(3))<.001 for p in segment['parts'])
            if not represented:missing.append(patch)
        if missing:
            sc=Sculpt()
            for index,p in enumerate(missing):
                sc.mass(p['at'],p['size'],PROFILES[kind][2],'body',index)
                sc.fur(p['at'],p['size'],PROFILES[kind][2],index+19)
            export_segment(kind,segment,sc,asset_id+'_grip',collection,root,'grip')
            manifest[-1]['patches']=missing
    print('V3_SCULPT_COMPLETE',kind,totals[kind])

# Organised family gallery in the source, with no substitute gameplay rig.
for row,family in enumerate(('humanoid','quadruped','serpent','bird','reptile','insect','worm')):
    for col,kind in enumerate(k for k in CONTRACT if PROFILES[k][0]==family):
        source_refs[kind].location=convert((col*42,row*0,row*80))
bpy.context.scene['provenance']='Original sculptures built in Blender from the project-owned rigid envelopes; no downloaded geometry.'
bpy.context.scene['rig_contract']='assets/colossi_v3_contracts.json; each GLB is local to one existing BodySegment.'
bpy.context.scene['readability']='Rough wool islands follow existing climb patches; smooth stone/metal do not grant grip.'
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/colossi_v3.blend'),compress=True)
(ROOT/'art/source/colossi_v3.blend1').unlink(missing_ok=True)
report={'source':'art/source/colossi_v3.blend','generator':'tools/art/generate_colossi_v3.py','license':'CC0-1.0','seed':SEED,'profiles':{k:{'family':p[0],'mask':p[4],'stone_tile':p[1],'fur_tile':p[2],'accent_tile':p[3],'lod_triangles':totals[k]} for k,p in PROFILES.items()},'assets':manifest,'texture_resolution':2048,'exported_collision_nodes':0,'lod_ratios':[1,.42,.15],'notes':['Original rigid visual sculptures. No gameplay changes, skin weights, imported protected models or replacement collision.','Twenty encounters, twenty-one physical bodies: Celosia and Cenobia get distinct lion/boar profiles.','Editable ring and tuft topology retained alongside three explicit mesh LODs.']}
(ROOT/'assets/colossi_v3_manifest.json').write_text(json.dumps(report,indent=2)+'\n')
(ROOT/'art/reports/colossi_v3/geometry.json').write_text(json.dumps({'totals':totals,'asset_count':len(manifest),'export_count':len(manifest)*3},indent=2)+'\n')
print('COLLOSSI_V3_GENERATION_OK',len(manifest),'segments',sum(t[0] for t in totals.values()),'LOD0 triangles')
