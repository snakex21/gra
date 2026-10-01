class_name HorseInputIntent
extends RefCounted
## What a rider wants from the horse this tick, independent of any input device.
## Filled by a riding player (keyboard / pad / later VR), the horse's own AI or a test;
## the horse controller only ever reads this.

## Desired travel direction (world, horizontal). ZERO = keep the current heading.
var direction := Vector3.ZERO
## 0..1: how strongly the rider pushes along ``direction`` (0 = no push, keep the gait).
var drive := 0.0
## -1..1 steering relative to the horse (used when ``direction`` is ZERO, e.g. while aiming).
var turn := 0.0
## Edge: a kick, one gait faster.
var gait_up := false
## Edge: one gait slower.
var gait_down := false
## Hold: pull the reins, slow down to a stop.
var rein := false
## >= 0: exact desired speed (AI / tests); < 0: use the gait the rider asked for.
var hold_speed := -1.0


func clear() -> void:
	direction = Vector3.ZERO
	drive = 0.0
	turn = 0.0
	gait_up = false
	gait_down = false
	rein = false
	hold_speed = -1.0
