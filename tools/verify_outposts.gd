extends SceneTree

var app: Node
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if ok: print("PASS ",what)
	else:
		printerr("FAIL ",what)
		failures += 1

func _run() -> void:
	WastelandSave.root_override = "user://verification/outpost-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	app.front.creation()
	var picker: OptionButton = app.front.shell.find_child("StartingOutpost",true,false)
	check(picker==null and app._default_config().start_id=="random","creation defaults to wilderness without station picker")
	await process_frame
	var cfg: Dictionary = app._default_config()
	for id: String in WastelandSite.STARTS:
		cfg.start_id = id
		app._enter_world(cfg,{},1,false)
		var s: WastelandSession = app.session
		s.simulation_paused = true
		var start := s.start_position()
		var cell := WastelandTerrainGen.chunk_at(Vector2(start.x,start.z))
		var chunk: WastelandChunk = s.stream.active[cell]
		check(chunk.site=="lodge" and cell!=WastelandSite.SHORE_CELL and start.y>0 and s.player.position.distance_to(start)<0.40,id+" dry spawn beside inland lodge")
		check(s.bag.counts.is_empty() and s.bag.current()=="" and s.bag.gear.values().all(func(item): return item==""),id+" empty starter inventory")
		var resources := {}
		for body in chunk.decoration_root.get_children():
			if body.get_meta("kind","")=="resource" and body.global_position.distance_to(start)<14.0:
				resources[body.get_meta("resource")] = body
		check(resources.has("fallen_stick") and resources.has("pebble") and resources.has("grass"),id+" loose starter materials within walking distance")
		var board: Vector2 = s.board_destination().at
		check(board.is_equal_approx(WastelandSite.board_at(cell)) and app.hud.destination().at==board,id+" local compass points to the lodge board")
		var nearby_board := chunk.decoration_root.get_children().filter(func(node):return node.get_meta("kind","")=="trader")
		check(nearby_board.size()==1 and Vector2(nearby_board[0].global_position.x,nearby_board[0].global_position.z).distance_to(board)<0.1,id+" generated physical board matches navigation")
		s.player.position=nearby_board[0].global_position
		s.ui_command("job")
		check(s.progress.accepted,id+" local board accepts campaign")
		s.progress.job=5
		var beacon: Vector2 = s.beacon_destination().at
		var target := WastelandTerrainGen.chunk_at(beacon)
		s.stream.ensure_landing(Vector3(beacon.x,0,beacon.y))
		var site: WastelandChunk = s.stream.active[target]
		var key := site.object_key("container/99")
		check(site.supply_caches.has(key) and beacon.distance_to(board)<256,id+" regional signal archive within 256 meters")
		if site.supply_caches.has(key):
			preload("res://tools/chest_actions.gd").take_all(s,site.supply_caches[key].get_parent())
			s.ui_command("job")
			check(s.progress.finish_day>0 and app.panels.active=="ending",id+" local final signal delivered")
		await process_frame
		s.respawn()
		check(s.player.position.distance_to(start)<0.4,id+" respawn returns to original station")
		s.save_now(false)
		var saved := WastelandSave.read(1)
		app._enter_world(saved.settings,saved,1,false)
		check(app.session.start_name()==WastelandSite.STARTS[id] or id=="seeded",id+" chosen station survives reopening")
	var journey: WastelandSession = app.session
	var expedition := Vector2(18400,-12200)
	journey.player.position = Vector3(expedition.x,40,expedition.y)
	var nearest := INF
	for cell: Vector2i in journey.stream.generator.nearby_outposts(expedition):
		nearest=minf(nearest,expedition.distance_to(WastelandSite.board_at(cell)))
	var remote_target: Vector2 = journey.board_destination().at
	check(is_equal_approx(nearest,expedition.distance_to(remote_target)),"expedition 22 km away routes to a regional outpost")
	for version in [1,2]:
		cfg.terrain_revision=version
		app._enter_world(cfg,{},1,false)
		var start: Vector3=app.session.start_position()
		check(Vector2(start.x,start.z)==WastelandTerrainGen.START,"legacy version %d keeps south shore spawn"%version)
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	await process_frame
	app.queue_free()
	await process_frame
	var stop := Time.get_ticks_msec()+450
	while Time.get_ticks_msec()<stop: await process_frame
	quit(1 if failures else 0)
