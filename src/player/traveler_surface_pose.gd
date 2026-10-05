class_name TravelerSurfacePose
extends Node3D
## Cosmetic-only surface skeleton. Reads the established rigid wrist/shoulder
## state after equipment IK; never writes gameplay or original rigid anchors.
## Cosmetic bones are siblings below SurfaceBody so longitudinal stretch does
## not introduce unrepresentable local shear through a scaled parent bone.
const MAX_STRETCH := 1.20
const BLENDS := {"SurfaceBlend25_": .25, "SurfaceBlend50_": .50, "SurfaceBlend75_": .75}
const MANIFEST := "res://assets/travelers_v3_manifest.json"
# Synthetic tests can inject an explicit contract; production reads source manifest.
var contract_override := {}
var _helper_centers := {}
var _corrective_bones := {}
var center_correction_enabled := true
# Diagnostic prototype; kept OFF by default until geometric/art review accepts it.
var girdle_lift_m := 0.0
# Cosmetic bend follows the immutable logical elbow; fixed pole only resolves
# near-collinear ambiguity. Never writes the original rig.
var use_logical_elbow_pole := true
var art
var skeleton: Skeleton3D
var rests := {}
var bones := {}
var wrist_rests: Array[Vector3] = []
var rigid_wrist_rests: Array[Transform3D] = []
var wrist_target_offsets: Array[Basis] = []
var leg_target_offsets: Array[Transform3D] = []
var contract_version := 1
var use_minimal_arc := false
var last_report := {"active":false,"sides":[],"max_stretch":1.0,"max_wrist_error":0.0}
var _reported_invalid := false

func _ready() -> void:
 process_priority = 30 # TravelerArt=10, WeaponArt=20; use their FINAL joint state.

