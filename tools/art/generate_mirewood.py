"""Mirewood, original wetland root and drowned-ruin kit. Local Blender only.
Full regeneration requires --regenerate to protect manual source edits.
"""
import ast, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
if (ROOT/'art/source/mirewood.blend').exists() and '--regenerate' not in sys.argv:
    raise RuntimeError('Existing editable source protected. Use -- --regenerate deliberately.')
source=ast.parse((ROOT/'tools/art/generate_art.py').read_text())
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[]),'art_primitives','exec'))
source=ast.parse((ROOT/'tools/art/generate_saltwind.py').read_text())
helpers={'uv_project','rounded','box_col','convex_col','B','P','prism','coursing'}
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name in helpers],type_ignores=[]),'reviewed_helpers','exec'))
SEED=58231
random.seed(SEED)
for folder in ['models/mirewood','environment/mirewood','art/source','assets','textures/mirewood']:(ROOT/folder).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials):bpy.data.materials.remove(material)
TILES={n:i for i,n in enumerate(['grass','rock','ruin_stone','basalt','soil','sand','path','bark','leaf','dry_grass','fur','patina','dark','chalk','moss','worn_gold'])}
palette=[(.29,.35,.20),(.36,.39,.33),(.47,.49,.40),(.25,.29,.27),(.25,.23,.17),(.43,.43,.33),(.38,.35,.26),(.27,.25,.18),(.29,.36,.22),(.41,.43,.25),(.32,.32,.24),(.31,.41,.32),(.12,.17,.15),(.60,.61,.49),(.34,.42,.24),(.48,.43,.26)]
atlas=np.zeros((1024,1024,3))
for i,color in enumerate(palette):
    field=texture_field(256,SEED+i,list(TILES)[i])*.7
    yy,xx=np.mgrid[:256,:256]/256
    if i==7:field+=.022*np.sin(xx*math.tau*19+np.sin(yy*math.tau*3))
    if i==14:field+=.018*np.sin(xx*math.tau*7)*np.cos(yy*math.tau*9)
    atlas[(i//4)*256:(i//4+1)*256,(i%4)*256:(i%4+1)*256]=np.array(color)[None,None,:]+field[:,:,None]
atlas_img=write_png(ROOT/'textures/mirewood/atlas_1k.png',atlas)
for name,color in [('peat',(.23,.24,.17)),('moss',(.32,.39,.23))]:
    field=texture_field(1024,SEED+len(name),'soil')*.8
    write_png(ROOT/f'textures/mirewood/{name}_albedo.png',np.array(color)[None,None,:]+field[:,:,None])
    gx=(np.roll(field,-1,1)-np.roll(field,1,1))*.5;gy=(np.roll(field,-1,0)-np.roll(field,1,0))*.5
    normal=np.stack((-gx*8,-gy*8,np.ones_like(field)),axis=-1);normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    write_png(ROOT/f'textures/mirewood/{name}_normal.png',normal*.5+.5)
mat=bpy.data.materials.new('Mirewood_Atlas_1K');mat.use_nodes=True
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas_img
mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.9
FACES=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
OBS,COLL,LOD=[],[],0
assets,manifest=[],[]

def limb(points,radius=.3,tile='bark',collision=False):
    # Continuous swept curved tube: shared rings avoid visible elbow seams.
    guides=[Vector(p) for p in points];pts=[]
    # Catmull-Rom sweep softens authored changes of direction without decimation.
    samples=[3,2,1][LOD]
    for j in range(len(guides)-1):
        p0=guides[max(0,j-1)];p1=guides[j];p2=guides[j+1];p3=guides[min(j+2,len(guides)-1)]
        for k in range(samples):
            t=k/samples
            pts.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
    pts.append(guides[-1]);n=[10,7,5][LOD];verts=[]
    for j,p in enumerate(pts):
        tangent=(pts[min(j+1,len(pts)-1)]-pts[max(j-1,0)]).normalized()
        u=tangent.cross(Vector((0,0,1))).normalized()
        if u.length<.1:u=tangent.cross(Vector((1,0,0))).normalized()
        v=tangent.cross(u).normalized();rad=radius*(1-.76*j/(len(pts)-1))
        for k in range(n):verts.append(tuple(p+rad*(math.cos(k*math.tau/n)*u+math.sin(k*math.tau/n)*v)))
    faces=[tuple(reversed(range(n))),tuple((len(pts)-1)*n+k for k in range(n))]
    for j in range(len(pts)-1):
        for k in range(n):a=j*n+k;b=j*n+(k+1)%n;faces.append((a,b,b+n,a+n))
    OBS.append(mesh_object('organic continuous root',verts,faces,tile))
    if collision:
        for j in range(len(guides)-1):
            start=j*samples;end=(j+1)*samples
            convex_col([verts[start*n+k] for k in range(n)]+[verts[end*n+k] for k in range(n)])

def root_fan(cx=0,cz=0,spread=6,height=2,count=7):
    for i in range(count):
        a=i*2.399+.4;d=spread*(.7+.3*math.sin(i*1.7)**2)
        points=[(cx,.8*height,cz),(cx+math.cos(a)*d*.32,height*(.45+.25*(i%2)),cz+math.sin(a)*d*.32),(cx+math.cos(a)*d*.68,.25,cz+math.sin(a)*d*.68),(cx+math.cos(a)*d,-.13,cz+math.sin(a)*d)]
        limb(points,.65 if spread>5 else .34,collision=True)
        if LOD==0:limb([points[2],(points[2][0]+.7,.05,points[2][2]-.6),(points[-1][0]+1,-.15,points[-1][2]-.5)],.14)

def mound(name,rx,rz,h,center=(0,0,0),tile='soil',col=True):
    sides=[24,16,10][LOD]
    ob=rings(name,[(rx*.8,rz*.8),(rx,rz),(rx*.83,rz*.83),(rx*.28,rz*.28)],[-.6,.0,h*.55,h],center,tile,sides,51,.14);OBS.append(ob)
    if col:
        points=[]
        for y,f in [(-.5,.78),(h*.58,.8),(h,.23)]:
            for k in range(8):a=k*math.tau/8;points.append((center[0]+math.cos(a)*rx*f,center[1]+y,center[2]+math.sin(a)*rz*f))
        convex_col(points)
    if LOD<2:
        OBS.append(rings('soft moss crown',[(rx*.75,rz*.75),(rx*.2,rz*.2)],[h*.59,h+.03],center,'moss',sides,51,.14))

def island():mound('root island',6,4,1.2);root_fan(spread=7,height=1.1,count=7)
def crescent():
    # Three overlapping soil lobes leave a real open water-facing crescent.
    for x,z in [(-4,0),(0,2),(4,0)]:mound('crescent lobe',3.8,2.6,.8,(x,0,z));root_fan(x,z,3,.65,3)
def bank():
    mound('shore bank',8,3,1.5);root_fan(-4,0,4,1.2,4);root_fan(3,0,4,1.3,4)
def bank_corner():
    mound('bank turn left',5,2.7,1.4,(-2,0,0));mound('bank turn right',2.7,5,1.4,(0,0,2));root_fan(0,1,5,1.4,6)
def root_bridge():
    for x in [-1.2,1.2]:limb([(x,0,-7),(x*.8,1.8,-3),(x*.6,2.8,0),(x,1.8,3),(x*1.3,0,7)],.9,collision=True)
    for i in range([7,5,3][LOD]):z=-4+i*8/([7,5,3][LOD]-1);limb([(-1.2,2.4-abs(z)*.13,z),(0,2.55-abs(z)*.13,z+.2),(1.2,2.4-abs(z)*.13,z)],.15,'moss')
def buttress():root_fan(spread=8,height=4,count=6);limb([(0,0,0),(.2,3,0),(1,7,.5)],1.3,collision=True)
def hollow(vertical=True,broken=False):
    # Irregular tapered rings with an actual bore, never a capped cylinder.
    n=[28,18,12][LOD];verts=[];length=10 if not vertical else 14
    stages=[0,.27,.64,1]
    def ringpoint(t,r,a):
        taper=1-.26*t if vertical else 1-.06*math.sin(t*math.pi)
        relief=1+.045*math.sin(a*7+.5)+.025*math.sin(a*11+1)
        h=t*length+(math.sin(a*3)*.9+.4*math.cos(a*5) if t==1 and broken else 0)
        p=(math.cos(a)*r*taper*relief+.7*t*t,h,math.sin(a)*r*taper*relief+.18*math.sin(t*math.pi))
        return p if vertical else (p[0],p[2]+2.7,p[1]-5)
    for t in stages:
        for r in [2.7,1.85]:
            for k in range(n):verts.append(ringpoint(t,r,k*math.tau/n))
    faces=[]
    for j in range(len(stages)-1):
        base=j*2*n
        for k in range(n):
            nxt=(k+1)%n
            faces.extend([(base+k,base+nxt,base+2*n+nxt,base+2*n+k),(base+n+nxt,base+n+k,base+3*n+k,base+3*n+nxt)])
    for k in range(n):
        nxt=(k+1)%n;top=(len(stages)-1)*2*n
        faces.extend([(nxt,k,n+k,n+nxt),(top+k,top+nxt,top+n+nxt,top+n+k)])
    OBS.append(mesh_object('bent open hollow trunk',verts,faces,'bark'))
    for j in range(len(stages)-1):
        for k in range(8):
            convex_col([ringpoint(t,radius,angle) for t in stages[j:j+2] for radius,angle in [(1.9,(k-.5)*math.tau/8),(2.6,(k-.5)*math.tau/8),(2.6,(k+.5)*math.tau/8),(1.9,(k+.5)*math.tau/8)]])
    if vertical:
        root_fan(spread=7,height=2.3,count=6)
        for i in range([4,3,2][LOD]):
            a=i*2.4;h=6+i*1.5
            limb([(math.cos(a)*1.8,h,math.sin(a)*1.8),(math.cos(a)*3,h+.8,math.sin(a)*3),(math.cos(a)*3.9,h+.5,math.sin(a)*3.9)],.22)
    else:
        for i in range([7,4,2][LOD]):
            z=-4+i*1.25;limb([(-1.6,4.8,z),(-.7,5.6,z+.3),(.8,5.3,z+.4),(1.8,4.5,z+.7)],.14,'moss')

def stump():
    # Short hollow stump and lateral regrowth, distinct from the passage log.
    for i in range([9,6,4][LOD]):
        a=i*math.tau/[9,6,4][LOD];limb([(math.cos(a)*1.8,0,math.sin(a)*1.8),(math.cos(a)*1.5,2.5+.5*math.sin(a*3),math.sin(a)*1.5)],.5,collision=True)
    root_fan(spread=5,height=1.3,count=5)
def elder():
    root_fan(spread=9,height=3,count=7)
    limb([(0,0,0),(-.6,6,.4),(.8,12,0),(-.4,17,.9)],1.8,collision=True)
    for i in range([9,6,4][LOD]):
        a=i*2.4;h=8+(i%4)*2;end=(math.cos(a)*7,h+4,math.sin(a)*5)
        limb([(.1,h,0),(end[0]*.5,h+2,end[2]*.5),end,(end[0]*1.15,h+2.5,end[2]*1.15)],.5)
        # Layered irregular leaf masses stay readable in every distance band.
        for j in range([3,2,1][LOD]):
            loc=(end[0]+math.sin(i*1.7+j)*1.2,end[1]-.3+j*.35,end[2]+math.cos(i*2+j)*.8)
            OBS.append(rock('torn elder leaf mass',(3.8,1.5,3.0),i*7+j,'leaf',[2,1,1][LOD],loc))
        if LOD==0:
            limb([end,(end[0]+.4,end[1]-1.2,end[2]+.2),(end[0]+.2,end[1]-2.3,end[2]+.4)],.065,'moss')
def fallen():limb([(-8,.4,-1),(-4,1.4,-.3),(0,1.6,.2),(4,1,1),(7,.3,2)],1.3,collision=True);root_fan(-7,-1,4,1.5,5)
def knees():
    for i in range([8,5,3][LOD]):
        x=math.sin(i*4.2)*2.3;z=math.cos(i*2.4)*1.5
        limb([(x,-.2,z),(x+.15,.8+(i%3)*.4,z),(x+.3,-.15,z+.4)],.33)

def walkway(kind):
    # 4m grid, timber cross-planks over two structural beams.
    length=8;gap=kind=='broken';turn=kind=='turn'
    for x in [-1.05,1.05]:
        if gap:
            for z in [-2.7,2.7]:B('broken stringer',(x,1.0,z),(.23,.3,2.6),'bark')
        else:B('long stringer',(x,1.0,0),(.23,.3,length),'bark')
    count=[17,13,9][LOD]
    for i in range(count):
        z=-3.8+i*7.6/(count-1)
        if gap and abs(z)<1.3:continue
        B('uneven cross plank',(0,1.22+.025*math.sin(i*2),z),(2.8,.18,7.6/count*.86),'path',False,.035)
    # Independent broad contact strips, gap remains open.
    if gap:
        for z in [-2.65,2.65]:box_col((0,1.15,z),(2.8,.28,2.7))
    else:box_col((0,1.15,0),(2.8,.28,8))
    for x in [-1.25,1.25]:
        for z in [-3.5,3.5]:B('embedded pile',(x,.6,z),(.25,2.5,.25),'bark')
    if kind=='rail':
        for x in [-1.35,1.35]:
            B('handrail',(x,2.2,0),(.12,.13,8),'bark')
            for z in [-3,0,3]:B('railing upright',(x,1.75,z),(.13,1.3,.13),'bark')
    if turn:
        B('landing turn',(2,1.15,2.7),(2,.3,2.6),'path');B('turn pile',(2.8,.2,3.5),(.3,2.4,.3),'bark')
def landing():
    for x in [-2,2]:B('landing beam',(x,1.0,0),(.3,.4,6),'bark')
    for i in range([16,11,7][LOD]):B('landing planks',(0,1.26,-2.8+i*5.6/([16,11,7][LOD]-1)),(5,.2,5.6/[16,11,7][LOD]*.9),'path',False)
    box_col((0,1.26,0),(5,.2,6))
    for x in [-2,2]:
        for z in [-2.5,2.5]:B('landing post',(x,.3,z),(.35,2.3,.35),'bark')
def piles():
    for x,h,z in [(-1,2,-1),(.8,1.4,0),(-.3,2.8,1)]:
        limb([(x,-.8,z),(x+.1,h,z+.15)],.24,collision=True)
        if LOD<2:B('wet band',(x,.45,z),(.48,.07,.48),'patina',False)

def arch():
    # Wide pointed arch assembled from contiguous voussoir wedges.
    for x in [-5,5]:B('moss gate pier',(x,3.5,0),(2,7,3));coursing(x,3.5,0,2,7,3)
    n=[15,11,7][LOD]
    for i in range(n):
        a=i*math.pi/n;b=(i+1)*math.pi/n
        polygon=[(math.cos(a)*4,6+math.sin(a)*5),(math.cos(b)*4,6+math.sin(b)*5),(math.cos(b)*6,6+math.sin(b)*7),(math.cos(a)*6,6+math.sin(a)*7)]
        prism('pointed drowned arch',polygon,-1.5,1.5,'ruin_stone')
    for x in [-5,5]:root_fan(x,0,4.5,3,4)
    limb([(-5,1,-1.7),(-4.3,5,-1.7),(-2.8,9,-1.65),(-.7,12,-1.55)],.38,'moss')
def tunnel():
    for x in [-3.6,3.6]:B('buried passage wall',(x,2.5,0),(1.6,5,8));coursing(x,2.5,0,1.6,5,8)
    B('contiguous buried roof',(0,5.1,0),(8.8,1.2,8))
    mound('tunnel moss roof',5,4.8,1.4,(0,5.5,0),'moss',False)
    for x in [-4.0,4.0]:limb([(x,0,-4.2),(x,3,-4.2),(x*.6,6,-4.1)],.6,collision=True)
def shrine():
    B('sunken dais',(0,.3,0),(7,.6,7));B('altar',(0,1.6,0),(2.8,2,2.8));
    for x in [-2.7,2.7]:B('shrine side',(x,3.5,1.8),(.8,7,.8));coursing(x,3.5,1.8,.8,7,.8)
    B('broken roof',(0,7.0,1.8),(6.5,.8,2.6));root_fan(2,1,4,2,4)
    if LOD<2:B('abstract concentric relief',(0,2.1,-1.44),(1.4,.25,.10),'patina',False)
def wall():
    B('submerged masonry',(0,1.4,0),(10,2.8,1.8));coursing(0,1.4,0,10,2.8,1.8)
    for x,h in [(-3.5,1.3),(0,.5),(3,1)]:mound('moss cap',2.3,1.1,h,(x,2.45,0),'moss',False)
    root_fan(-3,0,3,2,3)
def steps():
    for i in range(7):B('drowned broad step',(0,.16+i*.23,-3+i),(6,.32+i*.46,1.04),'ruin_stone',False)
    # The render stairs remain separate from a single inexpensive ramp proxy.
    convex_col([(-3,0,-3.5),(3,0,-3.5),(3,0,3.5),(-3,0,3.5),(-3,.32,-3.5),(3,.32,-3.5),(3,3.08,3.5),(-3,3.08,3.5)])
    if LOD<2:root_fan(2,2,2.5,.8,3)
def well():
    n=[20,14,10][LOD]
    for i in range(n):
        a=i*math.tau/n;b=(i+1)*math.tau/n
        points=[(math.cos(t)*r,y,math.sin(t)*r) for y in [0,1.4] for r,t in [(2,a),(2,b),(2.8,b),(2.8,a)]]
        P('open stone well ring',points,'ruin_stone')
    root_fan(2,0,3,1.5,4)
def waystone():
    B('leaning marker base',(0,.3,0),(2.8,.6,2));B('marker',(0,2.5,0),(1.4,4.5,.8));coursing(0,2.5,0,1.4,4.5,.8)
    root_fan(0,0,2.2,1,3)

def sedge():
    for i in range([27,16,8][LOD]):
        a=i*2.399;OBS.append(blade('broad wetland blade',(math.cos(a)*.22,0,math.sin(a)*.22),.7+(i%7)*.12,.13,a,'grass',.8))
def rush():
    for i in range([19,11,5][LOD]):
        a=i*2.4;x=math.cos(a)*.4;z=math.sin(a)*.4;h=1.6+(i%5)*.2
        limb([(x,0,z),(x+.08,h*.6,z),(x+.2,h,z+.05)],.032,'grass')
        if LOD<2:limb([(x+.2,h-.35,z+.05),(x+.2,h+.07,z+.05)],.08,'bark')
def fern():
    for i in range([8,6,4][LOD]):
        a=i*2.4;direction=Vector((math.cos(a),0,math.sin(a)));cross=Vector((-math.sin(a),0,math.cos(a)))
        def point(t):return direction*t*1.5+Vector((0,math.sin(t*math.pi)*.7+.1,0))
        limb([tuple(point(t)) for t in [0,.3,.65,1]],.025,'grass')
        for j in range([7,5,3][LOD]):
            t=(j+1)/([7,5,3][LOD]+1);p=point(t);length=.44*(1-t*.68)
            for side in [-1,1]:
                tip=p+cross*length*side+direction*.13
                verts=[tuple(p-direction*.035),tuple(p+cross*length*.5*side-direction*.075),tuple(tip),tuple(p+cross*length*.5*side+direction*.13)]
                OBS.append(mesh_object('attached paired fern pinna',verts,[(0,1,2),(0,2,3)],'leaf'))

def lilies():
    for i in range([9,6,3][LOD]):
        a=i*2.4;x=math.cos(a)*1.3;z=math.sin(a)*1.2;r=.32+(i%3)*.07;n=[12,8,6][LOD]
        verts=[(x,.015+i*.001,z)]+[(x+math.cos(.3+k*(math.tau-.6)/(n-1))*r,.02+i*.001,z+math.sin(.3+k*(math.tau-.6)/(n-1))*r) for k in range(n)]
        OBS.append(mesh_object('notched lily pad',verts,[(0,k,k+1) for k in range(1,n)],'leaf'))
def hummock():mound('peat hummock',2,1.6,.6);sedge()
def curtain():
    for i in range([15,9,5][LOD]):
        x=-2+i*4/([15,9,5][LOD]-1);h=1.5+.8*math.sin(i*1.8)**2
        limb([(x,3,0),(x+.12,3-h*.5,.15),(x-.12,3-h,.3)],.09,'moss')

SPECS=[('root_island',island,'shore'),('crescent_island',crescent,'shore'),('root_bank_16m',bank,'shore'),('root_bank_corner',bank_corner,'shore'),('woven_root_bridge',root_bridge,'roots'),('buttress_root',buttress,'roots'),('hollow_elder_trunk',lambda:hollow(True,True),'trees'),('hollow_fallen_log',lambda:hollow(False),'trees'),('crown_stump',stump,'trees'),('fen_elder_tree',elder,'trees'),('fallen_root_tree',fallen,'trees'),('cypress_knees',knees,'vegetation'),('boardwalk_8m',lambda:walkway('straight'),'walkway'),('boardwalk_broken',lambda:walkway('broken'),'walkway'),('boardwalk_railed',lambda:walkway('rail'),'walkway'),('boardwalk_turn',lambda:walkway('turn'),'walkway'),('mooring_landing',landing,'walkway'),('old_mooring_piles',piles,'walkway'),('rootbound_gate',arch,'ruins'),('buried_moss_passage',tunnel,'ruins'),('drowned_shrine',shrine,'ruins'),('moss_retaining_wall',wall,'ruins'),('drowned_stairs',steps,'ruins'),('rootwell_ring',well,'ruins'),('fen_waystone',waystone,'ruins'),('broad_sedge',sedge,'vegetation'),('cattail_rush',rush,'vegetation'),('marsh_fern',fern,'vegetation'),('lily_pad_raft',lilies,'vegetation'),('peat_hummock',hummock,'shore'),('hanging_moss',curtain,'vegetation')]
PROBES={
'rootbound_gate':[([0,4,-5],[0,4,5],'clear'),([5,4,-5],[5,4,5],'hit'),([0,16,0],[0,10,0],'hit')],
'buried_moss_passage':[([0,2,-6],[0,2,6],'clear'),([3.6,2,-6],[3.6,2,6],'hit'),([0,9,0],[0,4,0],'hit')],
'hollow_fallen_log':[([0,2.7,-8],[0,2.7,8],'clear'),([2.3,2.7,-8],[2.3,2.7,8],'hit')],
'hollow_elder_trunk':[([0,18,0],[0,3,0],'clear')],
'boardwalk_broken':[([0,3,0],[0,-1,0],'clear'),([0,3,2.5],[0,-1,2.5],'hit')],
'rootwell_ring':[([0,4,0],[0,-1,0],'clear'),([2.4,4,0],[2.4,-1,0],'hit')],
'boardwalk_8m':[([0,4,0],[0,-1,0],'hit')],
'drowned_stairs':[([0,5,0],[0,-1,0],'hit')],
'woven_root_bridge':[([0,.5,-3],[0,.5,3],'clear')]
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
        ob['original_design']='Mirewood original wetland geometry';ob['metres']=True
        path=ROOT/f'models/mirewood/{name}_lod{lod}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_normals=True,export_texcoords=True,export_cameras=False,export_lights=False,export_animations=False)
        if lod==0:collision=COLL.copy();bounds=rounded([[v[0],v[2],-v[1]] for v in ob.bound_box])
        variants.append(ob);ob.hide_set(True)
    assert counts[0]>counts[1]>=counts[2]>0,(name,counts)
    nominal=[round(max(v[k] for v in bounds)-min(v[k] for v in bounds),3) for k in range(3)]
    record={'id':name,'category':category,'runtime':f'models/mirewood/{name}_lod0.glb','lod_paths':[f'models/mirewood/{name}_lod{i}.glb' for i in range(3)],'lod_triangles':counts,'lod_method':'semantic silhouette rebuild with fewer profile rings, sides, twigs and relief','material':'Mirewood_Atlas_1K','atlas':'textures/mirewood/atlas_1k.png','collision':'compound' if collision else 'none','collision_shapes':collision,'collision_shape_count':len(collision),'collision_notes':'Independent boxes and coarse swept-root/annular hulls; small vegetation has none. Hollow bores and structural passages retained. No climbing contract.','bounds_godot':bounds,'nominal_size':nominal,'pivot':'ground-origin local metres','anchors':[{'name':'ground','position':[0,0,0]}],'license':'CC0-1.0','provenance':'Original deterministic Blender geometry; tools/art/generate_mirewood.py','passage_probes':[{'from':a,'to':b,'expect':e} for a,b,e in PROBES.get(name,[])]}
    manifest.append(record);assets.append((name,variants))
    (ROOT/f'environment/mirewood/{name}.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://art/scripts/mirewood_asset.gd" id="1"]\n[node name="'+name+'" type="Node3D"]\nscript = ExtResource("1")\nmodel_id = "'+name+'"\n')
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
scene=bpy.context.scene;scene.name='Mirewood Fen v5 editable catalogue';scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene['seed']=SEED;scene['license']='CC0-1.0';scene['atlas']='Original Mirewood shared 1K atlas'
bpy.context.preferences.filepaths.save_version=0
for image in list(bpy.data.images):
    if image.users==0:bpy.data.images.remove(image)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/mirewood.blend'),compress=True)
result={'version':5,'kit':'Mirewood Fen','seed':SEED,'source':'art/source/mirewood.blend','generator':'tools/art/generate_mirewood.py','coordinate_system':'Godot Y-up metres; -Z forward','shared_atlas':'textures/mirewood/atlas_1k.png','assets':manifest}
(ROOT/'assets/mirewood_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
print('MIREWOOD_GENERATION_OK',len(manifest),[sum(a['lod_triangles'][i] for a in manifest) for i in range(3)],flush=True)
