extends SceneTree
## Independent full-world ecology regression; baseline transform hashes from c363b1a.
const BASELINE := {
  "legacy": {
    "1": "d10c99918cdf01c8152d4e2e39d113cefd6c6f2ea4c0fd9d830abaa8ce7ed8f9",
    "2": "d10c99918cdf01c8152d4e2e39d113cefd6c6f2ea4c0fd9d830abaa8ce7ed8f9",
    "3": "d10c99918cdf01c8152d4e2e39d113cefd6c6f2ea4c0fd9d830abaa8ce7ed8f9",
    "4": "75e4b87dad0a5c7c4ee3c31d23d6518380f999c62a48a327a8b1fef1a49975d9"
  },
  "route": {
    "(0, -256)": "24f3eb0e9461f791e4cc21c3486112399d875c8d3009f436df758f7887776f61",
    "(0, -512)": "b6cc8bf0cf2e217a7e2ffba81e6e1aff30b3f375c8251ba4d1197e9a2fc1a5c2",
    "(0, -768)": "32d416acdbe82168b7b72e23fdc0eaaa4f7919fb0454c5d722246460ef9cf015",
    "(0, 0)": "761e48055429b9431ac78dce79658506f6e2eb208729ab58236e050ef816541e",
    "(256, -256)": "71915af49d34e422a7be8db66fed976f7085da0fcae8781dd7b5c2c9965f0a9d",
    "(256, -512)": "3665ccc6e72f0a6f3eccc7771ac7d79d5535282bf92c430a6d19ad6a0b623b23",
    "(256, -768)": "a6f0eccf3141fe4d1e265e2e7c5f4a6455800ff35f41c9c2b4f9b2969c03b49d",
    "(256, 0)": "79befa7ec88fdbad205562fced3b9cb703d8d9c027c5061a34f54d50246ba9a8",
    "(512, -256)": "7ec2e5bb64348b9ca219dff74e1aa99c81edddd3ae1cc129e221d43df487326f",
    "(512, -512)": "6429a14ad71e29b24c5f6297e0cb34ffb6cf1b8ec1783014a1587902358698e9",
    "(512, -768)": "81fc789c2f43400d66c20a6ff2fdb38d4efbda809dc77f6aef5314c232eba1b6",
    "(512, 0)": "2d3909173453a9f936df76a61e0f6d8de55fc338403a74a360825b8f476b3c9b"
  }
}
var failures := 0
var messages: Array = []
var mesh_bounds := {}
func check(ok: bool, message: String) -> void:
 if not ok:
  failures += 1
  if messages.size() < 40: messages.append(message)
func signature(cells: Dictionary) -> String:
 var records: Array = []
 for cell in cells:
  for kind in cells[cell]:
   for xf in cells[cell][kind]: records.append(var_to_bytes(xf).hex_encode())
 records.sort()
 return '\n'.join(records).sha256_text()
func _initialize() -> void:
 call_deferred('run')