func configure(owner_art: Node, model: Node3D) -> bool:
 art = owner_art
 skeleton = null
 rests.clear()
 bones.clear()
 wrist_rests.clear()
 rigid_wrist_rests.clear()
 wrist_target_offsets.clear()
 leg_target_offsets.clear()
 _helper_centers.clear()
 _corrective_bones.clear()
 _reported_invalid = false
 last_report = {"active":false,"sides":[],"max_stretch":1.0,"max_wrist_error":0.0}
 for node in model.find_children("*", "Skeleton3D", true, false):
  var candidate := node as Skeleton3D
  if candidate.find_bone("SurfaceBody") >= 0:
   if skeleton != null:
    push_error("Traveler contains multiple cosmetic SurfaceBody skeletons")
    return false
   skeleton = candidate
 if skeleton == null:
  # Old rigid assets remain loadable; a skinned surface without its rig is not.
  if model.find_child("Traveler_TunicSurface*",true,false):
   push_error("Traveler surface geometry has no cosmetic skeleton")
  return false
 var contract: Dictionary = contract_override.duplicate(true)
 if contract.is_empty():
  var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
  if manifest is Dictionary and manifest.get("surface_rig_contract") is Dictionary:
   contract = manifest.surface_rig_contract
 contract_version = int(contract.get("version",0))
 if contract_version not in [1,2,3,4,5] or not contract.get("rest_positions") is Dictionary or not contract.get("helper_centers") is Dictionary:
  push_error("Missing or malformed version1/2/3/4/5 cosmetic source contract")
  skeleton = null
  return false
 if contract_version >= 2 and (not contract.get("rigid_wrist_rest") is Dictionary or not contract.get("wrist_bind_axes") is Dictionary):
  push_error("T-bind contract requires separate logical wrist rests and bind axes")
  skeleton = null
  return false
 if contract_version>=4 and not contract.helper_centers.is_empty():
  push_error("Schema4/5 has no intermediate helper bones or centers")
  skeleton=null;return false
 use_minimal_arc = contract_version >= 2
 center_correction_enabled = bool(contract.get("centre_correction_enabled",contract_version==1))
 var names := ["SurfaceBody"]
 for side in 2:
  names.append("SurfaceUpper_%d" % side)
  names.append("SurfaceLower_%d" % side)
  names.append("SurfaceWrist_%d" % side)
  for prefix in (BLENDS if contract_version < 4 else {}): names.append(prefix+str(side))
 if contract_version==5:
  for side in 2:names.append("SurfaceLeg_%d"%side)
 if contract_version in [3,4,5]:
  var corrective_count := 8 if contract_version==3 else 10
  if not contract.get("corrective_bones") is Dictionary or contract.corrective_bones.size()!=corrective_count or center_correction_enabled:
   push_error("Corrective contract requires exact named bone coverage and disabled centre correction")
   skeleton=null;return false
  for side in 2:
   var specifications := {}
   if contract_version==3:
    for suffix in ["Body","25","50","75"]:
     specifications["SurfaceAxilla%s_%d"%[suffix,side]]="SurfaceBody" if suffix=="Body" else "SurfaceBlend%s_%d"%[suffix,side]
   else:
    specifications["SurfaceAxillaBody_%d"%side]="SurfaceBody"
    for region in ["Front","Back"]:
     for segment in ["Body","Upper"]:
      specifications["SurfaceFold%s%s_%d"%[region,segment,side]]="SurfaceBody" if segment=="Body" else "SurfaceUpper_%d"%side
   for name in specifications:
    var base:String=specifications[name]
    var entry = contract.corrective_bones.get(name)
    if not entry is Dictionary or entry.get("base")!=base or entry.get("side")!=side:
     push_error("Invalid corrective name/base/side contract: "+name)
     skeleton=null;return false
    var down := contract_vector(entry.get("down"))
    var up := contract_vector(entry.get("up"))
    if not down.is_finite() or not up.is_finite() or down.length()>.08 or up.length()>.08:
     push_error("Invalid or excessive cosmetic corrective translation: "+name)
     skeleton=null;return false
    if contract_version>=4 and String(name).begins_with("SurfaceFold") and (down.length()>.0000001 or absf(up.x)>.0000001 or absf(up.y)>.0000001):
     push_error("Schema4 folds require zero down offsets and model-Z-only up offsets: "+name)
     skeleton=null;return false
    _corrective_bones[name]={"base":base,"side":side,"down":down,"up":up}
    names.append(name)
 if skeleton.get_bone_count()!=names.size():
  push_error("Unexpected cosmetic bone count for declared contract")
  skeleton=null;return false
 for name in names:
  var index := skeleton.find_bone(name)
  if index < 0:
   push_error("Traveler cosmetic skeleton missing "+name)
   skeleton = null
   return false
  bones[name] = index
  rests[name] = skeleton.get_bone_global_rest(index)
 var body: int = bones["SurfaceBody"]
 for name in names:
  if name != "SurfaceBody" and skeleton.get_bone_parent(bones[name]) != body:
   push_error("Cosmetic bones must be SurfaceBody siblings to avoid stretch shear: "+name)
   skeleton = null
   return false
 if contract_vector(contract.rest_positions.get("SurfaceBody")).distance_to(Vector3.ZERO) > .00001:
  push_error("Cosmetic SurfaceBody must retain identity origin")
  skeleton = null
  return false
 for name in _corrective_bones:
  var base: String = _corrective_bones[name].base
  var actual: Transform3D = rests[name]
  var expected: Transform3D = rests[base]
  if actual.origin.distance_to(expected.origin)>.00001 or actual.basis.x.distance_to(expected.basis.x)>.0001 or actual.basis.y.distance_to(expected.basis.y)>.0001 or actual.basis.z.distance_to(expected.basis.z)>.0001:
   push_error("Corrective rest must exactly copy base rest: "+name)
   skeleton=null;return false
 var model_to_skeleton: Transform3D = skeleton.global_transform.affine_inverse() * art.visual.global_transform
 for name in names:
  var authored := contract_vector(contract.rest_positions.get(name))
  var actual: Transform3D = rests[name]
  if not authored.is_finite() or actual.origin.distance_to(model_to_skeleton*authored) > .001:
   push_error("Cosmetic imported rest differs from authored contract: "+name)
   skeleton = null
   return false
 if contract_version==5:
  if not contract.get("rigid_leg_rest") is Dictionary or contract.rigid_leg_rest.size()!=2:
   push_error("Schema5 requires two immutable logical hip rests")
   skeleton=null;return false
  for side in 2:
   var name:="SurfaceLeg_%d"%side
   var expected:=Vector3(-.118 if side==0 else .118,-.188,0)
   var rigid:=contract_vector(contract.rigid_leg_rest.get(name))
   var authored:=contract_vector(contract.rest_positions.get(name))
   if not rigid.is_finite() or rigid.distance_to(expected)>.00001 or authored.distance_to(expected)>.00001:
    push_error("Schema5 changes immutable logical hip rest: "+name)
    skeleton=null;return false
   var logical_rest:=model_to_skeleton*Transform3D(Basis.IDENTITY,rigid)
   leg_target_offsets.append(logical_rest.affine_inverse()*rests[name])
 for side in 2:
  var sign_side := -1.0 if side == 0 else 1.0
  var shoulder := contract_vector(contract.rest_positions["SurfaceUpper_%d"%side])
  var elbow := contract_vector(contract.rest_positions["SurfaceLower_%d"%side])
  var wrist := contract_vector(contract.rest_positions["SurfaceWrist_%d"%side])
  var wrist_name := "SurfaceWrist_%d"%side
  var rigid_wrist := contract_vector(contract.rigid_wrist_rest.get(wrist_name)) if contract_version>=2 else wrist
  var bind_axis := contract_vector(contract.wrist_bind_axes.get(wrist_name)) if contract_version>=2 else Vector3.DOWN
  var valid_rest := shoulder.is_finite() and elbow.is_finite() and wrist.is_finite() and rigid_wrist.is_finite() and bind_axis.is_finite()
  valid_rest = valid_rest and sign_side*shoulder.x >= .16 and sign_side*shoulder.x <= .28 and shoulder.y >= .35 and shoulder.y <= .46 and absf(shoulder.z) <= .03
  valid_rest = valid_rest and rigid_wrist.distance_to(Vector3(sign_side*.300,-.161,0)) <= .00001
  if contract_version==1:
   valid_rest = valid_rest and sign_side*elbow.x >= .20 and sign_side*elbow.x <= .32 and elbow.y >= .05 and elbow.y <= .18 and absf(elbow.z) <= .06
  else:
   valid_rest = valid_rest and absf(bind_axis.length()-1.0)<.00001 and bind_axis.distance_to(Vector3(sign_side,0,0))<.00001
   valid_rest = valid_rest and (elbow-shoulder).length() >= .24 and (elbow-shoulder).length() <= .35 and (wrist-elbow).length() >= .24 and (wrist-elbow).length() <= .32
   valid_rest = valid_rest and (elbow-shoulder).normalized().dot(bind_axis)>.9999 and (wrist-elbow).normalized().dot(bind_axis)>.9999
  if not valid_rest:
   push_error("Cosmetic rest exceeds accepted surface bounds or changes immutable logical wrist")
   skeleton = null
   return false
  wrist_rests.append(model_to_skeleton*wrist)
  rigid_wrist_rests.append(model_to_skeleton*Transform3D(Basis.IDENTITY,rigid_wrist))
  var rest_wrist: Transform3D = rests[wrist_name]
  var axis_alignment := minimal_arc(bind_axis,Vector3.DOWN,Vector3.BACK)
  wrist_target_offsets.append(axis_alignment*model_to_skeleton.basis.inverse()*rest_wrist.basis)
  for prefix in (BLENDS if contract_version < 4 else {}):
   var name: String = prefix+str(side)
   var center := contract_vector(contract.helper_centers.get(name))
   if not center.is_finite() or sign_side*center.x < .10 or sign_side*center.x > (.45 if contract_version>=2 else .30) or center.y < .24 or center.y > .46 or absf(center.z) > .06 or contract_vector(contract.rest_positions[name]).distance_to(shoulder) > .00001:
    push_error("Invalid authored cosmetic helper center/rest: "+name)
    skeleton = null
    return false
   _helper_centers[name] = center
 update_surface_pose()
 return true

