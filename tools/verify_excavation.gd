extends SceneTree

var failures := 0
var s: WastelandSession

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ",title)
	if not ok: failures+=1

func enter(save: Dictionary = {}) -> void:
	var cfg := WastelandSave.default_world()
	cfg.seed=2817
	cfg.start_id="seeded" # This fixture explicitly excavates the legacy station's foundations.
	s=WastelandSession.new()
	root.add_child(s)
	s.configure(cfg,save,1,WastelandCatalog.new(),WastelandSettings.new())
	s.simulation_paused=true

func leave() -> void:
	await s.stream.quiesce()
	await s.audio.finish_playback()
	s.queue_free()
	await process_frame

func collision_error(cell:Vector2i)->float:
	var largest:=0.0
	var max_normal_angle:=0.0
	var space:=s.get_world_3d().direct_space_state
	for x in range(1,31):
		for z in range(1,31):
			var sample:=Vector3(cell.x*32+x+(0.32 if (x+z)%2==0 else 0.82),0.0,cell.y*32+z+0.41)
			sample.y=s.stream.ground_at(sample)
			var ray:=PhysicsRayQueryParameters3D.create(sample+Vector3.UP*4,sample+Vector3.DOWN*4,1)
			var hit:=space.intersect_ray(ray)
			if hit.is_empty(): return INF
			largest=maxf(largest,absf((hit.position as Vector3).y-sample.y))
			max_normal_angle=maxf(max_normal_angle,s.stream.ground_normal_at(sample).angle_to(hit.normal))
	check(max_normal_angle<0.006,"hoof and foot support normals match both terrain triangles within 0.35 degrees")
	return largest

func punch_ground(at: Vector3, layer: String, loss: float) -> bool:
	var camera := s.player.camera
	var original := camera.transform
	camera.global_position = at + Vector3.UP * 1.3
	camera.look_at(at, Vector3.BACK)
	var hit := s._trace(2.58, 15, false, true, true)
	var terrain: bool = not hit.is_empty() and hit.collider.get_meta("kind", "") == "terrain" and s._dig_layer(hit.position)[0] == layer
	if terrain:
		var health := s.player.health
		s._melee({}, 1.0)
		check(s.player.health == health - loss, "a punch on %s costs %d health" % [layer, loss])
	camera.transform = original
	return terrain

