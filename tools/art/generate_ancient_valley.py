"""Original Ancient Valley v2. Blender -b --python tools/art/generate_ancient_valley.py.
Reuses the repository's audited mesh primitives; deterministic, no external assets.
"""
import ast
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
# Load primitive definitions only: no v1 asset-generation side effects.
source = ast.parse((ROOT/'tools/art/generate_art.py').read_text())
keep = [n for n in source.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))]
exec(compile(ast.Module(body=keep,type_ignores=[]),'generate_art_primitives','exec'))
SEED=24017
random.seed(SEED)
for folder in ['models/ancient_valley','textures/ancient_valley','environment/ancient_valley','art/source','assets']:
    (ROOT/folder).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
PALETTE=[('grass',(.31,.37,.20)),('rock',(.40,.43,.40)),('ruin_stone',(.62,.59,.47)),('basalt',(.23,.27,.28)),('soil',(.41,.32,.22)),('sand',(.70,.64,.48)),('path',(.52,.45,.33)),('bark',(.27,.27,.22)),('leaf',(.30,.39,.20)),('dry_grass',(.61,.53,.33)),('fur',(.42,.36,.25)),('patina',(.27,.43,.39)),('dark',(.12,.16,.17)),('chalk',(.76,.71,.55)),('moss',(.25,.35,.18)),('worn_gold',(.53,.44,.25))]
TILES={n:i for i,(n,c) in enumerate(PALETTE)}
atlas=np.zeros((1024,1024,3))
for i,(name,color) in enumerate(PALETTE):
    field=texture_field(256,SEED+i,name)
    atlas[(i//4)*256:(i//4+1)*256,(i%4)*256:(i%4+1)*256]=np.array(color)[None,None,:]+field[:,:,None]
atlas_img=write_png(ROOT/'textures/ancient_valley/atlas_1k.png',atlas)
mat=bpy.data.materials.new('AncientValley_Atlas_1K');mat.use_nodes=True
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas_img
mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.9
assets=[];manifest=[]
def finish(name,obs,collision='hull',category='ruin'):
    ob=finish_asset(name,obs,folder='ancient_valley',collision=collision,category=category)
    manifest[-1]['material']='AncientValley_Atlas_1K'
    manifest[-1]['provenance']='Original geometry; tools/art/generate_ancient_valley.py'
    return ob
# Grid-compatible 4 m modules. Pivot at ground centre; Y up, -Z forward in GLB.
for broken in [False,True]:
    obs=[block('square plinth',(0,.2,0),(2,.4,2)),block('chamfered base',(0,.5,0),(1.65,.2,1.65))]
    h=3.6 if broken else 6.0
    obs.append(rings('fluted ring shaft',[.70,.62,.57,.60],[.6,1.0,h-.3,h],tile='ruin_stone',sides=16,seed=4,irregular=.06))
    if broken:
        for v in obs[-1].data.vertices:
            if v.co.z>h-.1:v.co.z+=.25*math.sin(v.co.x*5)+.16*math.cos(v.co.y*7)
    else:
        obs.extend([block('capital',(0,6.15,0),(1.7,.3,1.7)),block('abacus',(0,6.42,0),(2,.24,2))])
    for y in [.75,2.2,3.3]:obs.append(rings('collar',[.69,.69],[y,y+.12],tile='chalk',sides=16))
    finish('column_broken' if broken else 'column',obs)
finish('column_base',[block('base',(0,.18,0),(2,.36,2)),block('top',(0,.47,0),(1.55,.22,1.55))])
finish('beam_4m',[block('beam',(0,.35,0),(4,.7,.9)),block('frieze',(0,.28,-.47),(3.8,.16,.08),'chalk',.01)])
for typ in ['wall','wall_broken','wall_corner']:
    obs=[]
    for row in range(4):
        for j in range(4):
            if typ=='wall_broken' and row>1 and j+row>4:continue
            obs.append(block('ashlar',(-1.5+j,.48+row*.98,0),(.97,.94,.8),bevel=.035))
    if typ=='wall_corner':
        for row in range(4):
            for j in range(1,4):obs.append(block('return',(-1.6,.48+row*.98,j),(.8,.94,.97),bevel=.035))
    finish(typ,obs)
for typ in ['arch','door']:
    radius=2.0 if typ=='arch' else 1.2; spring=3.0
    obs=[block('pier',(s*(radius+.4),1.5,0),(.8,3,1)) for s in [-1,1]]
    for j in range(11):
        a=j*math.pi/11+.009;b=(j+1)*math.pi/11-.009
        vs=[(math.cos(t)*r,spring+math.sin(t)*r,z) for z in [-.5,.5] for r,t in [(radius,a),(radius+.8,a),(radius+.8,b),(radius,b)]]
        obs.append(mesh_object('wedge',vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'chalk' if j==5 else 'ruin_stone'))
    finish(typ,obs,collision='opening_boxes')
for name,height in [('floor',.18),('platform',.9)]:
    finish(name,[block('slab',(0,height/2,0),(4,height,4)),block('inlaid cross',(0,height+.006,0),(.12,.012,3.6),'patina',0)])
finish('stairs',[block('tread',(0,(i+1)*.15,1.75-i*.5),(4,(i+1)*.3,.52),bevel=.02) for i in range(8)],collision='stair_ramp_v2')
finish('altar',[block('plinth',(0,.2,0),(2.8,.4,1.8)),block('body',(0,.9,0),(2.1,1,1.2)),block('table',(0,1.5,0),(2.7,.2,1.7)),rings('sunken seal',[.44,.44],[1.61,1.64],tile='patina',sides=16)])
obs=[block('relief slab',(0,1.8,0),(4,3.6,.35))]
for i in range(7):
    obs.append(block('abstract reed',(-1.45+i*.48,1.7,-.2),(.12,2.4-.25*abs(i-3),.08),'chalk',.01,rot=0))
finish('relief',obs)
finish('channel',[block('bed',(0,.12,0),(4,.24,1.2)),block('edge',(0,.35,-.65),(4,.7,.22)),block('edge',(0,.35,.65),(4,.7,.22))],collision='channel_boxes')
for k in range(2):
    rng=random.Random(SEED+k)
    finish('rubble_'+str(k),[block('fallen stone',(rng.uniform(-1.8,1.8),rng.uniform(.18,.5),rng.uniform(-1.8,1.8)),(rng.uniform(.3,1.3),rng.uniform(.3,.8),rng.uniform(.3,1)),rot=rng.random()*6.28) for j in range(9+k*4)])
# 3 distinct geology families, with large silhouette variations and 48-triangle hulls.
for family,tile in [('slate','rock'),('chalk','chalk'),('basalt','basalt')]:
    for k in range(3):
        dims=[(3.8,1.5,2.8),(5.5,3.8,3.1),(8.5,6,5)][k]
        ob=rock('eroded '+family,dims,SEED+k*11+len(family),tile,subdivisions=2)
        for v in ob.data.vertices:
            if family=='slate':v.co.z=round(v.co.z/.28)*.28
            if family=='basalt':v.co.x+=v.co.z*.16
        finish(family+'_'+str(k),[ob],category='rock')
for name,width,height in [('ledge',12,3),('cliff',18,18)]:
    obs=[]
    for k in range(4):
        obs.append(rings('weathered strata',[(width/5*1.35,4.8),(width/5*1.1,4.0),(width/5*1.14,4.1),(width/5*.85,3.3),(width/5*.9,3.45),(width/5*.56,2.4),(width/5*.30,1.7)],[0,height*.24,height*.28,height*.52,height*.56,height*.78,height*(.78+.06*k)],center=((k-1.5)*width/4,0,.4*math.sin(k)),tile='rock',sides=9,seed=SEED+k,irregular=.18))
    for ob in obs:
        for v in ob.data.vertices:
            fraction=v.co.z/height
            v.co.z+=fraction**2*(1.5*math.sin(v.co.x*.83)+1.1*math.cos(v.co.y*.67))
            v.co.x+=fraction*math.sin(v.co.y*.52)*1.1
        ob.data.update();uv_project(ob,'rock')
    finish(name,obs,category='cliff')
# Arched geology retains an open passage: separate box collision, never a solid hull.
obs=[rock('pier',(5,11,6),19,loc=(s*5,0,0),subdivisions=2) for s in [-1,1]]
obs.append(rock('lintel',(12,4,6),24,loc=(0,9,0),subdivisions=2))
finish('rock_arch',obs,collision='rock_arch_boxes',category='rock')
# Vegetation deliberately opaque, shared atlas, low shadow cost.
for name,tile,count,h in [('grass_dry_v2','dry_grass',9,.85),('fern','leaf',10,.7),('reed','grass',9,1.5),('moss_patch','moss',12,.13)]:
    obs=[]
    for j in range(count):
        a=j*math.tau/count;obs.append(blade('frond',(math.cos(a)*.17,0,math.sin(a)*.17),h*(.7+random.random()*.3),.16 if name!='moss_patch' else .35,a,tile,.4))
    finish(name,obs,collision='none',category='vegetation')
for name in ['shrub_heather','shrub_thorn']:
    obs=[]
    for j in range(9):
        a=j*math.tau/9;end=(math.cos(a)*.9,random.uniform(.6,1.25),math.sin(a)*.9)
        obs.append(branch('stem',(0,0,0),end,.04,.015))
        if name=='shrub_heather':obs.append(rock('leaf',(1,.5,.8),j,'leaf',1,end))
    finish(name,obs,collision='none',category='vegetation')
for name,ht in [('tree_cypress',9),('tree_oak',7),('tree_willow',8),('tree_dead',7)]:
    obs=[branch('trunk',(0,0,0),(.4,ht*.75,.2),.5,.13,sides=10)]
    for j in range(8):
        a=j*math.tau/8;spread=1 if name=='tree_cypress' else 3.4
        end=(math.cos(a)*spread,ht*(.56+.05*j),math.sin(a)*spread)
        obs.append(branch('bough',(.15,ht*.4,0),end,.18,.045))
        if name!='tree_dead':obs.append(rock('foliage',(2 if name=='tree_cypress' else 3.8,3 if name=='tree_cypress' else 1.5,2.5),j,'leaf',1,end))
    for j in range(5):
        a=j*math.tau/5;obs.append(branch('root',(0,.2,0),(math.cos(a)*1.6,.05,math.sin(a)*1.6),.23,.03))
    finish(name,obs,collision='trunk',category='tree')
finish('roots',[branch('root',(0,.3,0),(math.cos(j)*2.5,.05,math.sin(j)*2.5),.25,.04) for j in range(6)],collision='none',category='vegetation')
# Catalogue arrangement only after exporting at local origin.
for i,(name,variants) in enumerate(assets):
    for ob in variants:ob.location=vec(((i%8)*22,0,(i//8)*27));ob.hide_viewport=not ob.name.endswith('LOD0')
bpy.context.scene.name='Ancient Valley v2 editable catalogue'
bpy.context.scene.unit_settings.system='METRIC'
bpy.context.scene['seed']=SEED
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/ancient_valley_v2.blend'),compress=True)
(ROOT/'assets/ancient_valley_manifest.json').write_text(json.dumps({'seed':SEED,'source':'art/source/ancient_valley_v2.blend','grid_metres':4,'assets':manifest},indent=2)+'\n')
print('ANCIENT_VALLEY_GENERATION_OK',len(manifest))
for a in manifest:
    p=ROOT/'environment/ancient_valley'/(a['id']+'.tscn')
    p.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://art/scripts/valley_asset.gd" id="1"]\n[node name="'+a['id']+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+a['id']+'"\ncollidable = '+str(a['collision']!='none').lower()+'\ncollision_kind = "'+a['collision']+'"\n')
