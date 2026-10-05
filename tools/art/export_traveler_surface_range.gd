extends "res://tools/art/export_character_preview.gd"
## Prototype diagnostic: frozen production rigid anchors + their actual skinned
## cosmetic response. Nothing here certifies silhouette quality automatically.
var diagnostic_girdle_lift := 0.0
var diagnostic_lod := 0
var diagnostic_center_correction := false
var diagnostic_other_pitch := 0.0
var diagnostic_other_elbow := -1.0
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size() not in [1,2,4]:
  push_error("Expected output directory for shoulder-range snapshots")
  quit(2);return
 output=args[0];variant=args[2] if args.size()==4 else "after";baseline_commit=args[3] if args.size()==4 else "prototype-uncommitted"
 DirAccess.make_dir_recursive_absolute(output)
 InputSetup.ensure_defaults();Sfx.enabled=false;Fx.enabled=false
 world=Node3D.new();root.add_child(world)
 if args.size()>=2 and args[1]=="logical_pole":
  diagnostic_logical_elbow_pole=true
  for spec in [["both_000",0,0],["both_171",171,0],["bend_110",90,110],["bend_120",90,120]]:
   if not capture_range(spec[0]+"_core",float(spec[1]),false,0,float(spec[2]),true):quit(1);return
  for subject in ["traveler_idle","traveler_climb","rider"]:
   if not capture(subject,0):quit(1);return
  print("TRAVELER_LOGICAL_POLE_PROBE_OK neutral/171/110/120 and production sword/climb/rider")
  world.free();quit(0);return
 if args.size()>=2 and args[1]=="key_lods":
  for lod in range(3):
   diagnostic_lod=lod
   for angle in [0.0,90.0,171.0]:
    if not capture_range("lod%d_both_%03d_core"%[lod,int(angle)],angle,false,0,0,true):quit(1);return
  print("TRAVELER_SURFACE_KEY_LODS_EXPORT_OK 3 LODs x 0/90/171 core")
  world.free();quit(0);return
 if args.size()>=2 and args[1] in ["key","lift_key","center_key"]:
  diagnostic_center_correction=args[1]=="center_key"
  diagnostic_girdle_lift=.03 if args[1]=="lift_key" else 0.0
  if not capture_range("both_000",0,false,0,0) or not capture_range("both_171",171,false,0,0):quit(1);return
  for angle in [0.0,90.0,171.0]:
   if not capture_range("both_%03d_core"%int(angle),angle,false,0,0,true):quit(1);return
  print("TRAVELER_SURFACE_KEY_EXPORT_OK neutral/171 full +neutral/90/171 core-only")
  world.free();quit(0);return
 if args.size()>=2 and args[1]=="production_lods":
  for lod in range(3):
   for subject in ["traveler_idle","traveler_walk","traveler_climb","rider"]:
    if not capture(subject,lod):quit(1);return
  print("TRAVELER_PRODUCTION_LODS_EXPORT_OK 3 LODs x idle/walk/climb/rider")
  world.free();quit(0);return
 if args.size()>=2 and args[1]=="production":
  if not capture_range("bent_elbows",90.0,false,0.0,90.0) or not capture_range("outward_090",0.0,false,90.0,0.0):quit(1);return
  for subject in ["traveler_idle","traveler_climb","traveler_walk","rider"]:
   if not capture(subject,0):quit(1);return
  print("TRAVELER_SURFACE_PRODUCTION_EXPORT_OK 4 production +bent/outward")
  world.free();quit(0);return
 if args.size()>=2 and args[1]=="extended_motion":
  for step in range(13):
   if not capture_range("bend_%03d"%step,90.0,false,0,float(step)*10):quit(1);return
  diagnostic_other_pitch=90.0;diagnostic_other_elbow=90.0
  for step in range(20):
   if not capture_range("asym_%03d"%step,float(step)*9,true,0,0):quit(1);return
  print("TRAVELER_SURFACE_EXTENDED_EXPORT_OK 13 elbow-flexion +20 asymmetric shoulder/elbow frames")
  world.free();quit(0);return
 if args.size()>=2 and args[1]=="motion":
  for unilateral in [false,true]:
   for step in range(20):
    var label: String = ("one" if unilateral else "both")+"_%03d"%step
    if not capture_range(label,float(step)*9.0,unilateral,0,0):quit(1);return
  print("TRAVELER_SURFACE_MOTION_EXPORT_OK 40 frames, bilateral/unilateral 0..171deg by9deg")
  world.free();quit(0);return
 for angle in [0.0,30.0,60.0,90.0,135.0,171.0]:
  if not capture_range("both_%03d"%int(angle),angle,false,0.0,0.0):quit(1);return
 for angle in [90.0,171.0]:
  if not capture_range("one_%03d"%int(angle),angle,true,0.0,0.0):quit(1);return
 if not capture_range("outward_060",0.0,false,60.0,0.0):quit(1);return
 if not capture_range("bent_elbows",90.0,false,0.0,90.0):quit(1);return
 for subject in ["traveler_idle","traveler_climb","traveler_walk","rider"]:
  if not capture(subject,0):quit(1);return
 print("TRAVELER_SURFACE_RANGE_EXPORT_OK 10 diagnostic poses +4 production poses")
 world.free();quit(0)

