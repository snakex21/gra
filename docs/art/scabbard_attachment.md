# Visible hip scabbard and sword-belt suspension

Baseline: b152e6e8c4139218bb2a6207fbae243bf6e4f279.

The previous scabbard was a real hollow asset, but its back mount placed it behind the carried bow in rear views. It had no straps connecting its two suspension rings to the character. The asset itself was not replaced: the 3 mm walls, open mouth, bronze bands, blade cavity, source Blender file and all LODs remain unchanged.

`WeaponArt` now uses a body-local left-hip mount with two solid leather straps and two belt loops. Their endpoints share the actual asset ring positions. The stored sword shares the entire scabbard transform, keeping its blade inside the authored cavity. Drawing/equipping the sword leaves the empty scabbard visible. Switching back to bow restores exactly one stored sword. These remain the existing immediate equipment switches; this change does not introduce a draw-animation or combat system.

The mount blends with the existing continuous seat-contact weight. While seated, the case hangs diagonally alongside Agro's left side. The resting, on-foot bow hand is held slightly farther left to avoid the stored sword hilt. Aimed bow transforms, the physical arrow point, sword combat/hitboxes, reins, rider seating, cooperative play, and save formats are unchanged.

Validation adds geometric strap endpoint and actual ring-vertex checks to the existing `weapon_mounts` test across all LODs, climbing, bow use, and repeated mount/dismount/equipment switches. The existing mounted bow test now expects the revised cosmetic scabbard axis. Render evidence uses actual Godot-exported runtime meshes, skins and poses, then matched Blender Cycles CPU cameras/lights. This does not measure GPU FPS or prove continuous collision-free motion for every possible gameplay pose.
