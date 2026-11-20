extends SceneTree

const Chest := preload("res://game/art/supply_chest.gd")
const LAND := ["shore","forest","ridge","ash","town"]
const FRONTIER := ["alpine","desert"]
const WRECKS := ["ferry","pump","bridge"]
var failures := 0
var passed := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS ",message)
	else:
		failures += 1
		printerr("FAIL ",message)

func _label(parent: Node3D, content: String, point: Vector3, pixels: int, color: Color) -> void:
	var text := Label3D.new()
	text.text = content
	text.font = WastelandUIStyle.FONT
	text.font_size = pixels
	text.pixel_size = 0.0028
	text.modulate = color
	text.outline_size = 0
	text.position = point
	parent.add_child(text)

func _gallery() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1800,1350)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	root.add_child(view)
	var scene := Node3D.new()
	view.add_child(scene)
	var cam := Camera3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#203838")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e0ecdb")
	env.ambient_light_energy = 0.76
	cam.environment = env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.42
	cam.position = Vector3(0,0,11)
	scene.add_child(cam)
	var key := DirectionalLight3D.new()
	scene.add_child(key)
	key.rotation_degrees = Vector3(-40,22,0)
	key.light_color = Color("#ffe8be")
	key.light_energy = 1.08
	var fill := DirectionalLight3D.new()
	scene.add_child(fill)
	fill.rotation_degrees = Vector3(-25,152,0)
	fill.light_color = Color("#a2cbd0")
	fill.light_energy = 0.54
	for row in 3:
		var ids: Array = [LAND,FRONTIER,WRECKS][row]
		var y := 2.14-row*2.14
		_label(scene,["陆地补给","内陆专属补给","水下打捞"][row],Vector3(0,y+0.78,0),52,Color("#dfc59b"))
		for i in ids.size():
			var id: String = ids[i]
			var x := (float(i)-(ids.size()-1)*0.5)*(1.49 if row==0 else 1.95)
			var box := Chest.new()
			scene.add_child(box)
			box.configure(id,id+("_salvage" if row==2 else "_cache"))
			box.show_state(0,false)
			box.rotation = Vector3(0.26,-0.38,0.0)
			box.position = Vector3(x,y,0)
			_label(scene,Chest.NAMES[id],Vector3(x,y-(0.86 if row==1 else 0.65),0),38,Color("#e6eee4"))
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://build/qa/regional-chests.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	_check(view.get_texture().get_image().save_png(path)==OK,"ten chest models photographed")
	view.queue_free()

func _geometry(gen: WastelandTerrainGen) -> void:
	var signatures := {}
	var mapped := {}
	for z in range(-600,601,17):
		for x in range(-600,601,17):
			var point := Vector3(x,0,z)
			var index := gen.biome(x,z)
			if Chest.kind_at(gen,point)==LAND[index]:
				mapped[LAND[index]] = true
	for id: String in LAND+FRONTIER+WRECKS:
		var model := Chest.new()
		model.configure(id,id+"_cache" if id not in WRECKS else id+"_salvage")
		var signature := []
		for piece: MeshInstance3D in model.get_children():
			var vertices: PackedVector3Array = piece.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			signature.append(hash(vertices))
		if id not in WRECKS: signatures[hash(signature)] = true
		for state in 3:
			model.set_opened(true,false)
			model.show_state(state,false)
			_check(model.last_state==state and model.stores.visible==(state==1),id+" state "+str(state))
		model.free()
	_check(mapped.size()==5 and Chest.BIOME_KEYS==LAND,"all five biome indices map to encountered regions")
	_check(signatures.size()==7,"seven different land mesh geometries excluding color and scale")