func run() -> void:
 var began := Time.get_ticks_usec()
 var report := {'route_instances':0,'nonroute_instances':0,'route_batches':0,'nonroute_batches':0,'populated_nonroute_chunks':0,'max_nonroute_chunk':0,'max_cell_kinds':0,'kinds':{},'regions':{},'quadrants':{},'sliced_chunks':0,'legacy_layouts_checked':4,'route_transform_hashes':{}}
 var positions := {}
 var ecology_kinds := {}
 var focal_counts: Array = []
 focal_counts.resize(BiomeGroundcover.FOCAL_PATCHES.size());focal_counts.fill(0)
 for kind: String in BiomeGroundcover.KINDS:
  var b: AABB = EnvironmentGroundcover.ASSET.mesh_for(kind,0).get_aabb()
  for lod in [1,2]: b = b.merge(EnvironmentGroundcover.ASSET.mesh_for(kind,lod).get_aabb())
  mesh_bounds[kind] = b
 for layout in [1,2,3,4]:
  var raw: Array = []
  for z in range(-2304,1792,256):
   for x in range(-2304,1792,256):
    raw.append(var_to_bytes(EnvironmentGroundcover.sample_chunk(Vector2i(x,z),{},layout)).hex_encode())
  check('\n'.join(raw).sha256_text() == BASELINE.legacy[str(layout)],'Historical full-world sampler changed: '+str(layout))
 for z in range(-2304,1792,256):
  for x in range(-2304,1792,256):
   var origin := Vector2i(x,z)
   var route := EnvironmentGroundcover.is_route_chunk(origin,5)
   var cells := EnvironmentGroundcover.sample_chunk(origin,{},5)
   check(var_to_bytes(cells)==var_to_bytes(EnvironmentGroundcover.sample_chunk(origin,{},5)),'Nondeterminism: '+str(origin))
   if route:
    var hash_value := signature(cells)
    report.route_transform_hashes[str(origin)] = hash_value
    check(hash_value == BASELINE.route[str(origin)],'Route transform multiset changed: '+str(origin))
   else:
    var state := BiomeGroundcover.state_for(origin,5)
    while int(state.row)<int(state.total_rows): BiomeGroundcover.sample_rows(state,4)
    EnvironmentGroundcover._shuffle_route_cells(state.cells,state.rng)
    check(var_to_bytes(cells)==var_to_bytes(state.cells),'Four-candidate sliced output differs: '+str(origin))
    report.sliced_chunks+=1
    if not cells.is_empty(): report.populated_nonroute_chunks+=1
   var n := 0
   for cell: Vector2i in cells:
    if not route:
     check(cell.x % 2 == 0 and cell.y % 2 == 0,'Nonroute render batch is not 128m aligned: '+str(cell))
    for kind: String in cells[cell]:
     report['route_batches' if route else 'nonroute_batches']+=3
     for xf: Transform3D in cells[cell][kind]:
      n+=1
      var p := Vector2(xf.origin.x,xf.origin.z)
      var key := var_to_bytes(p).hex_encode()
      check(not positions.has(key),'Duplicate world position: '+str(p))
      positions[key]=true
      check(p.x>=x and p.x<x+256 and p.y>=z and p.y<z+256,'Escaped chunk: '+str(origin))
      check(absf(xf.origin.y-ForbiddenLandsTerrain.surface_height(p.x,p.y,5)+.035)<.001,'Floating placement: '+str(p))
      report.kinds[kind]=report.kinds.get(kind,0)+1
      if not route:
       var eco_cell := Vector2i(floori(p.x/64),floori(p.y/64))
       if not ecology_kinds.has(eco_cell):ecology_kinds[eco_cell]={}
       ecology_kinds[eco_cell][kind]=true
       check(cell == Vector2i(floori(p.x/128)*2,floori(p.y/128)*2),'Position not in128m render batch')
       for patch_index in BiomeGroundcover.FOCAL_PATCHES.size():
        var patch: Vector4 = BiomeGroundcover.FOCAL_PATCHES[patch_index]
        if Vector2((p.x-patch.x)/patch.z,(p.y-patch.y)/patch.w).length()<=1.0:focal_counts[patch_index]+=1
       check(BiomeGroundcover.KINDS.has(kind),'Unknown biome model: '+kind)
       check(EnvironmentGroundcover.allowed(p,false,5,210,12),'Clearance/slope failure: '+str(p))
       var bounds: AABB = xf*mesh_bounds[kind]
       check(not(bounds.position.x<180 and bounds.end.x> -180 and bounds.position.z<180 and bounds.end.z> -180),'Footprint breached shrine: '+str(p))
       var r := maxf(Vector2(bounds.position.x-p.x,bounds.position.z-p.y).length(),Vector2(bounds.end.x-p.x,bounds.end.z-p.y).length())
       check(ForbiddenLandsTerrain.road_distance(p,5)>=ForbiddenLands.road_half_at(p.x,p.y,5)+r,'Mesh footprint road overlap: '+kind+' '+str(p))
       var q := ('W' if p.x<0 else 'E')+('S' if p.y<0 else 'N')
       report.quadrants[q]=report.quadrants.get(q,0)+1
   report['route_instances' if route else 'nonroute_instances']+=n
   if not route:
    report.max_nonroute_chunk=maxi(report.max_nonroute_chunk,n)
    check(n<=1800,'Nonroute chunk population ceiling exceeded: '+str(origin))
 for eco_cell in ecology_kinds:
  report.max_cell_kinds=maxi(report.max_cell_kinds,ecology_kinds[eco_cell].size())
  check(ecology_kinds[eco_cell].size()<=2,'More than two kinds in64m ecology cell: '+str(eco_cell))
 check_batch_contract(report)
 check_queue_ordering(report)
 check_focal_patches(report,focal_counts)
 # Inspect unambiguous regions with many palette seeds, independent of coverage luck.
 for spec: Array in [['forest',Vector2(-800,-550),'biome_fern'],['desert',Vector2(-270,-1440),'biome_dry_scrub'],['highland',Vector2(-1060,600),'biome_heather'],['eastern',Vector2(940,-400),'biome_rush'],['volcanic',Vector2(1184,192),'biome_gravel']]:
  var totals := {}
  for seed_value in 100:
   var rng := RandomNumberGenerator.new();rng.seed=seed_value+793
   var palette := BiomeGroundcover.palette(spec[1],rng)
   for kind: String in palette.kinds:totals[kind]=totals.get(kind,0)+1
  report.regions[spec[0]]=totals
  check(totals.get(spec[2],0)>=60,'Representative biome missing expected dominant family: '+spec[0])
 check(report.route_instances==23328,'Approved route count changed')
 check(report.nonroute_instances>6558,'World coverage did not improve')
 check(report.route_instances+report.nonroute_instances<75000,'Global procedural population ceiling exceeded')
 check(report.route_batches+report.nonroute_batches<10200,'Procedural batches leave insufficient total-world budget')
 check(report.quadrants.size()==4,'Missing geographic quadrant')
 for kind: String in BiomeGroundcover.KINDS:check(report.kinds.get(kind,0)>50,'Insufficient world family coverage: '+kind)
 report.failures=failures
 report.failure_messages=messages
 report.elapsed_usec=Time.get_ticks_usec()-began
 report.gpu_fps_measured=false
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://tests/output'))
 var file:=FileAccess.open('res://tests/output/biome_groundcover.json',FileAccess.WRITE)
 file.store_string(JSON.stringify(report,'  '));file.close()
 print('BIOME_GROUNDCOVER: ',JSON.stringify(report))
 quit(1 if failures else 0)

