class_name PcVrScene
extends Node3D
## Separate, read-only PCVR preview; never opens campaign saves or recordings.

const RigScript := preload("res://src/vr/pc_vr_rig.gd")
const InputReader := preload("res://src/vr/pc_vr_input.gd")
const ArtAsset := preload("res://art/scripts/art_asset.gd")
const START := Vector3(-1.3, .95, -6.0)
var simulated := false
var with_art := true
var world: GameWorld
var rig: PcVrRig
var interface: OpenXRInterface
var startup_failed := false
var _old_physics_rate := 60
var _old_vsync := DisplayServer.VSYNC_ENABLED
var _simulation_yaw := 0.0
var _simulation_pitch := 0.0
var _build_clock := 0.0
var _desktop_status: Label


func _ready() -> void:
	_old_physics_rate = Engine.physics_ticks_per_second
	_old_vsync = DisplayServer.window_get_vsync_mode()
	simulated = simulated or "--vr-sim" in OS.get_cmdline_user_args()
	with_art = with_art and not OS.has_environment("NO_ART")
	if not simulated:
		interface = XRServer.find_interface("OpenXR") as OpenXRInterface
		# Vulkan OpenXR must initialize at engine startup (--xr-mode on). Never
		# retry initialization from a scene or alter the system runtime selection.
		if interface == null or not interface.is_initialized():
			startup_failed = true
			_show_failure()
			return
		if not floor_reference_supported(interface.get_play_area_mode()):
			startup_failed = true
			_show_failure("Runtime nie udostępnił śledzenia względem podłogi.\nUstaw poziom podłogi/obszar w goglach i uruchom podgląd ponownie.")
			return
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.physics_ticks_per_second = 90
		interface.session_visible.connect(_session_interrupted)
		interface.session_stopping.connect(_session_interrupted)
		interface.session_loss_pending.connect(_session_interrupted)
		interface.pose_recentered.connect(_runtime_recentered)
	_build_preview()
	if simulated:
		rig.head.position.y = 1.65
		rig.left.position = Vector3(-.22, 1.2, -.35)
		rig.right.position = Vector3(.22, 1.2, -.35)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_show_simulation_help()


func _build_preview() -> void:
	world = GameWorld.new()
	world.name = "PreviewWorld"
	world.with_input = false
	world.with_art = with_art
	world.save_path = ""
	world.layout_version = 3
	world.settings.graphics_profile = "low"
	world.settings.companion_mode = &"off"
	add_child(world)
	world.start(true)
	world.set_physics_process(false)
	# This is a scale/comfort preview, not a second campaign. Build only the first
	# arena's dressing gradually instead of simulating or decorating all 21 bosses.
	world._pending = world._pending.filter(func(item: Array) -> bool: return item[0] == &"valus")
	world._wake(&"valus")
	var actor := world.player()
	var arena: Dictionary = world.arenas[&"valus"]
	var xf: Transform3D = arena.xf
	actor.global_position = xf * START
	actor.velocity = Vector3.ZERO
	actor.visual.hide()
	actor.reset_physics_interpolation()
	_freeze_physics(world.region)
	var camera := world.refs.camera as PlayerCamera
	camera.current = false
	camera.set_process(false)
	for child in camera.get_children():
		child.set_process(false)
	(world.refs.hud as PlayerHud).hide()
	(world.refs.hud as PlayerHud).set_process(false)
	rig = RigScript.new()
	rig.name = "PcVrRig"
	rig.auto_step = false
	add_child(rig)
	rig.global_basis = xf.basis * Basis(Vector3.UP, PI)
	rig.setup(actor)
	rig.exit_requested.connect(func() -> void: get_tree().quit())
	# Weather uses the actual headset observer, without the third-person camera.
	world.refs.camera = rig.head
	GraphicsQuality.apply(world, "low")
	world.refresh_climate(true)
	_build_approach(xf)


static func floor_reference_supported(mode: int) -> bool:
	return mode in [XRInterface.XR_PLAY_AREA_STAGE, XRInterface.XR_PLAY_AREA_ROOMSCALE]


