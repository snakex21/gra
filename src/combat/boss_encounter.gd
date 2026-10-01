class_name BossEncounter
extends Node
## Runs one boss encounter (Valus, Quadratus, ...): watches for the player's death and the
## boss' defeat, and resets everything needed to fight again (player, health, stamina,
## boss state, weak point, Agro) without a long walk back.
##
##   RUNNING -> (player dead) PLAYER_DEAD -> short pause -> reset -> RUNNING
##   RUNNING -> (weak point destroyed) DEFEATED ("COLOSSUS DEFEATED")
## The quick debug reset (F5) calls reset_encounter() directly.

signal encounter_reset(count: int)

enum State { RUNNING, PLAYER_DEAD, DEFEATED }

@export var death_pause := 2.5

## The boss: any Colossus with a ``defeated`` signal and reset_encounter().
var boss: Colossus
var players: Array[PlayerCharacter] = []
var horse: Horse
var horse_start := Transform3D.IDENTITY
var state := State.RUNNING
var resets := 0
## Text shown in the middle of the screen ("" when none).
var banner := ""
var time := 0.0
var defeat_time := -1.0

var _dead_time := 0.0


func _ready() -> void:
	# After the colossus, the horse and the players.
	process_physics_priority = 50


func setup(p_boss: Colossus, p_players: Array[PlayerCharacter], p_horse: Horse) -> void:
	boss = p_boss
	players = p_players
	horse = p_horse
	if horse:
		horse_start = horse.global_transform
	for p in players:
		# The encounter owns death: pause, then reset the whole fight.
		p.auto_respawn = false
	boss.defeated.connect(_on_defeated)


func _physics_process(delta: float) -> void:
	time += delta
	match state:
		State.RUNNING:
			for p in players:
				if p.dead:
					state = State.PLAYER_DEAD
					_dead_time = 0.0
					banner = "YOU DIED"
					break
		State.PLAYER_DEAD:
			_dead_time += delta
			if _dead_time >= death_pause:
				reset_encounter()
		State.DEFEATED:
			pass


func reset_encounter() -> void:
	resets += 1
	boss.reset_encounter()
	for p in players:
		p.respawn()
	if horse:
		horse.set_rider(null)
		horse.command_stop()
		horse.teleport(horse_start.origin, horse_start.basis.get_euler().y)
	state = State.RUNNING
	banner = ""
	defeat_time = -1.0
	encounter_reset.emit(resets)


func state_name() -> String:
	return State.keys()[state]


func _on_defeated() -> void:
	state = State.DEFEATED
	defeat_time = time
	banner = "COLOSSUS DEFEATED"