func batch_records(parent: Node3D) -> Array:
 var result: Array = []
 for batch: MultiMeshInstance3D in parent.get_children():
  result.append([batch.name,batch.position,batch.multimesh.instance_count,batch.multimesh.visible_instance_count,batch.multimesh.custom_aabb,batch.visibility_range_begin,batch.visibility_range_end,batch.get_meta(&"groundcover_kind"),batch.get_meta(&"groundcover_lod")])
 return result
func check_batch_contract(report: Dictionary) -> void:
 var checked := 0
 var durations: Array = []
 for origin in [Vector2i(-1024,-768),Vector2i(-1280,512),Vector2i(-512,-1536),Vector2i(768,-512)]:
  var expected := EnvironmentGroundcover.sample_chunk(origin,{},5)
  var streamed := Node3D.new();root.add_child(streamed)
  streamed.set_meta(&"environment_groundcover_profile","low")
  var queue := ArenaArtBuild.new()
  streamed.set_meta(&"detail_job",queue)
  EnvironmentGroundcover.append_chunk(streamed,origin,{},5)
  check(queue.jobs.size()==1 and streamed.get_child_count()==0,"Nonroute append not deferred")
  streamed.remove_meta(&"detail_job")
  var state := BiomeGroundcover.state_for(origin,5)
  while not state.get("done",false):
   var start := Time.get_ticks_usec()
   EnvironmentGroundcover._append_route_step(streamed,state)
   durations.append(Time.get_ticks_usec()-start)
  var direct := Node3D.new();root.add_child(direct)
  direct.set_meta(&"environment_groundcover_profile","low")
  EnvironmentGroundcover.append_chunk(direct,origin,{},5)
  check(var_to_bytes(batch_records(streamed))==var_to_bytes(batch_records(direct)),"Streaming batch metadata differs: "+str(origin))
  for cell in expected:
   for kind in expected[cell]:
    var prepared := EnvironmentGroundcover._prepare_cell_kind(cell,kind,expected[cell][kind])
    for xf: Transform3D in expected[cell][kind]:
     var local := xf;local.origin-=prepared.anchor
     check(prepared.bounds.grow(.001).encloses(local*mesh_bounds[kind]),"Merged batch AABB clips geometry")
  for batch: MultiMeshInstance3D in streamed.get_children():
   check(batch.multimesh.visible_instance_count==maxi(1,ceili(batch.multimesh.instance_count*.35)),"Streamed low-profile density lost")
   check(batch.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Biome casts shadows")
   check(not batch.get_meta(&"route_meadow",false),"Nonroute batch mislabeled route")
  check(streamed.find_children("*","CollisionObject3D",true,false).is_empty(),"Biome adds physics")
  check(state.size()==1,"Completed job retains CPU arrays")
  streamed.free();direct.free();checked+=1
 durations.sort()
 report.streamed_fixture_chunks=checked
 report.mid_lod_profile_switch_checked=check_mid_lod_profile_switch()
 report.streamed_step_max_usec=durations.back() if not durations.is_empty() else 0
 report.streamed_step_p95_usec=durations[floori(durations.size()*.95)] if not durations.is_empty() else 0
 var cancelled := BiomeGroundcover.state_for(Vector2i(-1024,-768),5)
 check(EnvironmentGroundcover._append_route_step(null,cancelled) and cancelled.size()==1,"Cancelled biome job retained state")

func check_mid_lod_profile_switch() -> bool:
 var origin := Vector2i(-1024,-768)
 var cells := BiomeGroundcover.sample_chunk(origin,5)
 for cell in cells:
  for kind in cells[cell]:
   var transforms: Array = cells[cell][kind]
   var streamed := Node3D.new();root.add_child(streamed)
   streamed.set_meta(&"environment_groundcover_profile","low")
   var state := BiomeGroundcover.state_for(origin,5)
   state.row=state.total_rows;state.shuffled=true
   state.batches=[[cell,kind,transforms]]
   state.prepared=EnvironmentGroundcover._prepare_cell_kind(cell,kind,transforms)
   state.batch_lod=1
   EnvironmentGroundcover._append_cell_lod(streamed,cell,kind,transforms,"low",false,state.prepared,0)
   GraphicsQuality.apply(streamed,"high")
   while not EnvironmentGroundcover._append_route_step(streamed,state):pass
   var direct := Node3D.new();root.add_child(direct)
   EnvironmentGroundcover._append_cell_kind(direct,cell,kind,transforms,"high",false)
   check(var_to_bytes(batch_records(streamed))==var_to_bytes(batch_records(direct)),"Biome mid-LOD quality switch left mixed profiles")
   streamed.free();direct.free()
   return true
 check(false,"No populated batch for biome mid-LOD switch")
 return false

func check_queue_ordering(report: Dictionary) -> void:
 var holder := Node3D.new();root.add_child(holder)
 var queue := ArenaArtBuild.new()
 holder.set_meta(&"detail_job",queue)
 var specs := [Vector2i(-1024,-768),Vector2i(256,-256),Vector2i(-2304,-2304),Vector2i(512,-512),Vector2i(768,-512)]
 var fixtures: Array = []
 var initial_runs := {}
 for i in specs.size():
  var fixture := Node3D.new();holder.add_child(fixture);fixtures.append(fixture)
  var origin: Vector2i = specs[i]
  queue.add(func() -> void:
   initial_runs[i]=initial_runs.get(i,0)+1
   EnvironmentGroundcover.append_chunk(fixture,origin,{},5))
 queue.set_meta(&"meadow_start_index",queue.jobs.size())
 var initial_count := queue.jobs.size()
 while queue.cursor<initial_count:
  queue.step(1000000,1)
 check(queue.jobs.size()==initial_count*2,"Mixed queue lost or duplicated continuations")
 for i in specs.size():check(initial_runs.get(i,0)==1,"Initial chunk job did not run exactly once")
 for fixture in fixtures:check(fixture.get_child_count()==0,"Initial queue unexpectedly emitted groundcover")
 var completions := []
 while queue.cursor<queue.jobs.size():
  var prior := queue.cursor
  queue.step(1000000,1)
  check(queue.cursor==prior or queue.cursor==prior+1,"Queue cursor skipped continuation")
  if queue.cursor>prior:completions.append(prior)
  if prior<initial_count+2:
   for i in [0,2,4]:check(fixtures[i].get_child_count()==0,"Distant ecology started before both dense-route continuations completed")
 check(completions.size()==initial_count,"Not every continuation completed exactly once")
 var empty_checked := false
 for i in specs.size():
  var direct := Node3D.new();root.add_child(direct)
  EnvironmentGroundcover.append_chunk(direct,specs[i],{},5)
  check(var_to_bytes(batch_records(fixtures[i]))==var_to_bytes(batch_records(direct)),"Integrated queue output differs from direct append: "+str(specs[i]))
  if i==2:
   check(direct.get_child_count()==0,"Expected ocean chunk was not empty")
   empty_checked=true
  direct.free()
 report.priority_queue_initial_jobs=initial_count
 report.priority_queue_completed_jobs=queue.cursor
 report.priority_queue_empty_chunk_checked=empty_checked
 # A later request on the same queue must append safely after the cursor.
 var late := Node3D.new();holder.add_child(late)
 var old_cursor := queue.cursor
 var old_size := queue.jobs.size()
 EnvironmentGroundcover.append_chunk(late,Vector2i(0,0),{},5)
 check(queue.cursor==old_cursor and queue.jobs.size()==old_size+1,"Late append corrupted queue cursor")
 while not queue.step(1000000,1):pass
 var late_direct := Node3D.new();root.add_child(late_direct)
 EnvironmentGroundcover.append_chunk(late_direct,Vector2i(0,0),{},5)
 check(var_to_bytes(batch_records(late))==var_to_bytes(batch_records(late_direct)),"Late route append skipped or duplicated a job")
 check(queue.cursor==old_cursor+1,"Late route cursor advanced incorrectly")
 late_direct.free()
 report.priority_queue_late_append_checked=true
 holder.free()
 # Exercise a genuinely freed parent, not only a null argument.
 var cancelled_holder := Node3D.new();root.add_child(cancelled_holder)
 var cancelled_queue := ArenaArtBuild.new()
 cancelled_holder.set_meta(&"detail_job",cancelled_queue)
 var cancelled_child := Node3D.new();cancelled_holder.add_child(cancelled_child)
 EnvironmentGroundcover.append_chunk(cancelled_child,Vector2i(-1024,-768),{},5)
 cancelled_child.free()
 check(cancelled_queue.step(1000000,1),"Freed-parent continuation did not complete")
 check(cancelled_queue.cursor==1,"Freed-parent continuation cursor did not advance")
 cancelled_holder.free()
 report.priority_queue_freed_parent_checked=true

func check_focal_patches(report: Dictionary, counts: Array) -> void:
 var patches: Array = BiomeGroundcover.FOCAL_PATCHES
 var original_counts: Array = []
 original_counts.resize(patches.size());original_counts.fill(0)
 for z in range(-2304,1792,256):
  for x in range(-2304,1792,256):
   var origin := Vector2i(x,z)
   if EnvironmentGroundcover.is_route_chunk(origin,5):continue
   var cells := EnvironmentGroundcover._sample_legacy(origin,{},5)
   for cell in cells:
    for kind in cells[cell]:
     for xf: Transform3D in cells[cell][kind]:
      for i in patches.size():
       var patch: Vector4 = patches[i]
       if Vector2((xf.origin.x-patch.x)/patch.z,(xf.origin.z-patch.y)/patch.w).length()<=1.0:original_counts[i]+=1
 report.original_legacy_focal_populations=original_counts
 report.focal_patch_populations=counts
 for i in patches.size():
  var patch: Vector4 = patches[i]
  var centre := Vector2(patch.x,patch.y)
  check(EnvironmentGroundcover.allowed(centre,false,5,210,12),"Focal patch centre is not plantable: "+str(centre))
  check(counts[i]>=100,"Focal patch does not form substantial cover: "+str(centre))
  for dx in [-1.24,-1.20,-1.16,-1.0,-.5,0,.5,1.0,1.16,1.20,1.24]:
   for dz in [-1.24,-1.20,-1.16,-1.0,-.5,0,.5,1.0,1.16,1.20,1.24]:
    var p := centre+Vector2(dx*patch.z,dz*patch.w)
    var origin := Vector2i(floori(p.x/256)*256,floori(p.y/256)*256)
    var local := BiomeGroundcover.focus_at(p,BiomeGroundcover.patches_in_chunk(origin))
    var global := BiomeGroundcover.focus_at(p,patches)
    check(is_equal_approx(local,global),"Focal index clips density across chunk boundary: "+str(p))