static func contract_vector(value: Variant) -> Vector3:
 if not value is Array or value.size()!=3: return Vector3.INF
 for item in value:
  if not (item is int or item is float) or not is_finite(float(item)): return Vector3.INF
 return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _process(_delta: float) -> void:
 update_surface_pose()

static func axis_stretch(direction: Vector3, amount: float) -> Basis:
 var u := direction.normalized()
 var k := amount-1.0
 return Basis(Vector3.RIGHT+u*(k*u.x),Vector3.UP+u*(k*u.y),Vector3.BACK+u*(k*u.z))

static func segment_frame(direction: Vector3, pole: Vector3) -> Basis:
 var d := direction.normalized()
 var x := d.cross(pole)
 if x.length_squared() < .00000001:
  x = d.cross(Vector3.FORWARD if absf(d.dot(Vector3.FORWARD)) < .9 else Vector3.RIGHT)
 x = x.normalized()
 var y := -d
 return Basis(x,y,x.cross(y).normalized())

static func minimal_arc(source: Vector3, target: Vector3, fallback_axis: Vector3) -> Basis:
 var a := source.normalized()
 var b := target.normalized()
 if a.dot(b) > -.9999: return Basis(Quaternion(a,b).normalized())
 # Opposed vectors have no unique minimal arc. A stable authored perpendicular
 # intermediate maps the endpoint exactly, avoiding a NaN or an approximate PI.
 var intermediate := fallback_axis-a*fallback_axis.dot(a)
 if intermediate.length_squared()<.00000001:
  intermediate = Vector3.UP-a*Vector3.UP.dot(a)
  if intermediate.length_squared()<.00000001: intermediate=Vector3.RIGHT-a*Vector3.RIGHT.dot(a)
 intermediate=intermediate.normalized()
 return Basis((Quaternion(intermediate,b)*Quaternion(a,intermediate)).normalized())

