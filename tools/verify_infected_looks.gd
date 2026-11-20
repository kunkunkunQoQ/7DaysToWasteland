extends "res://tools/verify_frontier_economy.gd"

const KINDS := ["bloater", "bulwark", "rimecaller", "spitter", "sandrunner"]

func run() -> void:
	WastelandSave.root_override = "user://verification/infected-looks-%d" % OS.get_process_id()
	cfg = WastelandSave.default_world()
	cfg.seed = 2817
	cfg.start_id = "grassland"
	var flags := OS.get_cmdline_user_args()
	if "--host" in flags or "--guest" in flags:
		var port := 19585
		for arg in flags:
			if arg.begins_with("--port="):
				port = int(arg.get_slice("=", 1))
		await verify_network("--host" in flags, port)
		if "--guest" in flags and "--reconnect" in flags:
			await create_timer(0.75).timeout
			await verify_network(false, port)
	else:
		await verify_world()
	print("INFECTED LOOKS QA checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func spawn(kind: String, data: Dictionary) -> WastelandCreature:
	var at := s.player.global_position + Vector3(3, 0, 8)
	s.hordes._spawn(kind, at, false, data)
	return s.hordes.alive.back()

func mesh_shape(actor: WastelandCreature) -> int:
	var shapes := []
	for part: MeshInstance3D in actor.skeleton.find_children("*", "MeshInstance3D", true, false):
		if not part.is_visible_in_tree():
			continue
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			shapes.append([hash(arrays[Mesh.ARRAY_VERTEX]), hash(arrays[Mesh.ARRAY_COLOR])])
	return hash(shapes)

func verify_world() -> void:
	enter()
	var combat_rng := s.hordes.rng.state
	var loot_rng := s.hordes.trophy_rng.state
	for kind: String in KINDS:
		for morph: String in ["", "armored", "swift"]:
			var looks := {}
			var shapes := {}
			var stats := {}
			var pool_ids := {}
			for i in 3:
				var actor := spawn(kind, {"morph":morph, "wardrobe_index":0,"limb_index":0})
				looks[actor.look_index] = true
				shapes[mesh_shape(actor)] = true
				stats[[actor.hp, actor.max_health(), actor.capsule.height, actor.capsule.radius]] = true
				pool_ids[actor.get_instance_id()] = true
				s.hordes.release(actor)
			check(looks.has_all([0,1,2]) and shapes.size() == 3 and stats.size() == 1 and pool_ids.size() == 1,
				"%s/%s cycles three distinct models in one pool slot with identical health and hitbox" % [kind,morph])
	await verify_wardrobes()
	await verify_limbs()
	await verify_faces()
	var batches := {}
	var last := -1
	var distinct_neighbors := true
	for cycle in 15:
		var batch := []
		for pos in 3:
			var individual := spawn("spitter", {"morph":"armored"})
			distinct_neighbors = distinct_neighbors and individual.look_index != last
			last = individual.look_index
			batch.append(last)
			s.hordes.release(individual)
		batches[batch] = true
	check(batches.size() >= 3 and distinct_neighbors, "seeded shuffled batches vary their order and avoid adjacent duplicates")
	check(s.hordes.rng.state == combat_rng and s.hordes.trophy_rng.state == loot_rng, "cosmetic draws preserve encounter and drop RNG")
	var actor := spawn("bulwark", {"morph":"swift", "look_index":2,"wardrobe_index":34,"limb_index":74,"face_variant":1})
	actor.hp -= 3
	var serial := actor.spawn_serial
	var hp := actor.hp
	var cursor := s.hordes.next_looks.duplicate()
	check(s.save_now(false) == OK, "write living infected to normal save")
	var saved := WastelandSave.read(1)
	var next := spawn("bulwark", {"morph":"swift"})
	var expected := [next.look_index, next.wardrobe_index, next.limb_index, next.face_variant]
	await leave()
	enter(saved)
	restore_actors()
	actor = s.hordes.actors_by_serial.get(serial)
	check(is_instance_valid(actor) and actor.look_index == 2 and actor.wardrobe_index == 34 and actor.limb_index == 74 and actor.face_variant == 1 and actor.hp == hp and actor.hp == actor.max_health()-3 and actor.morph == "swift", "normal restore keeps individual, face, appearance, wardrobe, injured anatomy and remaining health")
	check(s.hordes.next_looks == cursor, "restoring an existing look leaves the cursor unchanged")
	next = spawn("bulwark", {"morph":"swift"})
	check([next.look_index, next.wardrobe_index, next.limb_index, next.face_variant] == expected, "same seed replays the next natural look, wardrobe, face and limb state")
	await leave()
	saved.threat.erase("next_looks")
	for row: Dictionary in saved.threat.actors:
		row.erase("look_index")
		row.erase("wardrobe_index")
		row.erase("limb_index")
		row.erase("face_variant")
	# Before spawn serials were introduced, the only stable identity was the
	# saved species and position. Reorder this fixture on a second load.
	var old_wolf: Dictionary = saved.threat.actors[0].duplicate()
	old_wolf.erase("serial")
	old_wolf.id = "wolf"
	old_wolf.morph = "local"
	old_wolf.at += Vector3.RIGHT * 2
	saved.threat.actors.append(old_wolf)
	check(WastelandSave.write(2, saved) == OK, "write legacy world without cosmetic fields")
	enter(WastelandSave.read(2))
	restore_actors()
	actor = s.hordes.actors_by_serial.get(serial)
	check(is_instance_valid(actor) and actor.look_index == 0 and actor.limb_damage == Vector4i.ZERO and actor.hp == hp and actor.morph == "swift", "legacy actor loads with complete limbs, base look, old health and morph")
	var old_wardrobe := actor.wardrobe_index
	var old_face := actor.face_variant
	var wolves := s.hordes.alive.filter(func(mob): return mob.type=="wolf")
	var old_wolf_face: int = wolves[0].face_variant
	var wolf := spawn("wolf", {"morph":"local", "look_index":2,"wardrobe_index":24})
	check(wolf.look_index == 0 and wolf.wardrobe_index == 0, "wildlife keeps its existing morph")
	await leave()
	saved = WastelandSave.read(2)
	saved.threat.actors.reverse()
	enter(saved)
	restore_actors()
	check(s.hordes.actors_by_serial[serial].wardrobe_index == old_wardrobe, "legacy individual's assigned wardrobe is stable across independent loads")
	wolves = s.hordes.alive.filter(func(mob): return mob.type=="wolf")
	check(s.hordes.actors_by_serial[serial].face_variant == old_face and wolves[0].face_variant == old_wolf_face, "legacy infected and serial-free wildlife keep assigned faces despite reversed restoration order")
	await leave()

func verify_wardrobes() -> void:
	for kind: String in WastelandHordes.KINDS:
		var wardrobes := {}
		var stats := {}
		for i in 50:
			var actor := spawn(kind, {"morph":"swift", "look_index":0,"limb_index":0})
			wardrobes[actor.wardrobe_index] = true
			stats[[actor.hp, actor.max_health(), actor.capsule.height, actor.capsule.radius]] = true
			s.hordes.release(actor)
		var outfits := {}
		var wear := {}
		var kits := {}
		for index: int in wardrobes:
			outfits[index % 3] = true
			wear[floori(index/3.0) % 3] = true
			kits[floori(index/9.0)] = true
		check(outfits.size() == 3 and wear.size() == 3 and kits.size() == 4 and stats.size() == 1,
			kind + " naturally spawns all clothing, wear and equipment values with one gameplay morph")
		var visuals := {}
		for index: int in [0,1,2,3,6,9,18,27]:
			var actor := spawn(kind, {"morph":"swift","look_index":0,"wardrobe_index":index,"limb_index":0})
			visuals[mesh_shape(actor)] = true
			s.hordes.release(actor)
		check(visuals.size() == 8, kind + " independently displays three outfits, three wear levels and four accessory choices")
		await process_frame

func verify_faces() -> void:
	var cells := {}
	var combinations := 0
	for kind: String in WastelandHordes.KINDS + WastelandHordes.WILDLIFE:
		var seen := {}
		for i in 20:
			var individual := spawn(kind,{})
			seen[individual.face_variant] = true
			s.hordes.release(individual)
		var rebuilt := true
		var forms := ["","young","local"] if kind in WastelandHordes.WILDLIFE else ["","armored","swift"]
		for morph: String in forms:
			for look in maxi(1, WastelandCreature.InfectedLooks.count_for(kind)):
				combinations += 2
				var data := {"morph":morph, "look_index":look, "limb_index":0, "wardrobe_index":0, "face_variant":0}
				var individual := spawn(kind,data)
				cells[face_cell(individual)] = true
				var first_head: int = individual.body_parts.head.get_instance_id()
				s.hordes.release(individual)
				data.face_variant = 1
				var next := spawn(kind,data)
				cells[face_cell(next)] = true
				rebuilt = rebuilt and next == individual and next.face_variant == 1 and next.body_parts.head.get_instance_id() != first_head
				s.hordes.release(next)
		check(seen.has_all([0,1]) and rebuilt, kind + " naturally rolls both faces and rebuilds when only face changes for every morph and look")
		await process_frame
	check(cells.size()==combinations and not cells.has([]), "all %d land-species/morph/look/face combinations select distinct real atlas cells on the native heads" % combinations)

func face_cell(actor: WastelandCreature) -> Array:
	for part: MeshInstance3D in actor.body_parts.head.find_children("*","MeshInstance3D",true,false):
		if not part.get_meta("species_face", false):
			continue
		var paint := part.material_override as ShaderMaterial
		if paint == null: continue
		var atlas := paint.get_shader_parameter("face_atlas") as Texture2D
		var rect: Vector4 = paint.get_shader_parameter("face_rect")
		if atlas != null and atlas.get_width() > 0 and rect.z > 0 and rect.w > 0:
			return [atlas.resource_path, rect]
	return []

func verify_limbs() -> void:
	var states := {}
	var complete := 0
	for serial in range(1,500001):
		var state := WastelandCreature.InfectedLimbs.roll(cfg.seed,serial)
		states[state] = true
		if state == 0:
			complete += 1
	check(states.size() == 81 and complete > 250000 and complete < 285000, "seeded natural rolls reach all 81 limb combinations with an intact majority")
	for kind: String in WastelandHordes.KINDS:
		var intact := spawn(kind, {"limb_index":0})
		var base_health := intact.max_health()
		var base_speed := intact.max_move_speed()
		var base_height := intact.capsule.height
		s.hordes.release(intact)
		var valid := true
		for state in range(1,81):
			var actor := spawn(kind, {"limb_index":state, "wardrobe_index":23})
			var limbs := WastelandCreature.InfectedLimbs.decode(state)
			valid = valid and actor == intact and actor.limb_damage == limbs and actor.hp == actor.max_health() and actor.hp < base_health
			for i in 4:
				var suffix := "_r" if i%2 else "_l"
				if i < 2 and actor.body_parts["hand"+suffix].visible != (limbs[i] == 0):
					valid = false
				var joint := "elbow" if i < 2 else "knee"
				var short_piece: MeshInstance3D = actor.body_parts[joint+suffix].get_node_or_null("ShortenedLimb")
				var shortened := limbs[i] >= (2 if i < 2 else 1)
				valid = valid and shortened == is_instance_valid(short_piece)
				if shortened:
					valid = valid and is_instance_valid(short_piece.mesh)
			if limbs.z + limbs.w > 0:
				valid = valid and actor.max_move_speed() < base_speed and actor.capsule.height < base_height
			if actor.low_crawl():
				actor._pose(0.1, 2)
				valid = valid and (kind=="crawler" or actor.rig.rotation.x < -1.0)
			if kind == "brute" and limbs.y > 0 and limbs.x == 0:
				valid = valid and actor.body_parts.hand_l.has_node("HammerGrip/Hammer")
			s.hordes.release(actor)
			if state % 20 == 0:
				await process_frame
		intact = spawn(kind, {"limb_index":0})
		valid = valid and intact.max_health()==base_health and intact.capsule.height==base_height and intact.max_move_speed()==base_speed and intact.body_parts.hand_l.visible and intact.body_parts.hand_r.visible
		check(valid, kind + " supports every multi-limb combination, health, movement, attachments and intact pool restoration")
		s.hordes.release(intact)
		await process_frame

func restore_actors() -> void:
	s.hordes.next_herd = INF
	s.hordes.next_patrol = INF
	s.hordes.next_heat = INF
	for row: Dictionary in s.hordes.fresh:
		s.stream.ensure_landing(row.at)
	s.hordes.simulate(0.01)

func verify_network(host: bool, port: int) -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	app.set_process_input(false)
	if host:
		app._enter_world(cfg, {}, 1, false)
		s = app.session
		s.hordes.next_patrol = INF
		s.hordes.next_herd = INF
		# Different appearances of each species share the same gameplay morph.
		for species in KINDS.size():
			for look in 3:
				var serial := 100 + species * 3 + look
				var at := s.player.global_position + Vector3(species * 2, 0, 28 + look * 2)
				at.y = s.stream.ground_at(at) + 0.1
				s.hordes._spawn(KINDS[species], at, false, {"serial":serial,"morph":"armored","look_index":look,"wardrobe_index":serial % 36,"limb_index":serial % 81,"face_variant":serial % 2})
		for species in WastelandHordes.KINDS.size():
			var at := s.player.global_position + Vector3(-species * 2, 0, 20)
			at.y = s.stream.ground_at(at) + 0.1
			s.hordes._spawn(WastelandHordes.KINDS[species], at, false, {"serial":150+species,"wardrobe_index":(species*5+1)%36,"limb_index":80-species,"face_variant":species%2})
		for species in WastelandHordes.WILDLIFE.size():
			var at := s.player.global_position + Vector3(species*2,0,-19)
			at.y = s.stream.ground_at(at) + 0.1
			s.hordes._spawn(WastelandHordes.WILDLIFE[species],at,false,{"serial":200+species,"morph":"local","face_variant":species%2})
		check(app.network.listen(port) == OK, "host listens with infected and wildlife faces already assigned")
		var joins := 2 if "--reconnect" in OS.get_cmdline_user_args() else 1
		for attempt in joins:
			if not await until(func(): return is_instance_valid(app.network.member), 25):
				check(false, "guest joins host")
				break
			check(await until(func(): return not is_instance_valid(app.network.member), 25), "guest finishes inspection %d and disconnects" % (attempt+1))
	else:
		check(app.network.connect_to("127.0.0.1", port) == OK, "guest connects over ENet")
		check(await until(func(): return is_instance_valid(app.session) and app.session.replica, 25), "guest receives world")
		var complete := func() -> bool:
			for species in KINDS.size():
				for look in 3:
					var actor: WastelandCreature = app.network.smooth_actors.get(100 + species * 3 + look)
					if not is_instance_valid(actor) or actor.type != KINDS[species] or actor.morph != "armored" or actor.look_index != look or actor.wardrobe_index != actor.spawn_serial % 36 or actor.limb_index != actor.spawn_serial % 81 or actor.face_variant != actor.spawn_serial%2:
						return false
			for species in WastelandHordes.KINDS.size():
				var actor: WastelandCreature = app.network.smooth_actors.get(150 + species)
				if not is_instance_valid(actor) or actor.type != WastelandHordes.KINDS[species] or actor.wardrobe_index != (species*5+1)%36 or actor.limb_index != 80-species or actor.hp != actor.max_health() or actor.face_variant != species%2:
					return false
			for species in WastelandHordes.WILDLIFE.size():
				var actor: WastelandCreature = app.network.smooth_actors.get(200 + species)
				if not is_instance_valid(actor) or actor.type != WastelandHordes.WILDLIFE[species] or actor.morph != "local" or actor.face_variant != species%2:
					return false
			return true
		check(await until(complete, 20), "guest sees every infected wardrobe, look and land species face across paged actor snapshots")
		var visible_gaits := func() -> bool:
			if app.network.posed_actor_frame != app.network.applied_actor_frame: return false
			var wildlife := false
			var infected := false
			for row: Array in app.network.replica_actors:
				var replica: WastelandCreature = app.network.smooth_actors.get(row[0])
				if not is_instance_valid(replica) or row.size()<24: continue
				var sample: Vector4i = row[23]
				if sample.y<120 or replica.motion_speed<0.06: continue
				var phase := replica.wildlife_cycle*TAU if replica.brain.animal else replica.pose_phase
				if absf(angle_difference(phase,float(sample.x)*TAU/65535.0))>1.0: continue
				if replica.motion_water!=bool(sample.z&4) or int(replica.brain.mode)!=((sample.z>>3)&15): continue
				if replica.brain.animal: wildlife = true
				else: infected = true
			return wildlife and infected
		check(await until(visible_gaits,10),"guest plays both moving wildlife and infected within the host stride, with matching water and behavior states")
		s = app.session
	app.network.stop()
	if is_instance_valid(s):
		s.simulation_paused = true
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.queue_free()
	await process_frame
