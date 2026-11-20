extends "res://tools/verify_game.gd"

# Each seed uses the normal random start roll and an empty bag.
const WORLD_SEEDS := [481516,75129,120840,-9251,182,101]

func _prepare() -> void:
	WastelandSave.root_override = "user://verification/wilderness-supplies-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	await process_frame
	var habitats := {}
	for world_seed: int in WORLD_SEEDS:
		var config: Dictionary = app._default_config()
		config.seed = world_seed
		app._enter_world(config,{},1,false)
		session = app.session
		session.simulation_paused = true
		session.stream.set_process(false)
		var start := session.start_position()
		var gen := session.stream.generator
		var habitat := gen.region_kind(start.x,start.z)
		habitats[habitat] = true
		for z in range(-1,2):
			for x in range(-1,2):
				session.stream.ensure_landing(start + Vector3(x*32,0,z*32))
		await physics_frame
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.38
		capsule.height = 1.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.exclude = [session.player.get_rid()]
		q.transform.origin = start + Vector3.UP
		_assert(session.bag.counts.is_empty() and not session.stream.water_at(start) and session.get_world_3d().direct_space_state.intersect_shape(q).is_empty(),"dry, clear, empty-handed spawn %d / %s" % [world_seed,habitat])
		var food_distance := await verify_provisions(start)
		var water := nearest_water(start)
		var water_distance := Vector2(start.x,start.z).distance_to(water)
		_assert(water.is_finite(),"natural water found near seed %d" % world_seed)
		if water.is_finite(): await boil_water(start,water)
		if habitat=="canyon": await verify_deposit(start,"ore","lead")
		if habitat=="marsh" and water.is_finite():
			await verify_deposit(Vector3(water.x,0,water.y),"clay_bank","clay")
		session.player.position = start
		var board: Vector2 = session.board_destination().at
		var lodge := Vector3(board.x,0,board.y)
		session.stream.ensure_landing(lodge)
		var site: WastelandChunk = session.stream.active[WastelandTerrainGen.chunk_at(board)]
		_assert(site.fixtures.has(site.object_key("trader")),"campaign destination has a physical board")
		session.player.position = lodge
		var beacon: Vector2 = session.beacon_destination().at
		session.stream.ensure_landing(Vector3(beacon.x,0,beacon.y))
		var archive: WastelandChunk = session.stream.active[WastelandTerrainGen.chunk_at(beacon)]
		var key := archive.object_key("container/99")
		var chest: Node3D = archive.supply_caches.get(key)
		if chest:
			var body: StaticBody3D = chest.get_parent()
			session.player.position = body.global_position + Vector3.BACK
			session._open_loot(body)
			_assert(session.chest_view(key).get("items",{}).get("beacon_log",0)>0,"indicated archive stocks the final beacon record")
		else:
			_assert(false,"indicated archive exists")
		print("ROUTE seed=%d region=%s food=%.1fm raw_water=%.1fm spawn_to_board=%.1fm board_to_archive=%.1fm" % [world_seed,habitat,food_distance,water_distance,Vector2(start.x,start.z).distance_to(board),board.distance_to(beacon)])
		await session.stream.quiesce()
		await session.audio.finish_playback()
	_assert(habitats.size()==6,"exercise all six wilderness starting regions")
	app.queue_free()
	await process_frame
	print("WILDERNESS SUPPLIES passed=%d failed=%d" % [passed,failures.size()])
	for failure in failures: printerr("FAIL ",failure)
	quit(1 if not failures.is_empty() else 0)