static func solve_exact(root: Vector3, target: Vector3, upper_length: float, lower_length: float, pole: Vector3) -> Dictionary:
 var delta := target-root
 var distance := delta.length()
 if distance < .00001 or upper_length <= 0 or lower_length <= 0:
  return {"valid":false,"reason":"Degenerate cosmetic limb"}
 # Small flex margin stabilizes the pole; unlike gameplay IK we compensate
 # its extension limit rather than leaving a visible gap at the rigid wrist.
 var stretch := maxf(1.0,distance/((upper_length+lower_length)*.9995))
 var upper := upper_length*stretch
 var lower := lower_length*stretch
 if distance <= absf(upper-lower)+.00001:
  lower = upper-distance*.5
 var upper_scale := upper/upper_length
 var lower_scale := lower/lower_length
 if maxf(upper_scale,lower_scale) > MAX_STRETCH:
  return {"valid":false,"reason":"Cosmetic stretch exceeds declared 20% maximum", "stretch":maxf(upper_scale,lower_scale)}
 var direction := delta/distance
 var bend := pole-direction*pole.dot(direction)
 if bend.length_squared() < .00000001:
  bend = Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
  if bend.length_squared() < .00000001: bend = Vector3.RIGHT-direction*Vector3.RIGHT.dot(direction)
 bend = bend.normalized()
 var cosine := clampf((upper*upper+distance*distance-lower*lower)/(2.0*upper*distance),-1.0,1.0)
 var middle := root+direction*(upper*cosine)+bend*(upper*sqrt(maxf(0,1.0-cosine*cosine)))
 return {"valid":true,"root":root,"mid":middle,"end":target,"upper_scale":upper_scale,"lower_scale":lower_scale,"stretch":maxf(upper_scale,lower_scale)}

