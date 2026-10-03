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
var _revive_wait := {}


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
	# A participant may leave the session; preserve the living player's encounter.
	for index in range(players.size() - 1, -1, -1):
		if not is_instance_valid(players[index]):
			players.remove_at(index)
	match state:
		State.RUNNING:
			var alive := 0
			for p in players:
				if is_instance_valid(p) and not p.dead:
					alive += 1
			if alive == 0 and not players.is_empty():
				state = State.PLAYER_DEAD
				_dead_time = 0.0
				banner = "YOU DIED"
			else:
				# A companion falling does not reset the host's fight or the boss' health.
				for p in players:
					if not is_instance_valid(p):
						continue
					var id := p.get_instance_id()
					if p.dead:
						_revive_wait[id] = float(_revive_wait.get(id, 0.0)) + delta
						if float(_revive_wait[id]) >= death_pause:
							p.respawn()
							_revive_wait.erase(id)
					else:
						_revive_wait.erase(id)
		State.PLAYER_DEAD:
			_dead_time += delta
			if _dead_time >= death_pause:
				reset_encounter()
		State.DEFEATED:
			pass


func reset_encounter() -> void:
	_revive_wait.clear()
	resets += 1
	boss.reset_encounter()
	for p in players:
		if is_instance_valid(p):
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
