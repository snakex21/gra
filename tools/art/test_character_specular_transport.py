"""Measured scalar transport only; no rendering or authored default substitution."""
import importlib.util,json,struct,tempfile,unittest
from pathlib import Path
SCRIPT=Path(__file__).with_name('complete_character_specular_transport.py')
spec=importlib.util.spec_from_file_location('transport',SCRIPT);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class Transport(unittest.TestCase):
 def fixture(self,directory,values,exported=None):
  path=Path(directory)/'pose.glb';names=list(values) if exported is None else exported
  doc={'asset':{'version':'2.0'},'materials':[{'name':name,'pbrMetallicRoughness':{'roughnessFactor':.8}}for name in names]}
  j=json.dumps(doc).encode();j+=b' '*(-len(j)%4);binary=b'unchanged-binary!';binary+=b'\0'*(-len(binary)%4)
  tail=struct.pack('<II',len(binary),0x004e4942)+binary
  path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(j)+len(tail))+struct.pack('<II',len(j),0x4e4f534a)+j+tail)
  snapshot={'meshes':[{'surfaces':[{'material':{'name':name,'metallic_specular':value}}for name,value in values.items()]}]}
  path.with_suffix('.json').write_text(json.dumps(snapshot));return path,tail
 def decode(self,path):
  raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];return json.loads(raw[20:20+n]),raw[20+n:]
 def test_three_measured_scalars_and_binary_preserved(self):
  with tempfile.TemporaryDirectory() as directory:
   values={'Traveler_skin_restrained_specular':.24,'Traveler_matte_hair_fibres':.16,'agro_mane_tail_fibres':.22,'ordinary':.5}
   path,tail=self.fixture(directory,values);proof=module.complete(path);doc,actual=self.decode(path)
   self.assertEqual(actual,tail);self.assertEqual(len(proof['changes']),3)
   for mat in doc['materials']:
    if mat['name']=='ordinary':self.assertNotIn('extensions',mat)
    else:self.assertAlmostEqual(mat['extensions']['KHR_materials_specular']['specularFactor'],2*values[mat['name']])
 def test_uses_observed_horse_value_not_intent_constant(self):
  with tempfile.TemporaryDirectory() as directory:
   path,_=self.fixture(directory,{'agro_mane_tail_fibres':.19});module.complete(path)
   self.assertAlmostEqual(self.decode(path)[0]['materials'][0]['extensions']['KHR_materials_specular']['specularFactor'],.38)
 def test_missing_measurement_rejected_without_writing(self):
  with tempfile.TemporaryDirectory() as directory:
   path,_=self.fixture(directory,{},['agro_mane_tail_fibres']);before=path.read_bytes()
   with self.assertRaises(AssertionError):module.complete(path)
   self.assertEqual(path.read_bytes(),before)
 def test_unmapped_export_alias_rejected(self):
  with tempfile.TemporaryDirectory() as directory:
   path,_=self.fixture(directory,{'agro_mane_tail_fibres':.22},['agro_mane_tail_fibres','agro_mane_tail_fibres2'])
   with self.assertRaises(AssertionError):module.complete(path)
 def test_invalid_measurement_rejected(self):
  for value in [True,float('nan'),float('inf'),-.1,.6]:
   with tempfile.TemporaryDirectory() as directory:
    path,_=self.fixture(directory,{'agro_mane_tail_fibres':value});before=path.read_bytes()
    with self.assertRaises(AssertionError):module.complete(path)
    self.assertEqual(path.read_bytes(),before)
 def test_idempotent_transport(self):
  with tempfile.TemporaryDirectory() as directory:
   path,_=self.fixture(directory,{'agro_mane_tail_fibres':.22});module.complete(path);before=path.read_bytes();module.complete(path);self.assertEqual(path.read_bytes(),before)
if __name__=='__main__':unittest.main()
