"""Pure authoring checks complementing actual imported visual-pose tests.
These checks intentionally do not certify the silhouette or motion quality.
"""
import ast
import math
import unittest
from pathlib import Path
from types import SimpleNamespace

SOURCE=Path(__file__).with_name('traveler_body_surface.py')

def functions():
    names={'shoulder_weights','surface_torso_alpha','surface_axilla_mask','surface_fold_mask','axilla_weights','lower_cloth_weights','trouser_rows','anatomical_boot'}
    nodes=[n for n in ast.parse(SOURCE.read_text()).body if isinstance(n,ast.FunctionDef) and n.name in names]
    ns={'math':math,'mesh':lambda name,v,f,t:{'name':name,'vertices':v,'faces':f,'tile':t},'tube':lambda *args:None}
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(SOURCE),'exec'),ns)
    return ns

class SurfaceSource(unittest.TestCase):
    def setUp(self):self.ns=functions()
    def test_weights_are_normalized_and_only_adjacent_bands(self):
        for side in range(2):
            for i in range(-10,111):
                w=self.ns['shoulder_weights'](side,i/100)
                self.assertAlmostEqual(sum(w.values()),1)
                self.assertLessEqual(len(w),2)
                self.assertTrue(all(0<=v<=1 for v in w.values()))
    def test_bind_extremes(self):
        w=self.ns['shoulder_weights'](0,0);self.assertEqual(w['SurfaceBody'],1)
        w=self.ns['shoulder_weights'](1,1);self.assertEqual(w['SurfaceUpper_1'],1)
    def test_weight_band_continuity(self):
        f=self.ns['shoulder_weights']
        for a in [.25,.5,.75]:
            lo=f(0,a-1e-7);hi=f(0,a+1e-7)
            self.assertLess(sum(abs(lo.get(n,0)-hi.get(n,0)) for n in set(lo)|set(hi)),2e-6)
    def test_torso_weight_is_localized(self):
        f=self.ns['surface_torso_alpha']
        self.assertEqual(f(0,.4,-.1),0)
        self.assertEqual(f(.08,.49,0),0)
        self.assertLess(f(.20,-.10,-.1),1e-12)
        self.assertGreater(f(.18,.36,-.07),0.10)
    def test_lateral_weight_is_mirrored_and_asymmetric_front_back(self):
        f=self.ns['surface_torso_alpha']
        self.assertAlmostEqual(f(.17,.35,-.05),f(-.17,.35,-.05))
        self.assertGreater(f(.17,.35,-.05),f(.17,.35,.05))
    def test_corrective_weight_split_preserves_normalization_and_four_influences(self):
        for side in range(2):
            for t in [i/100 for i in range(101)]:
                base=self.ns['shoulder_weights'](side,t)
                for mask in [-1,0,.2,.5,1,2]:
                    w=self.ns['axilla_weights'](side,base,mask)
                    self.assertAlmostEqual(sum(w.values()),1)
                    self.assertLessEqual(len(w),4)
                    self.assertTrue(all(0<=v<=1 for v in w.values()))
                    for name,value in base.items():
                        if value<=1e-9:continue
                        alias=('SurfaceAxillaBody_%d'%side if name=='SurfaceBody' else name.replace('SurfaceBlend','SurfaceAxilla'))
                        self.assertAlmostEqual(w.get(name,0)+(w.get(alias,0) if alias!=name else 0),value)
    def test_paired_fold_weights_preserve_body_upper_and_eight_limit(self):
        for side in range(2):
            for t in [0,.1,.25,.5,.9,1]:
                base=self.ns['shoulder_weights'](side,t)
                for mask in [0,.2,1]:
                    for fold in [0,.2,.8,1]:
                        for front in [True,False]:
                            w=self.ns['axilla_weights'](side,base,mask,fold,front)
                            self.assertAlmostEqual(sum(w.values()),1)
                            self.assertLessEqual(len(w),5)
                            self.assertTrue(all(0<=v<=1 for v in w.values()))
                            body=sum(v for n,v in w.items() if 'Body' in n)
                            upper=sum(v for n,v in w.items() if 'Upper' in n)
                            self.assertAlmostEqual(body,1-t);self.assertAlmostEqual(upper,t)
    def test_fold_mask_spares_saddle_midplane_neck_and_waist(self):
        f=self.ns['surface_fold_mask']
        self.assertEqual(f(.18,.34,0),0)
        self.assertEqual(f(0,.34,-.10),0)
        self.assertEqual(f(.18,.49,-.10),0)
        self.assertLess(f(.18,0,-.10),1e-12)
        self.assertGreater(f(.16,.34,-.07),.5)
        self.assertAlmostEqual(f(.16,.34,-.07),f(-.16,.34,.07))
    def test_corrective_mask_spares_collar_and_midline(self):
        f=self.ns['surface_axilla_mask']
        self.assertEqual(f(0,.335,-.1),0)
        self.assertEqual(f(.18,.49,-.1),0)
        self.assertLess(f(.18,-.1,-.1),1e-12)
        self.assertAlmostEqual(f(.18,.335,-.1),f(-.18,.335,-.1))
        self.assertGreater(f(.18,.335,-.1),f(.18,.335,.1))
    def test_lower_cloth_spares_waist_and_preserves_input(self):
        f=self.ns['lower_cloth_weights'];weights={'SurfaceBody':.8,'SurfaceUpper_0':.2}
        for y in [-.12,0,.4]:self.assertEqual(f(.15,y,-.13,weights),weights)
        self.assertEqual(weights,{'SurfaceBody':.8,'SurfaceUpper_0':.2})
    def test_lower_cloth_weights_are_normalized_and_mirrored(self):
        f=self.ns['lower_cloth_weights']
        for y in [-.4,-.32,-.28,-.23,-.18,-.13,-.12]:
            for x in [0,.02,.06,.12,.20]:
                for z in [-.15,0,.15]:
                    a=f(x,y,z,{'SurfaceBody':1});b=f(-x,y,z,{'SurfaceBody':1})
                    self.assertAlmostEqual(sum(a.values()),1)
                    self.assertTrue(all(0<=w<=1 for w in a.values()))
                    self.assertAlmostEqual(a.get('SurfaceBody',0),b.get('SurfaceBody',0))
                    self.assertAlmostEqual(a.get('SurfaceLeg_0',0),b.get('SurfaceLeg_1',0))
                    self.assertAlmostEqual(a.get('SurfaceLeg_1',0),b.get('SurfaceLeg_0',0))
        a=f(.12,-.32,-.13,{'SurfaceBody':1})
        self.assertAlmostEqual(a['SurfaceLeg_1'],.68359375)
        self.assertAlmostEqual(a['SurfaceBody'],.31640625)
    def test_trouser_waist_is_body_and_knee_is_own_leg(self):
        f=self.ns['lower_cloth_weights']
        for side,index in [(-1,0),(1,1)]:
            self.assertEqual(f(side*.118,-.098,0,{'SurfaceBody':1}),{'SurfaceBody':1})
            for x in [.0524,.118,.1836]:
                self.assertEqual(f(side*x,-.512,0,{'SurfaceBody':1}),{'SurfaceLeg_%d'%index:1})
    def test_lower_cloth_transition_has_no_weight_jump(self):
        f=self.ns['lower_cloth_weights']
        for y in [-.12,-.44]:
            a=f(.12,y-1e-7,-.13,{'SurfaceBody':1});b=f(.12,y+1e-7,-.13,{'SurfaceBody':1})
            self.assertLess(sum(abs(a.get(n,0)-b.get(n,0)) for n in set(a)|set(b)),1e-8)
    def test_boot_has_exact_flat_ground_contact(self):
        upper,sole,_=self.ns['anatomical_boot']()
        self.assertEqual(sorted(set(p[1] for p in sole['vertices'])),[-.084,-.073])
        self.assertGreater(min(p[1] for p in upper['vertices']),-.084)
    def test_boot_has_raised_instep_and_lower_toe(self):
        upper,_,_=self.ns['anatomical_boot']();v=upper['vertices']
        instep=max(p[1] for p in v if -.02<p[2]<.025)
        toe=max(p[1] for p in v if p[2]<-.15)
        self.assertGreater(instep,toe+.05)
    def test_boot_faces_are_valid(self):
        for mesh in self.ns['anatomical_boot']()[:2]:
            for face in mesh['faces']:
                self.assertGreaterEqual(len(face),3)
                self.assertEqual(len(face),len(set(face)))
                self.assertTrue(all(0<=i<len(mesh['vertices']) for i in face))

