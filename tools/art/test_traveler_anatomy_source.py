"""Pure-Python authoring tests: no Blender execution and no GPU required."""
import ast
import math
import unittest
from pathlib import Path
import numpy as np

SOURCE=Path(__file__).with_name('generate_travelers_v3.py')

def load_shapes():
    tree=ast.parse(SOURCE.read_text())
    names={'FACE_PROFILE','TUNIC_PROFILE','gaussian','profile_value','traveler_face_z','tunic_point'}
    selected=[]
    for node in tree.body:
        if isinstance(node,ast.FunctionDef) and node.name in names:selected.append(node)
        elif isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id in names for t in node.targets):selected.append(node)
    hair=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='traveler_hair')
    selected.append(next(n for n in hair.body if isinstance(n,ast.FunctionDef) and n.name=='cap_point'))
    namespace={'math':math,'np':np}
    exec(compile(ast.Module(body=selected,type_ignores=[]),str(SOURCE),'exec'),namespace)
    return namespace

class Shapes(unittest.TestCase):
    def setUp(self):self.ns=load_shapes()
    def test_landmarks_interpolate_exactly(self):
        p=self.ns['FACE_PROFILE']
        for row in p:
            for k in (1,2,3):self.assertAlmostEqual(self.ns['profile_value'](row[0],p,k),row[k],places=10)
    def test_cheek_jaw_radii_are_continuous(self):
        p=self.ns['FACE_PROFILE'];f=self.ns['profile_value'];h=1e-6
        for row in p[1:-1]:
            for k in (1,2,3):
                left=(f(row[0],p,k)-f(row[0]-h,p,k))/h
                right=(f(row[0]+h,p,k)-f(row[0],p,k))/h
                self.assertLess(abs(left-right),.005)
    def test_facial_surface_is_finite_and_bounded(self):
        for y in np.linspace(.615,.919,80):
            rx=self.ns['profile_value'](y,self.ns['FACE_PROFILE'],1)
            for x in np.linspace(-rx,rx,41):
                z=self.ns['traveler_face_z'](x,y)
                self.assertTrue(math.isfinite(z));self.assertLess(abs(z),.2)
    def test_hair_has_positive_skull_clearance(self):
        for t in np.linspace(.08,1,24):
            for a in np.linspace(math.pi,2*math.pi,50):
                x,y,z=self.ns['cap_point'](t,a)
                if y>.919 or y<.615:continue
                rx=self.ns['profile_value'](y,self.ns['FACE_PROFILE'],1)
                if abs(x)>=rx or z>=0:continue
                self.assertLess(z,self.ns['traveler_face_z'](x,y)-.001)
    def test_cloth_does_not_penetrate_belt(self):
        for y in np.linspace(-.110,-.053,24):
            rx=.79*float(np.interp(y,[-.110,-.075,-.053],[.224,.214,.210]))
            rz=.79*float(np.interp(y,[-.110,-.075,-.053],[.151,.140,.139]))
            for a in np.linspace(0,math.tau,80):
                x,z=self.ns['tunic_point'](y,a)
                self.assertLess((x/rx)**2+(z/rz)**2,.98)
    def test_tunic_seam_closes(self):
        for y in np.linspace(-.32,.477,70):
            self.assertTrue(np.allclose(self.ns['tunic_point'](y,0),self.ns['tunic_point'](y,math.tau),atol=1e-10))
    def test_tunic_is_within_existing_visual_envelope(self):
        for y in np.linspace(-.32,.477,60):
            for a in np.linspace(0,math.tau,80):
                x,z=self.ns['tunic_point'](y,a)
                self.assertLess(abs(x),.275);self.assertLess(abs(z),.195)

if __name__=='__main__':unittest.main()
