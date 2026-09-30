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

var _jump_pressed := false


func press_jump() -> void:
	_jump_pressed = true


## Returns true once per jump press.
func consume_jump() -> bool:
	var pressed := _jump_pressed
	_jump_pressed = false
	return pressed


func clear() -> void:
	move = Vector2.ZERO
	look_delta = Vector2.ZERO
	grab_held = false
	focus_held = false
	_jump_pressed = false