class TrouserClearance(unittest.TestCase):
    def test_neutral_upper_thigh_is_inside_actual_folded_tunic_sections(self):
        # Source-space sampling guards the specific ivory wedge regression.
        # Actual imported all-LOD/motion collision checks remain separate.
        import bisect
        source=SOURCE.with_name('generate_travelers_v3.py');tree=ast.parse(source.read_text())
        profile=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='TUNIC_PROFILE' for t in n.targets))
        node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='tunic_point')
        pants=functions()['trouser_rows']()
        def interp(x,xs,values):
            k=max(0,min(len(xs)-2,bisect.bisect_right(xs,x)-1));t=max(0,min(1,(x-xs[k])/(xs[k+1]-xs[k])))
            return values[k]*(1-t)+values[k+1]*t
        ns={'math':math,'np':SimpleNamespace(interp=interp),'TUNIC_PROFILE':profile}
        exec(compile(ast.Module(body=[node],type_ignores=[]),str(source),'exec'),ns)
        body=next(n for n in ast.parse(SOURCE.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='continuous_garment')
        ys=next(ast.literal_eval(n.value) for n in body.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='ys' for t in n.targets))
        pants=sorted(pants);minimum=99
        for j in range(48):
            y=-.317+j*(.214/47);k=max(0,min(len(ys)-2,bisect.bisect_right(ys,y)-1));t=(y-ys[k])/(ys[k+1]-ys[k])
            poly=[]
            for a in [i*math.tau/64 for i in range(64)]:
                u=ns['tunic_point'](ys[k],a);v=ns['tunic_point'](ys[k+1],a);poly.append(tuple(u[d]*(1-t)+v[d]*t for d in range(2)))
            local=y+.188;k=max(0,min(len(pants)-2,bisect.bisect_right([r[0] for r in pants],local)-1));t=(local-pants[k][0])/(pants[k+1][0]-pants[k][0])
            ring=[]
            for a in [i*math.tau/28 for i in range(28)]:
                points=[]
                for yy,rx,rz,zc in pants[k:k+2]:
                    f=1+.025*math.sin(a*8+yy*3);points.append((rx*f*math.cos(a),zc+rz*f*math.sin(a)))
                ring.append(tuple(points[0][d]*(1-t)+points[1][d]*t for d in range(2)))
            for side in [-1,1]:
                for a,b in zip(ring,ring[1:]+ring[:1]):
                    for u in [0,.25,.5,.75]:
                        x=side*.118+a[0]*(1-u)+b[0]*u;z=a[1]*(1-u)+b[1]*u;inside=False;distance=99
                        for c,d in zip(poly,poly[1:]+poly[:1]):
                            if (c[1]>z)!=(d[1]>z) and x<(d[0]-c[0])*(z-c[1])/(d[1]-c[1])+c[0]:inside=not inside
                            ex=d[0]-c[0];ez=d[1]-c[1];v=max(0,min(1,((x-c[0])*ex+(z-c[1])*ez)/(ex*ex+ez*ez)))
                            distance=min(distance,math.hypot(x-c[0]-v*ex,z-c[1]-v*ez))
                        self.assertTrue(inside,(side,y,x,z));minimum=min(minimum,distance)
        self.assertGreater(minimum,.0035)

