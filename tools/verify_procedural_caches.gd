extends "res://tools/verify_expeditions.gd"

const CELL:=Vector2i(3,-1)

func precinct(s:WastelandSession)->WastelandChunk:
	if not s.stream.active.has(CELL): s.stream._install(CELL,s.stream.generator.build(CELL,{}))
	return s.stream.active[CELL]

func signature(c:WastelandChunk)->Dictionary:
	var rows:={}
	for id:String in c.supply_caches:
		var body:StaticBody3D=c.supply_caches[id].get_parent()
		rows[id]=[body.position,body.rotation.y,body.get_meta("type"),body.get_meta("cache_profile"),body.get_meta("finish_variant")]
	return rows

func check_wreck_approaches(s:WastelandSession,landmarks:Dictionary)->bool:
	for id:String in landmarks:
		var origin:Vector3=landmarks[id]
		s.stream.ensure_landing(origin)
		var cell:=WastelandTerrainGen.chunk_at(Vector2(origin.x,origin.z))
		var chunk:WastelandChunk=s.stream.active[cell]
		var body:StaticBody3D=chunk.supply_caches[chunk.object_key("submerged/"+id)].get_parent()
		await physics_frame
		var found:=false
		var evidence:={}

		for direction in 36:
			var side:=Vector3(sin((direction%12)*TAU/12),0,cos((direction%12)*TAU/12))
			var pos:Vector3=body.global_position+side*[0.80,1.35,2.05][floori(direction/12.0)]
			pos.y=maxf(s.stream.ground_at(pos)+0.07,body.global_position.y-0.15)
			s.player.global_position=pos
			s.player.camera.look_at(body.global_position)
			var target:Object=s._interaction_trace().get("collider")
			if target: evidence[str(target.get_meta("kind",""),"/",target.name)]=true
			if target==body:
				s._use()
				if s.loot_target==body: s._tick_loot(s.loot_full+0.01)
				found=s.chest_key()==body.get_meta("key") and not s.chest_view(s.chest_key()).items.is_empty()
				evidence["stock"]=s.chest_view(s.chest_key()).get("items",{})
				s.chest_close(s.chest_key())
				if found: break
		if not found:
			print("unreachable ",id," at ",body.global_position," seed ",s.stream.generator.seed_value," ",evidence)
			return false
	return true

func run()->void:
	WastelandSave.root_override="user://verification/procedural-cache-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/settings.cfg"
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.start_id="shore"
	var quantities:={}
	var floors:={}
	var profiles:={}
	var signatures:={}
	var underwater:={}
	for seed_value:int in [67,191,522,803,1201,2451]:
		cfg.seed=seed_value
		app._enter_world(cfg,{},1,false)
		var s:WastelandSession=app.session
		s.simulation_paused=true
		var c:=precinct(s)
		await physics_frame
		await physics_frame
		var rows:=signature(c)
		signatures[hash(rows)]=true
		quantities[rows.size()]=true
		var reachable:=true
		for id:String in rows:
			var body:StaticBody3D=c.supply_caches[id].get_parent()
			if body.get_meta("quest",false): continue
			floors[body.get_meta("cache_floor")]=true
			profiles[body.get_meta("cache_profile")]=true
			var approach:Vector3=body.get_meta("cache_approach")
			var feet:=approach+Vector3.UP*0.18
			s.player.global_position=feet
			s.player.camera.look_at(body.global_position)
			var hit:=s._interaction_trace()
			var floor_hit:=s.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.2,feet+Vector3.DOWN*.6,2))
			reachable=reachable and hit.get("collider")==body and not floor_hit.is_empty()
		check(reachable,"seed %d ordinary boxes can be aimed at from supported room floor"%seed_value)
		var key:=c.object_key("container/0")
		var first:StaticBody3D=c.supply_caches[key].get_parent()
		var stored:=first.get_meta("cache_approach") as Vector3
		s.player.global_position=stored+Vector3.UP*.18
		s.player.camera.look_at(first.global_position)
		s._use()
		# Ordinary boxes take a short held search before opening.
		if s.loot_target==first: s._tick_loot(s.loot_full+0.01)
		check(s.chest_key()==key and not s.chest_view(key).items.is_empty(),"the precinct's specialty chest opens from its approach")
		s.bag.add("stick",2)
		s.ui_command("chest_put",[key,"stick",2])
		var cargo:Dictionary=s.chest_view(key).items.duplicate()
		s.ui_command("chest_close",[key])
		var wrecks:=WastelandSunkenSites.landmarks(s.stream.generator)
		var origin:Vector3=wrecks.ferry
		s.stream.ensure_landing(origin)
		var wc:WastelandChunk=s.stream.active[WastelandTerrainGen.chunk_at(Vector2(origin.x,origin.z))]
		var wreck_body:StaticBody3D=wc.supply_caches[wc.object_key("submerged/ferry")].get_parent()
		underwater[hash(wreck_body.global_position-origin)]=true
		check(await check_wreck_approaches(s,wrecks),"all three salvage boxes open using an actual underwater approach")
		check(wreck_body.global_position.y< -0.5 and wreck_body.get_meta("submerged_site")=="ferry","ferry retains submerged salvage identity")
		check(s.save_now(false)==OK,"save generated storage")
		var saved:=WastelandSave.read(1)
		app._enter_world(saved.settings,saved,1,false)
		s=app.session
		s.simulation_paused=true
		c=precinct(s)
		check(signature(c)==rows,"disk reload preserves every box location, orientation, profile and finish")
		first=c.supply_caches[key].get_parent()
		s.player.global_position=stored+Vector3.UP*.18
		s._open_loot(first)
		s.ui_command("chest_take",[key,"stick",1])
		check(s.bag.count("stick")==1 and int(s.chest_view(key).items.stick)==int(cargo.stick)-1,"reloaded stock retains player deposit and withdraws exactly one")
		s.ui_command("chest_close",[key])
	check(quantities.size()>1 and floors.size()>1 and signatures.size()==6 and profiles.size()>1 and underwater.size()>1,"multiple seeds vary counts, floors, regional forms and salvage positions")
	cfg.seed=27491
	cfg.loot=0.5
	app._enter_world(cfg,{},1,false)
	app.session.simulation_paused=true
	check_building_stock(app.session)
	cfg.site_revision=0
	app._enter_world(cfg,{},1,false)
	var c:=precinct(app.session)
	var old_body:StaticBody3D=c.supply_caches[c.object_key("container/0")].get_parent()
	check(is_equal_approx(old_body.position.x,12.6) and is_equal_approx(old_body.position.z,13.36) and old_body.rotation.y==0 and old_body.get_meta("finish_variant")==0 and c.supply_caches.has(c.object_key("container/99")),"legacy boxes retain exact positions, IDs and unmodified appearance")
	check_building_stock(app.session)
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.free()
	print("PROCEDURAL CHESTS failures=",fails," counts=",quantities.keys()," floors=",floors.keys()," profiles=",profiles.keys())
	quit(1 if fails else 0)

