"""Render exact Godot-exported colossus GLBs with matched Blender Cycles CPU settings.
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
    'valus': {
        'overview': {'position': (26,17,-37), 'target': (0,9,0), 'lens': 55},
        'surface': {'position': (10,15,-14), 'target': (0,12.4,0), 'lens': 57},
        'weakpoint': {'position': (5,22,-6), 'target': (0,16.8,.2), 'lens': 52},
    },
    'gaius': {
        'overview': {'position': (32,20,-45), 'target': (-.5,5.8,0), 'lens': 55},
        'surface': {'position': (10,15,-14), 'target': (0,12.4,0), 'lens': 57},
        'weakpoint': {'position': (5,22,-6), 'target': (0,16.8,.2), 'lens': 52},
    },
    'pelagia': {
        'overview': {'position': (23,17,-30), 'target': (0,4,-.5), 'lens': 55},
        'surface': {'position': (12,8,9), 'target': (1.5,4,1), 'lens': 57},
        'weakpoint': {'position': (9,14,13), 'target': (0,5,-.5), 'lens': 52},
    },
}
LIGHTS = {'world': {'color': (.18,.21,.25,1), 'strength': .4},
          'key': {'position': (-22,35,-28), 'power': 56000, 'color': (1,.91,.81), 'size': 24},
          'fill': {'position': (25,22,-7), 'power': 35000, 'color': (.80,.88,1), 'size': 18},
          'rim': {'position': (7,28,25), 'power': 65000, 'color': (1,.95,.87), 'size': 18}}


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def coord(p): return Vector((p[0], -p[2], p[1]))
def point(obj, target): obj.rotation_euler = (coord(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--subject', choices=CAMERAS, required=True)
    parser.add_argument('--view', choices=("overview","surface","weakpoint"), required=True)
    parser.add_argument('--width', type=int, default=960)
    parser.add_argument('--samples', type=int, default=64)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    source_digest = sha(args.source)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    imported = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert imported, 'No actual exported colossus geometry'
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
        point(obj,(0,8,0))
    config = CAMERAS[args.subject][args.view]
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
                'resolution':[scene.render.resolution_x,scene.render.resolution_y], 'subject':args.subject,'view':args.view,'camera':config,
                'lights':LIGHTS, 'view_transform':'AgX / Medium High Contrast; exposure 0; gamma 1',
                'imported_meshes':len(imported),'material_names':material_names,
                'scope':'Godot-loaded runtime meshes, current effective imported materials, production rest skeleton with actual protected weakpoint state. Presentation-only neutral studio lights. Not a Godot GPU screenshot or runtime performance validation.',
                'renderer_sha256':sha(Path(__file__).resolve())}
    args.output.with_suffix('.json').write_text(json.dumps(manifest,indent=2))
    print('COLOSSUS_RENDER_OK',args.output,flush=True)


if __name__ == '__main__': main()
