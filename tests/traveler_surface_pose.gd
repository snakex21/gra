extends Node3D
## Prototype contract only: exact old anchors, cosmetic endpoints, source array
## immutability and bounded finite poses. NOT a silhouette/no-clipping gate.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func mesh_digest(mesh: Mesh) -> int:
 var arrays := []
 for surface in mesh.get_surface_count(): arrays.append(mesh.surface_get_arrays(surface))
 return hash(var_to_bytes(arrays))
func check_correctives(driver: TravelerSurfacePose, visual: Node3D) -> void:
 if driver.contract_version not in [3,4,5]:return
 var expected_count:=21 if driver.contract_version==3 else (19 if driver.contract_version==5 else 17)
 check(driver.skeleton.get_bone_count()==expected_count and driver.last_report.cosmetic_bones==expected_count,"Wrong cosmetic bone count for source contract")
 var model_basis_to_skeleton:=driver.skeleton.global_basis.inverse()*visual.global_basis
 var model_up:Vector3=(model_basis_to_skeleton*Vector3.UP).normalized()
 for name in driver._corrective_bones:
  var entry:Dictionary=driver._corrective_bones[name]
  var side:int=entry.side
  var upper:=driver.skeleton.get_bone_global_pose(driver.bones["SurfaceUpper_%d"%side])
  var lower:=driver.skeleton.get_bone_global_pose(driver.bones["SurfaceLower_%d"%side])
  var component:float=(lower.origin-upper.origin).normalized().dot(model_up)
  var down:float=pow(maxf(0,-component),2);var up:float=pow(maxf(0,component),2)
  var side_report:Dictionary=driver.last_report.sides[side]
  check(absf(side_report.corrective_down_factor-down)<.000001 and absf(side_report.corrective_up_factor-up)<.000001,"Corrective activation disagrees with actual upper direction")
  var base:=driver.skeleton.get_bone_global_pose(driver.bones[entry.base])
  var posed:=driver.skeleton.get_bone_global_pose(driver.bones[name])
  var offset:Vector3=model_basis_to_skeleton*(entry.down*down+entry.up*up)
  check(posed.origin.distance_to(base.origin+offset)<.00001,"Corrective translation differs from declared coefficients")
  check(posed.basis.is_equal_approx(base.basis),"Translation-only corrective changed bone basis")
