extends Node3D
## Production upper-body pose, fixed segment lengths, head clearance and real shot.
var checks := 0
var failures := 0
var min_forearm_alignment := 1.0
var min_head_side := INF
var max_nock_error := 0.0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func freeze(n: Node) -> void:
 n.set_process(false); n.set_physics_process(false)
 for c in n.get_children(): freeze(c)
func _ready() -> void:
 InputSetup.ensure_defaults(); Sfx.enabled=false; Fx.enabled=false
 var h:=Horse.new();add_child(h);freeze(h)
 for frame in 90:h._pose(1.0/60.0)
 var p:=PlayerCharacter.new();add_child(p);freeze(p)
 var art:=p.visual.get_node("TravelerArt")as TravelerArt
 var gear:=p.visual.get_node("WeaponArt")as WeaponArt
 art.auto_lod=false;gear.auto_lod=false
 for riding in [false,true]:
  for slope in [Vector3.ZERO,Vector3(.15,.30,-.12)]:
   h.rotation=slope
   if riding:p.riding.mount_now(h)
   else:
    p.riding.phase=PlayerRiding.Phase.NONE;p.state=PlayerCharacter.State.GROUND
    p.position=Vector3(0,.895,0);p.visual.transform=Transform3D.IDENTITY
   for lod in 3:
    art.set_lod(lod);gear.set_lod(lod)
    for yaw in [-1.2,-.6,0.0,.6,1.2]:
     for pitch in [-.65,0.0,.65]:
      p.bow.aim_dir=Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)*Vector3.FORWARD
      p.actions.view_basis=Basis.looking_at(p.bow.aim_dir)
      for draw in [.0,.35,1.0]:
       p.weapon=PlayerCharacter.Weapon.BOW;p.bow.state=PlayerBow.State.AIM;p.bow.draw=draw
       art.pose_preview(&"ride"if riding else&"idle",.7)
       var player_root:=p.global_transform
       var left_hip:=art._legs[0].global_transform
       var right_hip:=art._legs[1].global_transform
       gear.update_equipment(0);art.update_surface_pose()
       var context:="riding=%s slope=%s LOD%d yaw%.2f pitch%.2f draw%.2f"%[riding,slope,lod,yaw,pitch,draw]
       var head_frame:=art._head.global_basis
       var expected_nock:=p.visual.global_position+head_frame*Vector3(.17,.55,.05)
       var nock_error:=expected_nock.distance_to(p.bow.bow_point(p))
       max_nock_error=maxf(max_nock_error,nock_error)
       check(nock_error<.00002,context+": physical nock is not at the actual right-cheek draw anchor")
       check(gear.arrow.global_position.distance_to(expected_nock)<.00002,context+": visible nock differs from head/physics anchor")
       var skin:=art._surface_pose.skeleton
       var report:=art.surface_pose_report()
       check(report.get("active",false),context+": cosmetic skin invalid")
       var elbow:Vector3=skin.to_global(report.sides[1].elbow)
       var wrist:=art._wrists[1].global_position
       var elbow_head:=head_frame.inverse()*(elbow-p.visual.global_position)
       var wrist_head:=head_frame.inverse()*(wrist-p.visual.global_position)
       min_head_side=minf(min_head_side,minf(elbow_head.x,wrist_head.x))
       check(elbow_head.x>.12 and wrist_head.x>.12,context+": right forearm crosses the neck/head center plane")
       var alignment:=(expected_nock-art._forearms[1].global_position).normalized().dot(p.bow.aim_dir)
       min_forearm_alignment=minf(min_forearm_alignment,alignment)
       check(alignment>.99,context+": elbow/forearm leaves the arrow draw line")
       check(absf(art._forearms[1].global_position.distance_to(p.visual._arms[1].global_position)-art._forearms[1].position.length())<.00001,context+": upper arm length changed")
       check(absf(wrist.distance_to(art._forearms[1].global_position)-art._wrists[1].position.length())<.00001,context+": forearm length changed")
       check(p.global_transform==player_root and art._legs[0].global_transform.is_equal_approx(left_hip) and art._legs[1].global_transform.is_equal_approx(right_hip),context+": archery moved gameplay root or seated pelvis")
       check(float(gear.hand_errors[0])<.00002 and float(gear.hand_errors[1])<.00002,context+": bow/string hand disconnected")
       check(gear.scabbard.transform.is_equal_approx(gear._scabbard_carry_frame(p.riding.cosmetic_seat_weight() if riding else 0.0)),context+": torso turn changed hip scabbard")
       var quiver_frame:=Transform3D(art.archery_torso_basis,Vector3.ZERO)*Transform3D(Basis(Vector3.FORWARD,.16),Vector3(.24,.29,.235))
       check(gear.quiver.transform.is_equal_approx(quiver_frame),context+": quiver stayed behind in the old shoulder frame")
       var quiver_elbow:=gear.quiver.to_local(elbow)
       var quiver_wrist:=gear.quiver.to_local(wrist)
       var near:=Geometry3D.get_closest_point_to_segment(Vector3.ZERO,Vector3(quiver_elbow.x,0,quiver_elbow.z),Vector3(quiver_wrist.x,0,quiver_wrist.z))
       check(near.length()>.14,context+": forearm intersects the quiver radial envelope")
    for state in [PlayerBow.State.IDLE,PlayerBow.State.RECOVERY]:
     p.bow.state=state;p.bow.state_time=.4;gear.update_equipment(0)
     check(art.archery_torso_basis.is_equal_approx(Basis.IDENTITY),"Archery torso not restored after letdown/recovery")
     check(art._head.basis.is_equal_approx(Basis.IDENTITY),"Archery head not restored")
     check(p.visual._arms[1].position.is_equal_approx(Vector3(.30,.40,0)),"Right shoulder not restored")
 # Real projectile and view-ray convergence against nearby walls at three pitches.
 h.rotation=Vector3.ZERO;p.riding.mount_now(h)
 var arrows:=ArrowSystem.of(p);arrows.set_physics_process(false)
 for pitch in [-.65,0.0,.65]:
  p.bow.state=PlayerBow.State.AIM;p.bow.draw=1;p.weapon=PlayerCharacter.Weapon.BOW
  p.actions.view_basis=Basis(Vector3.RIGHT,pitch)
  p.actions.aim_origin=p.global_position+Vector3.UP*.60
  var direction:=-p.actions.view_basis.z
  var wall:=StaticBody3D.new();wall.collision_layer=Layers.WORLD
  var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.3,1.3,.08);shape.shape=box;wall.add_child(shape);add_child(wall)
  wall.global_transform=Transform3D(p.actions.view_basis,p.actions.aim_origin+direction*.8)
  await get_tree().physics_frame;await get_tree().physics_frame
  p.bow._update_aim(p);art.pose_preview(&"ride",.7);gear.update_equipment(0)
  var nock:=gear.arrow.global_position
  check(p.bow.aim_point.distance_to(p.actions.aim_origin+direction*.76)<.001,"View ray misses near wall")
  check((p.bow.aim_point-nock).normalized().dot(p.bow.aim_dir)>.99999,"Near-wall arrow does not converge on crosshair ray")
  p.velocity=Vector3.ZERO;p.bow._shoot(p)
  var shot:Dictionary=p.bow.last_shot.arrow
  check((shot.start as Vector3).distance_to(nock)<.00001,"Near-wall real shot starts away from visible nock")
  for frame in 8:
   if shot.state==&"stuck":break
   arrows._physics_process(1.0/120.0)
  check(shot.state==&"stuck","Arrow passed through the near wall")
  check(absf(wall.to_local(shot.pos).z-.04)<.02,"Real arrow did not hit the visible front of the wall")
  arrows.clear();wall.free()
 p.free();h.free();arrows.free()
 print("ARCHERY_DRAW_ALIGNMENT: %d failures; %d checks; min_forearm_arrow_dot=%.7f min_head_side_m=%.7f max_nock_error_m=%.7f"%[failures,checks,min_forearm_alignment,min_head_side,max_nock_error])
 get_tree().quit(1 if failures else 0)
