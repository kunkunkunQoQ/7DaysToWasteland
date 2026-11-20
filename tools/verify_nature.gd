extends "res://tools/verify_harvest.gd"

func run() -> void:
	WastelandSave.root_override="user://verification/scenery-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.seed=2817
	config.terrain_revision=2
	open_world({})
	var harvested := {}
	var tested := 0
	var started := Time.get_ticks_usec()
	for coord: Vector2i in [Vector2i(-1,1),Vector2i(0,1),Vector2i(0,0),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,-1)]:
		var chunk := load_chunk(coord)
		var count := chunk.small_nature.size()
		check(chunk.aim_bodies.is_empty(),"unexamined scenery creates zero physics bodies")
		for key: String in chunk.small_nature.keys():
			if not chunk.small_nature.has(key): continue
			var row: Dictionary=chunk.small_nature[key]
			var point: Vector3 = row.bounds.get_center()+chunk.position
			var hit := chunk.trace_nature(point+Vector3.UP*2.0,point-Vector3.UP*2.0)
			if hit.is_empty(): continue
			tested+=1
			var body: StaticBody3D=hit.collider
			var kind: String=body.get_meta("resource")
			if harvested.has(kind): continue
			var target: String=body.get_meta("index")
			var product: String=WastelandSession.RESOURCES[kind][2].keys()[0]
			var before:=session.bag.count(product)
			var model: Dictionary=chunk.small_nature[target]
			if kind=="bedrock":
				session.bag.add("stone_axe",1)
				session.bag.assign("stone_axe",0)
			else:
				session.bag.assign("",0)
			strike(body,1000,1 if kind=="bedrock" else 0)
			check(session.bag.count(product)>before and not chunk.small_nature.has(target),"harvest "+kind)
			for batch: MultiMeshInstance3D in chunk.instances[model.group]:
				if DisplayServer.get_name()=="headless": continue
				check(batch.multimesh.get_instance_transform(model.instance).basis.x.length()<0.001,"harvest hides batch slot "+kind)
			harvested[kind]=[coord,target]
			strike(body,1000,1)
			check(session.stream.chunk_diff(coord).removed.has(target),"stable deletion "+kind)
		check(chunk.aim_bodies.size()<=4 and chunk.small_nature.size()<=count,"selection proxies bounded per chunk")
	var played := false
	for coord: Vector2i in session.stream.active:
		var chunk: WastelandChunk = session.stream.active[coord]
		for key: String in chunk.small_nature:
			var record: Dictionary = chunk.small_nature[key]
			if record.resource!="grass": continue
			var target: Vector3 = record.bounds.get_center()+chunk.position
			session.player.global_position=target+Vector3.BACK*0.22
			session.player.camera.global_position = target+Vector3(0,1.5,0.22)
			session.player.camera.look_at(target)
			var focus := session._interaction_trace()
			if not focus.has("collider") or focus.collider.get_meta("index","")!=key: continue
			session.bag.assign("",0)
			var initial := session.bag.count("fiber")
			var old_drops := session.fx.drop_records.keys()
			session._melee({},1)
			var released := session.fx.drop_records.keys().filter(func(id): return not old_drops.has(id) and session.fx.drop_records[id].items.get("fiber",0)==1)
			var uprooted := released.size()==1 and session.bag.count("fiber")==initial and not chunk.small_nature.has(key)
			session.fx.collect_nearby()
			played = uprooted and session.bag.count("fiber")==initial+1
			break
		if played: break
	check(played,"crosshair focus and normal empty-hand melee uproot a grass clump")
	check(harvested.size()==7 and tested>=160,"shore, land and submerged varieties covered "+str(harvested.keys()))
	print("Scenery rays with hits: ",tested,"; six installations plus harvest and ray workload in ms: ",(Time.get_ticks_usec()-started)/1000)
	check(session.save_now(false)==OK,"save actual harvesting")
	var snapshot:=WastelandSave.read(1)
	var delta:=session.stream.diffs.duplicate(true)
	await close_world()
	open_world(snapshot)
	for row: Array in harvested.values():
		check(not load_chunk(row[0]).small_nature.has(row[1]),"reinstalled chunk honors saved deletion")
	await close_world()
	open_world({})
	for row: Array in harvested.values():
		check(load_chunk(row[0]).small_nature.has(row[1]),"pristine replica has same deterministic slot")
	session.stream.mirror_deltas(delta,{})
	for row: Array in harvested.values():
		check(not load_chunk(row[0]).small_nature.has(row[1]),"active replica removed matching unexamined instance")
	await close_world()
	print("NATURE QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)

func load_chunk(coord: Vector2i) -> WastelandChunk:
	if not session.stream.active.has(coord):
		session.stream._install(coord,session.stream.generator.build(coord,{}))
	return session.stream.active[coord]