func _build_approach(xf: Transform3D) -> void:
	# A few existing stones frame the approach while leaving the calf corridor clear.
	if with_art:
		for spec: Array in [["rock_03", Vector3(-5.3, 0, -5.0), .65], ["ruin_column", Vector3(3.7, 0, -5.5), .5], ["rock_01", Vector3(4.8, 0, -2.5), .45]]:
			var art := ArtAsset.new()
			art.model_id = spec[0]
			art.collidable = false
			world.region.add_child(art)
			art.global_transform = xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(spec[2])), spec[1])
			for mesh: MeshInstance3D in art.find_children("*", "MeshInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sign := Label3D.new()
	sign.text = "Futro na tylnej stronie łydki\nDotknij dłonią i przytrzymaj boczny przycisk.\nPociągnij dłoń w dół, aby się podciągnąć."
	sign.font_size = 28
	sign.pixel_size = .004
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.region.add_child(sign)
	sign.global_position = xf * Vector3(-3.5, 1.8, -2.0)


func _physics_process(delta: float) -> void:
	if startup_failed or not is_instance_valid(rig):
		return
	_build_clock += delta
	if _build_clock >= 0.05:
		_build_clock = fmod(_build_clock, 0.05)
		world._build_step()
		world.refresh_climate()
	var frame := _simulation_frame() if simulated else InputReader.read(rig.left, rig.right)
	var focused := simulated or (interface != null and interface.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED)
	rig.step(delta, frame, focused and (simulated or PcVrRig.head_has_tracking()))


func _simulation_frame() -> Dictionary:
	var move := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	var turn := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	return {"move": move, "turn": turn, "confirm": Input.is_physical_key_pressed(KEY_SPACE), "back": false,
		"height": float(Input.is_physical_key_pressed(KEY_PAGEUP)) - float(Input.is_physical_key_pressed(KEY_PAGEDOWN)),
		"left_grip": 1.0 if Input.is_physical_key_pressed(KEY_F) else 0.0,
		"right_grip": 1.0 if Input.is_physical_key_pressed(KEY_G) else 0.0,
		"recenter": Input.is_physical_key_pressed(KEY_Y), "pause": Input.is_physical_key_pressed(KEY_X), "left_tracked": true, "right_tracked": true}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()
	elif simulated and is_instance_valid(rig) and event is InputEventMouseMotion:
		_simulation_yaw -= event.screen_relative.x * 0.002
		_simulation_pitch = clampf(_simulation_pitch - event.screen_relative.y * 0.002, -1.3, 1.3)
		rig.head.rotation = Vector3(_simulation_pitch, _simulation_yaw, 0.0)


func _session_interrupted() -> void:
	if is_instance_valid(rig):
		rig.suspend("Sesja przerwana. Wróć do gogli i naciśnij A.")


func _runtime_recentered() -> void:
	# Stage-space recenter can change tracked poses. Require deliberate calibration
	# again instead of moving the player into an unrelated room or through a wall.
	if is_instance_valid(rig):
		rig.suspend("Zmieniono środek śledzenia. Ustaw się wygodnie i naciśnij A.")


static func _freeze_physics(root: Node) -> void:
	root.set_physics_process(false)
	for child in root.get_children():
		_freeze_physics(child)


func _show_failure(reason := "") -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-320, -120)
	panel.custom_minimum_size.x = 640
	layer.add_child(panel)
	var label := Label.new()
	label.text = "Nie uruchomiono OpenXR.\nPołącz gogle z komputerem i uruchom Uruchom-VR.bat.\nSprawdź aktywny runtime OpenXR w aplikacji gogli.\nGra nie zmienia sterowników ani ustawień systemu."
	if not reason.is_empty():
		label.text = reason
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	var button := Button.new()
	button.text = "Zamknij"
	button.pressed.connect(func() -> void: get_tree().quit())
	panel.add_child(button)
	button.grab_focus()
	print("PCVR unavailable: launch with --xr-mode on and a working OpenXR runtime/headset.")


func _show_simulation_help() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_desktop_status = Label.new()
	_desktop_status.position = Vector2(16, 16)
	_desktop_status.text = "SYMULACJA NA MONITORZE — BEZ GOGLI\nSpacja: gotowość   WASD: chód   Q/E: obrót\nMysz: widok   Y: wycentruj   X: pauza\nPageUp/Down w pauzie: wysokość   F/G: chwyt   Esc: wyjdź"
	layer.add_child(_desktop_status)


func _exit_tree() -> void:
	get_viewport().use_xr = false
	Engine.physics_ticks_per_second = _old_physics_rate
	DisplayServer.window_set_vsync_mode(_old_vsync)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
