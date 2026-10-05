"""Render exact Godot-exported character GLBs with matched Blender Cycles CPU settings.
No mesh, UV, texture or imported material edits are performed. Neutral studio floor
and lights are presentation-only and identical in the pair, not claimed gameplay.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

CAMERAS = {
    'traveler_whole': {'position': (2.45, 1.8, -4.1), 'target': (0, .97, 0), 'lens': 55},
    'traveler_face_front': {'position': (0, 1.60, -1.4), 'target': (0, 1.60, -.02), 'lens': 68},
    'traveler_face_side': {'position': (1.4, 1.60, -.02), 'target': (0, 1.60, -.02), 'lens': 68},
    'traveler_front': {'position': (0, 1.30, -4.2), 'target': (0, 1.02, 0), 'lens': 55},
    'traveler_gameplay': {'position': (2.8, 2.35, -6.5), 'target': (0, 1.05, 0), 'lens': 45},
    'traveler_face': {'position': (.64, 1.91, -1.34), 'target': (0, 1.64, -.06), 'lens': 64},
    'traveler_cloth': {'position': (.47, 1.43, -1.6), 'target': (0, 1.18, -.04), 'lens': 57},
    'traveler_climb': {'position': (2.1, 1.75, -4.1), 'target': (0, 1.22, 0), 'lens': 53},
    'agro_whole': {'position': (4.3, 2.8, -4.65), 'target': (0, 1.22, -.12), 'lens': 52},
    'agro_face': {'position': (1.6, 2.05, -3.5), 'target': (0, 1.78, -1.53), 'lens': 66},
    'agro_tack': {'position': (2.65, 2.05, -1.15), 'target': (0, 1.31, -.25), 'lens': 63},
    'rider_whole': {'position': (4.8, 3.1, -5.55), 'target': (0, 1.56, -.10), 'lens': 53},
}
LIGHTS = {'world': {'color': (.18,.21,.25,1), 'strength': .4},
          'key': {'position': (-3,5,-4), 'power': 650, 'color': (1,.91,.81), 'size': 4},
          'fill': {'position': (4,3,-1), 'power': 390, 'color': (.80,.88,1), 'size': 3},
          'rim': {'position': (1,4,4), 'power': 750, 'color': (1,.95,.87), 'size': 3}}


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def coord(p): return Vector((p[0], -p[2], p[1]))
def point(obj, target): obj.rotation_euler = (coord(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--view', choices=CAMERAS, required=True)
    parser.add_argument('--width', type=int, default=960)
    parser.add_argument('--samples', type=int, default=64)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    source_digest = sha(args.source)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    imported = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert imported, 'No actual exported character geometry'
    material_names = sorted({slot.material.name for o in imported for slot in o.material_slots if slot.material})
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = args.samples
    scene.cycles.seed = 42
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 8
    scene.render.resolution_x = args.width
    scene.render.resolution_y = round(args.width * .9)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    world = bpy.data.worlds.new('Matched neutral studio')
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = LIGHTS['world']['color']
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = LIGHTS['world']['strength']
    for name, data in LIGHTS.items():
        if name == 'world': continue
        light = bpy.data.lights.new(name, type='AREA')
        light.energy, light.color, light.shape, light.size = data['power'],data['color'],'DISK',data['size']
        obj = bpy.data.objects.new(name, light)
        scene.collection.objects.link(obj)
        obj.location = coord(data['position'])
        point(obj,(0,1.1,0))
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.02))
    ground = bpy.context.object
    ground.name = 'Evidence-only studio ground'
    mat = bpy.data.materials.new('Evidence-only neutral ground')
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (.16,.18,.19,1)
    bsdf.inputs['Roughness'].default_value = .88
    ground.data.materials.append(mat)
    config = CAMERAS[args.view]
    cam = bpy.data.cameras.new('Matched camera')
    obj = bpy.data.objects.new('Matched camera', cam)
    scene.collection.objects.link(obj)
    obj.location = coord(config['position'])
    point(obj,config['target'])
    cam.lens = config['lens']
    scene.camera = obj
    scene.render.filepath = str(args.output)
    bpy.ops.render.render(write_still=True)
    assert sha(args.source) == source_digest, 'Source GLB changed during render; discard and recapture'
    manifest = {'source':str(args.source),'source_sha256':source_digest,'output_sha256':sha(args.output),
                'renderer':'Blender Cycles CPU','blender_version':bpy.app.version_string,'samples':args.samples,'seed':42,
                'resolution':[scene.render.resolution_x,scene.render.resolution_y], 'view':args.view,'camera':config,
                'lights':LIGHTS, 'view_transform':'AgX / Medium High Contrast; exposure 0; gamma 1',
                'imported_meshes':len(imported),'material_names':material_names,
                'scope':'Godot-loaded runtime meshes, current effective imported materials, frozen production cosmetic poses. Presentation-only neutral studio floor/lights. Not a Godot GPU screenshot or runtime performance validation.',
                'renderer_sha256':sha(Path(__file__).resolve())}
    args.output.with_suffix('.json').write_text(json.dumps(manifest,indent=2))
    print('CHARACTER_RENDER_OK',args.output,flush=True)


if __name__ == '__main__': main()
