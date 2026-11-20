extends SceneTree

const Salvage:=preload("res://game/world/structural_salvage.gd")
var s:WastelandSession
var errors:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: errors+=1

func run()->void:
	WastelandSave.root_override="user://verification/site-ruin-%d"%OS.get_process_id()
	var app:Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	if "--host" in OS.get_cmdline_user_args() or "--guest" in OS.get_cmdline_user_args():
		await online(app,"--host" in OS.get_cmdline_user_args())
		quit(1 if errors else 0)
		return
	var cfg:Dictionary=app._default_config()
	cfg.seed=2817
	cfg.spawn_roll=74
	app._enter_world(cfg,{},1,false)
	s=app.session
	s.simulation_paused=true
	var plans:={}
	var furniture:={}
	var saved_cell:=Vector2i.ZERO
	var saved_piece:=""
	var signature:=[]
	var all_paths:=true
	var all_rooms:=true
	var walked:=false
	var visited:={}
	var cells:Array=WastelandTerrainGen.FIXED.keys()
	for z in range(-12,13):
		for x in range(-12,13):
			if s.stream.generator.site_for(Vector2i(x,z))=="cabin":
				cells.append(Vector2i(x,z))
				break
		if cells.size()>WastelandTerrainGen.FIXED.size(): break
	cells.append(s.stream.generator.starting_outpost("grassland"))
	cells.append(s.stream.generator.starting_outpost("foothills"))
	for cell:Vector2i in cells:
		var world:=Vector2(cell*32)+Vector2(16,16)
		s.stream.ensure_landing(Vector3(world.x,0,world.y))
		await physics_frame
		await physics_frame
		var c:WastelandChunk=s.stream.active[cell]
		visited[c.site]=true
		var span:=float(s.catalog.sites[c.site].span)
		var floors:=int(s.catalog.sites[c.site].stories)
		plans[c.ruin.condition]=true
		var room_ids:=[]
		for id:String in c.structures:
			if id.begins_with("furniture/"):
				room_ids.append(id)
				furniture[id.get_slice("/",2)]=true
				var contents:=Salvage.materials(c,id)
				var kind:=id.get_slice("/",2)
				check(not contents.is_empty() and (kind!="cot" or contents.has_all(["cloth","wood","scrap"])) and (kind!="lockers" or contents.keys()==["scrap"]),kind+" has recoverable frame and upholstery materials "+str(contents))
		all_rooms=all_rooms and room_ids.size()>=floors and c.ruin.furniture_bounds.size()==room_ids.size()
		var floor:=1 if c.site=="bunker" else 0
		var base_y:float=c.structures["slab/"+str(floor)][0].global_position.y
		var at:=Vector3(world.x-span*0.5,base_y+1.5,world.y+c.ruin.end*span*0.2)
		var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.LEFT*0.64,at+Vector3.RIGHT*0.64,2)
		var hit:=s.get_world_3d().direct_space_state.intersect_ray(ray)
		all_paths=all_paths and hit.is_empty() and c.structures.has("door/entrance")== (c.site!="bunker")
		if not walked and c.site=="lodge":
			s.player.global_position=Vector3(at.x-1.55,base_y+0.20,at.z)
			s.player.rotation.y=-PI/2
			s.player.velocity=Vector3.ZERO
			Input.action_press("up")
			for tick in 50:
				await physics_frame
				s.player.simulate(1.0/60,true)
			Input.action_release("up")
			walked=s.player.global_position.x>at.x+0.55
		if c.site in ["hospital","police","tower"]:
			all_paths=all_paths and c.supply_caches.has(c.object_key("container/99")) and c.structures.has("slab/"+str(floors-1))
		if c.site=="lodge":
			all_paths=all_paths and c.fixtures.has(c.object_key("trader"))
		if saved_piece=="" and not room_ids.is_empty():
			saved_cell=cell
			saved_piece=room_ids[0]
			signature=[c.ruin.condition,c.ruin.end,room_ids.duplicate()]
			var body:StaticBody3D=c.structures[saved_piece][0]
			s.hit_wall(body,10000)
		await check_frame(c)
	check(visited.size()==7,"exercised all seven building types "+str(visited.keys()))
	check(plans.size()>=2 and not plans.has(0),"all sampled POIs have damage, with distinct levels "+str(plans.keys()))
	check(all_rooms and furniture.size()>=4,"procedural rooms generate multiple furniture types "+str(furniture.keys()))
	check(all_paths,"first-person-height side breaches have no wall collider; stairs, loot floors and boards are preserved")
	check(walked,"actual survivor walks through a natural breach without jumping or breaking a panel")
	check(s.save_now(false)==OK,"save actual demolished furniture")
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	var p:=Vector2(saved_cell*32)+Vector2(16,16)
	s.stream.ensure_landing(Vector3(p.x,0,p.y))
	var c:WastelandChunk=s.stream.active[saved_cell]
	check(signature[0]==c.ruin.condition and signature[1]==c.ruin.end and not c.structures.has(saved_piece),"same weather damage and destroyed furniture stay after disk reload")
	check(not c.structures.has("ridge/post/4") and not c.structures.has("roof/timber/1/4") and c.structures.has("roof/timber/1/0"),"saved support failure removes the disconnected roof wing on reload")
	for id:String in signature[2]:
		if id!=saved_piece:check(c.structures.has(id),"remaining room furniture retains identity")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if errors else 0)

