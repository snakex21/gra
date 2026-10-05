"""Original continuous shoulder garment and asymmetric arm topology.
Executed from generate_travelers_v3.py with its authoring helpers available.
No reference mesh is imported; dimensions are authored in the game frame.
"""
COSMETIC_UPPER_LENGTH=math.sqrt(.040**2+.290**2)
COSMETIC_LOWER_LENGTH=math.sqrt(.050**2+.276**2)

def build_surface_rig(parent):
    data=bpy.data.armatures.new('TravelerSurfaceRig')
    rig=bpy.data.objects.new('TravelerSurfaceRig',data)
    scene.collection.objects.link(rig);rig.parent=parent
    bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    body=data.edit_bones.new('SurfaceBody');body.head=vec((0,0,0));body.tail=vec((0,.1,0))
    for i,side in enumerate([-1,1]):
        shoulder=(side*.210,.405,0);elbow=(side*(.210+COSMETIC_UPPER_LENGTH),.405,0);wrist=(side*(.210+COSMETIC_UPPER_LENGTH+COSMETIC_LOWER_LENGTH),.405,0)
        upper=data.edit_bones.new('SurfaceUpper_%d'%i);upper.head=vec(shoulder);upper.tail=vec(elbow);upper.parent=body
        lower=data.edit_bones.new('SurfaceLower_%d'%i);lower.head=vec(elbow);lower.tail=vec(wrist);lower.parent=body
        hand=data.edit_bones.new('SurfaceWrist_%d'%i);hand.head=vec(wrist);hand.tail=vec((wrist[0]+side*.050,.405,0));hand.parent=body
        leg=data.edit_bones.new('SurfaceLeg_%d'%i);leg.head=vec((side*.118,-.188,0));leg.tail=vec((side*.118,-.513,0));leg.parent=body
        variants=[('SurfaceAxillaBody_%d'%i,body)]
        for view in ['Front','Back']:
            variants.extend([('SurfaceFold%sBody_%d'%(view,i),body),('SurfaceFold%sUpper_%d'%(view,i),upper)])
        for name,base in variants:
            corrective=data.edit_bones.new(name)
            corrective.head=base.head.copy();corrective.tail=base.tail.copy();corrective.roll=base.roll;corrective.parent=body
    bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
    return rig

def bind_surface(ob,rig,weights):
    groups={b.name:ob.vertex_groups.new(name=b.name) for b in rig.data.bones}
    for vi,ws in enumerate(weights):
        for name,w in ws.items():
            if w>1e-7: groups[name].add([vi],w,'REPLACE')
    mod=ob.modifiers.new('Continuous cosmetic surface skin','ARMATURE');mod.object=rig
    ob.parent=rig
    return ob

def shoulder_weights(index,t):
    # T-bind never traverses the former 171-degree arms-down rotation.
    # Direct body/upper LBS lets the axillary fabric compress naturally rather
    # than inflating a wide helper-bone rotation arc around the shoulder.
    t=max(0,min(1,t))
    return {'SurfaceBody':1-t,'SurfaceUpper_%d'%index:t}

def surface_torso_alpha(x,y,z):
    lateral=max(0,min(1,(abs(x)-.085)/.085))
    vertical=math.exp(-((y-.355)/.140)**4)
    front_back=1.10 if z<0 else .90
    return min(.20,.18*lateral*lateral*vertical*front_back)

def surface_axilla_mask(x,y,z):
    lateral=max(0,min(1,(abs(x)-.10)/.075))
    vertical=math.exp(-((y-.335)/(.175 if y<.335 else .100))**4)
    top=max(0,min(1,(.445-y)/.050))
    return lateral*lateral*vertical*top*(.90 if z>0 else 1.0)

def surface_fold_mask(x,y,z):
    lateral=max(0,min(1,(abs(x)-.07)/.08))
    vertical=math.exp(-((y-.340)/.120)**4)
    top=max(0,min(1,(.450-y)/.045))
    front_back=max(0,min(1,(abs(z)-.012)/.040))
    return .70*lateral*lateral*vertical*top*front_back*front_back

