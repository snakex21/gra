class_name Dormin
extends Valus
## Alternate playable finale. The three independent shadow locks open the body
## for a physical climb to the back and crown. Defeat never kills the player.
signal seals_changed(count: int)
const SEALS_LOCAL := [Vector3(-24, .85, 16), Vector3(24, .85, 16), Vector3(0, .85, -26)]
var seals: Array[DorminSeal] = []
var back_sigil: WeakPoint
var seals_broken := 0
var windows := 0
var _climb_open := true
var _open_left := 0.0
var _patches: Array[ClimbPatch] = []
var _seal_root: Node3D

func _init() -> void:
	arena_radius = 31
	notice_radius = 45
	brain_seed = 127
	stomp_damage = 22
	sweep_damage = 25

func _ready() -> void:
	super()
	for segment in segments:
		for child in segment.get_children():
			if child is ClimbPatch:
				_patches.append(child)
				# The extra back sigil adds two charged hits before the shoulder rest.
				# Dense shadow fibres give that longer route a fair stamina budget.
				child.grip_cost = .65
			if child is MeshInstance3D:
				var shadow := StandardMaterial3D.new()
				shadow.albedo_color = Color(.055, .075, .085)
				shadow.roughness = .95
				child.material_override = shadow
	back_sigil = WeakPoint.create(_seg_by_bone[&"spine"], Vector3(0, 1.80, 1.31), 80)
	back_sigil.radius = 1.15
	back_sigil.rotation.x = PI * .5
	back_sigil.struck.connect(_on_weak_point_struck)
	back_sigil.destroyed.connect(_on_weak_point_destroyed)
	_seal_root = Node3D.new()
	_seal_root.name = "DorminShadowLocks"
	_seal_root.top_level = true
	add_child(_seal_root)
	_seal_root.global_transform = _start_xf
	for index in 3:
		var seal := DorminSeal.new()
		seal.name = "Seal%d" % index
		seal.kind = index as DorminSeal.Kind
		seal.position = SEALS_LOCAL[index]
		_seal_root.add_child(seal)
		seals.append(seal)
		seal.dispelled.connect(_seal_broken)
	_dress_shadow_crown()
	reset_encounter()

func _dress_shadow_crown() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(.08, .11, .12)
	for side in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.bottom_radius = .30
		shape.top_radius = .04
		shape.height = 1.9
		shape.radial_segments = 8
		horn.mesh = shape
		horn.material_override = dark
		horn.position = Vector3(side * .80, 2.05, -.65)
		horn.rotation.z = side * -.44
		_seg_by_bone[&"head"].add_child(horn)

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	super(xf, use_xf)
	if is_instance_valid(_seal_root):
		_seal_root.global_transform = _start_xf
		for seal in seals:
			seal.reset()
	if is_instance_valid(back_sigil):
		back_sigil.reset()
	_gate(false)
	weak_point.set_protected(true)
	if back_sigil:
		back_sigil.set_protected(true)

func _reset_extra() -> void:
	super()
	seals_broken = 0
	windows = 0
	_open_left = 0

func _gate(open: bool) -> void:
	if open == _climb_open:
		return
	_climb_open = open
	for patch in _patches:
		patch.set_deferred(&"disabled", not open)

func _seal_broken() -> void:
	seals_broken = 0
	for seal in seals:
		seals_broken += 1 if seal.broken else 0
	if seals_broken == 3:
		windows += 1
		_open_left = 85
		_gate(true)
	seals_changed.emit(seals_broken)

func _extra_rules(out: Array[StringName]) -> void:
	out.append(PROTECT)

func _update_extra(_it: ColossusIntent, delta: float) -> void:
	if is_defeated():
		return
	if _climb_open:
		var ridden := false
		for p in get_tree().get_nodes_in_group(&"players"):
			ridden = ridden or owns_body(p.get_support_body())
		if not ridden:
			_open_left = maxf(0, _open_left - delta)
		if _open_left <= 0:
			seals[2].reset()
			seals_broken = 2
			_gate(false)
			seals_changed.emit(2)
	weak_point.set_protected(not _climb_open or back_sigil.state != WeakPoint.State.DESTROYED)
	back_sigil.set_protected(not _climb_open)

func _on_weak_point_destroyed() -> void:
	if back_sigil and back_sigil.state == WeakPoint.State.DESTROYED and weak_point.state == WeakPoint.State.DESTROYED:
		_set_encounter(Encounter.DEFEATED)

func beam_weak_point() -> WeakPoint:
	return back_sigil if back_sigil and back_sigil.state != WeakPoint.State.DESTROYED else super()

func beam_target() -> Vector3:
	for seal in seals:
		if not seal.broken:
			return seal.global_position
	return super()

func encounter_hint() -> String:
	if is_defeated():
		return "Cień Dormina rozproszony. Wander żyje."
	if seals_broken == 3:
		return "Ciało otwarte. Wejdź po nodze i plecach; rozbij sigil na grzbiecie, potem na koronie."
	return "Trzy więzy: światło (zielony), światło + mocny cios (bursztyn), światło + szybki cios (ruchomy cień)."

func _debug_extra() -> String:
	return "Dormin locks %d/3, window %.1f, back %.0f" % [seals_broken, _open_left, back_sigil.health if back_sigil else 80]