func _scatter(session: WastelandSession) -> void:
	var stream := session.stream
	for i in range(1,5000):
		var cell := Vector2i(i%65-32, floori(i/65.0)-30)
		var rng := RandomNumberGenerator.new()
		rng.seed = stream.generator.seed_at(cell,7819)
		if rng.randf()>0.1 or stream.generator.ground(cell.x*32+16,cell.y*32+16)<1: continue
		var pos := Vector3(cell.x*32+16,0,cell.y*32+16)
		stream.ensure_landing(pos)
		var chunk: WastelandChunk = stream.active[cell]
		var key := chunk.object_key("wilderness/supply")
		if not chunk.supply_caches.has(key): continue
		var body: StaticBody3D = chunk.supply_caches[key].get_parent()
		var profile := Chest.kind_at(stream.generator,body.global_position)
		_check(body.get_meta("cache_profile")==profile and body.get_meta("type")==profile+"_cache","wilderness chest uses actual biome and supply table")
		var clone := WastelandChunk.new()
		stream.add_child(clone)
		clone.install(stream,cell,stream.generator.build(cell,{}))
		_check(clone.supply_caches.has(key) and clone.supply_caches[key].get_parent().transform.is_equal_approx(body.transform),"same seed reproduces wilderness key, location and angle")
		clone.free()
		return
	_check(false,"wilderness supply spawned")

func _gameplay() -> void:
	WastelandSave.root_override = "user://verification/chests-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	var app: Node = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg: Dictionary = app._default_config()
	cfg.terrain_revision=2 # Historic Gray Bay coastal fixture.
	cfg.loot_days = 2
	var cell := Vector2i(-1,1)
	var key := "-1,1:container/0"
	var original := {"items":{"wood":4},"next":4,"earned":true}
	app._enter_world(cfg,{"diffs":{"-1,1":{"containers":{key:original}}}},2,false)
	var session: WastelandSession = app.session
	session.stream.ensure_landing(Vector3(-16,0,48))
	var chunk: WastelandChunk = session.stream.active[cell]
	if not chunk.supply_caches.has(key):
		_check(false,"legacy cabin chest exists")
		app.free()
		return
	var model: Node3D = chunk.supply_caches[key]
	var body: StaticBody3D = model.get_parent()
	var record: Dictionary = session.stream.chunk_diff(cell).containers[key]
	_check(model.name=="SupplyChest" and record==original and model.last_state==1,"legacy stable key restores original items and visual state")
	session.bag.counts = {"wood":session.bag.stack_size("wood")*session.bag.capacity()-2}
	preload("res://tools/chest_actions.gd").take_all(session,body)
	_check(record.items=={"wood":2} and model.last_state==1,"partial transfer leaves exact remainder")
	_check(session.save_now(false)==OK and WastelandSave.read(2).diffs["-1,1"].containers[key].items=={"wood":2},"partial remainder survives disk serialization")
	session.bag.counts.clear()
	preload("res://tools/chest_actions.gd").take_all(session,body)
	_check(record.items.is_empty() and session.bag.counts=={"wood":2} and model.last_state==2,"empty state transfers last two units")
	preload("res://tools/chest_actions.gd").take_all(session,body)
	_check(session.bag.counts=={"wood":2},"no duplicate reward on immediate reopen")
	_geometry(session.stream.generator)
	_scatter(session)
	var sites := WastelandSunkenSites.landmarks(session.stream.generator)
	var submerged: Array[StaticBody3D] = []
	for id: String in WRECKS:
		var pos: Vector3 = sites[id]
		session.stream.ensure_landing(pos)
		var site_cell := WastelandTerrainGen.chunk_at(Vector2(pos.x,pos.z))
		var site_chunk: WastelandChunk = session.stream.active[site_cell]
		var site_key := site_chunk.object_key("submerged/"+id)
		var chest: StaticBody3D = site_chunk.supply_caches[site_key].get_parent()
		_check(chest.get_meta("cache_profile")==id and chest.get_meta("type")==id+"_salvage",id+" stable wreck key and table")
		session.bag.counts.clear()
		preload("res://tools/chest_actions.gd").take_all(session,chest)
		_check(not session.bag.counts.is_empty() and session.progress.records.has("recover_"+id),id+" field recovery recorded")
		submerged.append(chest)
	session.clock.hours += 120
	session.stream.advance_loot_day(session.clock.day())
	_check(model.last_state==0,"eligible empty land chest closes when refill day arrives")
	session.bag.counts.clear()
	preload("res://tools/chest_actions.gd").take_all(session,body)
	_check(not session.bag.counts.is_empty() and session.stream.chunk_diff(cell).containers[key].next==session.clock.day()+2,"land chest issues refreshed supplies and advances deadline")
	for chest in submerged:
		session.bag.counts.clear()
		preload("res://tools/chest_actions.gd").take_all(session,chest)
		_check(session.bag.counts.is_empty() and chest.get_node("SupplyChest").last_state==2,"wreck stays empty after multiple days")
	_check(session.save_now(false)==OK,"session serialized")
	var saved := WastelandSave.read(2)
	_check(saved.diffs==session.stream.diffs,"land and underwater records round trip through disk")
	app._enter_world(cfg,saved,2,false)
	session = app.session
	session.stream.ensure_landing(Vector3(-16,0,48))
	_check(session.stream.active[cell].supply_caches[key].last_state==2,"fresh session restores empty chest from disk")
	session.simulation_paused = true
	await session.stream.quiesce()
	app._remove_session()
	app.queue_free()
	await process_frame

