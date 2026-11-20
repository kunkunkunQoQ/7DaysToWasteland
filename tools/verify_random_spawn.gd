extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: print("PASS ",message)
	else:
		printerr("FAIL ",message)
		failures+=1

func run() -> void:
	var regions := {}
	var positions := {}
	var safe := true
	for seed_value in [481516,60347,75129]:
		var gen := WastelandTerrainGen.new(seed_value)
		for roll in 16:
			var at := gen.wilderness_start(roll)
			var cell := gen.chunk_at(at)
			regions[gen.region_kind(at.x,at.y)] = true
			positions[at] = true
			var y := gen.ground(at.x,at.y)
			for i in 24:
				var p := at+Vector2.from_angle(TAU*i/24.0)*3
				safe = safe and not gen.water_basin(p.x,p.y) and gen.ground(p.x,p.y)>0.4 and absf(gen.ground(p.x,p.y)-y)<1.05
			for z in range(-3,4):
				for x in range(-3,4):
					var c := cell+Vector2i(x,z)
					if gen.site_for(c)!="": safe = safe and at.distance_to(Vector2(c*32)+Vector2(16,16))>=77
		check(gen.wilderness_start(0)==WastelandTerrainGen.new(seed_value).wilderness_start(0),"saved roll reproduces location for terrain seed %d"%seed_value)
	check(safe and positions.size()==48,"48 starts have stable dry footing and clearance from buildings")
	check(regions.size()>=5,"biomes sampled "+str(regions.keys()))
	WastelandSave.root_override="user://verification/random-spawn-%d"%OS.get_process_id()
	var app: Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	var cfg: Dictionary=app._default_config()
	app._enter_world(cfg,{},1,false)
	var first: Vector2=app.session.stream.generator.wild_start
	app._enter_world(cfg,{},1,false)
	var s: WastelandSession=app.session
	s.simulation_paused=true
	var start := s.start_position()
	var original := s.stream.generator.wild_start
	check(first==original and start.distance_to(s.player.position)<0.4,"two independent new worlds with the same seed reproduce the safe starting point")
	await physics_frame
	var query:=PhysicsShapeQueryParameters3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=0.38
	capsule.height=1.8
	query.shape=capsule
	query.exclude=[s.player.get_rid()]
	query.transform.origin=start+Vector3.UP
	check(s.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"standing capsule is clear at the actual loaded spawn")
	var gathered:={}
	for c: WastelandChunk in s.stream.active.values():
		for node in c.decoration_root.get_children():
			if node.get_meta("kind","")=="resource" and node.global_position.distance_to(start)<6:
				var id: String=node.get_meta("resource")
				gathered[id]=1+int(gathered.get(id,0))
	check(gathered.get("fallen_stick",0)>=1 and gathered.get("pebble",0)>=2 and gathered.get("grass",0)>=2,"physical stone axe materials within six metres")
	s.player.position=start+Vector3(11,3,4)
	var last := s.player.position
	check(s.save_now(false)==OK,"wild start saved")
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	check(s.stream.generator.wild_start==original and s.player.position.distance_to(last)<0.1,"reload restores last player position and original origin separately")
	s.respawn()
	check(s.player.position.distance_to(start)<0.4,"revival returns to this world's original clearing")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
