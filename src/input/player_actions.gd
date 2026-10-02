class_name PlayerActions
extends RefCounted
## Abstract per-player action frame.
##
## Gameplay code reads ONLY this object, never Input/InputMap directly.
## Flat input (keyboard/mouse/gamepad), VR controllers, an AI companion or an
## automated test are just different sources that fill it in.
## Continuous values are overwritten every frame by the source; edge-triggered
## values (``*_pressed``) are latched by the source and consumed by gameplay.

## Planar movement request. x = right, y = forward (relative to ``view_basis``), length <= 1.
var move := Vector2.ZERO
## Accumulated camera rotation request in radians (x = yaw, y = pitch). Consumed by the camera.
var look_delta := Vector2.ZERO
## Orientation that ``move`` is relative to (camera for flat play, HMD for VR).
var view_basis := Basis.IDENTITY
## Grip is held. Flat play drives both hands from one button; VR will split this per hand
## once the VR spike happens (the climbing code already stores a single anchor per grip).
var grab_held := false
## Hold to frame the current target (colossus) with the camera.
var focus_held := false
## Weapon use: sword (hold to charge, release to strike) or bow (hold to draw, release
## to shoot).
var attack_held := false
## Hold to raise the sword to the sun (the beam that leads to the next colossus).
var beam_held := false
## Hold to dive (swimming: down under the surface; let go to come up).
var dive_held := false
## Where the aim ray starts (camera / controller position); INF = from the player's eyes.
## The aim direction is -view_basis.z.
var aim_origin := Vector3.INF

var _jump_pressed := false
var _interact_pressed := false
var _call_pressed := false
var _switch_weapon_pressed := false


func press_jump() -> void:
	_jump_pressed = true


## Returns true once per jump press.
func consume_jump() -> bool:
	var pressed := _jump_pressed
	_jump_pressed = false
	return pressed


## Edge: interact (mount / dismount).
func press_interact() -> void:
	_interact_pressed = true


func consume_interact() -> bool:
	var pressed := _interact_pressed
	_interact_pressed = false
	return pressed


## Edge: call the horse.
func press_call() -> void:
	_call_pressed = true


func consume_call() -> bool:
	var pressed := _call_pressed
	_call_pressed = false
	return pressed


## Edge: next weapon (sword <-> bow).
func press_switch_weapon() -> void:
	_switch_weapon_pressed = true


func consume_switch_weapon() -> bool:
	var pressed := _switch_weapon_pressed
	_switch_weapon_pressed = false
	return pressed


## Everything gameplay reads this tick (no consuming): for recording and replay.
func snapshot() -> Array:
	return [move, view_basis, grab_held, focus_held, attack_held, beam_held, aim_origin,
		_jump_pressed, _interact_pressed, _call_pressed, _switch_weapon_pressed, dive_held]


## Puts a snapshot back (replay).
func restore(s: Array) -> void:
	move = s[0]
	view_basis = s[1]
	grab_held = s[2]
	focus_held = s[3]
	attack_held = s[4]
	beam_held = s[5]
	aim_origin = s[6]
	_jump_pressed = s[7]
	_interact_pressed = s[8]
	_call_pressed = s[9]
	_switch_weapon_pressed = s[10]
	# Recordings from before diving (Etap 10) have no dive.
	dive_held = s[11] if s.size() > 11 else false


func clear() -> void:
	move = Vector2.ZERO
	look_delta = Vector2.ZERO
	grab_held = false
	focus_held = false
	attack_held = false
	beam_held = false
	dive_held = false
	_jump_pressed = false
	_interact_pressed = false
	_call_pressed = false
	_switch_weapon_pressed = false