func _frontier_caches()->void:
	var app:Node=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg:Dictionary=app._default_config()
	cfg.seed=40917
	cfg.terrain_revision=3
	cfg.loot_days=0
	app._enter_world(cfg,{},3,false)
	var session:WastelandSession=app.session
	var stream:=session.stream
	var found:Dictionary={}
	for z in range(-70,71):
		for x in range(-22,23):
			if found.size()==2: break
			var cell:=Vector2i(x,z)
			var mid:=Vector3(x*32+16,0,z*32+16)
			var region:=stream.generator.region_kind(mid.x,mid.z)
			if region not in FRONTIER or found.has(region) or stream.generator.site_for(cell)!="": continue
			var rng:=RandomNumberGenerator.new()
			rng.seed=stream.generator.seed_at(cell,7819)
			if rng.randf()>0.14: continue
			stream.ensure_landing(mid)
			var chunk:WastelandChunk=stream.active[cell]
			var key:=chunk.object_key("wilderness/supply")
			if not chunk.supply_caches.has(key): continue
			var model:Node3D=chunk.supply_caches[key]
			var box:StaticBody3D=model.get_parent()
			if box.get_meta("cache_profile")!=region: continue
			found[region]={"cell":cell,"key":key,"at":box.global_position}
			var table:=region+"_cache"
			_check(box.get_meta("type")==table and session._cache_title(box)==Chest.NAMES[region],"actual "+region+" terrain has the correctly named exclusive cache")
			session.bag.counts={"wood":session.bag.stack_size("wood")*session.bag.capacity()}
			preload("res://tools/chest_actions.gd").take_all(session,box)
			var record:Dictionary=stream.chunk_diff(cell).containers[key]
			var goods:Dictionary=record.items.duplicate()
			var allowed:={}
			for row:Array in session.catalog.loot[table].items: allowed[row[0]]=true
			_check(not model.opened and model.last_state==1 and not goods.is_empty() and goods.keys().all(func(id): return allowed.has(id)),"preview opens with region-specific cargo in "+region)
			session.bag.counts.clear()
			preload("res://tools/chest_actions.gd").take_all(session,box)
			preload("res://tools/chest_actions.gd").take_all(session,box)
			_check(session.bag.counts==goods and model.last_state==2 and record.items.is_empty(),"contents transfer exactly once from "+region)
		if found.size()==2: break
	_check(found.size()==2,"both wilderness supply types are found in generated terrain")
	_check(session.save_now(false)==OK,"frontier supply state is written to disk")
	var saved:=WastelandSave.read(3)
	app._enter_world(cfg,saved,3,false)
	session=app.session
	for region:String in found:
		var row:Dictionary=found[region]
		session.stream.ensure_landing(row.at)
		var model:Node3D=session.stream.active[row.cell].supply_caches[row.key]
		_check(model.last_state==2 and not model.stores.visible and session.stream.chunk_diff(row.cell).containers[row.key].earned,"reloaded "+region+" cache preserves empty state with closed lid")
	session.simulation_paused=true
	await session.stream.quiesce()
	app._remove_session()
	app.queue_free()
	await process_frame
	WastelandSave.delete_slot(3)

func _run() -> void:
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		await _gallery()
	else:
		await _gameplay()
		await _frontier_caches()
		var audio_finish := Time.get_ticks_msec()+450
		while Time.get_ticks_msec()<audio_finish: await process_frame
	print("CACHE QA passed=%d failed=%d" % [passed,failures])
	quit(1 if failures else 0)
