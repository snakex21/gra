"""Original Stonewater hydraulic ruin kit. Blender 4.3+; no downloads.

Run: blender -b --python-exit-code 1 --python tools/art/generate_stonewater.py
Units/pivots/recipes are Godot coordinates (X right, Y up, Z depth), metres.
LOD meshes are rebuilt from semantic parts, never whole-mesh decimated: openings,
walkable silhouettes and the open oculus survive every LOD. Existing v2 atlas only.
"""
import ast
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
source = ast.parse((ROOT / 'tools/art/generate_art.py').read_text())
keep = [n for n in source.body if isinstance(n, (ast.Import, ast.ImportFrom, ast.FunctionDef))]
exec(compile(ast.Module(body=keep, type_ignores=[]), 'generate_art_primitives', 'exec'))
SEED = 36041
random.seed(SEED)
for folder in ['models/stonewater', 'environment/stonewater', 'art/source', 'assets']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials): bpy.data.materials.remove(material)
TILES = {n: i for i, n in enumerate(['grass','rock','ruin_stone','basalt','soil','sand','path','bark','leaf','dry_grass','fur','patina','dark','chalk','moss','worn_gold'])}
atlas_img = bpy.data.images.load(str(ROOT / 'textures/ancient_valley/atlas_1k.png'), check_existing=True)
mat = bpy.data.materials.new('AncientValley_Atlas_1K'); mat.use_nodes = True
tex = mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = atlas_img
mat.node_tree.links.new(tex.outputs['Color'], mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .92
FACES = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
OBS, COLL, LOD = [], [], 0
assets, manifest = [], []

def uv_project(obj, tile):
    """Atlas-safe planar UVs with a common metric scale on both face axes.

    Legacy primitives map every face dimension to a full tile independently,
    stretching the long hydraulic vault/pier faces. This local override keeps
    their aspect ratio and does not change the earlier kits or shared texture.
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

def arch(name, radius, thick, spring, depth, count, center=(0,0,0), axis='z', start=0, end=math.pi, collision=True, spandrel=None):
    for j in range(count):
        a=start+(end-start)*j/count; b=start+(end-start)*(j+1)/count
        # Structural wedge ends meet exactly: no through-open roof masonry.
        gap=.004 if LOD==0 and not collision else 0
        aa=a+gap; bb=b-gap
        p=[(radius*math.cos(aa),spring+radius*math.sin(aa)),((radius+thick)*math.cos(aa),spring+(radius+thick)*math.sin(aa)),((radius+thick)*math.cos(bb),spring+(radius+thick)*math.sin(bb)),(radius*math.cos(bb),spring+radius*math.sin(bb))]
        p=[(u+center[0 if axis=='z' else 2],y+center[1]) for u,y in p]
        zz=center[2 if axis=='z' else 0]
        prism(name+' voussoir',p,zz-depth/2,zz+depth/2,'chalk' if j==count//2 else 'ruin_stone',axis,False)
        if spandrel is not None:
            p=[((radius+thick)*math.cos(a),spring+(radius+thick)*math.sin(a)),((radius+thick)*math.cos(a),spandrel),((radius+thick)*math.cos(b),spandrel),((radius+thick)*math.cos(b),spring+(radius+thick)*math.sin(b))]
            p=[(u+center[0 if axis=='z' else 2],y+center[1]) for u,y in p]
            prism(name+' spandrel',p,zz-depth*.47,zz+depth*.47,'ruin_stone',axis,False)
    if collision and LOD==0:
        proxy_count=6 if radius<=1 else max(3,round(12*(end-start)/math.pi))
        for j in range(proxy_count):
            a=start+(end-start)*j/proxy_count;b=start+(end-start)*(j+1)/proxy_count
            poly=[(radius*math.cos(a),spring+radius*math.sin(a)),((radius+thick)*math.cos(a),spring+(radius+thick)*math.sin(a)),((radius+thick)*math.cos(b),spring+(radius+thick)*math.sin(b)),(radius*math.cos(b),spring+radius*math.sin(b))]
            poly=[(u+center[0 if axis=='z' else 2],y+center[1]) for u,y in poly]
            zz=center[2 if axis=='z' else 0]
            convex_col([(u,y,z) if axis=='z' else (z,y,u) for z in [zz-depth/2,zz+depth/2] for u,y in poly])
            if spandrel is not None:
                poly=[((radius+thick)*math.cos(a),spring+(radius+thick)*math.sin(a)),((radius+thick)*math.cos(a),spandrel),((radius+thick)*math.cos(b),spandrel),((radius+thick)*math.cos(b),spring+(radius+thick)*math.sin(b))]
                poly=[(u+center[0 if axis=='z' else 2],y+center[1]) for u,y in poly]
                convex_col([(u,y,z) if axis=='z' else (z,y,u) for z in [zz-depth*.47,zz+depth*.47] for u,y in poly])

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

def channel(length, floor, width=2.8, x=0):
    B('hydraulic bed',(x,floor-.2,0),(length,.4,width),'ruin_stone')
    for s in [-1,1]:
        B('channel cheek',(x,floor+.35,s*(width/2+.2)),(length,.7,.4))
        if LOD<2:B('worn coping',(x,floor+.76,s*(width/2+.2)),(length,.12,.5),'chalk',False)
    if LOD<2:B('mineral-lined channel',(x,floor+.007,0),(length-.04,.014,width-.08),'patina',False,0)

def aqueduct():
    for s in [-1,1]:
        x=s*6.8
        B('broad pier footing',(x,.25,0),(2.4,.5,3.6))
        B('tall square pier',(x,3.2,0),(1.6,5.4,2.8))
        B('springing impost',(x,5.9,0),(2,.2,3.2),'chalk')
        B('outer spandrel pier',(s*7.6,9.6,0),(.8,7.2,2.8))
        coursing(x,3.2,0,1.6,5.4,2.8,9)
    arch('load bearing arch',6,1.2,6,2.8,[24,16,10][LOD],spandrel=13.25)
    if LOD<2:
        for s in [-1,1]:
            arch('raised archivolt',6.08,.17,6,.13,[24,16,10][LOD],center=(0,0,s*1.46),collision=False)
            B('aqueduct cornice',(0,13.18,s*1.54),(16,.2,.28),'chalk',False)
    channel(16,13.4)

def causeway():
    # Three real drain openings, independently collidable vault segments.
    B('road foundation',(0,.12,0),(8,.24,5),'rock')
    for x in [-3.6,-1.2,1.2,3.6]:
        B('drain partition',(x,.65,0),(.8,1.3,4.68))
    for x in [-2.4,0,2.4]:
        arch('culvert',.8,.38,.65,4.6,[10,8,6][LOD],center=(x,0,0),spandrel=2)
    B('causeway bed',(0,2.1,0),(8,.6,5),'ruin_stone')
    if LOD<2:
        for s in [-1,1]:B('road margin',(0,2.43,s*2.1),(8,.06,.18),'chalk',False,.01)
    if LOD==0:
        for x in [-3,-1,1,3]: B('jointed paving',(x,2.41,0),(1.94,.025,3.8),'path',False,.01)

def broken_end():
    B('surviving footing',(-6.8,.25,0),(2.4,.5,3.6))
    B('surviving pier',(-6.8,3.2,0),(1.6,5.4,2.8))
    B('remaining impost',(-6.8,5.9,0),(2,.2,3.2),'chalk')
    B('outer shoulder',(-7.6,9.6,0),(.8,7.2,2.8))
    arch('fractured arch',6,1.2,6,2.8,[11,7,5][LOD],start=math.pi*.57,end=math.pi,spandrel=13.25)
    channel(5.9,13.4,x=-5.05)
    if LOD<2:
        for x,y,z,w in [(-2.08,13.17,-.7,.9),(-2.3,13.37,.65,.6),(-2.6,13.75,1.6,.7)]:
            B('sheared lip',(x,y,z),(w,.38,.65),'chalk',False)
        coursing(-6.8,3.2,0,1.6,5.4,2.8,9)
    if LOD==0:
        for j in range(6):
            B('exposed fractured core',(-2.5-j*.28,11.8+j*.17,(-1)**j*.9),(.34,.28,.55),'rock',False)

def bridge_deck():
    B('continuous structural deck',(0,.65,0),(12,.9,6))
    B('continuous paving substrate',(0,1.14,0),(12,.12,6),'path')
    for s in [-1,1]:
        B('overhanging deck fascia',(0,.64,s*3),(12,.56,.3),'chalk')
        if LOD<2:B('recessed drip band',(0,.71,s*3.16),(11.9,.13,.035),'dark',False,.005)
    if LOD==0:
        for x in range(6):
            for z in range(3):B('flagstone wearing course',(-5+x*2,1.205,-2+z*2),(1.94,.03,1.94),'chalk' if (x+z)%5==0 else 'ruin_stone',False,.014)
    elif LOD==1:
        for x in [-4,0,4]:B('paving seam',(x,1.208,0),(.03,.015,5.8),'dark',False,0)

def parapet():
    B('parapet toe',(0,.13,0),(4,.26,.64))
    B('parapet body',(0,.71,0),(4,.92,.44))
    B('crowned coping',(0,1.3,0),(4,.2,.6),'chalk')
    if LOD<2:
        for x in [-1,1]:
            B('inset water cartouche',(x,.72,-.232),(.58,.46,.032),'patina',False,.008)
            if LOD==0:
                for dx in [-.19,0,.19]:B('cartouche reed',(x+dx,.72,-.26),(.042,.34,.04),'chalk',False,.003)
        coursing(0,.7,0,4,.88,.44,3)

def parapet_end():
    B('terminal foot',(0,.16,0),(1,.32,.8))
    B('terminal shaft',(0,.87,0),(.7,1.1,.62))
    B('terminal capital',(0,1.49,0),(.92,.14,.78),'chalk')
    # Faceted sloping hip rather than v2 generic column.
    P('hipped cap',[(-.45,1.56,-.38),(.45,1.56,-.38),(.22,1.8,-.19),(-.22,1.8,-.19),(-.45,1.56,.38),(.45,1.56,.38),(.22,1.8,.19),(-.22,1.8,.19)],'chalk')
    if LOD<2:B('terminal patina panel',(0,.94,-.32),(.36,.66,.025),'patina',False,.007)
    if LOD==0:
        for yy in [.62,.92,1.2]:B('panel relief',(0,yy,-.35),(.22,.05,.035),'chalk',False,.004)

def abutment():
    B('wide abutment plinth',(0,.35,0),(6,.7,8))
    B('main retaining mass',(0,2.9,0),(5.4,4.4,7.2))
    B('support shoulder',(0,5.4,0),(6,1.2,8),'chalk')
    for s in [-1,1]:
        P('splayed retaining rib',[(s*2.7,.7,-3.8),(s*3,.7,-3.8),(s*2.8,5,-3.8),(s*2.7,5,-3.8),(s*2.7,.7,3.8),(s*3,.7,3.8),(s*2.8,5,3.8),(s*2.7,5,3.8)])
    if LOD<2:
        for s in [-1,1]:
            B('water line course',(0,1.3,s*3.64),(5.4,.25,.12),'patina',False)
            coursing(0,2.9,0,5.4,4.4,7.2,7)
    if LOD==0:
        for x in [-1.8,0,1.8]:B('retaining face pilaster',(x,3,-3.72),(.34,4.2,.3),'chalk',False)

def ramp():
    # Axial X ramp, low -X end and high +X end. Solid six-plane convex wedge.
    P('ramped bridge approach',[(-4,0,-3),(4,0,-3),(4,1.2,-3),(-4,.2,-3),(-4,0,3),(4,0,3),(4,1.2,3),(-4,.2,3)],'ruin_stone')
    if LOD<2:
        for s in [-1,1]:
            P('ramp edge',[(-4,.2,s*2.85),(4,1.2,s*2.85),(4,1.32,s*2.85),(-4,.32,s*2.85),(-4,.2,s*3),(4,1.2,s*3),(4,1.32,s*3),(-4,.32,s*3)],'chalk',False)
    if LOD==0:
        for x in [-3,-2,-1,0,1,2,3]:B('transverse ramp joint',(x,.2+(x+4)/8+.013,0),(.035,.028,5.65),'dark',False,0)

def cistern():
    B('cistern floor',(0,.15,0),(8,.3,8),'rock')
    for s in [-1,1]:
        B('cistern side wall',(0,1.65,s*3.5),(8,2.7,1))
        B('vault spring moulding',(0,2.93,s*3.45),(8,.22,1.3),'chalk')
        coursing(0,1.65,s*3.5,8,2.7,1,5)
    arch('continuous barrel vault',3,.7,3,8,[20,14,8][LOD],axis='x')
    if LOD<2:
        for x in [-3.7,0,3.7]:arch('transverse cistern rib',2.9,.18,3,.28,[20,14,8][LOD],center=(x,0,0),axis='x',collision=False)
        for s in [-1,1]:B('shallow floor drain',(0,.308,s*2.4),(8,.016,.32),'patina',False,0)
    if LOD==0:
        for x in [-3,0,3]:B('vault floor marker',(x,.313,0),(.16,.025,3.4),'chalk',False,.008)

def oculus():
    count=[24,16,8][LOD]
    # Square outside / circular inside annulus: no triangles or hull through hole.
    for j in range(count):
        a=j*math.tau/count;b=(j+1)*math.tau/count
        outer=lambda t:(4*math.cos(t)/max(abs(math.cos(t)),abs(math.sin(t))),4*math.sin(t)/max(abs(math.cos(t)),abs(math.sin(t))))
        ax,az=outer(a);bx,bz=outer(b)
        points=[(1.6*math.cos(a),0,1.6*math.sin(a)),(ax,0,az),(bx,0,bz),(1.6*math.cos(b),0,1.6*math.sin(b)),(1.6*math.cos(a),.7,1.6*math.sin(a)),(ax,.7,az),(bx,.7,bz),(1.6*math.cos(b),.7,1.6*math.sin(b))]
        P('open oculus roof sector',points,collision=False)
        if LOD<2:
            p=[(r*math.cos(t),y,r*math.sin(t)) for y in [.7,1.1] for r,t in [(1.6,a),(1.92,a),(1.92,b),(1.6,b)]]
            P('oculus raised lip',p,'chalk',False)
    if LOD==0:
        for j in range(12):
            a=j*math.tau/12;b=(j+1)*math.tau/12
            outer=lambda t:(4*math.cos(t)/max(abs(math.cos(t)),abs(math.sin(t))),4*math.sin(t)/max(abs(math.cos(t)),abs(math.sin(t))))
            angles=[a]+[t for t in [math.pi/4+k*math.pi/2 for k in range(4)] if a+1e-6<t<b-1e-6]+[b]
            outline=[(1.6*math.cos(a),1.6*math.sin(a))]+[outer(t) for t in angles]+[(1.6*math.cos(b),1.6*math.sin(b))]
            convex_col([(x,y,z) for y in [0,.7] for x,z in outline])
            convex_col([(r*math.cos(t),y,r*math.sin(t)) for y in [.7,1.1] for r,t in [(1.6,a),(1.92,a),(1.92,b),(1.6,b)]])
    if LOD==2:
        # Low-LOD keeps the same lip silhouette with eight sectors.
        for j in range(8):
            a=j*math.tau/8;b=(j+1)*math.tau/8
            P('coarse oculus lip',[(r*math.cos(t),y,r*math.sin(t)) for y in [.7,1.1] for r,t in [(1.6,a),(1.92,a),(1.92,b),(1.6,b)]],'chalk',False)
    if LOD==0:
        for s in [-1,1]:
            B('roof edge crest',(s*3.84,.82,0),(.25,.24,8),'chalk',False)
            B('roof edge crest',(0,.82,s*3.84),(7.4,.24,.25),'chalk',False)
        for x,z in [(2.6,0),(-2.6,0),(0,2.6),(0,-2.6)]:B('roof water stain',(x,.713,z),(.38,.024,.9),'patina',False,.008)

def ribbed_pier():
    B('ribbed pier footing',(0,.3,0),(3,.6,3))
    B('square inner pier',(0,4.95,0),(1.65,8.7,1.65))
    for x,z in [(-1,0),(1,0),(0,-1),(0,1)]:
        B('engaged vertical rib',(x,4.95,z),(.42 if x else 1.4,8.7,1.4 if x else .42),'chalk')
    B('pier bearing',(0,9.65,0),(3,.7,3),'chalk')
    if LOD<2:
        for y in [2.5,5,7.5]:B('pier tie collar',(0,y,0),(2.65,.18,2.65),'ruin_stone',False)
    if LOD==0:
        for s in [-1,1]:coursing(0,4.95,s*1.21,1.35,8.7,.06,12)

def sluice():
    for s in [-1,1]:
        B('sluice foot',(s*2.45,.3,0),(1.1,.6,2))
        B('grooved frame pier',(s*2.4,2.8,0),(1.2,4.4,1.4))
        if LOD<2:
            B('gate slide recess',(s*1.79,2.6,0),(.025,4,.24),'dark',False,0)
            for z in [-.62,.62]:B('slide guide rib',(s*1.92,2.6,z),(.25,4,.2),'chalk',False)
        coursing(s*2.4,2.8,0,1.2,4.4,1.4,7)
    B('sluice lintel',(0,5.05,0),(6,.9,1.7))
    B('sluice upper bearing',(0,5.72,0),(5.5,.44,1.5),'chalk')
    B('fixed counterweight housing',(0,6.2,0),(2,.6,1.3),'ruin_stone')
    if LOD==0:
        for x in [-.5,0,.5]:B('housing inset',(x,6.2,-.662),(.23,.32,.027),'patina',False,.006)

def basin_corner():
    for pos,size in [((-2.5,.18,0),(1,.36,6)),((.5,.18,-2.5),(5,.36,1))]:B('basin foundation',pos,size,'rock')
    for pos,size in [((-2.55,.7,0),(.6,.8,6)),((.375,.7,-2.55),(5.25,.8,.6))]:B('basin upright curb',pos,size)
    for pos,size in [((-2.55,1.16,0),(.9,.12,6)),((.45,1.16,-2.55),(5.1,.12,.9))]:B('rolled basin coping',pos,size,'chalk')
    if LOD<2:
        B('mineral waterline',(-2.235,.65,0),(.03,.19,5.8),'patina',False,0)
        B('mineral waterline',(.3,.65,-2.235),(5.1,.19,.03),'patina',False,0)
    if LOD==0:
        for x in [-1,1,2.7]:B('coping joints',(x,1.229,-2.55),(.03,.015,.82),'dark',False,0)
        for z in [-1,1,2.7]:B('coping joints',(-2.55,1.229,z),(.82,.015,.03),'dark',False,0)

def spillway():
    # Cascading hydraulic apron, not a generic stair: wide recessed wet channel,
    # high lateral cheeks, six irregularly spaced spill lips, continuous support.
    count=[8,8,4][LOD]
    for j in range(count):
        height=(j+1)*2.4/count; z=3-(j+.5)*6/count
        B('spill apron tread',(0,height/2,z),(5.2,height,6/count+.015),'rock')
        if LOD<2:B('mineral cascade lip',(0,height+.008,z-3/count+.11),(5,.018,.2),'patina',False,.005)
    for s in [-1,1]:
        P('sloping spillway cheek',[(s*2.6,0,-3),(s*3,0,-3),(s*3,3,-3),(s*2.6,3,-3),(s*2.6,0,3),(s*3,0,3),(s*3,.6,3),(s*2.6,.6,3)])
        if LOD==0:
            for j in range(8):B('spill cheek dressed face',(s*2.99,(j+1)*.3+.18,2.65-j*.75),(.055,.28,.62),'chalk',False,.01)

def portal():
    for s in [-1,1]:
        B('portal base',(s*4.5,.4,0),(3,.8,3))
        B('portal broad pier',(s*4.5,2.4,0),(3,3.2,2.4))
        B('upper portal shoulder',(s*4.6,7.15,0),(2.8,6.3,2.46))
        B('portal spring',(s*4.5,4,0),(3.1,.3,2.7),'chalk')
        coursing(s*4.5,2.4,0,3,3.2,2.4,6)
    arch('deep portal archivolt',3,1,4,2.4,[20,14,8][LOD],spandrel=10.3)
    B('monumental lintel cornice',(0,10.5,0),(12,.4,3),'chalk')
    B('portal attic',(0,10.85,0),(11.4,.3,2.7))
    if LOD<2:
        for s in [-1,1]:
            arch('portal inner trim',3.04,.16,4,.14,[20,14,8][LOD],center=(0,0,s*1.29),collision=False)
            B('ceremonial patina crest',(0,8.8,s*1.26),(1.5,1.15,.1),'patina',False)
    if LOD==0:
        for s in [-1,1]:
            for x in [-5,-4,4,5]:B('portal vertical relief',(x,6.8,s*1.25),(.13,3.4,.11),'chalk',False)
            for x in [-.48,0,.48]:B('crest reed',(x,8.8,s*1.33),(.08,.78,.05),'chalk',False,.005)

def buttress():
    B('buttress footing',(-1.5,.3,0),(2,.6,2))
    B('buttress outer pier',(-1.5,2.7,0),(1.25,4.2,1.5))
    # Sloping flying strut leaves genuine empty space under its diagonal.
    P('flying stone strut',[(-2,4.4,-.7),(-1,4.4,-.7),(2.5,7.3,-.7),(2.5,8,-.7),(-2,4.4,.7),(-1,4.4,.7),(2.5,7.3,.7),(2.5,8,.7)])
    B('upper bearing stone',(2.26,7.76,0),(.58,.48,2),'chalk')
    if LOD<2:
        B('buttress band',(-1.5,3.9,0),(1.6,.2,1.8),'chalk',False)
        coursing(-1.5,2.7,0,1.25,4.2,1.5,6)
    if LOD==0:
        for j in range(5):B('diagonal masonry joint',(-.5+j*.55,5.05+j*.45,-.716),(.04,.5,.035),'dark',False,0)

def marker():
    B('waymarker plinth',(0,.15,0),(1.6,.3,1.4))
    P('tapered marker monolith',[(-.6,.3,-.46),(.6,.3,-.46),(.43,2.88,-.35),(-.43,2.88,-.35),(-.6,.3,.46),(.6,.3,.46),(.43,2.88,.35),(-.43,2.88,.35)])
    B('marker chamfer crown',(0,3.03,0),(.96,.3,.82),'chalk')
    if LOD<2:
        B('wayfinding patina inset',(0,1.75,-.409),(.65,1.8,.065),'patina',False)
        B('directional stem',(0,1.63,-.461),(.08,1.27,.065),'chalk',False,.008)
    if LOD==0:
        for y,w in [(1.25,.48),(1.58,.3),(2.12,.5),(2.35,.35)]:B('carved flow glyph',(0,y,-.47),(w,.09,.055),'chalk',False,.008)
        for s in [-1,1]:B('marker basal flute',(s*.37,.6,-.486),(.055,.37,.05),'dark',False,.004)

def outlet():
    # Mouth toward +X. Empty cross section remains open above a continuous bed.
    B('outlet pedestal',(-1,.6,0),(2,1.2,3.8))
    B('spout bed',(0,1.32,0),(4,.24,2.4))
    for s in [-1,1]:
        B('projecting open spout cheek',(0,1.86,s*1.35),(4,1.08,.3))
        B('outlet side capital',(-1.51,2.705,s*1.34),(.94,.69,.44),'chalk')
        if LOD<2:B('spout patina rail',(0,2.41,s*1.35),(4,.035,.32),'patina',False,.005)
    B('outlet rear lintel',(-1.5,2.77,0),(1,.46,3.2),'chalk')
    if LOD<2:
        B('worn water bed',(0,1.449,0),(3.95,.018,2.35),'patina',False,0)
        B('terminal spill lip',(1.86,1.37,0),(.28,.3,2.6),'chalk',False)
    if LOD==0:
        for s in [-1,1]:
            for x in [-1,.1,1.15]:B('outlet shallow carving',(x,1.9,s*1.512),(.65,.4,.035),'patina',False,.012)

def anchor(name, position, direction):return {'name':name,'position':position,'direction':direction}
SPECS = [
 ('aqueduct_span_12m',aqueduct,[16,14.2,3.6],[anchor('channel_left',[-8,13.4,0],[-1,0,0]),anchor('channel_right',[8,13.4,0],[1,0,0])],{'clear_width':12,'spring_y':6,'crown_y':12,'channel_floor_y':13.4,'repeat_x':16}),
 ('causeway_8m',causeway,[8,2.4,5],[anchor('road_left',[-4,2.4,0],[-1,0,0]),anchor('road_right',[4,2.4,0],[1,0,0])],{'drain_centers_x':[-2.4,0,2.4],'drain_clear_width':1.6,'drain_crown_y':1.45}),
 ('aqueduct_broken_end',broken_end,[8,14.2,3.6],[anchor('channel_left',[-8,13.4,0],[-1,0,0])],{'surviving_side':'negative_x','channel_floor_y':13.4}),
 ('bridge_deck_12m',bridge_deck,[12,1.2,6],[anchor('deck_left',[-6,1.2,0],[-1,0,0]),anchor('deck_right',[6,1.2,0],[1,0,0])],{'walkable_top_y':1.2,'clear_deck_width':6}),
 ('parapet_4m',parapet,[4,1.4,.64],[anchor('left',[-2,0,0],[-1,0,0]),anchor('right',[2,0,0],[1,0,0])],{}),
 ('parapet_end',parapet_end,[1,1.8,.8],[anchor('base',[0,0,0],[0,-1,0])],{}),
 ('bridge_abutment',abutment,[6,6,8],[anchor('bearing',[0,6,0],[0,1,0])],{'bearing_y':6}),
 ('bridge_ramp_8m',ramp,[8,1.32,6],[anchor('low_end',[-4,.2,0],[-1,0,0]),anchor('high_end',[4,1.2,0],[1,0,0])],{'slope_axis':'positive_x','rise':1,'run':8}),
 ('cistern_vault_8m',cistern,[8,6.7,8],[anchor('passage_left',[-4,.3,0],[-1,0,0]),anchor('passage_right',[4,.3,0],[1,0,0])],{'clear_width_z':6,'spring_y':3,'crown_y':6,'floor_y':.3}),
 ('oculus_roof_8m',oculus,[8,1.1,8],[anchor('roof_base',[0,0,0],[0,-1,0]),anchor('oculus',[0,.7,0],[0,1,0])],{'oculus_clear_diameter':3.2,'placement':'elevate whole module above courtyard; aperture never collides'}),
 ('ribbed_pier_10m',ribbed_pier,[3,10,3],[anchor('bearing',[0,10,0],[0,1,0])],{}),
 ('sluice_frame_6m',sluice,[6,6.5,2],[anchor('aperture',[0,0,0],[0,0,-1])],{'clear_width':3.6,'clear_height':4.6,'moving_parts':False}),
 ('basin_corner_6m',basin_corner,[6,1.22,6],[anchor('rim_x',[3,0,-2.55],[1,0,0]),anchor('rim_z',[-2.55,0,3],[0,0,1])],{'rim_arms':'negative_x and negative_z; interior positive_x/positive_z'}),
 ('spillway_steps_6m',spillway,[6,3,6],[anchor('high',[0,2.4,-3],[0,0,-1]),anchor('low',[0,.3,3],[0,0,1])],{'flow_axis':'positive_z','channel_clear_width':5.2}),
 ('monumental_portal',portal,[12,11,3],[anchor('passage',[0,0,0],[0,0,-1])],{'clear_width':6,'spring_y':4,'crown_y':7}),
 ('flying_buttress',buttress,[5,8,2],[anchor('upper_bearing',[2.5,7.76,0],[1,0,0])],{'open_below_diagonal':True}),
 ('carved_waymarker',marker,[1.6,3.2,1.4],[anchor('base',[0,0,0],[0,-1,0])],{}),
 ('water_outlet',outlet,[4,3,3.8],[anchor('inlet',[-2,1.44,0],[-1,0,0]),anchor('mouth',[2,1.44,0],[1,0,0])],{'flow_axis':'positive_x','clear_channel_width':2.4,'water_surface_not_included':True}),
]
PROBES = {
    'aqueduct_span_12m': [([-1,3,-4],[-1,3,4],'clear'),([0,11.8,-4],[0,11.8,4],'clear'),([6.8,3,-4],[6.8,3,4],'hit'),([0,14.8,0],[0,12.8,0],'hit'),([-8.1,13.7,0],[8.1,13.7,0],'clear')],
    'causeway_8m': [([0,1,-4],[0,1,4],'clear'),([0,3,0],[0,1.7,0],'hit')],
    'bridge_deck_12m': [([0,3,0],[0,0,0],'hit')],
    'bridge_ramp_8m': [([0,2,0],[0,-1,0],'hit')],
    'cistern_vault_8m': [([-5,2,0],[5,2,0],'clear'),([-5,5.7,0],[5,5.7,0],'clear'),([0,7,0],[0,5.8,0],'hit'),([0,2,0],[0,-1,0],'hit')],
    'oculus_roof_8m': [([0,3,0],[0,-1,0],'clear'),([1,3,0],[1,-1,0],'clear'),([3,3,0],[3,-1,0],'hit')],
    'sluice_frame_6m': [([0,2,-3],[0,2,3],'clear'),([0,4.4,-3],[0,4.4,3],'clear'),([2.4,2,-3],[2.4,2,3],'hit')],
    'monumental_portal': [([0,3,-4],[0,3,4],'clear'),([0,6.7,-4],[0,6.7,4],'clear'),([4.5,3,-4],[4.5,3,4],'hit')],
    'water_outlet': [([-2.1,1.9,0],[2.1,1.9,0],'clear'),([1,3,0],[1,1,0],'hit')],
    'flying_buttress': [([1,3,-2],[1,3,2],'clear'),([-1.5,2,-2],[-1.5,2,2],'hit')],
}
for index,(name,builder,nominal,anchors,assembly) in enumerate(SPECS):
    variants=[]; counts=[]; collision=[]; bounds=[]
    for lod in range(3):
        LOD=lod;OBS=[];COLL=[]
        builder()
        bpy.ops.object.select_all(action='DESELECT')
        for ob in OBS:ob.select_set(True)
        bpy.context.view_layer.objects.active=OBS[0]; bpy.ops.object.join()
        ob=bpy.context.object; ob.name=name+f'_LOD{lod}'
        bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        ob.data.materials.clear();ob.data.materials.append(mat)
        for poly in ob.data.polygons:poly.material_index=0
        tri=ob.modifiers.new('Explicit runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
        ob.data.validate(verbose=False, clean_customdata=False);ob.data.update()
        assert len(ob.data.uv_layers)==1
        counts.append(len(ob.data.polygons))
        ob['asset_id']=name;ob['lod']=lod;ob['source_seed']=SEED;ob['metres']=True
        ob['original_design']='Stonewater original hydraulic architecture'
        ob['lod_method']='Semantic rebuild: fewer voussoirs and no small relief/chamfers'
        path=ROOT/f'models/stonewater/{name}_lod{lod}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,export_cameras=False,export_lights=False,export_animations=False)
        if lod==0:
            collision=COLL.copy();bounds=rounded([[v[0],v[2],-v[1]] for v in ob.bound_box])
        variants.append(ob)
        ob.hide_set(True)
    assert counts[0]>counts[1]>counts[2]>0,(name,counts)
    record={'id':name,'category':'hydraulic_architecture','runtime':f'models/stonewater/{name}_lod0.glb','lod_paths':[f'models/stonewater/{name}_lod{i}.glb' for i in range(3)],'lod_triangles':counts,'lod_method':'semantic geometry rebuild; passage voids retained at every LOD','material':'AncientValley_Atlas_1K','atlas':'textures/ancient_valley/atlas_1k.png','collision':'compound','collision_shapes':collision,'collision_shape_count':len(collision),'collision_max_curve_chord_error_metres':.07,'collision_notes':'Independent 12-sector large arches/oculus, 6-sector drains; structural opening chords deviate inward by at most 6cm; exterior chords by at most 7cm. Reliefs are visual-only.','bounds_godot':bounds,'nominal_size':nominal,'pivot':'ground-origin local metres; roof module base at local Y0','grid_metres':2,'anchors':anchors,'sockets':{a['name']:a['position'] for a in anchors},'assembly':assembly,'license':'CC0-1.0','provenance':'Original deterministic Blender geometry; tools/art/generate_stonewater.py','budgets':{'max_lod0_triangles':9000,'max_lod1_triangles':2500,'max_lod2_triangles':1500,'mesh_surfaces':1,'materials':1,'embedded_images':0}}
    assert counts[0]<9000 and counts[1]<2500 and counts[2]<1500,(name,counts)
    record['passage_probes']=[{'from':a,'to':b,'expect':expect} for a,b,expect in PROBES.get(name,[])]
    manifest.append(record);assets.append((name,variants))
    prefab='[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://art/scripts/stonewater_asset.gd" id="1"]\n\n[node name="'+name+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+name+'"\n'
    (ROOT/f'environment/stonewater/{name}.tscn').write_text(prefab)
    print('STONEWATER_ASSET',name,counts,len(collision),flush=True)
# Editable catalogue. Exported models remain at their authored local origin.
for index,(name,variants) in enumerate(assets):
    collection=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(collection)
    for ob in variants:
        for old in list(ob.users_collection):old.objects.unlink(ob)
        collection.objects.link(ob)
        ob.location=vec(((index%6)*24,0,(index//6)*24))
        ob.hide_set(not ob.name.endswith('_LOD0'));ob.hide_render=not ob.name.endswith('_LOD0')
        ob['catalogue_offset_only']=True
# Exact manifest collision recipes are editable, independently inspectable proxies.
# Their collection is disabled for both viewport and render, and is never exported.
import bmesh
collision_collection=bpy.data.collections.new('COLLISION_RECIPES_DISABLED')
bpy.context.scene.collection.children.link(collision_collection)
for index,record in enumerate(manifest):
    offset=vec(((index%6)*24,0,(index//6)*24))
    for shape_index,shape in enumerate(record['collision_shapes']):
        if shape['type']=='box':
            x,y,z=shape['position'];sx,sy,sz=[v/2 for v in shape['size']]
            points=[(x+dx*sx,y+dy*sy,z+dz*sz) for dx in [-1,1] for dy in [-1,1] for dz in [-1,1]]
        else:points=shape['points']
        bm=bmesh.new()
        for point in points:bm.verts.new(vec(point))
        hull=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
        bmesh.ops.delete(bm,geom=list(set(hull['geom_interior'])|set(hull['geom_unused'])),context='VERTS')
        mesh=bpy.data.meshes.new(record['id']+f'_COL_{shape_index:02d}');bm.to_mesh(mesh);bm.free()
        proxy=bpy.data.objects.new(mesh.name,mesh);collision_collection.objects.link(proxy)
        proxy.location=offset;proxy.display_type='WIRE';proxy.hide_render=True
        proxy['collision_recipe']=json.dumps(shape,sort_keys=True)
        proxy['asset_id']=record['id'];proxy['recipe_index']=shape_index
collision_collection.hide_viewport=True;collision_collection.hide_render=True
scene=bpy.context.scene;scene.name='Stonewater v3 editable hydraulic architecture'
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene['seed']=SEED;scene['atlas_reuse']='Ancient Valley 1024x1024; no new images';scene['license']='CC0-1.0'
scene['coordinate_convention']='Godot X right, Y up, Z depth; model export pivot ground origin'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/stonewater.blend'),compress=True)
result={'version':3,'kit':'Stonewater','seed':SEED,'source':'art/source/stonewater.blend','generator':'tools/art/generate_stonewater.py','grid_metres':2,'coordinate_system':'Godot right-handed Y-up metres','shared_material':'AncientValley_Atlas_1K','shared_atlas':'textures/ancient_valley/atlas_1k.png','collision_schema':'Separate local-space box(position,size,rotation radians) or convex(points) recipes; never use whole-object hull for openings. Recipes represent structural solids, decorative relief is non-colliding.','assets':manifest}
(ROOT/'assets/stonewater_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
print('STONEWATER_GENERATION_OK',len(manifest),[sum(a['lod_triangles'][i] for a in manifest) for i in range(3)],flush=True)
