# Nature Craft — pochodzenie

20 oryginalnych modeli proceduralnych wykonanych lokalnie w Blenderze 4.3.2, z oddzielnie modelowanymi trzema poziomami szczegółowości. Nie użyto ImageGen, pobranych modeli, tekstur fotograficznych, sieci ani płatnych dodatków.

Atlas textures/nature_atlas_1k.png jest niezmienioną kopią textures/mirewood/atlas_1k.png z istniejącego uprawnionego repo gry, commit 0fa42e831d636d86580f12748af0a91a581ab17b. Autorstwo i licencja atlasu opisane są w dołączonym SOURCE_ASSET_LICENSES.md. Geometria nowych modeli została napisana od zera w tools/build_nature.py. Nowe modele i rendery: CC0-1.0. Nowe skrypty: MIT (LICENSE_CODE.txt). Ta deklaracja nie zmienia licencji oryginalnej gry.

Podglądy previews/blender_*.png to rzeczywiste rendery Blender Cycles CPU, 48 próbek, bez odszumiania, bez retuszu. To nie są zrzuty Godota i nie są benchmarkiem gry. Pierwszy test wykazał brak OpenImageDenoise w lokalnym buildzie; końcowe rendery wykonano prawidłowo bez tego dodatku.

Cały zestaw jest osobny. Nie zmieniono repo gry, gotowego patcha środowiska, AI, co-op, gameplayu ani fizyki. Bryły są wizualne; brak kolizji jest celowy. Testy sprawdzają import i geometrię, a nie osiągi GPU użytkownika.

## Runtime integration packaging

These runtime GLBs are repackaged from the original Nature Craft deliverable by
`tools/art/package_nature_placement_assets.py`. Embedded atlas payloads and
material references were removed; geometry bytes, accessors, UVs, normals,
indices, nodes and transforms are unchanged and verified against the originals.
One original atlas is provided under `textures/nature_craft/`. The original
portable GLBs and editable Blender source remain in the prior Nature Craft
pack, not duplicated in this runtime patch. See
`data/environment/nature_source_manifest.json` for source/runtime hashes.
