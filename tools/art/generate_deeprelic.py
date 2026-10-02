"""Deeprelic: original subterranean architecture, storage and abandoned camp kit. Local Blender only.
Full regeneration requires --regenerate to protect manual source edits.
"""
import ast, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
if (ROOT/'art/source/deeprelic.blend').exists() and '--regenerate' not in sys.argv:
    raise RuntimeError('Existing editable source protected. Use -- --regenerate deliberately.')
source=ast.parse((ROOT/'tools/art/generate_art.py').read_text())
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[]),'art_primitives','exec'))
source=ast.parse((ROOT/'tools/art/generate_saltwind.py').read_text())
helpers={'uv_project','rounded','box_col','convex_col','B','P','prism','coursing'}
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name in helpers],type_ignores=[]),'reviewed_helpers','exec'))
SEED=70231
random.seed(SEED)
for folder in ['models/deeprelic','environment/deeprelic','art/source','assets']:(ROOT/folder).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials):bpy.data.materials.remove(material)
TILES={n:i for i,n in enumerate(['grass','rock','ruin_stone','basalt','soil','sand','path','bark','leaf','dry_grass','fur','patina','dark','chalk','moss','worn_gold'])}
atlas_img=bpy.data.images.load(str(ROOT/'textures/hollowvault/atlas_1k.png'))
mat=bpy.data.materials.new('Hollowvault_Atlas_1K');mat.use_nodes=True
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas_img
mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.9
FACES=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
OBS,COLL,LOD=[],[],0
assets,manifest=[],[]



def cylinder(name, radii, ys, center=(0,0,0),tile='ruin_stone',collision=True):
    OBS.append(rings(name,radii,ys,center,tile,[20,12,8][LOD],37,.025))
    if collision:
        for i in range(len(ys)-1):
            convex_col([(center[0]+math.cos(k*math.tau/8)*r,center[1]+y,center[2]+math.sin(k*math.tau/8)*r) for r,y in [(radii[i],ys[i]),(radii[i+1],ys[i+1])] for k in range(8)])

def arch(kind):
    w,h=(3.4,5.6) if kind==0 else (2.2,4.0)
    for x in [-w-.6,w+.6]:
        B('buried footing',(x,.35,0),(2,.7,2.4))
        B('dressed jamb',(x,h/2,0),(1.2,h,1.7))
        coursing(x,h/2,0,1.2,h,1.7,7)
    if kind<2:
        n=[17,11,7][LOD]
        for i in range(n):
            a=i*math.pi/n;b=(i+1)*math.pi/n
            prism('tapered voussoir',[(math.cos(a)*w,h+math.sin(a)*w),(math.cos(b)*w,h+math.sin(b)*w),(math.cos(b)*(w+1.2),h+math.sin(b)*(w+1.2)),(math.cos(a)*(w+1.2),h+math.sin(a)*(w+1.2))],-.85,.85)
        B('keystone crest',(0,h+w+.5,-.15),(1.0,1.1,2.1),'chalk')
    else:
        B('surviving lintel',(-1.25,h+.3,0),(3.2,.9,2.0))
        OBS.append(rock('fallen lintel end',(2.5,.8,1.8),26,'ruin_stone',[3,2,1][LOD],(3.4,0,2.0)))
    if LOD<2:
        for x in [-w-.6,w+.6]:B('old bronze inlay',(x,h*.65,-.87),(.24,1.6,.06),'patina',False,.01)

def bridge(kind):
    length=10 if kind==0 else 6
    B('continuous deck',(0,.35,0),(3.6,.7,length))
    for z in [-length/2+.5,length/2-.5]:
        for x in [-1.55,1.55]:B('end pier',(x,1.25,z),(.65,2.5,.8))
    if kind==0:
        for x in [-1.6,1.6]:
            B('worn parapet',(x,1.15,0),(.42,.8,length))
            for z in [-3,0,3]:B('parapet cap',(x,1.65,z),(.7,.25,.9),'chalk')
    elif kind==1:
        for x in [-1.5,1.5]:B('low curb',(x,.85,0),(.35,.3,length))
    else:
        # Split crossing leaves a real, visible broken end, not an invisible full deck.
        for ob in list(OBS):
            if 'continuous deck' in ob.name:OBS.remove(ob);bpy.data.objects.remove(ob,do_unlink=True)
        COLL.clear()
        B('broken deck',(0,.35,-1.8),(3.6,.7,2.4))
        B('second broken deck',(0,.35,2),(3.6,.7,2))
    if LOD<2:
        for z in range(-int(length/2)+1,int(length/2)):
            if kind!=2 or abs(z)>1:B('deck joint',(0,.706,z),(3.3,.016,.04),'dark',False,0)