func verify_provisions(start: Vector3) -> float:
	var max_distance := 0.0
	for source: String in ["fallen_stick","pebble","pebble","grass","grass"]:
		session.player.position = start
		var node := _aim_at_resource([source])
		if not node: continue
		max_distance = maxf(max_distance,start.distance_to(node.global_position))
		session._use()
		await physics_frame
		if source=="grass": await pick_material("fiber")
	_assert(max_distance<6 and session.bag.has_all(session.catalog.recipes.stone_axe.inputs),"pick all first axe ingredients within six metres: %.1fm, %s" % [max_distance,session.bag.counts])
	craft_by_hand("stone_axe")
	session.ui_command("assign",["stone_axe"])
	_assert(session.bag.current()=="stone_axe","craft and equip the first stone axe")
	for source: Array in [["oak","pine"],["boulder"]]:
		session.player.position = start
		var target := _aim_at_resource(source)
		if target: await harvest(target)
		for frame in 420:
			if session.timber.active.is_empty(): break
			session.timber.tick(1.0/60.0)
		await physics_frame
		await pick_material("wood" if source.size()==2 else "stone")
	_assert(session.bag.has_all({"wood":5,"stone":8}),"fell local timber and break stone for fire and boiling")
	craft_by_hand("campfire")
	session.player.position = start
	var food := _aim_at_resource(["brush","cactus"])
	if not food:
		_assert(false,"edible forage near spawn")
		return INF
	var distance := start.distance_to(food.global_position)
	var item := "berries" if food.get_meta("resource")=="brush" else "cactus_fruit"
	await harvest(food)
	await pick_material(item)
	session.player.hunger = 50
	session.ui_command("consume",[item])
	_assert(distance<48 and session.player.hunger>50,"harvest and eat local fruit within 48 metres")
	return distance

func harvest(target: StaticBody3D) -> void:
	var hit: Dictionary = session.catalog.items.get(session.bag.current(),{})
	for strike in 10:
		if target.is_queued_for_deletion(): return
		session._melee(hit,1.0)
		await physics_frame
		if not is_instance_valid(target): return

func pick_material(id: String) -> void:
	for i in 4:
		if not _aim_at_resource([id+"_drop"]): return
		session._use()
		await physics_frame

func craft_by_hand(id: String) -> void:
	session.ui_command("craft",[id,1,null])
	session.clock.advance(float(session.catalog.recipes[id].seconds)+0.1)
	session._finish_crafting()

func verify_deposit(at: Vector3, source: String, product: String) -> void:
	for z in range(-1,2):
		for x in range(-1,2):
			session.stream.ensure_landing(at+Vector3(x*32,0,z*32))
	await physics_frame
	session.player.position = at
	var target := _aim_at_resource([source])
	var before := session.bag.count(product)
	if target:
		var products: Dictionary = WastelandSession.RESOURCES[source][2]
		await harvest(target)
		var drops: Array = products.keys().map(func(id): return id+"_drop")
		for i in products.size():
			if not _aim_at_resource(drops): break
			session._use()
			await physics_frame
	_assert(session.bag.count(product)>before,"harvest %s from a generated %s with the crafted axe" % [product,source])

func nearest_water(start: Vector3) -> Vector2:
	var gen := session.stream.generator
	var origin := Vector2(start.x,start.z)
	var nearest := Vector2.INF
	var best := INF
	for z in range(-448,449,12):
		for x in range(-448,449,12):
			var offset := Vector2(x,z)
			if offset.length_squared()>=best: continue
			var point := origin + offset
			if gen.ground(point.x,point.y)<-0.25 and gen.water_basin(point.x,point.y):
				nearest = point
				best = offset.length_squared()
	return nearest

func boil_water(start: Vector3, water: Vector2) -> void:
	var at := Vector3(water.x,0,water.y)
	session.stream.ensure_landing(at)
	session.player.position = at + Vector3.UP*0.1
	await physics_frame
	session.player.camera.look_at(at+Vector3.FORWARD*0.4)
	session.action_lock = 0
	session._use()
	_assert(session.bag.count("dirty_water")==1,"draw natural water through the interaction ray")
	session.player.position = start
	for z in range(-3,4):
		for x in range(-3,4):
			var p := start + Vector3(x,0,z)
			var cell := Vector3i(floori(p.x),ceili(session.stream.ground_at(p)-0.42),floori(p.z))
			if not session.construction.place(cell,"campfire",0,0,start): continue
			session.ui_command("feed_fire",[cell,"wood"])
			session.ui_command("enable",[cell])
			session.ui_command("craft",["clean_water",1,cell])
			session.clock.advance(7.0)
			session.construction.simulate(7.0)
			session.ui_command("collect",[cell])
			session.player.hydration = 50
			session.ui_command("consume",["clean_water"])
			_assert(session.player.hydration==84 and session.bag.count("dirty_water")==0,"boil and drink collected water at a crafted campfire")
			return
	_assert(false,"place the crafted campfire")