func check_frame(c:WastelandChunk)->void:
	var timber:=c.site in ["lodge","cabin"]
	var bare:Array=[]
	for id:String in c.structures:
		if id.begins_with("wreck/") or id.begins_with("expedition/") or id.begins_with("dock/"): continue
		if not c.footings.has(id) and not c.support_graph.has(id): bare.append(id)
	check(bare.is_empty(),c.site+" all parts have a foundation or a bearing "+str(bare))
	if timber:
		for bay in 5:
			if c.ruin.damaged(0,3,bay,c.site):
				check(not c.structures.has("roof/rafter/-1/%d/1"%bay) and not c.structures.has("roof/timber/-1/%d"%bay),c.site+" broken wall carries no roof bay "+str(bay))
	var top:int=int(s.catalog.sites[c.site].stories)-1
	var pillar:="ridge/post/4" if timber else "column/0/1/0"
	var beam:="ridge/beam/1" if timber else "girder/%d/0"%top
	var roof:="roof/timber/1/4" if timber else "roof/plate/1/0"
	var neighbor:="roof/timber/1/0" if timber else "roof/plate/1/1"
	if not c.structures.has(pillar) or not c.structures.has(beam) or not c.structures.has(roof):
		check(false,c.site+" complete load path exists before demolition")
		return
	var fragment:StaticBody3D=c.structures[roof][0]
	var resources:=Salvage.materials(c,roof)
	var roof_material:="scrap" if timber else "stone"
	check(resources.has(roof_material) and resources[roof_material]<=Salvage.MAX_UNITS and Salvage.materials(c,pillar).has("wood" if timber else "scrap"),c.site+" roof and post salvage match materials with capped yields")
	check(Salvage.origin(c,roof).distance_to(fragment.global_position)<0.01,c.site+" reclaimed material originates on the correct section")
	if timber:
		var wall_id:="wall/0/1/2"
		var wall_resources:=Salvage.materials(c,wall_id)
		check(c.structures[wall_id].size()>1 and wall_resources.keys()==["wood"] and wall_resources.wood<=Salvage.MAX_UNITS,"wall core and weatherboards form a single capped wood yield")
	s.hit_wall(c.structures[pillar][0],9999)
	check(Salvage.materials(c,pillar).is_empty() and Salvage.materials(c,roof).is_empty(),c.site+" demolished geometry has no second salvage yield")
	check(not c.structures.has(beam) and not c.structures.has(roof) and c.structures.has(neighbor),c.site+" removing a column brings down every dependent level while adjacent spans survive")
	check(not is_instance_valid(fragment) or fragment.collision_layer==0,c.site+" fallen roof no longer blocks the old space")
	if c.site=="fuel":
		s.hit_wall(c.structures["canopy/post/-1"][0],9999)
		check(not c.structures.has("canopy") and not c.structures.has("landmark/fittings/canopy") and c.structures.has("pump/1"),"fuel canopy and fascia fall together")
	if c.site=="lodge":
		s.hit_wall(c.structures["porch/post/-1"][0],9999)
		check(not c.structures.has("porch") and c.structures.has("porch/deck"),"porch roof falls off the broken post")

func until(test:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+16000
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await process_frame
	return false

func online(app:Node,host:bool)->void:
	var cell:=WastelandSite.SHORE_CELL
	var point:=Vector3(-16,0,48)
	if host:
		var cfg:Dictionary=app._default_config()
		cfg.seed=2817
		cfg.spawn_roll=74
		app._enter_world(cfg,{},1,false)
		s=app.session
		s.stream.ensure_landing(point)
		s.player.position=point+Vector3(0,s.stream.ground_at(point)+0.24,7)
		check(app.network.listen(19482)==OK,"host listens")
		if await until(func():return is_instance_valid(app.network.member)):
			var c:WastelandChunk=s.stream.active[cell]
			var id:=first_furniture(c)
			var label:="%d/%d/%s"%[c.ruin.condition,c.ruin.end,id]
			check(await until(func():return s.marker_records.any(func(m):return m.name==label.left(18))),"guest generated matching structure and room identity")
			if id!="": s.hit_wall(c.structures[id][0],9999)
			s.hit_wall(c.structures["ridge/post/4"][0],9999)
			check(await until(func():return s.marker_records.any(func(m):return m.name=="家具已拆")), "guest confirmed authoritative furniture removal")
		else:check(false,"guest joined")
	else:
		check(app.network.connect_to("127.0.0.1",19482)==OK,"guest connects")
		if await until(func():return is_instance_valid(app.session) and app.session.replica and app.session.stream.active.has(cell)):
			s=app.session
			var c:WastelandChunk=s.stream.active[cell]
			var id:=first_furniture(c)
			var label:="%d/%d/%s"%[c.ruin.condition,c.ruin.end,id]
			check(id!="" and c.ruin.condition>0,"guest sees ruined architecture and furnished room")
			s.ui_command("marker",[Vector2(point.x,point.z),label.left(18)])
			check(await until(func():return not c.structures.has(id)), "guest loses furniture mesh and collision after host dismantles it")
			check(await until(func():return not c.structures.has("ridge/beam/1") and not c.structures.has("roof/timber/1/4") and c.structures.has("roof/timber/1/0")),"guest loses the disconnected roof wing after host removes its support")
			s.ui_command("marker",[Vector2(point.x+4,point.z),"家具已拆"])
			await create_timer(0.6).timeout
		else:check(false,"guest streamed the authority's POI")
	app.network.stop()
	if is_instance_valid(s):
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.queue_free()
	await process_frame

func first_furniture(chunk:WastelandChunk)->String:
	for id:String in chunk.structures:
		if id.begins_with("furniture/"): return id
	return ""
