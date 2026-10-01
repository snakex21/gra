"""Original Saltwind Expanse desert kit. Blender 4.3+; no downloads.

Run: blender -b --python-exit-code 1 --python tools/art/generate_saltwind.py
Units/pivots/recipes are Godot coordinates (X right, Y up, Z depth), metres.
LOD meshes are rebuilt from semantic parts. Structural passages, mineral profiles
and plant silhouettes survive simplification. All five textures are original.
"""
import ast
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
source = ast.parse((ROOT / 'tools/art/generate_art.py').read_text())
keep = [n for n in source.body if isinstance(n, (ast.Import, ast.ImportFrom, ast.FunctionDef))]
exec(compile(ast.Module(body=keep, type_ignores=[]), 'generate_art_primitives', 'exec'))
SEED = 47063
random.seed(SEED)
for folder in ['models/saltwind', 'environment/saltwind', 'art/source', 'assets']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials): bpy.data.materials.remove(material)
TILES = {n: i for i, n in enumerate(['grass','rock','ruin_stone','basalt','soil','sand','path','bark','leaf','dry_grass','fur','patina','dark','chalk','moss','worn_gold'])}
# Local procedural texture authorship, period-one fields with periodic normals.
texdir=ROOT/'textures/saltwind';texdir.mkdir(parents=True,exist_ok=True)
palette=[(.58,.57,.45),(.53,.47,.36),(.63,.57,.44),(.32,.33,.31),(.48,.40,.29),(.70,.64,.50),(.59,.51,.39),(.33,.31,.25),(.46,.48,.35),(.61,.55,.39),(.48,.43,.33),(.43,.50,.45),(.19,.22,.22),(.76,.77,.72),(.55,.56,.43),(.62,.53,.32)]
def saltfield(n):
    # Toroidal jittered Voronoi edges form tileable polygonal salt cells.
    yy,xx=np.mgrid[:n,:n]/n
    nearest=np.full((n,n),100.);second=np.full((n,n),100.)
    rng=np.random.default_rng(SEED)
    for j in range(7):
        for i in range(7):
            px=(i+rng.uniform(.15,.85))/7;py=(j+rng.uniform(.15,.85))/7
            dx=np.abs(xx-px);dy=np.abs(yy-py);dx=np.minimum(dx,1-dx);dy=np.minimum(dy,1-dy)
            d=dx*dx+dy*dy;second=np.minimum(second,np.maximum(nearest,d));nearest=np.minimum(nearest,d)
    edge=np.exp(-np.maximum(second-nearest,0)*17000)
    return texture_field(n,SEED,'chalk')*.38-edge*.095
