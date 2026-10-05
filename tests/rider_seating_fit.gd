extends Node3D
## Cosmetic seating/contact regression. Does not certify silhouette or live FPS.
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value: failures += 1; push_error(message)
func _ready() -> void:
 InputSetup.ensure_defaults(); Sfx.enabled=false; Fx.enabled=false
 var horse:=Horse.new();add_child(horse);horse.set_physics_process(false)
 for tick in 360: horse._pose(1.0/120.0)
 var p:=PlayerCharacter.new();add_child(p);p.set_physics_process(false)
 var art:=p.visual.get_node("TravelerArt") as TravelerArt
 art.set_process(false);art.auto_lod=false
 var gear:=p.visual.get_node("WeaponArt") as WeaponArt
 gear.set_process(false);gear.auto_lod=false
 p.riding.mount_now(horse)
 var root_before:=p.global_transform
 var shape_before:=p._shape
 var max_error:=0.0
 for level in 3:
  art.set_lod(level);gear.set_lod(level)
  await get_tree().process_frame
  art._surface_pose.set_process(false)
  for tilt in [Vector3.ZERO,Vector3(.20,0,0),Vector3(0,0,.12),Vector3(-.20,0,-.12)]:
   horse.skeleton.set_bone_pose_rotation(horse._bone[&"body"],Quaternion.from_euler(tilt))
   p.riding.update(1.0/60.0)
   var physical:=p.global_transform
   p.visual.update_visual(p,1.0)
   art._apply_pose(&"ride",.7,.8,1.0)
   gear.update_equipment(0)
   art.update_surface_pose()
   var reins:=horse.get_node("AgroReins") as AgroReins
   reins.update_reins(1.0)
   var rein_arrays:=reins.straps.mesh.surface_get_arrays(0)
   check(rein_arrays[Mesh.ARRAY_INDEX].size()/3==AgroReins.TRIANGLE_COUNT,"Rein budget changed")
   for point in rein_arrays[Mesh.ARRAY_VERTEX]:check(point.is_finite(),"Nonfinite rein geometry")
   var body:=horse.body_transform()
   for i in 2:
    var side:float=-1 if i==0 else 1
    var goal:=body*Vector3(side*.435,.100,-.030)
    var error:=art._ankles[i].global_position.distance_to(goal)
    max_error=maxf(max_error,error)
    check(error<.00001,"Seated ankle does not reach stirrup goal")
    check(art._legs[i].global_transform.is_finite() and art._knees[i].global_transform.is_finite(),"Nonfinite seated leg")
    var heel_local:=body.affine_inverse()*art._ankles[i].global_position
    check(absf(heel_local.z+.05)<.03,"Heel not aligned below pelvis")
   check(p.global_transform==physical and p._shape==shape_before,"Cosmetic fit moved gameplay root or collider")
   check(art.surface_pose_report().active,"Continuous traveler surface failed in seated pose")
   check(p.visual.global_basis.is_equal_approx(body.basis),"Seated torso does not follow saddle tilt")
  horse.skeleton.set_bone_pose_rotation(horse._bone[&"body"],Quaternion.IDENTITY)
  p.riding.update(1.0/60.0)
  for phase in [PlayerRiding.Phase.MOUNTING,PlayerRiding.Phase.DISMOUNTING]:
   p.riding.phase=phase
   var last_weight:float=-1 if phase==PlayerRiding.Phase.MOUNTING else 2
   for k in 101:
    p.riding._t=k/100.0
    var weight:=p.riding.cosmetic_seat_weight()
    check(weight>=0 and weight<=1,"Unbounded transition fit weight")
    check(weight>=last_weight if phase==PlayerRiding.Phase.MOUNTING else weight<=last_weight,"Nonmonotone transition fit")
    last_weight=weight
  p.riding.phase=PlayerRiding.Phase.RIDING
 check(p.global_transform.is_equal_approx(root_before),"Synthetic tilt round trip moved mechanical saddle root")
 # The far leg must pass OVER the saddle at three-quarter mount, from either side.
 for approach in [-1.0,1.0]:
  p.riding._finish(Vector3.ZERO)
  p.position=Vector3(approach*1.15,.895,0)
  check(p.riding.try_mount(),"Side mount refused in close fixture")
  p.state=PlayerCharacter.State.RIDE
  for frame in 54:
   p.riding.update(1.0/120.0);p.visual.update_visual(p,1.0/120.0)
   art._apply_pose(&"ride",.7,0,1.0/120.0)
  var far:int=1 if approach<0 else 0
  var local_knee:=horse.body_transform().affine_inverse()*art._knees[far].global_position
  var local_ankle:=horse.body_transform().affine_inverse()*art._ankles[far].global_position
  check(local_knee.y>.43 and local_ankle.y>.43,"Far mounting leg crosses through saddle instead of above it")
  p.riding._t=.50;p.visual.update_visual(p,1.0)
  art._apply_pose(&"ride",.7,0,1.0/30.0)
  var sampled:Transform3D=art._ankles[far].global_transform
  for frame in 17:art._apply_pose(&"ride",.7,0,1.0/120.0)
  check(sampled.is_equal_approx(art._ankles[far].global_transform),"Mount leg pose depends on preceding render frame count")
 p.riding.phase=PlayerRiding.Phase.NONE;p.state=PlayerCharacter.State.GROUND
 horse.current_rider=null
 var reins:=horse.get_node("AgroReins") as AgroReins
 reins.update_reins(1.0)
 for i in 2:
  var rest:=horse.to_local(horse.body_transform()*Vector3(-.21 if i==0 else .21,.47,-.27))
  check(reins._ends[i].distance_to(rest)<.00001,"Unmounted rein remains suspended at absent rider hand")
 p.visual.update_visual(p,1.0);art._apply_pose(&"idle",0,0,1.0)
 check(p.visual.position.length()<.00001,"Mounted visual offset persists after dismount")
 for ankle in art._ankles:check(ankle.rotation.is_zero_approx(),"Seated ankle rotation leaks into walking pose")
 print("RIDER_SEATING_FIT: %d failures; %d checks; max ankle error %.9f m"%[failures,checks,max_error])
 get_tree().quit(1 if failures else 0)