def axilla_weights(index,weights,mask,fold_mask=0,front=True):
    out={};mask=max(0,min(1,mask));fold_mask=max(0,min(.85,fold_mask))
    for name,w in weights.items():
        if w<=1e-9:continue
        kind='Body' if name=='SurfaceBody' else ('Upper' if name=='SurfaceUpper_%d'%index else '')
        if not kind:out[name]=w;continue
        axilla=mask*(1-fold_mask) if kind=='Body' else 0
        remaining=1-axilla-fold_mask
        if remaining>1e-9:out[name]=w*remaining
        if axilla>1e-9:out['SurfaceAxillaBody_%d'%index]=w*axilla
        if fold_mask>1e-9:out['SurfaceFold%s%s_%d'%('Front' if front else 'Back',kind,index)]=w*fold_mask
    return out

def lower_cloth_weights(x,y,z,weights):
    """Lower fabric follows unchanged logical hips; waist/upper body stay put."""
    vertical=max(0,min(1,(-y-.12)/.32))
    vertical=vertical*vertical*(3-2*vertical)
    if vertical<=1e-9:return dict(weights)
    strength=vertical
    right=max(0,min(1,(x+.045)/.09));right=right*right*(3-2*right)
    out={name:w*(1-strength) for name,w in weights.items() if w*(1-strength)>1e-9}
    for index,w in [(0,strength*(1-right)),(1,strength*right)]:
        if w>1e-9:out['SurfaceLeg_%d'%index]=w
    return out

def trouser_rows():
    base=[(.09,.040,.063,0),(.03,.054,.067,0),(-.05,.065,.067,0),(-.20,.067,.063,0),(-.324,.064,.057,0)]
    ordered=sorted(base)
    def interp(y,column):
        for a,b in zip(ordered,ordered[1:]):
            if a[0]<=y<=b[0]:
                t=(y-a[0])/(b[0]-a[0]);return a[column]*(1-t)+b[column]*t
        return ordered[0 if y<ordered[0][0] else -1][column]
    # Match both outer and rolled-inner hem sampling planes. The ring vertices
    # are protected through LOD because their weight samples prevent clipping.
    ys=sorted({r[0] for r in base}|{-.132,-.1285},reverse=True)
    return [(y,interp(y,1),interp(y,2),0) for y in ys]