func check_building_stock(s: WastelandSession) -> void:
	var gen := s.stream.generator
	var cells := WastelandTerrainGen.FIXED.duplicate()
	var found := {}
	for site: String in cells.values(): found[site] = true
	for z in range(-20,21):
		for x in range(-20,21):
			var pos := Vector2i(x,z)
			var site := gen.site_for(pos)
			if site != "" and not found.has(site):
				cells[pos] = site
				found[site] = true
		if found.size() == s.catalog.sites.size(): break
	var stations: Dictionary = s.catalog.sites.lodge.outpost_loots
	for district: String in stations:
		if district == "outpost": continue
		cells[gen.starting_outpost(district)] = district
	for pos: Vector2i in gen.nearby_outposts(Vector2.ZERO):
		if not cells.has(pos):
			cells[pos] = "outpost"
			break
	check(found.size() == s.catalog.sites.size() and cells.values().has("outpost"),
		"generated sample includes all ten buildings and three inland stations")
	for pos: Vector2i in cells:
		var place: String = cells[pos]
		var definition: Dictionary = s.catalog.sites.lodge if stations.has(place) else s.catalog.sites[place]
		var ordinary: Array = stations.get(place,definition.loots)
		var at := Vector2(pos * WastelandTerrainGen.SIZE) + Vector2(16,16)
		s.stream.ensure_landing(Vector3(at.x,0,at.y))
		var chunk: WastelandChunk = s.stream.active[pos]
		var checked := 0
		var valid := true
		var has_archive := false
		for key: String in chunk.supply_caches:
			var slot := key.get_slice(":",1)
			if not slot.begins_with("container/") and slot != "nest/deep": continue
			var body: StaticBody3D = chunk.supply_caches[key].get_parent()
			var table: String = body.get_meta("type")
			var quest := slot == "container/99"
			valid = valid and bool(body.get_meta("quest",false)) == quest
			if quest:
				has_archive = true
				valid = valid and table == definition.get("archive_loot","")
			elif slot == "nest/deep": valid = valid and table == definition.get("deep_loot","")
			elif slot == "container/0": valid = valid and table == ordinary[0]
			else: valid = valid and table in ordinary
			s.player.global_position = body.global_position + Vector3.BACK
			s._open_loot(body)
			var view := s.chest_view(key)
			var contents: Dictionary = view.get("items",{})
			var stage := 2 + (int(definition.tier) - 1) * 6 if gen.site_revision > 0 else s.hordes.stage()
			var allowed := {}
			for row: Array in s.catalog.loot[table].items:
				if stage >= int(row[4]): allowed[row[0]] = true
			if quest: allowed["beacon_log"] = true
			var box_ok: bool = body.get_meta("building_cache",false) and not contents.is_empty() and allowed.has_all(contents.keys()) and contents.get("beacon_log",0) == int(quest)
			box_ok = box_ok and s.catalog.loot[table].name in view.get("title","")
			var staples: Array = s.catalog.loot[table].get("staples",[])
			if not staples.is_empty(): box_ok = box_ok and staples.any(func(item): return contents.has(item))
			if not box_ok: printerr("Bad chest ",key," ",table," ",contents)
			valid = valid and box_ok
			checked += 1
			s.chest_close(key)
		check(checked > 0 and valid and has_archive == definition.has("archive_loot"), "%s rev %d opens %d containers with site stock, valid stage and correct quest log" % [place,gen.site_revision,checked])