func _ready() -> void:
 InputSetup.ensure_defaults();Sfx.enabled=false;Fx.enabled=false
 var player:=PlayerCharacter.new();add_child(player);player.set_physics_process(false)
 var art:=player.visual.get_node("TravelerArt") as TravelerArt
 art.set_process(false);art.auto_lod=false
 var gear:=player.visual.get_node("WeaponArt") as WeaponArt
 gear.set_process(false);gear.auto_lod=false
 var original_player_transform:=player.transform
 var original_shape:=player._shape
 var original_actions:=player.actions
 var original_blade:=player.visual._blade
 var maximum_stretch:=1.0;var maximum_error:=0.0;var poses:=0;var maximum_bound:=0.0
 for level in 3:
  art.set_lod(level)
  await get_tree().process_frame
  await get_tree().process_frame
  var driver:=art._surface_pose
  check(is_instance_valid(driver) and is_instance_valid(driver.skeleton),"LOD missing cosmetic skeleton")
  if not is_instance_valid(driver) or not is_instance_valid(driver.skeleton):continue
  driver.set_process(false)
  var skin_meshes: Array[MeshInstance3D]=[]
  var hashes:=[]
  for node in art.model.find_children("*","MeshInstance3D",true,false):
   var mesh:=node as MeshInstance3D
   if mesh.skin:
    skin_meshes.append(mesh);hashes.append(mesh_digest(mesh.mesh))
  if driver.contract_version==5:
   check(skin_meshes.size()==6,"Schema5 final asset requires six cosmetic skin meshes")
   for name in ["Traveler_TunicSurface","Traveler_ArmSurface_0","Traveler_ArmSurface_1","Traveler_Torso","Traveler_Thigh_0","Traveler_Thigh_1"]:
    var mesh:=art.model.find_child(name+"*",true,false) as MeshInstance3D
    check(mesh!=null and mesh.skin!=null and mesh.get_node_or_null(mesh.skeleton)==driver.skeleton,"Expected mesh missing from shared cosmetic rig: "+name)
  else:check(skin_meshes.size()>=3,"Expected tunic and two arm skin surfaces")
  for pitch in [0.0,30.0,60.0,90.0,135.0,171.0]:
   for outward in [-60.0,0.0,60.0,90.0]:
    for elbow in [0.0,60.0,120.0]:
     for side in 2:
      var sign_side:float=-1 if side==0 else 1
      player.visual._arms[side].basis=Basis(Vector3.FORWARD,deg_to_rad(-sign_side*outward))*Basis(Vector3.RIGHT,deg_to_rad(pitch))
      art._forearms[side].rotation=Vector3(deg_to_rad(elbow),0,0)
      art._wrists[side].rotation=Vector3.ZERO
     var anchors:=[]
     var anchor_nodes: Array[Node3D]=[]
     anchor_nodes.append_array(player.visual._arms);anchor_nodes.append_array(art._forearms);anchor_nodes.append_array(art._wrists);anchor_nodes.append_array(art._grips);anchor_nodes.append_array(art._legs);anchor_nodes.append_array(art._knees);anchor_nodes.append_array(art._ankles)
     for node in anchor_nodes: anchors.append(node.global_transform)
     art.update_surface_pose();poses+=1
     check(driver.last_report.active,"Cosmetic solve failed: "+str(driver.last_report))
     if not driver.last_report.active:continue
     check_correctives(driver,player.visual)
     if driver.contract_version==5:check(float(driver.last_report.max_leg_anchor_error)<.00001,"Cosmetic leg mapping differs from immutable old anchor")
     check(driver.last_report.max_wrist_error<.00001,"Cosmetic wrist visibly separates from rigid hand")
     check(driver.last_report.max_stretch<=TravelerSurfacePose.MAX_STRETCH,"Cosmetic stretch exceeded maximum")
     maximum_stretch=maxf(maximum_stretch,driver.last_report.max_stretch);maximum_error=maxf(maximum_error,driver.last_report.max_wrist_error)
     for side in 2:check(float(driver.last_report.sides[side].get("wrist_basis_error",INF))<.00001,"Cosmetic wrist basis differs from rigid hand")
     for i in anchor_nodes.size(): check(anchor_nodes[i].global_transform==anchors[i],"Surface driver mutated existing rigid anchor")
     for i in driver.skeleton.get_bone_count():
      var pose:=driver.skeleton.get_bone_global_pose(i);check(pose.origin.is_finite() and pose.basis.is_finite(),"Cosmetic bone nonfinite")
  # Exact reach-extremum witness for the triangle-inequality bound, valid only
  # for original rigid local lengths and unit scales (not arbitrary corrupt rigs).
  for side in 2:
   var rest_upper:Transform3D=driver.rests["SurfaceUpper_%d"%side]
   var rest_lower:Transform3D=driver.rests["SurfaceLower_%d"%side]
   var old_root:=driver.skeleton.to_local(player.visual._arms[side].global_position)
   var direction:Vector3=(old_root-rest_upper.origin).normalized()
   var local_direction:Vector3=player.visual.global_basis.inverse()*driver.skeleton.global_basis*direction
   player.visual._arms[side].basis=TravelerSurfacePose.segment_frame(local_direction,Vector3(-.8 if side==0 else .8,-.6,.3))
   art._forearms[side].rotation=Vector3.ZERO;art._wrists[side].rotation=Vector3.ZERO
   var old_length:float=art._forearms[side].position.length()+art._wrists[side].position.length()
   var new_length:float=(rest_lower.origin-rest_upper.origin).length()+(driver.wrist_rests[side]-rest_lower.origin).length()
   var bound:float=(old_length+old_root.distance_to(rest_upper.origin))/(new_length*.9995)
   maximum_bound=maxf(maximum_bound,bound)
   art.update_surface_pose()
   check(driver.last_report.active and absf(float(driver.last_report.sides[side].stretch)-bound)<.00001,"Exact reach witness differs from conservative bound")
   if driver.use_logical_elbow_pole:check(driver.last_report.sides[side].pole_source=="fixed_collinear_fallback","Collinear logical elbow did not use stable fixed fallback")
   check(bound<TravelerSurfacePose.MAX_STRETCH,"Valid rigid-hierarchy bound exceeds visual stretch ceiling")
   maximum_stretch=maxf(maximum_stretch,driver.last_report.max_stretch)
  for i in skin_meshes.size():check(mesh_digest(skin_meshes[i].mesh)==hashes[i],"Surface driver mutated shared source arrays")
  check(player.transform==original_player_transform and player._shape==original_shape and player.actions==original_actions and player.visual._blade==original_blade,"Surface posing changed gameplay state/resources")
 player.free()
 print("TRAVELER_SURFACE_POSE: %d failures; %d checks; %d bilateral poses; max stretch %.8f; max wrist error %.9fm; conservative reach bound %.8f; silhouette review still required" % [failures,checks,poses,maximum_stretch,maximum_error,maximum_bound])
 get_tree().quit(1 if failures else 0)
