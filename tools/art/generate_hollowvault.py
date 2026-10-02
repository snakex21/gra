"""Hollowvault, original wetland root and drowned-ruin kit. Local Blender only.
Full regeneration requires --regenerate to protect manual source edits.
"""
import ast, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
if (ROOT/'art/source/hollowvault.blend').exists() and '--regenerate' not in sys.argv:
    raise RuntimeError('Existing editable source protected. Use -- --regenerate deliberately.')
source=ast.parse((ROOT/'tools/art/generate_art.py').read_text())
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[]),'art_primitives','exec'))
source=ast.parse((ROOT/'tools/art/generate_saltwind.py').read_text())
helpers={'uv_project','rounded','box_col','convex_col','B','P','prism','coursing'}
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name in helpers],type_ignores=[]),'reviewed_helpers','exec'))
SEED=69173
random.seed(SEED)
for folder in ['models/hollowvault','environment/hollowvault','art/source','assets','textures/hollowvault']:(ROOT/folder).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials):bpy.data.materials.remove(material)
TILES={n:i for i,n in enumerate(['grass','rock','ruin_stone','basalt','soil','sand','path','bark','leaf','dry_grass','fur','patina','dark','chalk','moss','worn_gold'])}
palette=[(.29,.35,.20),(.34,.38,.40),(.51,.48,.39),(.25,.29,.27),(.25,.23,.17),(.43,.43,.33),(.38,.35,.26),(.27,.25,.18),(.29,.36,.22),(.41,.43,.25),(.32,.32,.24),(.29,.46,.47),(.12,.17,.15),(.70,.64,.49),(.34,.42,.24),(.48,.43,.26)]
atlas=np.zeros((1024,1024,3))
for i,color in enumerate(palette):
    field=texture_field(256,SEED+i,list(TILES)[i])*.24
    yy,xx=np.mgrid[:256,:256]/256
    if i==7:field+=.022*np.sin(xx*math.tau*19+np.sin(yy*math.tau*3))
    if i==14:field+=.018*np.sin(xx*math.tau*7)*np.cos(yy*math.tau*9)
    atlas[(i//4)*256:(i//4+1)*256,(i%4)*256:(i%4+1)*256]=np.array(color)[None,None,:]+field[:,:,None]
atlas_img=write_png(ROOT/'textures/hollowvault/atlas_1k.png',atlas)
for name,color in [('peat',(.23,.24,.17)),('moss',(.32,.39,.23))]:
    field=texture_field(1024,SEED+len(name),'soil')*.8
    write_png(ROOT/f'textures/hollowvault/{name}_albedo.png',np.array(color)[None,None,:]+field[:,:,None])
    gx=(np.roll(field,-1,1)-np.roll(field,1,1))*.5;gy=(np.roll(field,-1,0)-np.roll(field,1,0))*.5
    normal=np.stack((-gx*8,-gy*8,np.ones_like(field)),axis=-1);normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    write_png(ROOT/f'textures/hollowvault/{name}_normal.png',normal*.5+.5)
mat=bpy.data.materials.new('Hollowvault_Atlas_1K');mat.use_nodes=True
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas_img
mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.9
FACES=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
OBS,COLL,LOD=[],[],0
assets,manifest=[],[]


def surface_shell(name, verts, faces, tile='rock', thickness=1.2):
    # Author inner-facing surface. A solidify modifier builds outer skin and rims.
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([vec(p) for p in verts],[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    mod=ob.modifiers.new('Solid rock thickness outward','SOLIDIFY');mod.thickness=-thickness;mod.offset=1
    bpy.ops.object.modifier_apply(modifier=mod.name);uv_project(ob,tile);OBS.append(ob)
    ob.select_set(False)
    # Separate coarse convex surface patches, not a hull sealing the chamber.
    if LOD==0:
        for face in faces:
            ps=[Vector(verts[i]) for i in face]
            normal=(ps[1]-ps[0]).cross(ps[2]-ps[0]).normalized()
            convex_col([tuple(p) for p in ps]+[tuple(p-normal*thickness) for p in ps])

def dome(small=False):
    rx,rz,h=(12,15,11) if small else (22,28,20)
    n=[48,32,24][LOD];m=[10,7,5][LOD];verts=[]
    # Fixed portal half-angle preserves 5.7m/10.6m lower openings across LODs.
    # All upper rings are complete; welded single apex closes the roof.
    for j in range(m+1):
        angle=max(0,(j-1)/(m-1))*math.pi/2*.91
        y=0 if j==0 else 6+h*math.sin(angle)
        for k in range(n):
            a=k*math.tau/n
            relief=1+.045*math.sin(a*7+angle*3)*math.sin(angle*2)
            verts.append((rx*math.cos(angle)*math.cos(a)*relief,y+(0 if j<2 else .65*math.sin(a*5+angle*4)*math.sin(angle*2)),rz*math.cos(angle)*math.sin(a)*relief))
    faces=[]
    for j in range(m):
        for k in range(n):
            a=(k+.5)*math.tau/n
            if j==0 and abs(math.cos(a))<.24:continue
            # Winding inward.
            faces.append((j*n+k,(j+1)*n+k,(j+1)*n+(k+1)%n,j*n+(k+1)%n))
    tip=len(verts);verts.append((0,6+h,0))
    for k in range(n):faces.append((m*n+k,tip,m*n+(k+1)%n))
    surface_shell('continuous enclosed mineral dome',verts,[tuple(reversed(f)) for f in faces],thickness=1.4)
    # Foundation is deliberately wider than the interior, so no floor seam.
    OBS.append(rings('cave floor',[(rx+1,rz+1),(rx+1,rz+1)],[-.7,0],tile='soil',sides=n))
    convex_col([(math.cos(k*math.tau/16)*(rx+1),y,math.sin(k*math.tau/16)*(rz+1)) for y in [-.7,0] for k in range(16)])

def tunnel(kind='straight'):
    n=[20,14,10][LOD];stages=[8,5,3][LOD];length=12
    verts=[]
    for j in range(stages+1):
        t=j/stages;z=-6+t*length
        cx=3*math.sin(t*math.pi/2) if kind=='bend' else 0
        base=t*2 if kind=='ramp' else 0
        for k in range(n+1):
            a=k*math.pi/n
            verts.append((cx+5.6*math.cos(a),base+6*math.sin(a),z))
    faces=[]
    for j in range(stages):
        for k in range(n):a=j*(n+1)+k;faces.append((a+n+1,a+n+2,a+1,a))
    surface_shell('arched passage with continuous ceiling',verts,faces,thickness=1.0)
    for j in range(stages):
        t=(j+.5)/stages;cx=3*math.sin(t*math.pi/2) if kind=='bend' else 0
        base=t*2 if kind=='ramp' else 0
        B('passage floor',(cx,base-.25,-6+t*12),(11.3,.5,12/stages+.05),'soil',True,0)

def spike(name,h=5,r=1,down=False,seed=1,loc=(0,0,0),tile='chalk'):
    n=[16,10,6][LOD];steps=[8,5,3][LOD]
    radii=[];ys=[]
    for j in range(steps+1):
        t=j/steps;radii.append(max(.025,r*(1-t)**1.4*(1+.1*math.sin(t*17+seed))))
        ys.append(h*(1-t) if down else h*t)
    OBS.append(rings(name,radii,ys,loc,tile,n,seed,.17))
    if not down:convex_col([(loc[0]+math.cos(k*math.tau/6)*r,loc[1],loc[2]+math.sin(k*math.tau/6)*r) for k in range(6)]+[(loc[0],loc[1]+h,loc[2])])

def cluster(down=False):
    for i in range([9,6,4][LOD]):
        a=i*2.4;r=1.6*math.sqrt(i/9)
        spike('mineral cluster',2+(i%4)*.7,.3+(i%3)*.12,down,i,(math.cos(a)*r,0,math.sin(a)*r))

def boulder(kind=0):
    sizes=[(7,4,5),(3,2.5,3),(10,2,5),(3,8,3)]
    size=sizes[kind];OBS.append(rock('weathered cave stone',size,111+kind,'rock',[3,2,1][LOD]))
    convex_col([(x*size[0]*.42,y*size[1],z*size[2]*.42) for x in [-1,1] for y in [0,.8] for z in [-1,1]])

def rubble():
    for i in range([15,9,5][LOD]):
        a=i*2.4;d=2.8*math.sqrt(i/15);size=(.7+i%3*.3,.35+i%4*.16,.6+i%2*.5)
        OBS.append(rock('broken talus',size,i,'rock',[2,1,1][LOD],(math.cos(a)*d,0,math.sin(a)*d)))

def column():
    spike('floor mineral column',11,1.9,False,3);spike('ceiling mineral column',10,2.4,True,7,(.1,5,0))

def curtain():
    for i in range([11,8,5][LOD]):
        x=-4+i*8/([11,8,5][LOD]-1);spike('calcite drapery',5+.8*math.cos(x),.65,True,i,(x,0,.5*math.sin(x)) )

def shelf():
    for i in range([5,4,3][LOD]):
        OBS.append(rock('flowstone terrace',(7-i*.9,.8,3.5-i*.3),i,'chalk',[3,2,1][LOD],(0,i*.65,i*.22)))
        box_col((0,i*.65+.25,i*.22),(6.2-i*.9,.5,3-i*.3))

def pool():
    n=[24,16,10][LOD]
    for i in range(n):
        a=i*math.tau/n;OBS.append(rock('travertine rim',(.9,.35,.7),i,'chalk',[2,1,1][LOD],(math.cos(a)*3.5,0,math.sin(a)*2.4)))
    OBS.append(rings('still mineral water',[(3.3,2.2),(3.3,2.2)],[.08,.12],tile='patina',sides=n))

def ruin(kind):
    if kind=='altar':
        B('altar base',(0,.3,0),(5,.6,4));B('carved monolith',(0,1.5,.5),(2,2.4,1.6));B('sacrificial empty bowl',(0,2.8,.5),(2.6,.35,2),'chalk')
    elif kind=='stairs':
        for i in range(8):B('broad worn step',(0,.16+i*.2,-3.5+i),(5,.32+i*.4,1.04),'ruin_stone',False)
        convex_col([(-2.5,0,-4),(2.5,0,-4),(2.5,0,4),(-2.5,0,4),(-2.5,.32,-4),(2.5,.32,-4),(2.5,3.12,4),(-2.5,3.12,4)])
    elif kind=='gate':
        for x in [-4,4]:B('gate pier',(x,3,0),(1.8,6,2))
        for i in range([15,11,7][LOD]):
            n=[15,11,7][LOD];a=i*math.pi/n;b=(i+1)*math.pi/n
            prism('arched gate',[(math.cos(a)*3.1,5+math.sin(a)*3),(math.cos(b)*3.1,5+math.sin(b)*3),(math.cos(b)*4.9,5+math.sin(b)*4.5),(math.cos(a)*4.9,5+math.sin(a)*4.5)],-1,1)
    elif kind=='bridge':
        for x in [-2.2,2.2]:B('stone parapet',(x,1,0),(.55,2,10))
        B('crossing deck',(0,-.3,0),(5,.6,10))
    elif kind=='lantern':
        B('lamp plinth',(0,.3,0),(.9,.6,.9));B('lamp pedestal',(0,1,0),(.45,1.4,.45));B('mineral light cup',(0,1.7,0),(1,.2,1),'worn_gold')
    elif kind=='marker':
        OBS.append(rock('inscribed waystone',(1.4,3.2,.8),33,'ruin_stone',[3,2,1][LOD]));box_col((0,1.3,0),(1,2.6,.6))
        for i in range(3):B('abstract old incision',(0,1.4+i*.3,-.39),(.55,.05,.04),'patina',False,0)
    elif kind=='wall':
        for i in range(4):B('worn ashlar',(0,.5+i*.8,0),(7-i*.8,.78,1.5))
    elif kind=='pillar':
        B('pillar foot',(0,.3,0),(2.6,.6,2.6));B('pillar shaft',(0,3,0),(1.7,5,1.7));B('fracture',(0,5.6,0),(2.3,.6,2.3))
    if LOD==0 and kind not in ['stairs','gate']:
        for i in range(4):B('surface mineral fleck',(-.5+i*.3,.7,-.5),(.16,.05,.15),'chalk',False,0)

SPECS=[('great_closed_dome',lambda:dome(),'chambers'),('side_closed_dome',lambda:dome(True),'chambers'),('vault_tunnel_12m',lambda:tunnel(),'passages'),('vault_bend_12m',lambda:tunnel('bend'),'passages'),('vault_ramp_12m',lambda:tunnel('ramp'),'passages'),('stalagmite_great',lambda:spike('great stalagmite',9,1.7),'minerals'),('stalagmite_slender',lambda:spike('slender stalagmite',5,.6),'minerals'),('stalactite_great',lambda:spike('great stalactite',8,1.5,True),'minerals'),('stalactite_slender',lambda:spike('slender stalactite',4,.55,True),'minerals'),('stalagmite_cluster',lambda:cluster(),'minerals'),('stalactite_cluster',lambda:cluster(True),'minerals'),('fused_column',column,'minerals'),('calcite_curtain',curtain,'minerals'),('flowstone_shelf',shelf,'minerals'),('travertine_pool',pool,'minerals'),('cave_boulder_large',lambda:boulder(0),'rocks'),('cave_boulder_small',lambda:boulder(1),'rocks'),('fallen_slab',lambda:boulder(2),'rocks'),('stone_needle',lambda:boulder(3),'rocks'),('talus_scatter',rubble,'rocks')]+[(f'buried_{kind}',lambda k=kind:ruin(k),'ruins') for kind in ['altar','stairs','gate','bridge','lantern','marker','wall','pillar']]
PROBES={
'great_closed_dome':[([0,2,-35],[0,2,35],'clear'),([0,2,0],[0,40,0],'hit'),([0,2,0],[30,2,0],'hit')],
'side_closed_dome':[([0,2,-20],[0,2,20],'clear'),([0,2,0],[0,25,0],'hit')],
'vault_tunnel_12m':[([0,2,-7],[0,2,7],'clear'),([0,2,0],[0,10,0],'hit')],
'buried_gate':[([0,2,-3],[0,2,3],'clear')]
}
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
        ob['original_design']='Hollowvault original enclosed cavern geometry';ob['metres']=True
        path=ROOT/f'models/hollowvault/{name}_lod{lod}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,export_cameras=False,export_lights=False,export_animations=False)
        if lod==0:collision=COLL.copy();bounds=rounded([[v[0],v[2],-v[1]] for v in ob.bound_box])
        variants.append(ob);ob.hide_set(True)
    assert counts[0]>=counts[1]>=counts[2]>0,(name,counts)
    nominal=[round(max(v[k] for v in bounds)-min(v[k] for v in bounds),3) for k in range(3)]
    record={'id':name,'category':category,'runtime':f'models/hollowvault/{name}_lod0.glb','lod_paths':[f'models/hollowvault/{name}_lod{i}.glb' for i in range(3)],'lod_triangles':counts,'lod_method':'Semantic reduction of dome/tunnel rings, mineral cross-sections, rock subdivisions and detail','material':'Hollowvault_Atlas_1K','atlas':'textures/hollowvault/atlas_1k.png','collision':'compound' if collision else 'none','collision_shapes':collision,'collision_shape_count':len(collision),'collision_notes':'Compound surface patch hulls and boxes, opt-in. Dome/tunnel voids preserved. Hanging minerals and small debris are decorative. No climbing contract.','bounds_godot':bounds,'nominal_size':nominal,'pivot':'ground-origin local metres','anchors':[{'name':'ground','position':[0,0,0]}],'license':'CC0-1.0','provenance':'Original deterministic Blender geometry; tools/art/generate_hollowvault.py','passage_probes':[{'from':a,'to':b,'expect':e} for a,b,e in PROBES.get(name,[])]}
    manifest.append(record);assets.append((name,variants))
    (ROOT/f'environment/hollowvault/{name}.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://art/scripts/hollowvault_asset.gd" id="1"]\n[node name="'+name+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+name+'"\n')
    print('MIREWOOD_ASSET',name,counts,len(collision),flush=True)
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
scene=bpy.context.scene;scene.name='Hollowvault Fen v6 editable catalogue';scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene['seed']=SEED;scene['license']='CC0-1.0';scene['atlas']='Original Hollowvault shared 1K atlas'
bpy.context.preferences.filepaths.save_version=0
for image in list(bpy.data.images):
    if image.users==0:bpy.data.images.remove(image)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/hollowvault.blend'),compress=True)
result={'version':6,'kit':'Hollowvault','seed':SEED,'source':'art/source/hollowvault.blend','generator':'tools/art/generate_hollowvault.py','coordinate_system':'Godot Y-up metres; -Z forward','shared_atlas':'textures/hollowvault/atlas_1k.png','assets':manifest}
(ROOT/'assets/hollowvault_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
print('MIREWOOD_GENERATION_OK',len(manifest),[sum(a['lod_triangles'][i] for a in manifest) for i in range(3)],flush=True)