func update_surface_pose() -> void:
 if not is_instance_valid(skeleton) or art == null or art._wrists.size() != 2:
  return
 var body_rest: Transform3D = rests["SurfaceBody"]
 var torso_frame: Basis = skeleton.global_basis.inverse() * art.visual.global_basis * art.archery_torso_basis * art.visual.global_basis.inverse() * skeleton.global_basis
 var body_pose := Transform3D(torso_frame, Vector3.ZERO) * body_rest
 var desired := {"SurfaceBody":body_pose}
 var report := {"active":true,"sides":[],"max_stretch":1.0,"max_wrist_error":0.0,"cosmetic_bones":bones.size(),"corrective_bones":_corrective_bones.size(),"logical_elbow_pole":use_logical_elbow_pole,"blend_center_correction":center_correction_enabled,"girdle_lift_m":girdle_lift_m,"contract_version":contract_version,"rotation_mode":"minimal_arc" if use_minimal_arc else "pole_frame"}
 for side in 2:
  var upper_name := "SurfaceUpper_%d" % side
  var lower_name := "SurfaceLower_%d" % side
  var upper_rest: Transform3D = rests[upper_name]
  var lower_rest: Transform3D = rests[lower_name]
  var rest_end := wrist_rests[side]
  var target: Vector3 = skeleton.to_local(art._wrists[side].global_position)
  var pole: Vector3 = skeleton.global_basis.inverse() * art.visual.global_basis * Vector3(-.8 if side == 0 else .8,-.6,.3)
  var body_up: Vector3 = (skeleton.global_basis.inverse()*art.visual.global_basis*Vector3.UP).normalized()
  var lift_activation := 0.0
  if girdle_lift_m > 0.0:
   var old_arm_direction: Vector3 = (skeleton.global_basis.inverse()*art.visual._arms[side].global_basis*Vector3.DOWN).normalized()
   lift_activation = smoothstep(0.0,.85,old_arm_direction.dot(body_up))
  var lift := body_up*(clampf(girdle_lift_m,0.0,.04)*lift_activation)
  var cosmetic_root := torso_frame * upper_rest.origin + lift
  var upper_direction := lower_rest.origin-upper_rest.origin
  var lower_direction := rest_end-lower_rest.origin
  var pole_source := "fixed_model"
  var logical_elbow:Vector3=Vector3.INF
  if use_logical_elbow_pole and art._forearms.size()==2:logical_elbow=skeleton.to_local(art._forearms[side].global_position)
  if use_logical_elbow_pole and logical_elbow.is_finite():
   var reach_direction:Vector3=(target-cosmetic_root).normalized()
   var guided_pole:=logical_elbow-cosmetic_root
   var projected:=guided_pole-reach_direction*guided_pole.dot(reach_direction)
   if projected.length_squared()>.000001:
    pole=guided_pole;pole_source="logical_elbow"
   else:pole_source="fixed_collinear_fallback"
  var solved := solve_exact(cosmetic_root,target,upper_direction.length(),lower_direction.length(),pole)
  if not solved.valid:
   last_report = {"active":false,"error":solved,"side":side}
   if not _reported_invalid: push_error("Traveler cosmetic pose failed: "+str(solved))
   _reported_invalid = true
   return
  var middle: Vector3 = solved.mid
  var upper_rotation := segment_frame(middle-cosmetic_root,pole) * segment_frame(upper_direction,pole).inverse()
  var lower_rotation := segment_frame(target-middle,pole) * segment_frame(lower_direction,pole).inverse()
  if use_minimal_arc:
   var bind_front: Vector3 = skeleton.global_basis.inverse()*art.visual.global_basis*Vector3.BACK
   upper_rotation=minimal_arc(upper_direction,middle-cosmetic_root,bind_front)
   lower_rotation=minimal_arc(lower_direction,target-middle,bind_front)
  var upper_basis := upper_rotation * axis_stretch(upper_direction,solved.upper_scale) * upper_rest.basis
  var lower_basis := lower_rotation * axis_stretch(lower_direction,solved.lower_scale) * lower_rest.basis
  desired[upper_name] = Transform3D(upper_basis,cosmetic_root)
  desired[lower_name] = Transform3D(lower_basis,middle)
  var wrist_name := "SurfaceWrist_%d" % side
  var actual_wrist: Transform3D = skeleton.global_transform.affine_inverse() * art._wrists[side].global_transform
  desired[wrist_name] = Transform3D(actual_wrist.basis*wrist_target_offsets[side],actual_wrist.origin)
  var rotation := upper_rotation.get_rotation_quaternion().normalized()
  for prefix in (BLENDS if contract_version < 4 else {}):
   var alpha: float = BLENDS[prefix]
   var blend_rest: Transform3D = rests[prefix+str(side)]
   var partial_rotation := Basis(Quaternion.IDENTITY.slerp(rotation,alpha))
   var partial_scale := axis_stretch(upper_direction,lerpf(1.0,solved.upper_scale,alpha))
   var partial_pose := Transform3D(partial_rotation*partial_scale*blend_rest.basis,upper_rest.origin+lift*alpha)
   if center_correction_enabled:
    # Keep each transition section on a blended centreline rather than the
    # forward circular arc produced by quaternion interpolation alone.
    # This does not certify fold quality; source/runtime clay review is required.
    var model_to_skeleton: Transform3D = skeleton.global_transform.affine_inverse() * art.visual.global_transform
    var center: Vector3 = model_to_skeleton * (_helper_centers[prefix+str(side)] as Vector3)
    var full_delta: Transform3D = desired[upper_name] * upper_rest.affine_inverse()
    var partial_delta := partial_pose * blend_rest.affine_inverse()
    partial_pose.origin += center.lerp(full_delta*center,alpha)-partial_delta*center
   desired[prefix+str(side)] = partial_pose
  var up_component := (middle-cosmetic_root).normalized().dot(body_up)
  var down_factor := pow(maxf(0.0,-up_component),2.0)
  var up_factor := pow(maxf(0.0,up_component),2.0)
  var corrective_offsets := {}
  var model_basis_to_skeleton: Basis = skeleton.global_basis.inverse()*art.visual.global_basis
  for name in _corrective_bones:
   var entry: Dictionary = _corrective_bones[name]
   if entry.side!=side:continue
   var offset: Vector3 = entry.down*down_factor+entry.up*up_factor
   var corrected: Transform3D = desired[entry.base]
   corrected.origin += model_basis_to_skeleton*offset
   desired[name]=corrected
   corrective_offsets[name]=offset
  report.max_stretch = maxf(report.max_stretch,solved.stretch)
  report.sides.append({"side":side,"stretch":solved.stretch,"upper_scale":solved.upper_scale,"lower_scale":solved.lower_scale,"target":target,"elbow":middle,"cosmetic_shoulder":cosmetic_root,"lift_activation":lift_activation,"lift":lift,"pole_source":pole_source,"logical_elbow":logical_elbow if logical_elbow.is_finite() else null,"logical_elbow_error":middle.distance_to(logical_elbow) if logical_elbow.is_finite() else -1.0,"corrective_down_factor":down_factor,"corrective_up_factor":up_factor,"corrective_offsets_model":corrective_offsets})
 report["max_leg_anchor_error"]=0.0
 if contract_version==5:
  if art._legs.size()!=2:
   last_report={"active":false,"error":"Schema5 missing immutable logical leg anchors"};return
  for side in 2:
   var name:="SurfaceLeg_%d"%side
   var actual_leg:Transform3D=skeleton.global_transform.affine_inverse()*art._legs[side].global_transform
   desired[name]=actual_leg*leg_target_offsets[side]
   var reconstructed:Transform3D=desired[name]*leg_target_offsets[side].affine_inverse()
   report.max_leg_anchor_error=maxf(report.max_leg_anchor_error,reconstructed.origin.distance_to(actual_leg.origin))
   report.max_leg_anchor_error=maxf(report.max_leg_anchor_error,maxf(reconstructed.basis.x.distance_to(actual_leg.basis.x),maxf(reconstructed.basis.y.distance_to(actual_leg.basis.y),reconstructed.basis.z.distance_to(actual_leg.basis.z))))
 # All surface bones are direct Body children. Their local transforms remain
 # orthogonal even with longitudinal stretch; no deprecated pose overrides.
 var body_index: int = bones["SurfaceBody"]
 var body_parent := skeleton.get_bone_parent(body_index)
 skeleton.set_bone_pose(body_index,body_pose if body_parent < 0 else skeleton.get_bone_global_pose(body_parent).affine_inverse()*body_pose)
 for name in desired:
  if name == "SurfaceBody": continue
  skeleton.set_bone_pose(bones[name],body_pose.affine_inverse()*desired[name])
 skeleton.force_update_all_bone_transforms()
 for side in 2:
  var lower_name := "SurfaceLower_%d" % side
  var lower_rest: Transform3D = rests[lower_name]
  var local_end := lower_rest.affine_inverse()*wrist_rests[side]
  var posed_end := skeleton.get_bone_global_pose(bones[lower_name])*local_end
  var target: Vector3 = skeleton.to_local(art._wrists[side].global_position)
  var error := posed_end.distance_to(target)
  report.max_wrist_error = maxf(report.max_wrist_error,error)
  report.sides[side]["wrist_error"] = error
  var wrist_name := "SurfaceWrist_%d" % side
  var posed_wrist := skeleton.get_bone_global_pose(bones[wrist_name])
  var posed_anchor := Transform3D(posed_wrist.basis*wrist_target_offsets[side].inverse(),posed_wrist.origin)
  var expected_anchor: Transform3D = skeleton.global_transform.affine_inverse() * art._wrists[side].global_transform
  report.sides[side]["wrist_basis_error"] = maxf(posed_anchor.basis.x.distance_to(expected_anchor.basis.x),maxf(posed_anchor.basis.y.distance_to(expected_anchor.basis.y),posed_anchor.basis.z.distance_to(expected_anchor.basis.z)))
 last_report = report