func capture_range(label: String, pitch: float, unilateral: bool, outward: float, elbow: float, hide_outfit: bool=false) -> bool:
 source_hashes={}
 capture_materials.clear()
 for path in ["tools/art/export_character_preview.gd","src/player/traveler_art.gd","src/player/traveler_surface_pose.gd","src/player/player_visual.gd","src/player/weapon_art.gd","tools/art/skin_snapshot_baker.gd","tools/art/export_traveler_surface_range.gd"]:track("res://"+path)
 var player:=PlayerCharacter.new();world.add_child(player);freeze(player)
 player.position=Vector3(0,.895,0);player.visual.transform=Transform3D.IDENTITY
 var art:=player.visual.get_node("TravelerArt") as TravelerArt
 art.auto_lod=false;art.set_lod(diagnostic_lod)
 if diagnostic_logical_elbow_pole and art.has_method("set_surface_logical_elbow_pole"):art.call("set_surface_logical_elbow_pole",true)
 if diagnostic_center_correction:
  var surface_driver=art.get("_surface_pose")
  if surface_driver:surface_driver.set("center_correction_enabled",true)
 if art.has_method("set_surface_girdle_lift"):art.call("set_surface_girdle_lift",diagnostic_girdle_lift)
 if hide_outfit:
  var outfit:=art.model.find_child("Traveler_Torso*",true,false) as Node3D
  if outfit:outfit.visible=false
 var gear:=player.visual.get_node("WeaponArt") as WeaponArt
 gear.visible=false;gear.set_process(false)
 art.pose_preview(&"idle",0)
 for side in 2:
  var sign_side:float=-1 if side==0 else 1
  var raise_angle:float=diagnostic_other_pitch if unilateral and side==1 else pitch
  player.visual._arms[side].basis=Basis(Vector3.FORWARD,deg_to_rad(-sign_side*outward))*Basis(Vector3.RIGHT,deg_to_rad(raise_angle))
  art._forearms[side].rotation=Vector3(deg_to_rad(diagnostic_other_elbow if side==1 and diagnostic_other_elbow>=0 else elbow),0,0)
  art._wrists[side].rotation=Vector3.ZERO
 var pose_report:Dictionary={"active":false,"legacy_rigid":true}
 if art.has_method("update_surface_pose"):art.call("update_surface_pose")
 if art.has_method("surface_pose_report"):pose_report=art.call("surface_pose_report")
 if art.model.find_child("Traveler_TunicSurface*",true,false) and not pose_report.get("active",false):
  push_error("Surface pose inactive in range capture: "+str(pose_report));player.free();return false
 var snapshot:=Node3D.new();snapshot.name="SurfaceRangeSnapshot";root.add_child(snapshot)
 records=[]
 if not flatten(player.visual,snapshot,0):snapshot.free();player.free();return false
 var document:=GLTFDocument.new();var state:=GLTFState.new()
 if document.append_from_scene(snapshot,state)!=OK: snapshot.free();player.free();return false
 if document.write_to_filesystem(state,output.path_join(label+".glb"))!=OK:snapshot.free();player.free();return false
 var record:={"prototype":true,"label":label,"lod":diagnostic_lod,"pitch_degrees":pitch,"unilateral":unilateral,"outward_degrees":outward,"elbow_degrees":elbow,"other_pitch_degrees":diagnostic_other_pitch,"other_elbow_degrees":diagnostic_other_elbow,"surface_pose":json_data(pose_report),"rigid_anchors":rigid_anchor_info(player),"variant":variant,"diagnostic_outfit_hidden":hide_outfit,"diagnostic_girdle_lift_m":diagnostic_girdle_lift,"diagnostic_center_correction":diagnostic_center_correction,"meshes":records,"source_sha256s":source_hashes.duplicate(),"scope":"Actual loaded skin baked after specified diagnostic rigid-anchor pose; clay/silhouette visual inspection required"}
 var file:=FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE);file.store_string(JSON.stringify(record,"  "));file.close()
 print("SURFACE_RANGE_POSE_OK ",label," stretch=",pose_report.get("max_stretch",1.0)," wrist_error=",pose_report.get("max_wrist_error",0.0))
 snapshot.free();player.free();return true