class ExportInfluenceGuard(unittest.TestCase):
    def setUp(self):
        source=SOURCE.with_name('generate_travelers_v3.py')
        node=next(n for n in ast.parse(source.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='validate_surface_influences')
        ns={'math':math};exec(compile(ast.Module(body=[node],type_ignores=[]),str(source),'exec'),ns)
        self.validate=ns['validate_surface_influences']
    def fixture(self,weights):
        return [SimpleNamespace(type='MESH',name='fixture',modifiers=[SimpleNamespace(type='ARMATURE')],data=SimpleNamespace(vertices=[SimpleNamespace(groups=[SimpleNamespace(weight=w) for w in weights])]))]
    def test_small_skinned_thigh_is_not_decimated(self):
        source=SOURCE.with_name('generate_travelers_v3.py')
        node=next(n for n in ast.parse(source.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='apply_surface_lod')
        ns={};exec(compile(ast.Module(body=[node],type_ignores=[]),str(source),'exec'),ns)
        class MeshObject(SimpleNamespace):
            def __setitem__(self,key,value):setattr(self,key,value)
        vertices=[object() for _ in range(196)]
        for ratio in [.52,.12]:
            ob=MeshObject(name='Traveler_Thigh_0',modifiers=[SimpleNamespace(type='ARMATURE')],data=SimpleNamespace(vertices=vertices))
            ns['apply_surface_lod'](ob,ratio)
            self.assertIs(ob.data.vertices,vertices)
            self.assertEqual(ob.lod_preserved_full_thigh_vertices,196)
    def test_eight_normalized_influences_allowed(self):self.validate(self.fixture([.125]*8))
    def test_ninth_influence_rejected(self):
        with self.assertRaises(AssertionError):self.validate(self.fixture([1/9]*9))
    def test_invalid_weights_rejected(self):
        for weights in [[1,float('nan')],[1,float('inf')],[1,-.1],[.4,.4],[]]:
            with self.assertRaises(AssertionError):self.validate(self.fixture(weights))

if __name__=='__main__':unittest.main()
