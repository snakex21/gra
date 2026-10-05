extends Node3D
## Two live cosmetic instances share immutable imported resources, never poses.
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func pose_digest(skeleton:Skeleton3D)->int:
 var values:=[]
 for i in skeleton.get_bone_count():values.append(skeleton.get_bone_global_pose(i))
 return hash(var_to_bytes(values))
func source_digest(node:MeshInstance3D)->int:
 var values:=[]
 for i in node.mesh.get_surface_count():values.append(node.mesh.surface_get_arrays(i))
 if node.skin:
  for i in node.skin.get_bind_count():values.append([node.skin.get_bind_bone(i),node.skin.get_bind_name(i),node.skin.get_bind_pose(i)])
 return hash(var_to_bytes(values))
func set_pose(player:PlayerCharacter,angle:float)->void:
 var art:=player.visual.get_node("TravelerArt") as TravelerArt
 for side in 2:
  player.visual._arms[side].rotation=Vector3(angle,0,0)
  art._forearms[side].rotation=Vector3(-.2 if angle>1.0 else .05,0,0)
  art._wrists[side].rotation=Vector3(.13,.4 if side==0 else -.6,-.17)
 art.update_surface_pose()
func _ready()->void:
 InputSetup.ensure_defaults();Sfx.enabled=false;Fx.enabled=false
 var players:Array[PlayerCharacter]=[]
 var arts:Array[TravelerArt]=[]
 for side in 2:
  var player:=PlayerCharacter.new();add_child(player);player.position=Vector3(side*2.0,0,0);player.set_physics_process(false)
  var art:=player.visual.get_node("TravelerArt") as TravelerArt;art.set_process(false);art.auto_lod=false
  var gear:=player.visual.get_node("WeaponArt") as WeaponArt;gear.set_process(false);gear.auto_lod=false
  art._surface_pose.set_process(false);players.append(player);arts.append(art)
 var immutable:=[]
 var shared_meshes:=0
 for cycle in 6:
  var lod:=cycle%3
  arts[0].set_lod(lod);arts[1].set_lod(lod)
  await get_tree().process_frame
  await get_tree().process_frame
  for art in arts:art._surface_pose.set_process(false)
  check(arts[0]._surface_pose.skeleton!=arts[1]._surface_pose.skeleton,"Instances share a mutable skeleton node")
  var first:=arts[0].model.find_children("*","MeshInstance3D",true,false)
  var second:=arts[1].model.find_children("*","MeshInstance3D",true,false)
  check(first.size()==second.size(),"Matched LOD instances differ in mesh count")
  for i in mini(first.size(),second.size()):
   var a:=first[i] as MeshInstance3D;var b:=second[i] as MeshInstance3D
   if a.mesh==b.mesh:shared_meshes+=1
   immutable.append({"node":a,"mesh":a.mesh,"skin":a.skin,"signature":source_digest(a)})
  set_pose(players[0],PI*.95)
  set_pose(players[1],0)
  var first_pose:=pose_digest(arts[0]._surface_pose.skeleton)
  check(first_pose!=pose_digest(arts[1]._surface_pose.skeleton),"Opposite poses unexpectedly equal")
  for angle in [0.2,1.2,2.7,0.0]:
   set_pose(players[1],angle)
   check(pose_digest(arts[0]._surface_pose.skeleton)==first_pose,"Player2 pose contaminated Player1 skeleton")
  var second_pose:=pose_digest(arts[1]._surface_pose.skeleton)
  arts[0].set_lod((lod+1)%3)
  await get_tree().process_frame
  await get_tree().process_frame
  arts[0]._surface_pose.set_process(false)
  check(pose_digest(arts[1]._surface_pose.skeleton)==second_pose,"Player1 LOD replacement contaminated Player2 pose")
  for art in arts:
   art.update_surface_pose();check(art.surface_pose_report().active,"Cosmetic instance lost active rig")
 # Source records keep resources alive even after their instance/LOD is freed.
 for record in immutable:
  var temporary:=MeshInstance3D.new();temporary.mesh=record.mesh;temporary.skin=record.skin
  check(source_digest(temporary)==record.signature,"Shared bind arrays or Skin bind transforms mutated")
  temporary.free()
 check(shared_meshes>0,"Fixture did not exercise shared imported mesh resources")
 for player in players:player.free()
 print("TRAVELER_SURFACE_ISOLATION: %d failures; %d checks; 2 instances; 6 paired LOD cycles; %d shared mesh references; original arrays/binds unchanged" % [failures,checks,shared_meshes])
 get_tree().quit(1 if failures else 0)