def pillar(kind):
    if kind==3:
        for i in range(4):B('fallen drum',(i*.9-1.5,.65,math.sin(i)*.3),(1.1,1.3,1.8),'ruin_stone',True,.09)
        return
    h=[8,4.4,2.6][kind]
    B('plinth',(0,.3,0),(2.8,.6,2.8))
    cylinder('tapered shaft',[1.0,.86,.73],[.6,h*.5,h])
    cylinder('capital',[.75,1.2,1.25],[h,h+.35,h+.65],tile='chalk')
    if kind==0:
        for x in [-.65,.65]:B('capital horn',(x,h+.9,0),(.45,.6,1.3))
    if LOD<2:
        for y in [1.0,h*.48,h*.8]:cylinder('carved collar',[1.01,1.01],[y,y+.1],collision=False)

def stairs(kind):
    n=[9,5,7][kind];width=[5.2,3.2,4][kind];rise=[.28,.22,.3][kind];run=.7
    for i in range(n):B('worn step',(0,(i+1)*rise/2,(i-(n-1)/2)*run),(width,(i+1)*rise,run+.015),collision=False)
    z0=-n*run/2;z1=n*run/2
    convex_col([(x,y,z) for x in [-width/2,width/2] for y,z in [(0,z0),(0,z1),(rise,z0),(n*rise,z1)]])
    if kind==0:
        for x in [-width/2-.3,width/2+.3]:
            prism('sloping side wall',[(z0,0),(z1,0),(z1,n*rise+.8),(z0,rise+.8)],x-.25,x+.25,axis='x')
    elif kind==2:B('upper landing',(0,n*rise-.3,z1+1.4),(width,.6,2.8))

def altar(kind):
    if kind==0:
        B('two-tier dais',(0,.2,0),(4.6,.4,3.6));B('altar foot',(0,.6,0),(3.6,.4,2.6))
        for x in [-1.2,1.2]:B('table support',(x,1.2,0),(.6,.9,1.8))
        B('offering table',(0,1.8,0),(4.1,.45,2.8),'chalk')
    elif kind==1:
        cylinder('ritual font',[1.6,1.25,1.45],[0,.55,1.6])
        # Open bowl profile: annular segments preserve the basin depression.
        n=[24,16,8][LOD]
        for i in range(n):
            a=i*math.tau/n;b=(i+1)*math.tau/n
            P('font rim',[(math.cos(t)*rr,y,math.sin(t)*rr) for y in [1.6,2.05] for rr,t in [(1.0,a),(1.0,b),(1.65,b),(1.65,a)]],'chalk',False)
        cylinder('basin interior',[1.04,1.04],[1.6,1.63],tile='patina',collision=False)
    elif kind==2:
        B('shrine foundation',(0,.25,0),(4,.5,3))
        for x in [-1.5,1.5]:B('shrine jamb',(x,2,0),(.6,3.5,1.1))
        B('shrine lintel',(0,4,0),(4,.7,1.4));B('shrine back',(0,2,.7),(3.4,3.5,.35))
        cylinder('empty offering pedestal',[.6,.5],[.5,1.6],tile='chalk')
    else:
        B('standing tablet',(0,1.9,.4),(2.1,3.8,.65));B('tablet foundation',(0,.25,0),(3,.5,2))
        if LOD<2:
            for i in range(5):B('abstract carved bar',(-.3+(i%2)*.35,1.2+i*.4,.065),(.8,.065,.04),'patina',False,0)