def continuous_garment(parent,rig):
    # Side openings are genuine topology holes in the trunk. Their boundary
    # vertices are shared by the sleeve crown: no intersecting cover/cap meshes.
    sides=64
    ys=[-.32,-.28,-.23,-.18,-.13,-.09,-.05,0,.05,.10,.15,.19,.23,.27,.31,.35,.39,.43,.455,.475,.492]
    profile=[r[:3] for r in TUNIC_PROFILE]
    verts=[];faces=[];tiles=[];weights=[];face_uvs=[]
    def append_face(f,tile,uv=None):faces.append(f);tiles.append(tile);face_uvs.append(uv)
    for j,y in enumerate(ys):
        rx,rz=[float(np.interp(y,[r[0] for r in profile],[r[k] for r in profile])) for k in [1,2]]
        for k in range(sides):
            a=k*math.tau/sides
            x,z=tunic_point(y,a)
            verts.append((x,y,z));index=0 if x<0 else 1
            weights.append(axilla_weights(index,shoulder_weights(index,surface_torso_alpha(x,y,z)),surface_axilla_mask(x,y,z),surface_fold_mask(x,y,z),z<0))
    low=ys.index(.27);high=ys.index(.455);half=7
    def opening(j,k,c):return low<=j<high and ((k-c+32)%64-32)>=-half and ((k-c+32)%64-32)<half
    for j in range(len(ys)-1):
        for k in range(sides):
            if opening(j,k,0) or opening(j,k,32):continue
            append_face((j*sides+k,j*sides+(k+1)%sides,(j+1)*sides+(k+1)%sides,(j+1)*sides+k),'bluecloth')
    # Open fabric hem with a thin folded lip, not a solid capped cylinder.
    inner_hem=[]
    for k in range(sides):
        x,y,z=verts[k];inner_hem.append(len(verts));verts.append((x*.985,y+.0035,z*.985));weights.append({'SurfaceBody':1})
    hem_faces=[]
    for k in range(sides):
        b=(k+1)%sides
        hem_faces.append(len(faces))
        append_face((k,b,inner_hem[b],inner_hem[k]),'bluecloth',[(k/sides,0),((k+1)/sides,0),((k+1)/sides,.03),(k/sides,.03)])
    # Neck opening remains open beneath collar. Export source has no false cap.
    for index,side in enumerate([-1,1]):
        c=32 if side<0 else 0
        boundary=[low*sides+(c+k)%sides for k in range(-half,half+1)]
        boundary += [j*sides+(c+half)%sides for j in range(low+1,high+1)]
        boundary += [high*sides+(c+k)%sides for k in range(half-1,-half-1,-1)]
        boundary += [j*sides+(c-half)%sides for j in range(high-1,low,-1)]
        # Map the rectangular grid boundary smoothly onto a noncircular armhole.
        angles=[]
        for vi in boundary:
            x,y,z=verts[vi]
            th=math.atan2(z/.075,(y-.3625)/.0925);angles.append(th)
            y=.3625+.0925*math.cos(th);z=.075*math.sin(th)
            rx=float(np.interp(y,[r[0] for r in profile],[r[1] for r in profile]));rz=float(np.interp(y,[r[0] for r in profile],[r[2] for r in profile]))
            x=side*rx*math.sqrt(max(.05,1-(z/rz)**2))
            verts[vi]=(x,y,z)
            # Deformation fades into the chest around the sewn shoulder line.
            weights[vi]=axilla_weights(index,shoulder_weights(index,surface_torso_alpha(x,y,z)),surface_axilla_mask(x,y,z),surface_fold_mask(x,y,z),z<0)
        prev=boundary
        for row in range(1,9):
            t=row/8;ring=[]
            # T-bind sleeve axis; runtime skin rotates the fitted sleeve downward.
            cx=.165+(.430-.165)*t
            ry=.046+.0465*(1-t)**4
            rz=.047+.028*(1-t)**3
            cy=.455-ry-.004*t
            angle=0.0
            for n,th in enumerate(angles):
                # Flattened crown and taper define the sleeve in its lateral T bind.
                crown=math.cos(th)
                # Broad proximal attachment, flatter acromial top and narrower
                # anterior surface; volume tapers instead of forming a ball.
                crown*=1-.26*max(0,crown)*math.sin(math.pi*t)
                x=side*(cx+math.sin(angle)*ry*crown)
                y=cy+math.cos(angle)*ry*crown
                z=rz*math.sin(th)*(1-.13*math.sin(math.pi*t))
                # Match exact trunk boundary at start, fade from authored ellipse.
                p0=Vector(verts[boundary[n]])
                ideal0=Vector((side*.165,.3625+.0925*math.cos(th),.075*math.sin(th)))
                p=Vector((x,y,z))+(p0-ideal0)*(1-t)**2
                # restrained longitudinal cloth breaks, no inflated ring waves
                p.z+=.003*math.sin(th*5+.6)*math.sin(math.pi*t)**2
                # Paired anterior/posterior axillary cloth ridges. Keep a soft
                # recess between them; do not fill the joint with a flat web.
                folded=math.sin(math.pi*t)**2*math.exp(-((t-.30)/.28)**2)
                for sign in [-1,1]:
                    da=math.atan2(math.sin(th-sign*1.95),math.cos(th-sign*1.95))
                    db=math.atan2(math.sin(th-sign*2.40),math.cos(th-sign*2.40))
                    p.z+=sign*folded*(.017*math.exp(-(da/.32)**2)-.005*math.exp(-(db/.28)**2))
                ring.append(len(verts));verts.append(tuple(p))
                wa=surface_torso_alpha(*verts[boundary[n]])
                mb=surface_axilla_mask(*verts[boundary[n]])
                under=max(0,-math.cos(th))**2
                blend=min(1,t/.25)
                fade=max(0,min(1,(.85-t)/.25));fade=fade*fade*(3-2*fade)
                mask=((1-blend)*mb+blend*under)*fade
                boundary_fold=surface_fold_mask(*verts[boundary[n]])
                fold_lobe=math.exp(-((abs(th)-1.95)/.55)**2)
                longitudinal=math.sin(math.pi*min(1,t/.85))**2
                front_back=max(0,min(1,(abs(p.z)-.012)/.025))
                fold_mask=((1-blend)*boundary_fold+blend*.85*fold_lobe*longitudinal)*fade*front_back
                weights.append(axilla_weights(index,shoulder_weights(index,wa+(1-wa)*min(1,t/.80)),mask,fold_mask,p.z<0))
            for n in range(len(ring)):
                append_face((prev[n],prev[(n+1)%len(ring)],ring[(n+1)%len(ring)],ring[n]),'linen' if t>.34 else 'bluecloth',[(t-1/8,n/len(ring)),(t-1/8,(n+1)/len(ring)),(t,(n+1)/len(ring)),(t,n/len(ring))])
            prev=ring
        # cuff inner lip, not a filled cap across the arm
        inner=[]
        for vi in prev:
            x,y,z=verts[vi];inner.append(len(verts));verts.append((x-side*.004,.405+(y-.405)*.96,z*.96));weights.append({'SurfaceUpper_%d'%index:1})
        for n in range(len(prev)):append_face((prev[n],prev[(n+1)%len(prev)],inner[(n+1)%len(prev)],inner[n]),'linen',[(1,n/len(prev)),(1,(n+1)/len(prev)),(.98,(n+1)/len(prev)),(.98,n/len(prev))])
    weights=[lower_cloth_weights(*p,w) for p,w in zip(verts,weights)]
    used=sorted({vi for face in faces for vi in face})
    remap={old:new for new,old in enumerate(used)}
    verts=[verts[i] for i in used];weights=[weights[i] for i in used]
    faces=[tuple(remap[i] for i in face) for face in faces]
    ob=mesh('Traveler_TunicSurface',verts,faces,'bluecloth')
    # A folded fabric lip has a real shading crease. Do not average its inward/
    # downward normal fan into the outer garment's radial normals.
    sharp={tuple(sorted((remap[k],remap[(k+1)%sides]))) for k in range(sides)}
    sharp.update(tuple(sorted((remap[inner_hem[k]],remap[inner_hem[(k+1)%sides]]))) for k in range(sides))
    for edge in ob.data.edges:
        if tuple(sorted(edge.vertices)) in sharp:edge.use_edge_sharp=True
    for fi in hem_faces:ob.data.polygons[fi].use_smooth=False
    ob.data.update()
    ob['authored_hem_normal_split']=True

    # Atlas tile per face, maintaining continuous shared geometric vertices.
    uv=ob.data.uv_layers.active
    for poly,tile,face_uv in zip(ob.data.polygons,tiles,face_uvs):
        idx=TILES[tile]
        for corner,li in enumerate(poly.loop_indices):
            p=godot(ob.data.vertices[ob.data.loops[li].vertex_index].co)
            u,v=face_uv[faces[poly.index].index(ob.data.loops[li].vertex_index)] if face_uv is not None else ((p.x+.36)/.72,(p.y+.32)/.82)
            uv.data[li].uv=((idx%4+.03+max(0,min(1,u))*.94)/4,(idx//4+.03+max(0,min(1,v))*.94)/4)
    return bind_surface(ob,rig,weights)

def continuous_arm(index,side,rig):
    # Cross sections follow biceps/triceps, flattened elbow, offset forearm
    # flexors, then an oval wrist. This skin is continuous across the elbow.
    # The hidden upper skin starts INSIDE the fully Upper-weighted sleeve
    # band (source T x>.3969). A higher rigid stub would protrude through the
    # differently weighted shoulder crown and expose its open cut rim.
    rows=[(.215,.2362,.0385,.0375,0),(.185,.2404,.038,.036,0),(.16,.2438,.035,.034,-.002),(.125,.2486,.033,.032,-.001),(.105,.2518,.034,.032,.001),(.075,.2572,.037,.034,.003),(.035,.2645,.040,.033,.002),(-.015,.2736,.039,.030,0),(-.065,.2826,.033,.026,-.001),(-.115,.2917,.026,.022,-.001),(-.135,.297,.026,.023,0),(-.162,.300,.025,.022,0)]
    verts=[];faces=[];weights=[];n=32
    for y,x,rx,rz,zc in rows:
        for k in range(n):
            a=k*math.tau/n
            # Distinct broad back-plane and gentler anterior plane.
            f=1+.055*math.cos(3*a+.4)*math.exp(-((y-.02)/.12)**2)
            along=COSMETIC_UPPER_LENGTH*(.405-y)/.290 if y>=.115 else COSMETIC_UPPER_LENGTH+COSMETIC_LOWER_LENGTH*(.115-y)/.276
            verts.append((side*(.210+along),.405+rx*math.cos(a)*f,zc+rz*math.sin(a)))
            lower=max(0,min(1,(.15-y)/.09))
            wrist=max(0,min(1,(-.115-y)/.047))
            weights.append({'SurfaceUpper_%d'%index:1-lower,'SurfaceLower_%d'%index:lower*(1-wrist),'SurfaceWrist_%d'%index:wrist})
    for j in range(len(rows)-1):
        for k in range(n):a=j*n+k;b=j*n+(k+1)%n;faces.append((a,b,b+n,a+n))
    ob=mesh('Traveler_ArmSurface_%d'%index,verts,faces,'skin')
    return bind_surface(ob,rig,weights)

def anatomical_boot():
    # Heel, raised instep, metatarsal break and low toe box share a continuous
    # leather shell. Flat outsole keeps the canonical ankle/ground contact.
    rows=[(.065,.028,-.016,-.073),(.046,.042,.014,-.074),(.010,.047,.036,-.074),
          (-.032,.049,.020,-.074),(-.075,.053,-.010,-.075),(-.120,.052,-.028,-.075),
          (-.157,.044,-.039,-.075),(-.183,.026,-.048,-.075),(-.190,.008,-.058,-.074)]
    verts=[];faces=[];n=24
    for z,rx,top,bottom in rows:
        for i in range(n):
            a=i*math.tau/n
            y=(top+bottom)/2+(top-bottom)/2*math.sin(a)
            if math.sin(a)<-.50:y=bottom
            verts.append((rx*math.cos(a),y,z))
    for j in range(len(rows)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
    faces.extend([tuple(reversed(range(n))),tuple((len(rows)-1)*n+i for i in range(n))])
    leather=mesh('Boot heel instep metatarsal toe planes',verts,faces,'boots')
    outline=[(-.030,.065),(-.047,.035),(-.052,-.035),(-.057,-.087),(-.055,-.126),(-.045,-.163),(-.028,-.189),(0,-.197),(.028,-.189),(.045,-.163),(.055,-.126),(.057,-.087),(.052,-.035),(.047,.035),(.030,.065)]
    verts=[(x,y,z) for y in [-.084,-.073] for x,z in outline];m=len(outline)
    faces=[tuple(reversed(range(m))),tuple(m+i for i in range(m))]
    faces += [(i,(i+1)%m,(i+1)%m+m,i+m) for i in range(m)]
    sole=mesh('Boot flat stitched outsole',verts,faces,'leather')
    seam=tube('Boot fitted forefoot seam',[(-.047,-.046,-.135),(-.026,-.031,-.134),(0,-.029,-.134),(.026,-.031,-.134),(.047,-.046,-.135)],.0018,'thread',6,3)
    return [leather,sole,seam]

def setup_authoring_bind_display(root,rig):
    """Linked editor-only T-pose views of the immutable rigid hands and wraps.

    The runtime keeps those meshes under its original wrist/forearm hierarchy.
    Copies share mesh data for editing, follow cosmetic wrist bones in Blender,
    and are explicitly excluded from BOTH generator and edited-source exports.
    """
    from mathutils import Matrix
    bpy.context.view_layer.update()
    for i,side in enumerate([-1,1]):
        old_end=vec((side*.300,-.161,0))
        new_end=vec((side*(.210+COSMETIC_UPPER_LENGTH+COSMETIC_LOWER_LENGTH),.405,0))
        delta=Matrix.Translation(new_end)@Matrix.Rotation(-side*math.pi/2,4,'Y')@Matrix.Translation(-old_end)
        for prefix in ['Traveler_Forearm_','Traveler_Hand_']:
            original=bpy.data.objects[prefix+str(i)]
            cp=original.copy();cp.data=original.data
            cp.name='Studio_T_'+prefix+str(i)
            scene.collection.objects.link(cp)
            desired=root.matrix_world@delta@root.matrix_world.inverted()@original.matrix_world
            cp.parent=rig;cp.parent_type='BONE';cp.parent_bone='SurfaceWrist_%d'%i
            cp['source_display_only']=True
            cp['editing_note']='Linked original mesh data; editor display transform only, excluded from runtime export.'
            bpy.context.view_layer.update();cp.matrix_world=desired
            cp.hide_set(False);cp.hide_render=False
            original.hide_set(True);original.hide_render=True
            bpy.context.view_layer.update()
            assert max(abs(cp.matrix_world[r][c]-desired[r][c]) for r in range(4) for c in range(4))<1e-5