func run() -> void:
	WastelandSave.root_override="user://verification/excavate-%d"%OS.get_process_id()
	enter()
	var st:=s.stream
	var initial:=s.start_position()
	var node:=Vector2i(roundi(initial.x),roundi(initial.z))
	var p:=Vector3(node.x,0,node.y)
	var original:=st.ground_at(p)
	var old_cell:=WastelandTerrainGen.chunk_at(Vector2(node))
	for i in 2: await physics_frame
	check(collision_error(old_cell)<0.003,"900 off-grid rays match terrain before excavation")
	check(st.generator.site_for(old_cell)=="lodge","fixture starts within the previously protected POI")
	var soil := Vector3(old_cell.x * 32 + 1, 0, old_cell.y * 32 + 1)
	soil.y = st.ground_at(soil)
	check(punch_ground(soil, "泥土", 0.0), "punch reaches undisturbed soil")
	var road := soil + Vector3.BACK * 22.0
	road.y = st.ground_at(road)
	check(punch_ground(road, "路面", 3.0), "punch reaches the paved road")
	for i in 100: st.excavate(p)
	check(is_equal_approx(float(st.digs[WastelandTerrainGen.grid_key(node)]),-58.0),"100 continuous strikes excavate 58 meters")
	check(st.digs.size()==9,"stroke affects adjoining vertices as well as center")
	var corner:=Vector2i(-96,-64)
	st.excavate(Vector3(corner.x,0,corner.y))
	var canonical:=WastelandTerrainGen.grid_key(corner)
	var neighbors:=true
	for dx in 2:
		for dz in 2:
			var cell:=Vector2i(-3-dx,-2-dz)
			var diff:=st._delta_for(cell)
			neighbors = neighbors and is_equal_approx(float(diff.get(canonical,0.0)),-0.58)
			var product:=st.generator.build(cell,diff,false)
			var v:Vector3=product.points[(dz*32)*33+dx*32]
			neighbors = neighbors and absf(v.y-(st.generator.ground(corner.x,corner.y)-0.58))<0.001
	check(neighbors,"four negative-coordinate chunks agree on an excavated boundary")
	var wet:=Vector3(23,0,-42)
	var wet0:=st.ground_at(wet)
	st.excavate(wet)
	check(absf(st.ground_at(wet)-wet0+0.58)<0.01,"unloaded submerged floor immediately reflects its saved excavation")
	var deadline:=Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline and absf(st.ground_at(p)-original+58)>0.01: await physics_frame
	await physics_frame
	await physics_frame
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(p.x,original+2,p.z),Vector3(p.x,original-61,p.z),1)
	var hit:=s.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit.position.y-original+58)<0.03,"physics surface reaches the regenerated pit floor")
	check(not hit.is_empty() and punch_ground(hit.position, "岩层", 3.0), "punch reaches the exposed rock layer")
	check(s.start_position().distance_to(initial)>1.0 and s.start_position().y>original-4,"spawn selects nearby land after the outpost spawn is undermined")
	check(collision_error(old_cell)<0.003,"900 off-grid rays match terrain after digging 58 metres deep")
	var deep:=Vector3(p.x,original-58.0+0.2,p.z)
	s.player.global_position=deep
	s.player.simulate(0.016,false)

	check(s.player.health>0 and s.player.position.y < -32,"standing below the old kill plane is survivable")
	s.player.global_position=deep
	check(s.save_now(false)==OK,"save from inside excavated site")
	var save:=WastelandSave.read(1)
	await leave()
	enter(save)

	check(s.player.position.distance_to(deep)<0.05 and absf(s.stream.ground_at(p)-original+58.0)<0.01,"deep survivor and terrain restore together")
	var shelf := p+Vector3(5,0,0)
	for dx in range(-1,3):
		for dz in range(-1,3):
			for stroke in 38: s.stream.excavate(shelf+Vector3(dx,0,dz))
	var sample := shelf+Vector3(0.5,0,0.5)
	deadline=Time.get_ticks_msec()+7000
	while Time.get_ticks_msec()<deadline and s.stream.ground_at(sample)>-35: await physics_frame
	var base:=Vector3i(floori(sample.x),roundi(s.stream.ground_at(sample)),floori(sample.z))
	s.bag.add("frame",2)
	check(base.y < -30 and s.construction.place(base,"frame",0,0,s.player.position) and s.construction.place(base+Vector3i.UP,"frame",0,0,s.player.position),"underground scaffold can be anchored and extended below -30")
	var chunk:WastelandChunk=s.stream.active[old_cell]
	var board:StaticBody3D=chunk.fixtures.get(chunk.object_key("trader"))
	var key:String=board.get_meta("key")
	var board_y:=board.global_position.y
	board.global_position.y+=8
	s.stream.settle_interactables(old_cell)
	for frame in 5: await physics_frame
	var bottom:=board.global_position-Vector3.UP*0.93
	var support:=PhysicsRayQueryParameters3D.create(bottom+Vector3.UP*0.12,bottom-Vector3.UP*0.16,11,[board.get_rid()])
	check(board.get_meta("key")==key and board.global_position.y<board_y+7.5 and not s.get_world_3d().direct_space_state.intersect_ray(support).is_empty(),"unanchored notice board settles onto real support and retains quest identity")
	var contacts:=0
	for x in range(3,29,3):
		if contacts==2: break
		var target:=Vector3(old_cell.x*32+x,0,old_cell.y*32+28)
		var tool: String=["shovel","iron_pick"][contacts]
		s.bag.add(tool,1)
		s.bag.bar[s.bag.active]=tool
		s.player.global_position=Vector3(target.x,s.stream.ground_at(target)+0.12,target.z)
		s.player.eyes.rotation.x=-PI/2.0
		s.player.camera.force_update_transform()
		var trace:=s._trace(3.1,15,false,true)
		if trace.is_empty() or trace.collider.get_meta("kind","")!="terrain": continue
		var pos:Vector3=trace.position
		var grid:=WastelandTerrainGen.grid_key(Vector2i(roundi(pos.x),roundi(pos.z)))
		var layer:=s._dig_layer(pos)
		var expected:=0.76 if (tool=="iron_pick")==bool(layer[1]) else 0.32
		var previous:=float(s.stream.digs.get(grid,0))
		var reward:String=layer[2].keys()[0]
		var count:=s.bag.count(reward)
		var before:=s.fx.drop_records.keys()
		s._melee(s.catalog.items[tool],1.0)
		var physical:=false
		for id:String in s.fx.drop_records.keys():
			if not before.has(id) and s.fx.drop_records[id].items.has(reward):
				physical=s.bag.count(reward)==count
				s.fx.take_drop(id)
				break
		check(is_equal_approx(float(s.stream.digs.get(grid,0)),previous-expected) and physical and s.bag.count(reward)>count,"tool ray cuts the matching layer and releases collectible material: "+tool)
		contacts+=1
	check(contacts==2,"both tool ray contacts found a reachable patch of terrain")
	await leave()
	print("EXCAVATION QA failures=",failures)
	quit(1 if failures else 0)
