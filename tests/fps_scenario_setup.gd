extends Node
## Arena-owned ground must replace the bootstrap collider before the first tick.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func freeze(node: Node) -> void:
 node.set_process(false);node.set_physics_process(false)
 for child in node.get_children():freeze(child)
func _ready() -> void:
 InputSetup.ensure_defaults();Sfx.enabled=false;Fx.enabled=false
 var scene_script:=load("res://tests/fps_scenario.gd")as Script
 for scenario in ["quadratus","quadratus_horse"]:
  var fixture:=scene_script.new()as Node
  fixture.scenario=scenario
  add_child(fixture)
  freeze(fixture)
  var bootstrap_colliders:=0
  var queued_colliders:=0
  for child in fixture.get_children():
   if child is CollisionObject3D:bootstrap_colliders+=1
  for node in fixture.find_children("*","CollisionObject3D",true,false):
   if node.is_queued_for_deletion():queued_colliders+=1
  check(bootstrap_colliders==0,scenario+": temporary ground still belongs to the live scenario before tick one")
  check(queued_colliders==0,scenario+": a deferred collider removal can depend on the first render frame")
  var game:Dictionary=fixture.boss
  var arena:Node=game.quadratus.get_parent()
  var ground:=arena.get_node_or_null("Ground")as StaticBody3D
  check(ground!=null,scenario+": the actual arena ground is missing")
  if ground:
   check(ground.is_inside_tree()and not ground.is_queued_for_deletion(),scenario+": real ground is not active")
   check(ground.collision_layer==Layers.WORLD,scenario+": real ground lost its physics layer")
   var shape:=ground.get_child(0)as CollisionShape3D
   check(shape!=null and shape.shape is BoxShape3D and (shape.shape as BoxShape3D).size==Vector3(600,2,600),scenario+": arena geometry changed instead of removing the unused bootstrap")
  check(fixture.tick==0,scenario+": initialization verification skipped physics ticks")
  check(fixture.qbot.use_horse==(scenario=="quadratus_horse"),scenario+": scenario driver mode changed")
  remove_child(fixture);fixture.free()
 print("FPS_SCENARIO_SETUP: %d failures; %d checks; cold foot/horse setup, no queued collider, unchanged actual ground, no skipped ticks"%[failures,checks])
 get_tree().quit(1 if failures else 0)