def storage(kind):
    if kind in [0,1]:
        w=2.1 if kind==0 else 1.4;h=1.1;d=1.1
        B('chest body',(0,h/2,0),(w,h,d),'bark')
        B('chest lid',(0,h+.12,0),(w+.1,.24,d+.08),'bark')
        for x in [-w*.32,w*.32]:
            for z in [-d/2-.015,d/2+.015]:B('oxidised strap',(x,h*.6,z),(.13,h*1.15,.06),'patina',False,.015)
            B('lid strap',(x,h+.25,0),(.13,.06,d+.1),'patina',False,0)
        B('latch',(0,h*.82,-d/2-.07),(.23,.3,.1),'worn_gold',False)
    elif kind==2:
        B('stone coffer',(0,.7,0),(3.1,1.4,1.5));B('heavy lid',(0,1.5,0),(3.35,.3,1.7),'chalk')
        coursing(0,.7,0,3.1,1.4,1.5,3)
    elif kind==3:
        for i in range(3):
            x=(i%2)*1.3-.7;y=.6+(i//2)*1.2
            B('supply crate',(x,y,0),(1.2,1.2,1.2),'bark')
            if LOD<2:
                for yy in [y-.38,y+.38]:B('crate crosspiece',(x,yy,-.63),(1.25,.13,.08),'sand',False)
    else:
        cylinder('storage jar',[.45,.72,.78,.52,.35,.39],[0,.25,.8,1.2,1.35,1.45],tile='sand')
        cylinder('jar stopper',[.4,.42],[1.45,1.53],tile='bark',collision=False)

def camp(kind):
    if kind==0:
        for i in range([12,9,6][LOD]):
            a=i*math.tau/[12,9,6][LOD]
            OBS.append(rock('cold hearth stones',(.5,.3,.45),i,'rock',[2,1,1][LOD],(math.cos(a),0,math.sin(a))))
        cylinder('cold ash',[.85,.85],[.01,.025],tile='dark',collision=False)
        for z in [-.2,.2]:B('charred remnant',(0,.12,z),(1.2,.15,.2),'dark',False)
    elif kind==1:
        B('abandoned bedroll',(0,.08,0),(1.25,.16,2.6),'dry_grass',False,.1)
        cylinder('rolled blanket',[.27,.27],[-.58,.58],tile='bark',collision=False)
        # Bedroll is a low decorative prop; no capsule obstruction.
        for ob in OBS[1:]:ob.rotation_euler.y=math.pi/2;ob.location=vec((0,.28,.95))
    elif kind==2:
        for x in [-1.3,1.3]:B('bench foot',(x,.4,0),(.2,.8,.65),'bark')
        B('weathered seat',(0,.9,0),(3.1,.2,.75),'bark')
    elif kind==3:
        for x in [-1,1]:
            for z in [-.55,.55]:B('table leg',(x,.6,z),(.18,1.2,.18),'bark')
        B('provisions table',(0,1.25,0),(2.6,.16,1.5),'bark')
        B('folded empty cloth',(0,1.35,0),(1.2,.025,.8),'sand',False,0)
    elif kind==4:
        for x in [-1.4,1.4]:B('shelter post',(x,1,0),(.16,2,.16),'bark')
        # Torn lean-to: two thick textile planes, visibly open at both ends.
        prism('slumped canvas',[(-1.6,.35),(0,2.1),(.08,2.1),(-1.5,.35)],-1.5,1.5,'dry_grass',collision=False)
        prism('second canvas slope',[(0,2.1),(1.6,.35),(1.5,.35),(-.08,2.1)],-1.5,.65,'dry_grass',collision=False)
    else:
        B('lantern plinth',(0,.2,0),(.75,.4,.75));B('lamp upright',(0,.9,0),(.18,1.2,.18),'patina')
        cylinder('unlit lamp cup',[.3,.5],[1.4,1.6],tile='worn_gold',collision=False)

SPECS=[]
for category,fn,names in [
('gates',arch,['processional_arch','narrow_arch','broken_lintel_gate']),
('bridges',bridge,['parapet_crossing_10m','low_curb_crossing_6m','broken_crossing']),
('pillars',pillar,['horned_column','short_drum_column','fractured_column','fallen_column_drums']),
('stairs',stairs,['processional_stair','utility_stair','stair_with_landing']),
('altars',altar,['offering_table','mineral_font','empty_niche_shrine','carved_memorial']),
('storage',storage,['expedition_chest','small_lockbox','stone_coffer','supply_crate_stack','sealed_storage_jar']),
('camp',camp,['cold_hearth','abandoned_bedroll','timber_bench','provisions_table','torn_lean_to','unlit_lamp'])]:
    for k,name in enumerate(names):SPECS.append((name,lambda k=k,fn=fn:fn(k),category))
PROBES={name:[([0,2,-3],[0,2,3],'clear')] for name in ['processional_arch','narrow_arch','broken_lintel_gate']}
PROBES['broken_crossing']=[([0,3,0],[0,-1,0],'clear')]
for index,(name,builder,category) in enumerate(SPECS):
    variants=[];counts=[];collision=[];bounds=[]
    for lod in range(3):
        LOD=lod;OBS=[];COLL=[];builder()
        bpy.ops.object.select_all(action='DESELECT')
        for ob in OBS:ob.select_set(True)
        bpy.context.view_layer.objects.active=OBS[0];bpy.ops.object.join()
        ob=bpy.context.object;ob.name=name+f'_LOD{lod}'
        bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        ob.data.materials.clear();ob.data.materials.append(mat)
        for poly in ob.data.polygons:poly.material_index=0
        tri=ob.modifiers.new('Explicit runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
        ob.data.validate(verbose=False,clean_customdata=False);ob.data.update()
        counts.append(len(ob.data.polygons));ob['asset_id']=name;ob['lod']=lod;ob['source_seed']=SEED
        ob['original_design']='Deeprelic original subterranean ruin and camp geometry';ob['metres']=True
        path=ROOT/f'models/deeprelic/{name}_lod{lod}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,export_cameras=False,export_lights=False,export_animations=False)
        if lod==0:collision=COLL.copy();bounds=rounded([[v[0],v[2],-v[1]] for v in ob.bound_box])
        variants.append(ob);ob.hide_set(True)
    assert counts[0]>=counts[1]>=counts[2]>0,(name,counts)
    nominal=[round(max(v[k] for v in bounds)-min(v[k] for v in bounds),3) for k in range(3)]
    record={'id':name,'category':category,'runtime':f'models/deeprelic/{name}_lod0.glb','lod_paths':[f'models/deeprelic/{name}_lod{i}.glb' for i in range(3)],'lod_triangles':counts,'lod_method':'Semantic reduction of arch voussoirs, radial sections, bevels, coursing and small detail','material':'Hollowvault_Atlas_1K','atlas':'textures/hollowvault/atlas_1k.png','collision':'compound' if collision else 'none','collision_shapes':collision,'collision_shape_count':len(collision),'collision_notes':'Simple compound boxes and convex sections, opt-in. Gate openings and broken bridge gap preserved. Small camp textiles and hearth decorative. No climbing contract.','bounds_godot':bounds,'nominal_size':nominal,'pivot':'ground-origin local metres','anchors':[{'name':'ground','position':[0,0,0]}],'license':'CC0-1.0','provenance':'Original deterministic Blender geometry; tools/art/generate_deeprelic.py','passage_probes':[{'from':a,'to':b,'expect':e} for a,b,e in PROBES.get(name,[])]}
    manifest.append(record);assets.append((name,variants))
    (ROOT/f'environment/deeprelic/{name}.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://art/scripts/deeprelic_asset.gd" id="1"]\n[node name="'+name+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+name+'"\n')
    print('DEEPRELIC_ASSET',name,counts,len(collision),flush=True)
for index,(name,variants) in enumerate(assets):
    collection=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(collection)
    for ob in variants:
        for old in list(ob.users_collection):old.objects.unlink(ob)
        collection.objects.link(ob);ob.location=vec(((index%8)*55,0,(index//8)*55))
        ob.hide_set(not ob.name.endswith('_LOD0'));ob.hide_render=not ob.name.endswith('_LOD0');ob['catalogue_offset_only']=True
import bmesh
collection=bpy.data.collections.new('COLLISION_RECIPES_DISABLED');bpy.context.scene.collection.children.link(collection)
for i,record in enumerate(manifest):
    for j,shape in enumerate(record['collision_shapes']):
        if shape['type']=='box':
            x,y,z=shape['position'];sx,sy,sz=[v/2 for v in shape['size']]
            points=[(x+dx*sx,y+dy*sy,z+dz*sz) for dx in [-1,1] for dy in [-1,1] for dz in [-1,1]]
        else:points=shape['points']
        bm=bmesh.new()
        for p in points:bm.verts.new(vec(p))
        hull=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
        bmesh.ops.delete(bm,geom=list(set(hull['geom_interior'])|set(hull['geom_unused'])),context='VERTS')
        mesh=bpy.data.meshes.new(record['id']+f'_COL_{j:02d}');bm.to_mesh(mesh);bm.free()
        proxy=bpy.data.objects.new(mesh.name,mesh);collection.objects.link(proxy);proxy.location=vec(((i%8)*55,0,(i//8)*55));proxy.hide_render=True;proxy.display_type='WIRE';proxy['collision_recipe']=json.dumps(shape,sort_keys=True)
collection.hide_viewport=True;collection.hide_render=True
scene=bpy.context.scene;scene.name='Deeprelic v7 editable catalogue';scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene['seed']=SEED;scene['license']='CC0-1.0';scene['atlas']='Original Hollowvault shared 1K atlas'
bpy.context.preferences.filepaths.save_version=0
for image in list(bpy.data.images):
    if image.users==0:bpy.data.images.remove(image)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/deeprelic.blend'),compress=True)
result={'version':7,'kit':'Deeprelic','seed':SEED,'source':'art/source/deeprelic.blend','generator':'tools/art/generate_deeprelic.py','coordinate_system':'Godot Y-up metres; -Z forward','shared_atlas':'textures/hollowvault/atlas_1k.png','assets':manifest}
(ROOT/'assets/deeprelic_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
print('DEEPRELIC_GENERATION_OK',len(manifest),[sum(a['lod_triangles'][i] for a in manifest) for i in range(3)],flush=True)
