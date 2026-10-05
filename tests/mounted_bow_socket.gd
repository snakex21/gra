extends Node3D
## Mounted anatomical muzzle is shared by aiming, visible nock and real projectile.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func legacy_origin(p: PlayerCharacter) -> Vector3:
	var right := Vector3(p.actions.view_basis.x.x, 0, p.actions.view_basis.x.z).normalized()
	return p.global_position + Vector3.UP * .55 - right * .15
func cheek_origin(p: PlayerCharacter) -> Vector3:
	var up := Vector3.UP
	if p.riding and p.riding.is_active() and is_instance_valid(p.riding.horse):
		up = up.lerp(p.riding.horse.body_transform().basis.y.normalized(), p.riding.cosmetic_seat_weight()).normalized()
	var frame := Basis.looking_at(-p.actions.view_basis.z, up)
	return p.global_position + frame * Vector3(.17, .55, .05)
func _ready() -> void:
	InputSetup.ensure_defaults(); Sfx.enabled = false; Fx.enabled = false
	var horse := Horse.new(); add_child(horse); freeze(horse)
	for frame in 90: horse._pose(1.0 / 60.0)
	var p := PlayerCharacter.new(); add_child(p); freeze(p)
	p.weapon = PlayerCharacter.Weapon.BOW
	var gear := p.visual.get_node("WeaponArt") as WeaponArt
	var art := p.visual.get_node("TravelerArt") as TravelerArt
	gear.auto_lod = false; art.auto_lod = false
	p.actions.view_basis = Basis.IDENTITY
	check(p.bow.bow_point(p).is_equal_approx(cheek_origin(p)), "Ground physical muzzle is not the right-cheek anchor")
	p.riding.mount_now(horse)
	for slope in [Vector3.ZERO, Vector3(.15, .30, -.12)]:
		horse.rotation = slope
		p.riding.mount_now(horse)
		var mounted_root := p.global_transform
		for phase in [PlayerRiding.Phase.MOUNTING, PlayerRiding.Phase.DISMOUNTING]:
			p.riding.phase = phase
			var previous := Vector3.ZERO
			for step in 21:
				p.riding._t = step / 20.0
				gear.update_equipment(0)
				var seat_weight := p.riding.cosmetic_seat_weight()
				var sheath_axis := Vector3(-.055, -.79, .61).lerp(Vector3(-.24, -.59, .77), seat_weight).normalized()
				check(gear.scabbard.basis.y.distance_to(sheath_axis) < .00001, "Scabbard does not blend around the saddle with seat contact")
				check(absf(gear.stored_bow.position.y - (.11 + .15 * seat_weight)) < .00001, "Stored bow does not lift continuously clear of the saddle")
				var correction := p.bow.bow_point(p) - cheek_origin(p)
				var expected := horse.body_transform().basis.y * (PlayerRiding.SEATED_VISUAL_OFFSET * p.riding.cosmetic_seat_weight())
				check(correction.distance_to(expected) < .00001, "Transition muzzle diverges from seated visual offset/basis")
				check(correction.is_finite() and correction.length() <= absf(PlayerRiding.SEATED_VISUAL_OFFSET) + .00001, "Transition muzzle correction is unbounded")
				if step > 0: check(correction.distance_to(previous) < .03, "Mount/dismount muzzle snaps between adjacent weights")
				previous = correction
			check(p.global_transform == mounted_root, "Computing muzzle moved the gameplay player")
		p.riding.phase = PlayerRiding.Phase.RIDING; p.riding._t = 1
		for lod in 3:
			art.set_lod(lod); gear.set_lod(lod)
			for draw in [.35, 1.0]:
				p.bow.state = PlayerBow.State.AIM; p.bow.draw = draw
				p.bow.aim_dir = Vector3(0,.12,-1).normalized()
				p.actions.view_basis = Basis.looking_at(p.bow.aim_dir)
				var origin := p.bow.bow_point(p)
				for fps in [30, 60, 120]:
					p.visual.update_visual(p, 1.0 / fps)
					art.pose_preview(&"ride", .7)
					gear.update_equipment(0)
					check(p.bow.bow_point(p).is_equal_approx(origin), "Render FPS/LOD changed simulation muzzle")
					check(gear.arrow.global_position.distance_to(origin) < .00001, "Mounted visual nock differs from physical muzzle")
					check(float(gear.hand_errors[0]) < .04 and float(gear.hand_errors[1]) < .04, "Mounted archery wrist unreachable: %s" % [gear.hand_errors])
					check((-gear.arrow.global_basis.z).dot(p.bow.aim_dir) > .99999, "Mounted arrow aim differs from trajectory")
	# A low wall intercepts the seated arrow. Its top is below the old incorrect
	# launch point, demonstrating why visual-only nock correction is insufficient.
	horse.rotation = Vector3.ZERO; p.riding.mount_now(horse)
	p.actions.view_basis = Basis.IDENTITY
	var origin := p.bow.bow_point(p)
	var wall := StaticBody3D.new(); wall.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(1.2, .20, .10); shape.shape = box; wall.add_child(shape)
	add_child(wall); wall.global_position = origin + Vector3(0, -.04, -.90)
	await get_tree().physics_frame; await get_tree().physics_frame
	var old_ray := PhysicsRayQueryParameters3D.create(legacy_origin(p), legacy_origin(p) + Vector3.FORWARD * 2.0, Layers.WORLD)
	check(get_world_3d().direct_space_state.intersect_ray(old_ray).is_empty(), "Low-wall fixture no longer distinguishes the old high launch")
	var arrows := ArrowSystem.of(p); arrows.set_physics_process(false)
	for shot in 2:
		p.bow.draw = .35 if shot == 0 else 1.0
		p.bow.state = PlayerBow.State.AIM
		p.bow.aim_dir = Vector3.FORWARD
		p.actions.aim_origin = origin
		p.velocity = Vector3(.7, 0, -1.2)
		gear.update_equipment(0)
		var visible_nock := gear.arrow.global_position
		p.bow._shoot(p)
		var a: Dictionary = p.bow.last_shot.arrow
		var carrier := a.node as MeshInstance3D
		var model := carrier.get_node("ArrowModel") as Node3D
		check((a.start as Vector3).distance_to(origin) < .00001, "Projectile uses an origin other than mounted physical muzzle")
		check(model.global_position.distance_to(visible_nock) < .00001, "Visible arrow tail jumps at mounted release")
		check(model.position == Vector3.ZERO, "Hidden ArrowModel offset masks a physical muzzle mismatch")
		check((a.vel as Vector3).distance_to(p.bow.aim_dir * p.bow.speed_for(p.bow.draw) + p.velocity) < .00001, "Mounted shot lost speed or inherited horse velocity")
		check(carrier.find_children("*", "CollisionObject3D", true, false).is_empty(), "Visual projectile introduced a separate hitbox")
		for frame in 8:
			if a.state == &"stuck": break
			arrows._physics_process(1.0 / 60.0)
		check(a.state == &"stuck", "Seated arrow incorrectly clears the low wall")
		check(absf((a.pos as Vector3).z - (wall.global_position.z + .05)) < .02, "Arrow did not hit the visible wall front")
	arrows.clear()
	p.riding.phase = PlayerRiding.Phase.NONE; p.state = PlayerCharacter.State.GROUND
	check(p.bow.bow_point(p).is_equal_approx(cheek_origin(p)), "Ground right-cheek muzzle changed after dismount")
	p.free(); horse.free(); wall.free(); arrows.free()
	print("MOUNTED_BOW_SOCKET: %d failures; %d checks; slope/transition/FPS/LOD/partial+full release, identical visual/physics launch, inherited velocity and low-wall interception" % [failures, checks])
	get_tree().quit(1 if failures else 0)
