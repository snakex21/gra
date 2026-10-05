"""Measure actual opaque foliage silhouettes on a fixed preview camera ray grid.

Run inside Blender after scene export and preview (no beauty rendering):
  blender --background --threads 2 --python tests/meadow_visible_coverage.py -- \
    after_scene.json output_dir --manifest close_manifest.json --variant after

The denominator is visible route terrain, not botanical plantable area: road,
sea, sky, buildings and rock occluders are excluded. Holes between actual blades
remain bare pixels. Mesh AABBs only select production LOD, never count coverage.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


def coord(v):
    return Vector((v[0], -v[2], v[1]))


def selected_mesh(instance, camera, profile):
    if 'lod_meshes' not in instance or profile == 'authoring':
        return instance['mesh']
    density, distance_scale = {'low': (.35, .7), 'balanced': (.65, .85), 'high': (1, 1)}[profile]
    if instance['density_reduced'] and instance['batch_index'] >= max(1, math.ceil(instance['batch_size'] * density)):
        return None
    distance = (Vector(camera) - Vector(instance['lod_center'])).length
    lod = next((i for i in range(3) if instance['lod_ranges'][i] * distance_scale <= distance < instance['lod_ranges'][i + 1] * distance_scale), None)
    return None if lod is None else instance['lod_meshes'][lod]


def build_bvh(instances, meshes, camera, profile):
    vertices, faces, labels = [], [], []
    count = 0
    for instance in instances:
        mesh_id = selected_mesh(instance, camera, profile)
        if mesh_id is None:
            continue
        count += 1
        rows = instance['transform']
        matrix = Matrix(((rows[0][0], rows[1][0], rows[2][0], rows[3][0]),
                         (rows[0][1], rows[1][1], rows[2][1], rows[3][1]),
                         (rows[0][2], rows[1][2], rows[2][2], rows[3][2]), (0, 0, 0, 1)))
        # Actual triangles, including thin blades and gaps. Two-sided ray tests
        # match the double-sided foliage material used by the exported preview.
        name = instance['name']
        category = instance['category']
        is_grass = name.startswith('grass_') or name in ('biome_seedgrass', 'biome_rush', 'biome_fern', 'biome_wildflowers')
        is_shrub = name.startswith('shrub_') or name in ('biome_heather', 'biome_dry_scrub')
        label = ('grass' if is_grass else 'shrub') if category in ('groundcover', 'authored_nature') and (is_grass or is_shrub) else ('terrain' if '/Land_' in name and category == 'terrain_or_road' else 'excluded')
        for surface in meshes[mesh_id]['surfaces']:
            offset = len(vertices)
            vertices.extend(coord(matrix @ Vector(v)) for v in surface['vertices'])
            indices = surface['indices']
            faces.extend(tuple(offset + indices[i + j] for j in (0, 1, 2)) for i in range(0, len(indices), 3))
            labels.extend([label] * (len(indices) // 3))
    bvh = BVHTree.FromPolygons(vertices, faces, all_triangles=True) if faces else None
    return bvh, labels, {'selected_instances': count, 'triangles': len(faces)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--variant', choices=('before', 'after'), default='after')
    parser.add_argument('--width', type=int, default=192)
    parser.add_argument('--whole-map', action='store_true', help='Measure regional cameras beyond the original route bounds')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    raw = args.source.read_bytes()
    document = json.loads(raw)
    manifest = json.loads(args.manifest.read_text())
    config = manifest['camera_godot']
    profile = manifest['profile']
    instances = document['common'] + document[args.variant]
    ground_instances = [i for i in instances if i['category'] == 'terrain_or_road']
    detail_instances = [i for i in instances if i['category'] != 'terrain_or_road']
    ground, ground_labels, ground_stats = build_bvh(ground_instances, document['meshes'], config['position'], profile)
    details, detail_labels, detail_stats = build_bvh(detail_instances, document['meshes'], config['position'], profile)
    if ground is None:
        raise RuntimeError('No terrain triangles in scene export')
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = manifest['resolution']
    scene.render.resolution_percentage = 100
    camera = bpy.data.cameras.new('CoverageCamera')
    camera.lens = config['lens']
    frame = camera.view_frame(scene=scene)
    left, right = min(v.x for v in frame), max(v.x for v in frame)
    bottom, top = min(v.y for v in frame), max(v.y for v in frame)
    origin = coord(config['position'])
    rotation = (coord(config['target']) - origin).to_track_quat('-Z', 'Y')
    width = args.width
    height = round(width * manifest['resolution'][1] / manifest['resolution'][0])
    bands = [("foreground", 0, 60), ("midground", 60, 150), ("far", 150, 280)]
    stats = {name: {'vegetation_pixels': 0, 'grass_pixels': 0, 'shrub_pixels': 0, 'bare_terrain_pixels': 0} for name, _, _ in bands}
    colors = {'vegetation': (0.08, .85, .16, 1), 'bare': (.2, .4, .95, 1), 'excluded': (.10, .10, .10, 1)}
    masks = {name: list(colors['excluded']) * (width * height) for name, _, _ in bands}
    combined = list(colors['excluded']) * (width * height)
    for y in range(height):
        for x in range(width):
            ray = rotation @ Vector((left + (right - left) * (x + .5) / width, top - (top - bottom) * (y + .5) / height, frame[0].z)).normalized()
            hit, _, ground_index, distance = ground.ray_cast(origin, ray, 4000)
            if hit is None or ground_labels[ground_index] != 'terrain':
                continue
            # Blender -> Godot horizontal XZ. Restrict to the actual route region.
            if not args.whole_map and not (0 <= hit.x < 768 and -768 <= -hit.y < 256):
                continue
            band = next((name for name, low, high in bands if low <= distance < high), None)
            if band is None:
                continue
            label = 'bare'
            if details is not None:
                detail_hit, _, detail_index, detail_distance = details.ray_cast(origin, ray, distance + .0001)
                if detail_hit is not None and detail_distance <= distance + .0001:
                    if detail_labels[detail_index] not in ('grass', 'shrub'):
                        continue  # Landmark/rock occluders are not meadow coverage.
                    label = 'vegetation'
                    stats[band][detail_labels[detail_index] + '_pixels'] += 1
            stats[band]['vegetation_pixels' if label == 'vegetation' else 'bare_terrain_pixels'] += 1
            offset = ((height - 1 - y) * width + x) * 4
            masks[band][offset:offset + 4] = colors[label]
            combined[offset:offset + 4] = colors[label]
    for values in stats.values():
        total = values['vegetation_pixels'] + values['bare_terrain_pixels']
        values['eligible_pixels'] = total
        for category in ('vegetation', 'grass', 'shrub'):
            values[category + '_fraction'] = values[category + '_pixels'] / total if total else None
    args.output.mkdir(parents=True, exist_ok=True)
    stem = args.manifest.stem.replace('_manifest', '') + '_' + args.variant
    for name, pixels in {**masks, 'all': combined}.items():
        image = bpy.data.images.new('CoverageMask', width=width, height=height)
        image.pixels = pixels
        image.filepath_raw = str(args.output / f'{stem}_{name}_coverage.png')
        image.file_format = 'PNG'
        image.save()
        bpy.data.images.remove(image)
    report = {'source': str(args.source), 'source_sha256': hashlib.sha256(raw).hexdigest(),
              'manifest': str(args.manifest), 'camera': config, 'profile': profile, 'variant': args.variant,
              'grid': [width, height], 'bands': stats, 'ground_geometry': ground_stats, 'detail_geometry': detail_stats,
              'mask_legend': {'green': 'actual visible grass/shrub triangle', 'blue': 'bare route terrain', 'dark': 'excluded'},
              'method': 'One center ray per pixel against actual transformed exported triangles; exact quality density prefix and AABB-distance LOD selection; underlying terrain-ray distance determines bands',
              'limitations': ['Sparse camera-grid sampling, no antialiasing; thin blades may be missed', 'Opaque two-sided geometry; no alpha textures or shader displacement simulated', 'Eligible route terrain includes intentional natural clearings and nonplantable slopes; no production allowed() mask', 'Road, sea, sky and nearest nonvegetation occluders excluded', 'CPU preview geometry metric, not a Godot screenshot or FPS measurement'],
              'gpu_fps_measured': False}
    (args.output / f'{stem}_coverage.json').write_text(json.dumps(report, indent=2))
    print('MEADOW_VISIBLE_COVERAGE ' + json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
