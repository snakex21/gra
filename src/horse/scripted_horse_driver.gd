class_name ScriptedHorseDriver
extends Node3D
## A "rider" that is just data: tests and tools set the fields, the horse reads them
## through the same build_ride_intent() API a player or an AI companion uses.

var direction := Vector3.ZERO
var drive := 0.0
var turn := 0.0
var hold_speed := -1.0
var rein := false
var _kicks := 0
var _slow := 0


func kick() -> void:
	_kicks += 1


func slow() -> void:
	_slow += 1


func build_ride_intent(intent: HorseInputIntent) -> void:
	intent.direction = direction
	intent.drive = drive
	intent.turn = turn
	intent.hold_speed = hold_speed
	intent.rein = rein
	intent.gait_up = _kicks > 0
	intent.gait_down = _slow > 0
	_kicks = maxi(_kicks - 1, 0)
	_slow = maxi(_slow - 1, 0)
