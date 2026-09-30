class_name ClimbPatch
extends CollisionShape3D
## A collision shape the player can grip (fur, ledges, cracked stone...).
##
## Climbability is a property of the individual shape, not of the whole body, so a
## single colossus segment can mix fur (ClimbPatch) with smooth stone or armour
## (plain CollisionShape3D). Rays that hit a plain shape are treated as a wall
## the climber cannot hold on to.

## Multiplier for stamina drain while holding this patch (1 = normal, >1 = harder).
@export var grip_cost := 1.0
## Constant downward slide speed (m/s) even with full stamina. 0 = firm grip.
@export var slip_speed := 0.0
