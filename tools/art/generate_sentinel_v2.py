"""Sentinel v2 original rigid visual kit. Does not modify gameplay skeleton/physics.
Uses existing 17 joint origins, denser organic joint loops, readable textured grip fur
and smooth non-grip stone. Source catalogue is editable, not a replacement rig.
"""
import ast
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'tools/art/generate_art.py').read_text()
parsed=ast.parse(source)
exec(compile(ast.Module(body=[n for n in parsed.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[]),'art_primitives','exec'))
SEED=24018;random.seed(SEED)
for folder in ['models/sentinel_v2','textures/sentinel_v2','art/source']:(ROOT/folder).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
PALETTE=[('grass',(.31,.37,.20)),('rock',(.40,.43,.40)),('ruin_stone',(.59,.57,.48)),('basalt',(.22,.27,.29)),('soil',(.41,.32,.22)),('sand',(.70,.64,.48)),('path',(.52,.45,.33)),('bark',(.27,.27,.22)),('leaf',(.30,.39,.20)),('dry_grass',(.61,.53,.33)),('fur',(.39,.33,.22)),('patina',(.22,.43,.39)),('dark',(.10,.14,.15)),('chalk',(.74,.70,.57)),('moss',(.25,.35,.18)),('worn_gold',(.53,.44,.25))]
TILES={n:i for i,(n,c) in enumerate(PALETTE)}
atlas=np.zeros((2048,2048,3))
for i,(name,color) in enumerate(PALETTE):
 field=texture_field(512,SEED+i,'moss' if name=='fur' else name)
 if name=='fur':
  y,x=np.mgrid[0:512,0:512]/512
  clumps=np.maximum(0,np.sin(y*math.pi*39+x*math.pi*13))**3
  field-=.027*(np.sin(x*math.pi*87+np.sin(y*math.pi*17))>.55)*clumps
  field+=.014*np.sin(x*math.pi*7)*np.cos(y*math.pi*11)
 atlas[(i//4)*512:(i//4+1)*512,(i%4)*512:(i%4+1)*512]=np.array(color)[None,None,:]+field[:,:,None]*.35
atlas_img=write_png(ROOT/'textures/sentinel_v2/atlas_2k.png',atlas)
mat=bpy.data.materials.new('SentinelV2_Atlas_2K');mat.use_nodes=True
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas_img
mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.87
assets=[];manifest=[]
# Rounded tapered masses are fitted inside the original part envelopes.
def organic_mass(name,center,size,tile):
    sx,sy,sz=size;verts=[];faces=[];sides=24
    profile=[(-.5,.58),(-.43,.82),(-.28,.96),(-.05,1.0),(.2,.98),(.37,.87),(.46,.70),(.5,.42)]
    if name=='hips':profile=[(-.5,.74),(-.43,.87),(-.28,.97),(-.05,1.0),(.2,.96),(.37,.87),(.46,.82),(.5,.80)]
    if name=='spine':profile=[(-.5,.88),(-.43,.94),(-.28,.97),(-.05,.98),(.2,1.0),(.37,.99),(.46,.96),(.5,.94)]
    if name=='chest':profile=[(-.5,.68),(-.40,.79),(-.23,.9),(.0,.99),(.22,1.0),(.38,.96),(.47,.80),(.5,.55)]
    if name=='head':profile=[(-.5,.40),(-.42,.67),(-.20,.90),(.05,1.0),(.26,.98),(.42,.95),(.49,.86),(.5,.72)]
    for y,r in profile:
        for j in range(sides):
            a=j*math.tau/sides
            # Superellipse gives a broad creature mass without rectangular corners.
            exponent=.73 if name!='head' else .93
            x=math.copysign(abs(math.cos(a))**exponent,math.cos(a))*sx*.5*r
            z=math.copysign(abs(math.sin(a))**exponent,math.sin(a))*sz*.5*r
            verts.append((center[0]+x,center[1]+sy*y,center[2]+z))
    faces=[tuple(reversed(range(sides))),tuple((len(profile)-1)*sides+j for j in range(sides))]
    for i in range(len(profile)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides;faces.append((a,b,b+sides,a+sides))
    ob=mesh_object(name,verts,faces,tile)
    for poly in ob.data.polygons:poly.use_smooth=True
    return ob

def curved_band(name,y,width,height,rx,rz,tile):
    verts=[]
    for yy in [y-height/2,y+height/2]:
        for j in range(17):
            x=-width/2+j*width/16
            z=-rz*max(.03,1-abs(x/rx)**(2/.73))**(.73/2)-.075
            verts.append((x,yy,z))
    return mesh_object(name,verts,[(j,j+1,j+18,j+17) for j in range(16)],tile)

contract=json.loads((ROOT/'assets/colossus_visual_contract.json').read_text())
by_bone={}
for idx,part in enumerate(contract['parts']):
    bone=part['bone'];kind=part['kind'];size=part['size'];center=part['center']
    tile={'fur':'fur','stone':'ruin_stone','armor':'basalt'}[kind]
    obs=by_bone.setdefault(bone,[])
    rng=random.Random(SEED+idx*31)
    if len(size)==3:
        obs.append(organic_mass(bone if kind in ['stone','fur'] else kind,center,size,tile))
        if kind=='fur':
            sx,sy,sz=size
            # Broken tuft islands, varied lengths and tone, no repeated woodgrain sheets.
            for face in [-1,1]:
                for row in range(max(2,int(sy*.68/.26))):
                    for col in range(max(3,int(sx*.84/.27))):
                        if rng.random()<.27:continue
                        x=-sx*.42+col*.27+rng.uniform(-.05,.05)
                        yy=sy*.34-row*.26
                        rr=max(.35,1.0-(abs(yy)/max(sy*.5,.01))**3*.6)
                        z=face*sz*.5*rr*math.sqrt(max(.08,1-(x/(sx*.52))**2))
                        x+=center[0];y=yy+center[1];z+=center[2]
                        w=rng.uniform(.10,.18);h=rng.uniform(.19,.34)
                        obs.append(mesh_object('irregular fur clump',[(x-w,y,z),(x+w,y+.03,z),(x+w*.6,y-h*.5,z+face*.045),(x-.03,y-h,z+face*.07),(x-w*.5,y-h*.65,z+face*.03)],[(0,1,2,3,4)],'fur' if rng.random()<.86 else 'bark'))
    else:
        r,h=size
        ys=[-h*.5,-h*.5+r*.16,-h*.5+r*.38,-h*.5+r*.72,-h*.5+r,h*.5-r,h*.5-r*.72,h*.5-r*.38,h*.5-r*.16,h*.5]
        radii=[r*.06,r*.42,r*.74,r*.94,r,r,r*.94,r*.74,r*.42,r*.06]
        core=rings('organic joint loops',radii,ys,center,'fur',sides=20)
        for poly in core.data.polygons:poly.use_smooth=True
        obs.append(core)
        for row in range(max(2,int((h-2*r)/.25))):
            y=center[1]-h*.5+r+row*.25
            for j in range(17):
                if rng.random()<.20:continue
                a=(j+rng.uniform(-.22,.22))*math.tau/17
                hh=rng.uniform(.19,.36);ww=rng.uniform(.095,.16)
                v=[]
                for da,dy,dr in [(-ww,hh*.45,.012),(ww,hh*.40,.012),(ww*.6,-hh*.2,.055),(0,-hh*.55,.075),(-ww*.7,-hh*.22,.04)]:
                    v.append((center[0]+math.cos(a+da)*(r+dr),y+dy,center[2]+math.sin(a+da)*(r+dr)))
                obs.append(mesh_object('broken fur tuft',v,[(0,1,2,3,4)],'fur' if rng.random()<.88 else 'bark'))
# Broad weathered ceramic bands follow a rounded breastplate, never cabinet-like ribs.
by_bone['chest'].append(curved_band('upper ceremonial band',1.96,4.4,.20,2.50,1.5,'chalk'))
by_bone['chest'].append(curved_band('lower broken band',.89,3.9,.16,2.32,1.41,'basalt'))
# An original asymmetric, faceted saltstone face mask over the organic head shell.
vs=[(0,.08,-.87),(-.68,.48,-.91),(-.86,1.4,-.80),(-.43,2.02,-.73),(.34,2.07,-.76),(.83,1.5,-.83),(.63,.43,-.93),(0,1.2,-1.14)]
by_bone['head'].append(mesh_object('faceted mask',vs,[(i,(i+1)%7,7) for i in range(7)],'chalk'))
by_bone['head'].append(branch('weathered central seam',(0,.48,-1.01),(0,1.6,-1.13),.042,.065,'patina',sides=6))
for side in [-1,1]:
    by_bone['head'].append(branch('deep-set mask hollow',(side*.33,1.25,-1.02),(side*.60,1.36,-.96),.055,.045,'dark',sides=6))
# Optional visual fit for the newer a3ef45a gameplay foot envelope.
for side in ['l','r']:
    by_bone['foot_'+side+'_extended']=[organic_mass('foot_'+side,(0,-.05,-.85),(1.7,.7,3.6),'ruin_stone')]
editable_sources=[]
editable_collection=bpy.data.collections.new('Editable pre-triangulation sources');bpy.context.scene.collection.children.link(editable_collection)
for bone,obs in by_bone.items():
    for ob in obs:
        src=ob.copy();src.data=ob.data.copy();src.name='EDIT_'+bone+'_'+ob.name;editable_collection.objects.link(src)
        src.hide_viewport=True;src.hide_render=True;editable_sources.append((bone,src))
    finish_asset('sentinel_'+bone,obs,folder='sentinel_v2',collision='existing_segment',category='colossus')

contract=json.loads((ROOT/'assets/colossus_visual_contract.json').read_text())
refs={}
for joint in contract['rest_joints']:
 ref=bpy.data.objects.new('reference_joint_'+joint['bone'],None);bpy.context.scene.collection.objects.link(ref)
 if joint['parent']:ref.parent=refs[joint['parent']]
 ref.location=vec(joint['offset']);ref.empty_display_type='PLAIN_AXES';ref.empty_display_size=.3
 refs[joint['bone']]=ref
for bone,ob in editable_sources:ob.parent=refs[bone.removesuffix('_extended')]
for name,variants in assets:
 for ob in variants:
  ob.parent=refs[name.removeprefix('sentinel_').removesuffix('_extended')];ob.location=(0,0,0);ob.hide_viewport=not ob.name.endswith('LOD0')
bpy.context.scene.name='Sentinel v2 17m joint-reference visual source'
bpy.context.scene['not_gameplay_rig']=True
bpy.context.scene['grip_readability']='Brown ridged fur = existing fur regions; pale stone/dark smooth armor = non-grip. Visuals do not assign grip.'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/sentinel_v2.blend'),compress=True)
for a in manifest:a['provenance']='Original geometry; tools/art/generate_sentinel_v2.py';a['material']='SentinelV2_Atlas_2K'
(ROOT/'assets/sentinel_v2_manifest.json').write_text(json.dumps({'assets':[a for a in manifest if not a['id'].endswith('_extended')],'optional_foot_variants':[a for a in manifest if a['id'].endswith('_extended')],'source':'art/source/sentinel_v2.blend','texture_resolution':2048,'height_metres':17,'joint_count':17,'joint_contract':'assets/colossus_visual_contract.json','notes':['Rigid visual segments, editable source loops. No skin weights or gameplay skeleton replacement.','10 longitudinal rings x 20 sides around capsule joints before artist LOD reductions.','Grip versus non-grip color/topology follows existing gameplay regions; visual code never grants grip.']},indent=2)+'\n')
print('SENTINEL_V2_GENERATION_OK',len(manifest))
