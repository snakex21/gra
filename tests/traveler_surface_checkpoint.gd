extends Node
## Cosmetic skeletons never enter the simulation checkpoint. Gameplay actors,
## PlayerVisual and original arm anchors must remain recorded and restorable.
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func freeze(n:Node)->void:
 n.set_process(false);n.set_physics_process(false)
 for child in n.get_children():freeze(child)
func actors(game:GameWorld)->Array:
 return [game.player(),game.companion()]
func assert_graph(data:Dictionary,game:GameWorld)->void:
 var keys:=[]
 for record in data.nodes:
  var key:String=str(record.key);keys.append(key)
  check(not "TravelerArt" in key and not "TravelerSurface" in key,"Cosmetic subtree entered checkpoint: "+key)
 for player_name in ["Player1","Player2"]:
  check(str([player_name]) in keys,"Gameplay player missing: "+player_name)
  check(str([player_name,"Visual"]) in keys,"Gameplay PlayerVisual missing: "+player_name)
 var codec:=WorldSnapshot.new();codec.root=game.region
 for actor in actors(game):
  for arm in actor.visual._arms:check(str(codec._key(arm)) in keys,"Original gameplay arm missing from checkpoint")
func _ready()->void:
 InputSetup.ensure_defaults();Sfx.enabled=false;Fx.enabled=false
 var game:=GameWorld.new();game.with_input=false;game.with_art=true;game.save_path="";add_child(game);game.start(true)
 game.set_companion_mode(&"programmed");freeze(game)
 await get_tree().process_frame
 for actor in actors(game):
  check(actor is PlayerCharacter,"Coop actor missing")
  if not actor:return
 for direction in [[0,2],[2,0]]:
  var old_states:=[]
  for index in range(2):
   var p:PlayerCharacter=actors(game)[index]
   p.health=73.0+index;p.velocity=Vector3(index+.25,.5,-.75)
   p.weapon=PlayerCharacter.Weapon.BOW if index==0 else PlayerCharacter.Weapon.SWORD
   var art:=p.visual.get_node("TravelerArt") as TravelerArt;art.auto_lod=false;art.set_lod(direction[index])
   for anchor in p.visual._arms:check(not art.is_ancestor_of(anchor),"Gameplay arm entered cosmetic subtree")
   for anchor in art._grips:check(not art.is_ancestor_of(anchor),"Rigid grip entered cosmetic subtree")
   p.visual._arms[0].rotation=Vector3(.31+index*.1,.07,0);p.visual._arms[1].rotation=Vector3(-.27-index*.1,-.04,0)
   old_states.append({"health":p.health,"velocity":p.velocity,"weapon":p.weapon,"transform":p.transform,"arms":[p.visual._arms[0].transform,p.visual._arms[1].transform]})
  await get_tree().process_frame
  var saved:=WorldSnapshot.capture(game);assert_graph(saved,game)
  var byte_count:=var_to_bytes(saved).size();var node_count:int=saved.nodes.size();var object_count:int=saved.objects.size()
  for index in range(2):
   var p:PlayerCharacter=actors(game)[index]
   var art:=p.visual.get_node("TravelerArt") as TravelerArt;art.set_lod(direction[1-index])
  await get_tree().process_frame
  var other:=WorldSnapshot.capture(game);assert_graph(other,game)
  check(other.nodes.size()==node_count and other.objects.size()==object_count and var_to_bytes(other).size()==byte_count,"Cosmetic LOD changed checkpoint graph/size")
  check(WorldSnapshot.restore(game,bytes_to_var(var_to_bytes(saved))),"Binary restore failed across cosmetic LOD switch")
  freeze(game)
  for index in range(2):
   var p:PlayerCharacter=actors(game)[index];var expected:Dictionary=old_states[index]
   check(p.health==expected.health and p.velocity==expected.velocity and p.weapon==expected.weapon and p.transform.is_equal_approx(expected.transform),"Restored coop gameplay state changed")
   for side in 2:check(p.visual._arms[side].transform.is_equal_approx(expected.arms[side]),"Original arm transform did not restore")
   var art:=p.visual.get_node("TravelerArt") as TravelerArt;art.auto_lod=false;art.set_lod(direction[1-index]);art.update_surface_pose()
   check(art.surface_pose_report().get("active",false),"Restored cosmetic rig did not reconstruct at requested LOD")
  await get_tree().process_frame
 # Unknown real simulation paths must still fail; no generic missing-node bypass.
 var bad:=WorldSnapshot.capture(game);bad.nodes[0].key=["DefinitelyMissingSimulationNode"]
 check(not WorldSnapshot.restore(game,bad),"Unknown simulation node was silently ignored")
 game.free()
 print("TRAVELER_SURFACE_CHECKPOINT: %d failures; %d checks; bidirectional LOD0/2, two coop actors, graph invariance, binary restore and unknown-path rejection"%[failures,checks])
 get_tree().quit(1 if failures else 0)
