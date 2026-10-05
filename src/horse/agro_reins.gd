class_name AgroReins
extends Node3D
## Cosmetic leather only. Endpoints follow a free hand or rest at the saddle;
## neither horse steering nor the player's collision/weapon state is changed.
const TRIANGLE_COUNT := 40
var horse: Horse
var straps: MeshInstance3D
var _ends: Array[Vector3] = []
func configure(owner_horse: Horse) -> void:
 horse=owner_horse
 name="AgroReins"
 process_priority=40 # after TravelerArt, WeaponArt and their final hand solve
 straps=MeshInstance3D.new();straps.name="CosmeticReinStraps";add_child(straps)
 straps.material_override=AgroArt.skin_palette().get("agro_worn_leather")
 straps.mesh=ArrayMesh.new()
 update_reins(1.0)
func _process(delta: float) -> void:
 update_reins(delta)
func update_reins(delta: float) -> void:
 if not is_instance_valid(horse) or not is_instance_valid(straps):return
 var body:=horse.body_transform()
 var endpoints: Array[Vector3]=[]
 for side in [-1.0,1.0]: endpoints.append(body*Vector3(side*.21,.47,-.27))
 var rider:=horse.current_rider as PlayerCharacter
 if is_instance_valid(rider) and rider.riding.phase==PlayerRiding.Phase.RIDING:
  var art:=rider.visual.get_node_or_null("TravelerArt") as TravelerArt
  if art and art._grips.size()==2 and not rider.bow.is_aiming() and not (art._draw_hand and art._draw_hand.visible):
   var hand:=0 if rider.weapon==PlayerCharacter.Weapon.SWORD else 1
   var grip:=art._grips[hand]
   for side in 2: endpoints[side]=grip.global_position+body.basis.x*(-.009 if side==0 else .009)
 var slack:=_front_transition_slack()
 var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var indices:=PackedInt32Array()
 var inv:=horse.global_transform.affine_inverse()
 var head:=horse.skeleton.global_transform*horse.skeleton.get_bone_global_pose(horse._bone[&"head"])
 for i in 2:
  var side:float=-1 if i==0 else 1
  var end:=inv*endpoints[i]
  if _ends.size()<2:_ends.append(end)
  else:_ends[i]=_ends[i].lerp(end,1.0-exp(-20.0*delta))
  var bit:=inv*(head*Vector3(side*.120,-.3471,-.5148))
  var midpoint:=inv*(body*Vector3(side*.31,.36,-.85))
  var points: Array[Vector3]=[bit,midpoint,_ends[i]]
  var legacy_vertices:=PackedVector3Array();var legacy_normals:=PackedVector3Array()
  for p in points.size():
   var tangent:Vector3=(points[mini(p+1,2)]-points[maxi(p-1,0)]).normalized()
   var across:=tangent.cross(Vector3.UP).normalized()
   if across.length_squared()<.01:across=Vector3.RIGHT
   var normal:=tangent.cross(across).normalized()
   for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
    legacy_vertices.append(points[p]+across*corner.x*.0045+normal*corner.y*.0025);legacy_normals.append(normal*corner.y)
  var offset:=vertices.size()
  var ring_count:=4 if i==0 else 3
  for ring in ring_count:
   if i==0 and ring==1:
    # Subdivide the existing front span and give its slack a shallow bend.
    # Original bit, midpoint, hand/saddle rings remain byte-for-byte solved
    # by the same code; the right rein is untouched. Eight cosmetic triangles.
    var bend:=inv.basis*(body.basis*Vector3(.08,-.20,0))*slack
    for corner in 4:
     vertices.append(legacy_vertices[corner].lerp(legacy_vertices[4+corner],.4)+bend)
     normals.append(legacy_normals[corner].lerp(legacy_normals[4+corner],.4).normalized())
   else:
    var source_ring:=ring-1 if i==0 and ring>1 else ring
    for corner in 4:
     vertices.append(legacy_vertices[source_ring*4+corner]);normals.append(legacy_normals[source_ring*4+corner])
  for p in ring_count-1:
   for edge in 4:
    var a:=offset+p*4+edge;var b:=offset+p*4+(edge+1)%4
    indices.append_array([a,b,b+4,a,b+4,a+4])
 var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
 var mesh:=straps.mesh as ArrayMesh
 mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

## Only a bend in the left leather span yields during a front mount arc. Bit and
## hand/saddle endpoints retain their native solve and exponential smoothing.
func _front_transition_slack() -> float:
 var transition_rider:=horse.current_rider as PlayerCharacter
 if not is_instance_valid(transition_rider):
  # Native dismount releases current_rider before its visible arc finishes.
  for node in get_tree().get_nodes_in_group(&"players"):
   var candidate:=node as PlayerCharacter
   if candidate and candidate.riding and candidate.riding.horse==horse and candidate.riding.phase==PlayerRiding.Phase.DISMOUNTING:
    transition_rider=candidate
    break
 if not is_instance_valid(transition_rider) or not transition_rider.riding:return 0.0
 var riding:=transition_rider.riding
 if riding.phase not in [PlayerRiding.Phase.MOUNTING,PlayerRiding.Phase.DISMOUNTING]:return 0.0
 var route:=riding._from_local if riding.phase==PlayerRiding.Phase.MOUNTING else riding._to_local
 if route.z>=-.5 or absf(route.z)<=absf(route.x):return 0.0
 var t:=clampf(riding._t,0.0,1.0)
 # The slack yields after the approaching leg passes the span, then settles
 # before the ordinary seated/standing attachment takes over.
 var approach:=t if riding.phase==PlayerRiding.Phase.MOUNTING else 1.0-t
 return smoothstep(.30,.50,approach)*(1.0-smoothstep(.75,1.0,approach))