atlas=np.zeros((1024,1024,3))
for i,color in enumerate(palette):
    field=saltfield(256) if i==13 else texture_field(256,SEED+i,list(TILES)[i])*.68
    atlas[(i//4)*256:(i//4+1)*256,(i%4)*256:(i%4+1)*256]=np.array(color)[None,None,:]+field[:,:,None]
atlas_img=write_png(texdir/'atlas_1k.png',atlas)
for name,n,color in [('salt_crust',2048,(.73,.75,.71)),('wind_sediment',1024,(.60,.53,.41))]:
    field=saltfield(n) if name=='salt_crust' else texture_field(n,SEED+83,'sand')*.6
    if name=='wind_sediment':
        yy,xx=np.mgrid[:n,:n]/n;field+=.014*np.sin(xx*math.tau*21+np.sin(yy*math.tau*3))
    write_png(texdir/(name+'_albedo.png'),np.array(color)[None,None,:]+field[:,:,None])
    gx=(np.roll(field,-1,1)-np.roll(field,1,1))*.5;gy=(np.roll(field,-1,0)-np.roll(field,1,0))*.5
    normal=np.stack((-gx*9,-gy*9,np.ones_like(field)),axis=-1);normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    write_png(texdir/(name+'_normal.png'),normal*.5+.5)
mat = bpy.data.materials.new('Saltwind_Atlas_1K'); mat.use_nodes = True
tex = mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = atlas_img
mat.node_tree.links.new(tex.outputs['Color'], mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .92
FACES = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
OBS, COLL, LOD = [], [], 0
assets, manifest = [], []

def uv_project(obj, tile):
    """Atlas-safe planar UVs with a common metric scale on both face axes.

    A common scale on both planar axes preserves surface aspect ratios; this
    override does not change earlier kits or their shared textures.
    """
    uv=obj.data.uv_layers.new(name='UVMap') if not obj.data.uv_layers else obj.data.uv_layers[0]
    idx=TILES[tile]
    for poly in obj.data.polygons:
        axis=max(range(3),key=lambda a:abs(poly.normal[a]))
        axes=[a for a in range(3) if a!=axis]
        coords=[obj.data.vertices[obj.data.loops[li].vertex_index].co for li in poly.loop_indices]
        lo=[min(c[a] for c in coords) for a in axes]
        hi=[max(c[a] for c in coords) for a in axes]
        extent=max(hi[0]-lo[0],hi[1]-lo[1],.001)
        padding=[(1-(h-l)/extent)/2 for l,h in zip(lo,hi)]
        for li,co in zip(poly.loop_indices,coords):
            u,v=[pad+(co[a]-l)/extent for a,l,pad in zip(axes,lo,padding)]
            uv.data[li].uv=((idx%4+.03+u*.94)/4,(idx//4+.03+v*.94)/4)


def rounded(v):
    if isinstance(v, (list, tuple)): return [rounded(x) for x in v]
    return round(float(v), 6)

def box_col(pos, size, rotation=(0,0,0)):
    if LOD == 0: COLL.append({'type':'box', 'position':rounded(pos), 'size':rounded(size), 'rotation':rounded(rotation)})

def convex_col(points):
    if LOD == 0: COLL.append({'type':'convex', 'points':rounded(points)})

def B(name, pos, size, tile='ruin_stone', collision=True, bevel=.045):
    OBS.append(block(name, pos, size, tile, bevel if LOD == 0 else 0))
    if collision: box_col(pos, size)

def P(name, points, tile='ruin_stone', collision=True):
    OBS.append(mesh_object(name, points, FACES, tile))
    if collision: convex_col(points)

def prism(name, polygon, front, back, tile='ruin_stone', axis='z', collision=True):
    # Four-corner cross section extruded along Z, or along X for vaults.
    points = [(u,y,z) if axis == 'z' else (z,y,u) for z in [front,back] for u,y in polygon]
    P(name, points, tile, collision)

def coursing(x, y, z, width, height, depth, rows=6, sides=True):
    # Face reliefs and projecting string courses are kept outside collision.
    if LOD == 2: return
    count=rows if LOD==0 else max(2,rows//3)
    for k in range(count):
        yy=y-height/2+(k+.5)*height/count
        for s in [-1,1] if sides else [-1]:
            B('recessed mortar course',(x,yy,z+s*(depth/2+.018)),(width*.97,.032,.035),'dark',False,.004)
    if LOD==0:
        for j in [-.25,.25]:
            B('water weathering',(x+j*width,y-height*.15,z-depth/2-.025),(.045,height*.55,.035),'patina',False,.008)

# Every family uses a semantic silhouette and independent coarse proxy.
def formation(name,profile,width,depth,height,lean=0,tile='rock',cx=0,cz=0,proxy=True):
    sides=[22,14,9][LOD];steps=[len(profile),max(4,len(profile)-2),min(4,len(profile))][LOD]
    sample=[profile[round(i*(len(profile)-1)/(steps-1))] for i in range(steps)]
    verts=[]
    for j,(y,rad) in enumerate(sample):
        for k in range(sides):
            a=math.tau*k/sides;f=1+.14*math.sin(a*3+.9)+.065*math.cos(a*5+.5+y*2)-.10*math.cos(a+.4)
            verts.append((cx+math.cos(a)*width*.5*rad*f+lean*y+width*.045*math.sin(y*5+.3)*y, y*height,cz+math.sin(a)*depth*.5*rad*f+depth*.09*math.sin(y*4+.9)*y))
    faces=[tuple(reversed(range(sides))),tuple((steps-1)*sides+k for k in range(sides))]
    for j in range(steps-1):
        for k in range(sides):
            a=j*sides+k;b=j*sides+(k+1)%sides;faces.append((a,b,b+sides,a+sides))
    ob=mesh_object(name,verts,faces,tile);OBS.append(ob)
    if LOD==0 and proxy:
        # Narrow waist retained: stacked small convex sections, not a full hull.
        for j in range(len(profile)-1):
            points=[]
            for y,rad in profile[j:j+2]:
                for k in range(6):
                    a=math.tau*k/6;points.append((cx+math.cos(a)*width*.46*rad+lean*y,y*height,cz+math.sin(a)*depth*.46*rad))
            convex_col(points)
    if LOD<2:
        # Sparse near/mid mineral ledges rather than noisy all-over greebles.
        for j,(y,rad) in enumerate(profile[1:-1:2 if LOD==0 else 4]):
            OBS.append(rings('sedimentary band',[(width*.5*rad,depth*.5*rad),(width*.503*rad,depth*.503*rad)],[y*height,y*height+.055],(cx+lean*y,0,cz),'chalk' if j%2 else 'sand',sides,23,.045))

def needle():formation('slender eroded needle',[(0,1.3),(.12,.96),(.32,.64),(.58,.57),(.8,.34),(1,.06)],5,4,25,2.1)
def fork():
    formation('fork western tine',[(0,1.2),(.25,.65),(.5,.55),(.75,.4),(1,.06)],4,3,17,-2,cx=-1.5)
    formation('fork eastern tine',[(0,1.2),(.25,.65),(.5,.48),(.75,.3),(1,.05)],3.7,3,22,2.6,cx=1.4)
def blade_rock():formation('knife edge fin',[(0,1.2),(.18,1),(.4,.82),(.64,.6),(.86,.42),(1,.07)],13,2.3,18,1.8)
def hoodoo():formation('hoodoo cap and neck',[(0,.82),(.14,.56),(.36,.35),(.64,.29),(.76,.85),(.9,1),(1,.65)],7,6,14,.8)
def mushroom():formation('wind undercut mushroom',[(0,.5),(.12,.4),(.32,.26),(.54,.27),(.67,1),(.83,1.1),(1,.62)],11,9,8,1)
def yardang():formation('long wind abraded yardang',[(0,1),(.2,.85),(.45,.62),(.67,.53),(.86,.3),(1,.1)],23,4,6,3)
def bank():formation('undercut wind bank',[(0,.8),(.18,.64),(.4,.62),(.62,1),(.86,1.05),(1,.8)],19,8,7,1.8)
def ridge():formation('serrated ridge',[(0,1.1),(.2,1),(.46,.76),(.66,.6),(.83,.35),(1,.12)],31,8,18,-1)
def escarpment():
    # An authored jagged cliff silhouette, distinct from isolated radial pillars.
    n=[25,17,11][LOD];verts=[]
    for side in [-1,1]:
        for layer in range(4):
            t=layer/3
            for i in range(n):
                x=-32+64*i/(n-1)
                crest=18+9*math.sin(i/(n-1)*math.pi)**.6+4*math.sin(x*.27)+2*math.cos(x*.49)
                z=side*(12-6*t)+2*math.sin(x*.24+t*1.7)
                verts.append((x,crest*t,z))
    faces=[]
    for side in range(2):
        for j in range(3):
            for i in range(n-1):
                a=side*4*n+j*n+i;faces.append((a,a+1,a+n+1,a+n))
    for i in range(n-1):faces.append((3*n+i,3*n+i+1,7*n+i+1,7*n+i))
    for i in [0,n-1]:
        for j in range(3):faces.append((j*n+i,(j+1)*n+i,(j+5)*n+i,(j+4)*n+i))
    for i in range(n-1):faces.append((i,i+1,4*n+i+1,4*n+i))
    OBS.append(mesh_object('eroded jagged horizon wall',verts,faces,'rock'))
    if LOD==0:
        for x in [-24,-8,8,24]:box_col((x,8,0),(16,16,13))
    if LOD<2:
        for x in range(-27,29,9):
            formation('cliff basal talus',[(0,1),(.25,.8),(.6,.53),(1,.15)],10,8,7,1,'sand',cx=x,cz=-9,proxy=False)

def plateau():formation('asymmetric receding mesa',[(0,1.13),(.16,1.03),(.36,.94),(.57,.87),(.78,.81),(1,.76)],32,24,19,3.1)

def salt_plate():
    for i,(x,z,w,d) in enumerate([(-1.4,-.7,2.8,2.3),(1.25,-.9,2.3,2.5),(-.5,1.3,3.2,2.1),(2,1.1,1.5,1.4)]):
        OBS.append(rings('polygon salt plate',[(w*.5,d*.5),(w*.48,d*.48)],[0,.16+i*.015],(x,0,z),'chalk',[9,7,5][LOD],i,.14))
    if LOD==0:box_col((0,.08,0),(5,.16,4))
    if LOD<2:
        for x in [-1,.8]:B('raised mineral seam',(x,.2,0),(.035,.05,2.8),'sand',False,.01)
def salt_ridge():formation('heaved salt pressure ridge',[(0,1),(.2,.9),(.5,.52),(.7,.3),(1,.08)],9,1.9,1.8,.2,'chalk')
def crystals():
    for i in range([9,6,3][LOD]):
        a=i*2.4;r=.7*(i%3)/2;h=.7+(i%4)*.35
        OBS.append(rings('opaque mineral blade',[.18,.22,.08],[0,h*.65,h],(math.cos(a)*r,0,math.sin(a)*r),'chalk',[6,5,4][LOD],i,.05))
def shelf():formation('salt shelf lip',[(0,.74),(.22,.66),(.48,.7),(.7,1.05),(1,1)],10,6,1.5,.4,'chalk')
def rosette():
    for i in range([14,9,5][LOD]):
        a=i*math.tau/[14,9,5][LOD]
        OBS.append(branch('radial salt fan',(0,.15,0),(math.cos(a)*1.6,.35+.2*(i%2),math.sin(a)*1.6),.3,.09,'chalk',[7,5,4][LOD]))
def rill():
    for sign in [-1,1]:
        formation('dry rill bank',[(0,1),(.25,1),(.6,.8),(1,.1)],2.2,10,.6,0,'sand',cx=sign*1.9)
    if LOD<2:
        for z in [-3,0,3]:B('rill silt tongue',(0,.03,z),(1.3,.06,1.6),'soil',False,.015)

# Buried ruins have no humanoid motifs and do not claim climbable surfaces.
def wind_gate():
    for sign in [-1,1]:
        B('splayed gate footing',(sign*5,.4,0),(3.2,.8,4.8))
        B('tall tapered gate cheek',(sign*5,5.9,0),(2.2,11,3.8))
        coursing(sign*5,5.9,0,2.2,11,3.8,9)
    B('continuous wind gate lintel',(0,12.2,0),(13,1.6,4.2),'chalk')
    B('projecting coping',(0,13.25,0),(13.8,.5,4.6))
    if LOD<2:
        for x in [-5,0,5]:B('sun worn inset',(x,12.15,-2.14),(1.5,.72,.06),'sand',False,.01)
    if LOD==0:
        for x in [-1.5,0,1.5]:B('abstract wind slit',(x,12.16,-2.19),(.11,.62,.05),'dark',False,.008)
def sunken_wall():
    B('buried retaining wall',(0,1.25,0),(12,2.5,1.5))
    for x,h in [(-4.5,4),(-1.5,3.2),(1.5,2.9),(4.5,3.7)]:
        B('uneven exposed crest',(x,(2.5+h)/2,0),(3,h-2.5,1.5),'chalk')
    coursing(0,1.3,0,12,2.4,1.5,5)
    if LOD==0:
        for x in [-4,-2,1,3]:B('shallow wind channel',(x,1.4,-.77),(.045,1.6,.045),'sand',False,.002)
def tower():
    for sign in [-1,1]:B('wind tower flank',(sign*2.7,8,0),(1.4,16,5))
    for y in [3,8,13,16]:B('tower cross beam',(0,y,0),(6.8,.7,5.4),'chalk')
    B('tower broad footing',(0,.3,0),(8,.6,7))
    if LOD<2:
        for sign in [-1,1]:coursing(sign*2.7,8,0,1.4,16,5,12)
    if LOD==0:
        for y in [5,10]:
            for sign in [-1,1]:B('inner worn bracket',(sign*2.2,y,2.1),(.6,.15,.5),'sand',False)
def pillar():
    B('ribbed salt pillar core',(0,4,0),(2,8,2))
    for sign in [-1,1]:
        B('projecting fin',(sign*1.15,4,0),(.3,8,2.6),'chalk')
    B('pillar foot',(0,.3,0),(3.2,.6,3.2));B('pillar capital',(0,8.2,0),(3,.4,3))
    coursing(0,4,0,2,7,2,7)
    if LOD==0:
        for x in [-.6,0,.6]:B('flute',(x,4,-1.03),(.08,5,.05),'sand',False,.003)
def plinth():
    for y,w in [(.4,10),(1.1,8.4),(1.7,6.8)]:B('stepped ceremonial plinth',(0,y,0),(w,.8,w),'chalk')
    if LOD<2:
        for s in [-1,1]:B('recessed plinth band',(0,1.1,s*4.23),(7.8,.16,.04),'sand',False,.005)
    if LOD==0:
        for x in [-2,0,2]:B('plinth surface joints',(x,2.11,0),(.025,.025,6.5),'sand',False,0)
def buried_stairs():
    for i in range([10,6,3][LOD]):
        n=[10,6,3][LOD];run=8/n;h=3*(i+1)/n
        B('exposed stair tread',(0,h/2,-4+(i+.5)*run),(5,h,run),'ruin_stone',False)
    P('independent stair ramp',[(-2.5,0,-4),(2.5,0,-4),(2.5,.3,-4),(-2.5,.3,-4),(-2.5,0,4),(2.5,0,4),(2.5,3,4),(-2.5,3,4)],'sand',False)
    if LOD==0:convex_col([(-2.5,0,-4),(2.5,0,-4),(-2.5,.3,-4),(2.5,.3,-4),(-2.5,0,4),(2.5,0,4),(-2.5,3,4),(2.5,3,4)])
def lintel():
    B('fallen monumental lintel',(-1,.85,0),(8,1.7,2.6))
    P('fractured lintel end',[(3,0,-1.3),(4.3,0,-1.3),(3.7,1.7,-1.3),(3,1.7,-1.3),(3,0,1.3),(4.6,0,1.3),(4.1,1.7,1.3),(3,1.7,1.3)])
    coursing(-1,.85,0,8,1.7,2.6,3)
    if LOD==0:
        for x in [-3,-1,1]:B('wind relief',(x,.9,-1.32),(.6,.6,.04),'sand',False,.01)
def waystone():
    formation('asymmetric route stele',[(0,1),(.18,.74),(.5,.73),(.83,.55),(1,.3)],1.8,1.2,4,.2,'ruin_stone')
    if LOD<2:B('route notch',(0,2.35,-.48),(.12,1.2,.08),'dark',False,.01)
    if LOD==0:
        for y in [1.9,2.3,2.7]:B('route tick',(.18,y,-.5),(.5,.08,.07),'chalk',False,.004)

# Opaque tubular vegetation, no alpha planes or overdraw; no collision except snag/acacia trunks.
def twig(a,b,r=.04,tile='dry_grass'):OBS.append(branch('dry branching stem',a,b,r,r*.38,tile,[7,5,3][LOD]))
def grass_fan():
    for i in range([19,11,5][LOD]):
        a=i*2.4;end=(math.cos(a)*.8,.5+(i%5)*.16,math.sin(a)*.5)
        twig((0,0,0),(end[0]*.3,end[1]*.62,end[2]*.3),.022);twig((end[0]*.3,end[1]*.62,end[2]*.3),end,.018)
def tumble():
    n=[14,8,4][LOD]
    for i in range(n):
        a=i*math.tau/n;p=(math.cos(a)*.65,.45,math.sin(a)*.65)
        twig((0,.04,0),p,.033);twig(p,(math.cos(a+.8)*.5,1.1,math.sin(a+.8)*.5),.025);twig((math.cos(a+.8)*.5,1.1,math.sin(a+.8)*.5),(0,1.2,0),.02)
def thorn():
    for sign in [-1,1]:
        prev=(sign*.8,0,0)
        for j in range([7,5,3][LOD]):
            t=(j+1)/[7,5,3][LOD];p=(sign*(.8-.65*t),math.sin(t*math.pi/2)*1.8,.12*math.sin(t*5))
            twig(prev,p,.08*(1-t*.6),'bark')
            if LOD<2:twig(p,(p[0]+sign*.28,p[1]+.12,p[2]+.25),.028,'bark')
            prev=p

def saltbrush():
    for i in range([16,9,4][LOD]):
        a=i*2.4;p=(math.cos(a)*.7,.45+(i%3)*.14,math.sin(a)*.7)
        twig((0,0,0),p,.034,'bark')
        OBS.append(rings('dry seed cushion',[(.22,.13),(.28,.17),(.08,.06)],[0,.16,.32],p,'leaf',[7,5,3][LOD],i,.13))
def spear_fan():
    for i in range([13,8,4][LOD]):
        a=i*2.4;r=.6+.1*(i%3);p=(math.cos(a)*r,1+(i%4)*.27,math.sin(a)*r)
        twig((0,0,0),p,.085,'dry_grass')
        if LOD==0:twig((p[0]*.8,p[1]*.8,p[2]*.8),(p[0]*1.04,p[1]*1.14,p[2]*1.04),.035,'chalk')
def reed():
    for i in range([12,7,3][LOD]):
        a=i*2.4;x=math.cos(a)*.4;z=math.sin(a)*.4;h=1.3+(i%4)*.18
        twig((x,0,z),(x+.25,h,z),.028)
        twig((x+.25,h,z),(x+.45,h+.25,z),.07,'bark')
def snag():
    twig((0,0,0),(.4,2,0),.22,'bark');twig((.4,2,0),(1,3.3,.2),.14,'bark')
    for i in range([9,6,3][LOD]):
        a=i*2.4;p=(math.cos(a)*1.5,.05,math.sin(a)*1.5)
        twig((0,.3,0),p,.12,'bark')
        if LOD==0:twig(p,(p[0]*1.3,.025,p[2]*1.3),.06,'bark')
    if LOD==0:box_col((.2,1,0),(.55,2,.55))
def acacia():
    twig((0,0,0),(.6,3.5,0),.34,'bark');twig((.6,3.5,0),(1.5,5.4,.2),.22,'bark')
    for i in range([11,7,4][LOD]):
        a=i*2.4;p=(math.cos(a)*3+1,4.5+(i%3)*.35,math.sin(a)*2)
        twig((.6,3.2,0),p,.12,'bark')
        if LOD<2:
            twig(p,(p[0]+.6,p[1]+.4,p[2]+.3),.045,'bark')
            twig(p,(p[0]-.35,p[1]+.3,p[2]-.3),.04,'bark')
    if LOD==0:box_col((.3,1.75,0),(.7,3.5,.7))

SPECS=[
('eroded_needle',needle,'geology'),('forked_spire',fork,'geology'),('blade_fin',blade_rock,'geology'),('hoodoo_crown',hoodoo,'geology'),('mushroom_outcrop',mushroom,'geology'),('wind_yardang',yardang,'geology'),('undercut_bank',bank,'geology'),('serrated_ridge',ridge,'geology'),('tiered_escarpment',escarpment,'geology'),('tabletop_mesa',plateau,'geology'),
('salt_polygon_plates',salt_plate,'salt'),('salt_pressure_ridge',salt_ridge,'salt'),('mineral_blades',crystals,'salt'),('crust_shelf',shelf,'salt'),('salt_rosette',rosette,'salt'),('dry_rill_banks',rill,'salt'),
('wind_gate_13m',wind_gate,'ruins'),('sunken_retaining_wall',sunken_wall,'ruins'),('wind_sieve_tower',tower,'ruins'),('ribbed_salt_pillar',pillar,'ruins'),('stepped_sun_plinth',plinth,'ruins'),('buried_stair_8m',buried_stairs,'ruins'),('fallen_fractured_lintel',lintel,'ruins'),('notched_waystone',waystone,'ruins'),
('dry_fan_grass',grass_fan,'vegetation'),('tumble_cage',tumble,'vegetation'),('arched_thorn',thorn,'vegetation'),('saltbrush_cushion',saltbrush,'vegetation'),('spear_fan',spear_fan,'vegetation'),('dry_seed_reeds',reed,'vegetation'),('root_snag',snag,'vegetation'),('dead_flat_acacia',acacia,'vegetation')]
PROBES={
'wind_gate_13m':[([0,5,-5],[0,5,5],'clear'),([5,5,-5],[5,5,5],'hit'),([0,15,0],[0,10,0],'hit')],
'wind_sieve_tower':[([0,5,-5],[0,5,5],'clear'),([0,10,-5],[0,10,5],'clear'),([2.7,5,-5],[2.7,5,5],'hit')],
'dry_rill_banks':[([0,.3,-6],[0,.3,6],'clear')],
'buried_stair_8m':[([0,5,0],[0,-1,0],'hit')],
'salt_polygon_plates':[([0,2,0],[0,-1,0],'hit')]}
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
        ob['original_design']='Saltwind original salt desert geometry';ob['metres']=True
        path=ROOT/f'models/saltwind/{name}_lod{lod}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,export_cameras=False,export_lights=False,export_animations=False)
        if lod==0:collision=COLL.copy();bounds=rounded([[v[0],v[2],-v[1]] for v in ob.bound_box])
        variants.append(ob);ob.hide_set(True)
    assert counts[0]>counts[1]>counts[2]>0,(name,counts)
    nominal=[round(max(v[k] for v in bounds)-min(v[k] for v in bounds),3) for k in range(3)]
    record={'id':name,'category':category,'runtime':f'models/saltwind/{name}_lod0.glb','lod_paths':[f'models/saltwind/{name}_lod{i}.glb' for i in range(3)],'lod_triangles':counts,'lod_method':'semantic silhouette rebuild with fewer profile rings, sides, twigs and relief','material':'Saltwind_Atlas_1K','atlas':'textures/saltwind/atlas_1k.png','collision':'compound' if collision else 'none','collision_shapes':collision,'collision_shape_count':len(collision),'collision_notes':'Independent conservative coarse boxes and stacked six-sided hulls; plants and mineral decoration have none. Narrow waists and structural passages retained. No climbing contract.','bounds_godot':bounds,'nominal_size':nominal,'pivot':'ground-origin local metres','anchors':[{'name':'ground','position':[0,0,0]}],'license':'CC0-1.0','provenance':'Original deterministic Blender geometry; tools/art/generate_saltwind.py','passage_probes':[{'from':a,'to':b,'expect':e} for a,b,e in PROBES.get(name,[])]}
    manifest.append(record);assets.append((name,variants))
    (ROOT/f'environment/saltwind/{name}.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://art/scripts/saltwind_asset.gd" id="1"]\n[node name="'+name+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+name+'"\n')
    print('SALTWIND_ASSET',name,counts,len(collision),flush=True)
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
scene=bpy.context.scene;scene.name='Saltwind Expanse v4 editable catalogue';scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene['seed']=SEED;scene['license']='CC0-1.0';scene['atlas']='Original Saltwind shared 1K atlas'
bpy.context.preferences.filepaths.save_version=0
for image in list(bpy.data.images):
    if image.users==0:bpy.data.images.remove(image)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/saltwind.blend'),compress=True)
result={'version':4,'kit':'Saltwind Expanse','seed':SEED,'source':'art/source/saltwind.blend','generator':'tools/art/generate_saltwind.py','coordinate_system':'Godot Y-up metres; -Z forward','shared_atlas':'textures/saltwind/atlas_1k.png','assets':manifest}
(ROOT/'assets/saltwind_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
print('SALTWIND_GENERATION_OK',len(manifest),[sum(a['lod_triangles'][i] for a in manifest) for i in range(3)],flush=True)
