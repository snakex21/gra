"""Original split-finger bow-string hook, with a relaxed release shape.

Wrist-local -Y follows the forearm, -Z is the finger-row up direction. The
contact lies between the index and middle fingers at (0,-.090,0); it is a
string contact, not a cylindrical grip around the arrow shaft. The closed
sword/rein hand and its HandGrip marker remain untouched.
"""
import math
from mathutils import Vector

def build_archery_hand(api, wrist):
    bpy=api['bpy']; mesh=api['mesh']; vec=api['vec']
    def geometry(opened):
        verts=[];faces=[];finger_ranges=[]
        def add(v,f):
            off=len(verts);verts.extend(v);faces.extend(tuple(off+i for i in face) for face in f)
        # Anatomical palm: thick at the wrist, flattened across the metacarpals.
        rows=[(.006,.023,.023),(-.014,.021,.032),(-.039,.016,.037),(-.061,.012,.035),(-.069,.009,.028)]
        v=[];f=[];n=20
        for y,rx,rz in rows:
            for j in range(n):
                a=math.tau*j/n;v.append((rx*math.cos(a)+.004,y,rz*math.sin(a)))
        f.append(tuple(reversed(range(n))));f.append(tuple((len(rows)-1)*n+i for i in range(n)))
        for i in range(len(rows)-1):
            for j in range(n): a=i*n+j;b=i*n+(j+1)%n;f.append((a,b,b+n,a+n))
        add(v,f)
        def tube(points,radius):
            # Equal vertex topology in hook/release, smooth finite centreline.
            p=[Vector(x) for x in points];pp=[]
            for i in range(len(p)-1):
                for k in range(4):
                    t=k/4;pp.append(.5*((2*p[i])+(-p[max(0,i-1)]+p[min(len(p)-1,i+1)])*t+(2*p[max(0,i-1)]-5*p[i]+4*p[min(len(p)-1,i+1)]-p[min(len(p)-1,i+2)])*t*t+(-p[max(0,i-1)]+3*p[i]-3*p[min(len(p)-1,i+1)]+p[min(len(p)-1,i+2)])*t*t*t))
            pp.append(p[-1]);v=[];f=[];sides=10
            for i,p0 in enumerate(pp):
                tangent=(pp[min(i+1,len(pp)-1)]-pp[max(i-1,0)]).normalized();u=tangent.cross(Vector((0,0,1)))
                if u.length<.01:u=tangent.cross(Vector((1,0,0)))
                u.normalize();w=tangent.cross(u).normalized();r=radius*(.65 if i==len(pp)-1 else 1.)
                for j in range(sides):a=math.tau*j/sides;v.append(tuple(p0+r*(math.cos(a)*u+math.sin(a)*w)))
            f.append(tuple(reversed(range(sides))));f.append(tuple((len(pp)-1)*sides+i for i in range(sides)))
            for i in range(len(pp)-1):
                for j in range(sides):a=i*sides+j;b=i*sides+(j+1)%sides;f.append((a,b,b+sides,a+sides))
            add(v,f)
        for i,(z,r) in enumerate([(-.020,.0070),(.013,.0075),(.031,.0068),(.046,.0054)]):
            little=i==3
            closed=[(.004,-.055,z),(.004,-.076 if not little else -.069,z),(.001,-.083 if not little else -.076,z),(-.017,-.084 if not little else -.079,z),(-.023,-.069 if not little else -.068,z)]
            release=[(.004,-.055,z),(.002,-.079,z),(0,-.097,z),(-.003,-.112 if not little else -.102,z),(-.005,-.119 if not little else -.108,z)]
            first=len(verts)
            tube([tuple(Vector(a).lerp(Vector(b),opened)) for a,b in zip(closed,release)],r)
            finger_ranges.append((first,len(verts)))
        # Thumb rests beside the index; it never clamps across the arrow/nock.
        tube([(.004,-.018,-.025),(-.010,-.031,-.038),(-.015,-.049,-.041),(-.013,-.063,-.036)],.008)
        return verts,faces,finger_ranges
    closed,faces,finger_ranges=geometry(0);opened,_,_=geometry(1)
    ob=mesh('Traveler_BowDrawHand_1',closed,faces,'skin')
    # Triangulate before adding shapes. Keep this small hand mesh at all LODs.
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('Authored hand triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.shape_key_add(name='Basis');release=ob.shape_key_add(name='ReleaseOpen')
    assert len(release.data)==len(opened)
    for v,p in zip(release.data,opened):v.co=vec(p)
    # Four additive corrective shapes follow the REAL top/bottom string rays.
    # Only drawing phalanges move; palm, thumb and relaxed little finger remain.
    for label,fingers in [('Upper',[0]),('Lower',[1,2])]:
        for axis,component in [('X',0),('Y',1)]:
            shape=ob.shape_key_add(name='String'+label+axis)
            shape.slider_min=-2.;shape.slider_max=2.
            for finger in fingers:
                first,end=finger_ranges[finger]
                for index in range(first,end):
                    p=list(closed[index]);t=max(0.,min(1.,(-p[1]-.059)/.018));influence=t*t*(3-2*t)
                    p[component]+=abs(p[2])*influence
                    shape.data[index].co=vec(p)
    ob.parent=wrist;ob.location=(0,0,0)
    ob['original_design']='Original split-finger draw hand; authoring script archery_draw_hand.py'
    ob['bow_string_contact_wrist_local']=[0,-.090,0]
    ob['source_display_only']=False
    contact=api['empty']('BowStringContact_1',(0,-.090,0),wrist)
    ob.hide_set(True);ob.hide_render=True
    return ob,contact
