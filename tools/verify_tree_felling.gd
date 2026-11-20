extends "res://tools/verify_lan_discovery.gd"

const CELL := Vector2i(-1, 1)
const INDEX := "22"
const CENTER := Vector3(-8.39, 8.51, 39.67)
const FALL := Vector3.BACK
const STEP := 1.0 / 60.0
var s: WastelandSession

func run() -> void:
	var args := OS.get_cmdline_user_args()
	port = 19671
	for arg in args:
		if arg.begins_with("--port="): port = int(arg.get_slice("=", 1))
	WastelandSave.root_override = "user://verification/tree-felling-%d" % OS.get_process_id()
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	if "--guest" in args:
		await guest()
	else:
		var config := WastelandSave.default_world()
		config.seed = 2817
		config.terrain_revision = 5
		config.start_id = "seeded"
		open_world(config, {})
		if "--host" in args: await host()
		else: await offline()
	app.network.stop()
	if is_instance_valid(app.session):
		app.session.simulation_paused = true
		await app.session.stream.quiesce()
		await app.session.audio.finish_playback()
	app.queue_free()
	await process_frame
	print("TREE FELLING failures=", failures)
	quit(1 if failures else 0)

func open_world(config: Dictionary, state: Dictionary) -> void:
	app._enter_world(config, state, 1, false)
	s = app.session
	s.simulation_paused = true
	s.stream.refresh(CENTER, 2)
	s.stream.ensure_landing(CENTER)

func chunk() -> WastelandChunk:
	return s.stream.active[CELL]

func trunk() -> StaticBody3D:
	for node in chunk().decoration_root.get_children():
		if node.get_meta("resource", "") == "oak" and node.get_meta("index", "") == INDEX and not node.is_queued_for_deletion():
			return node
	return null

func stump() -> StaticBody3D:
	var node: Node = chunk().timber_visuals.get(INDEX)
	if node is StaticBody3D and node.get_meta("kind", "") == "stump":
		return node
	return null

func ground(at: Vector3) -> Vector3:
	at.y = s.stream.ground_at(at) + 0.03
	return at

func stage() -> void:
	s.player.global_position = ground(CENTER - FALL * 2.0)
	s.player.velocity = Vector3.ZERO
	aim(CENTER + Vector3.UP * 1.1)

func aim(at: Vector3) -> void:
	var ray := at - s.player.camera.global_position
	s.player.rotation.y = atan2(-ray.x, -ray.z)
	s.player.pitch = atan2(ray.y, Vector2(ray.x, ray.z).length())
	s.player.eyes.rotation.x = s.player.pitch

func equip_axe() -> void:
	if s.bag.count("stone_axe") == 0: s.bag.add("stone_axe", 1)
	s.bag.assign("stone_axe", 0)
	s.bag.active = 0

func chop(target: StaticBody3D) -> bool:
	var axe: Dictionary = s.catalog.items.stone_axe
	if not check(s._trace(axe.reach, 15, false, true, true).get("collider") == target, "equipped axe ray reaches intended collider"): return false
	s.player.stamina = 100
	s._melee(axe, 1.0)
	return true

func wood() -> int:
	return item_total("wood")

func item_total(id: String) -> int:
	var total := s.bag.count(id)
	for drop: Dictionary in s.fx.drop_records.values(): total += int(drop.items.get(id, 0))
	return total

func active_falls() -> Dictionary:
	return s.timber.active

func advance(count: int) -> void:
	for i in count: s.timber.tick(STEP)

func fell(target: StaticBody3D) -> bool:
	var key: String = target.get_meta("key")
	for i in 7:
		if not chop(target): return false
		if target.is_queued_for_deletion(): break
	return check(active_falls().has(key) and target.collision_layer == 0, "last axe blow releases one tree and clears standing collision")

func actor_at(at: Vector3, species := "brute") -> WastelandCreature:
	if not s.hordes._spawn(species, ground(at), false): return null
	return s.hordes.actors_by_serial[s.hordes.spawn_serial]

func offline() -> void:
	await physics_frame
	await physics_frame
	var tree := trunk()
	if not check(is_instance_valid(tree), "seeded oak and its harvest collider exist"): return
	equip_axe()
	stage()
	var baseline := wood()
	if not chop(tree): return
	var diff := s.stream.chunk_diff(CELL)
	var hp := float(diff.resources.get(INDEX, 0))
	if not check(hp > 0 and hp < float(WastelandSession.RESOURCES.oak[1]) and active_falls().is_empty() and wood() == baseline, "partial cut preserves tree and withholds wood"): return
	if not check(diff.get("tree_cuts", {}).has(INDEX) and chunk().timber_visuals.has(INDEX), "partial work has a visible cut and a persisted direction"): return
	var cut: Dictionary = diff.tree_cuts[INDEX].duplicate(true)
	if not check(s.save_now(false) == OK, "save partially chopped tree"): return
	var state := WastelandSave.read(1)
	var half_cut := state
	open_world(state.settings, state)
	await physics_frame
	await physics_frame
	tree = trunk()
	diff = s.stream.chunk_diff(CELL)
	if not check(is_instance_valid(tree) and is_equal_approx(diff.resources[INDEX], hp) and diff.tree_cuts[INDEX] == cut and chunk().timber_visuals.has(INDEX), "load restores same cut, direction and remaining work"): return
	stage()
	var key: String = tree.get_meta("key")
	if not fell(tree): return
	if not check(wood() == baseline and stump() != null, "stump appears before timber reaches ground"): return
	var victim := actor_at(CENTER + FALL * 3.2)
	var bystander := actor_at(CENTER + Vector3.RIGHT * 5.5)
	if not check(victim != null and bystander != null, "live infected stand inside and outside the fall path"): return
	var stag := actor_at(CENTER + FALL * 2.3, "stag")
	if not check(stag != null, "director spawns a gray bay stag inside the trunk sweep"): return
	var stag_hp := stag.hp
	var victim_hp := victim.hp
	var safe_hp := bystander.hp
	var owner_hp := s.player.health
	s.player.global_position = ground(CENTER + FALL * 4.4)
	var hit_count := 0
	var player_hits := 0
	var stag_hits := 0
	var prev_hp := victim_hp
	var prev_player_hp := owner_hp
	advance(5)
	if not check(victim.hp == victim_hp and s.player.health == owner_hp and wood() == baseline, "early lean leaves standing targets and timber untouched"): return
	if not check(s.save_now(false) == OK, "save a moving tree"): return
	state = WastelandSave.read(1)
	check(not state.get("falling_trees", {}).is_empty(), "disk contains unfinished fall")
	var struck_state := {}
	for i in 420:
		advance(1)
		if victim.hp < prev_hp: hit_count += 1
		if stag.hp < stag_hp: stag_hits += 1
		stag_hp = stag.hp
		if s.player.health < prev_player_hp:
			player_hits += 1
			if s.save_now(false) == OK: struck_state = WastelandSave.read(1)
		prev_hp = victim.hp
		prev_player_hp = s.player.health
	check(hit_count == 1 and player_hits == 1 and bystander.hp == safe_hp, "swept trunk hurts player and infected once, lateral bystander stays safe")
	check(stag_hits == 1, "falling oak strikes the living stag exactly once")
	check(not active_falls().has(key) and not is_instance_valid(trunk()) and stump() != null, "settled tree leaves one stump")
	var drops := 0
	for row: Dictionary in s.fx.drop_records.values():
		if row.items.has("wood"):
			drops += 1
			check((Vector3(row.point) - CENTER).dot(FALL) > 0, "wood is on the side opposite the axe")
	check(drops >= 2 and wood() == baseline + int(WastelandSession.RESOURCES.oak[2].wood), "grounded timber yields exact original wood quantity over several pickups")
	var total := wood()
	open_world(state.settings, state)
	await physics_frame
	if not check(active_falls().has(key) and wood() == baseline, "loading an airborne tree resumes it without a premature payout"): return
	advance(420)
	check(wood() == total and active_falls().is_empty(), "resumed tree pays once")
	if not struck_state.is_empty():
		open_world(struck_state.settings, struck_state)
		await physics_frame
		var saved_hp := s.player.health
		advance(420)
		check(s.player.health == saved_hp and wood() == total, "saving immediately after contact does not replay the hit or duplicate wood")
	s.stream.refresh(CENTER + Vector3.RIGHT * 280, 2)
	if not check(not s.stream.active.has(CELL), "travel unloads the harvested chunk"): return
	await process_frame
	s.stream.refresh(CENTER, 2)
	s.stream.ensure_landing(CENTER)
	await physics_frame
	check(trunk() == null and stump() != null and wood() == total, "streaming chunk back keeps stump and original yield")
	if not check(s.save_now(false) == OK, "save settled stump and wood"): return
	state = WastelandSave.read(1)
	open_world(state.settings, state)
	await physics_frame
	await physics_frame
	check(trunk() == null and stump() != null and wood() == total and active_falls().is_empty(), "settled reload restores stump and pickups once")
	await verify_log_pickups()
	if stump() == null: return
	stage()
	aim(stump().global_position + Vector3.UP * 0.1)
	for i in 12:
		if stump() == null: break
		if not chop(stump()): return
	check(stump() == null, "axe removes stump through normal harvest trace")
	if not check(s.save_now(false) == OK, "save cleared stump"): return
	state = WastelandSave.read(1)
	open_world(state.settings, state)
	await physics_frame
	check(trunk() == null and stump() == null, "cleared stump stays absent after reload")
	await verify_structure_impact(half_cut)

func place_frame_stack(position: Vector3) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var cell := WastelandConstruction.cell_at(position)
	cell.y = roundi(s.stream.ground_at(WastelandConstruction.position_of(cell)))
	for height in 3:
		var next := cell + Vector3i.UP * height
		if not s.construction.place(next, "frame", 0, 0, s.player.global_position): break
		cells.append(next)
	return cells

func stack_hp(cells: Array[Vector3i]) -> Array[float]:
	var result: Array[float] = []
	for cell in cells: result.append(s.construction.blocks.get(cell, {}).get("hp", 0.0))
	return result

func verify_structure_impact(partial: Dictionary) -> void:
	open_world(partial.settings, partial)
	await physics_frame
	await physics_frame
	stage()
	s.bag.add("frame", 6)
	var obstacle := place_frame_stack(CENTER + FALL * 3.8)
	var bystander := place_frame_stack(CENTER + FALL * 3.8 + Vector3.RIGHT * 5.0)
	if not check(obstacle.size() == 3 and bystander.size() == 3, "build two wood-frame columns through normal placement"): return
	await physics_frame
	var intact := stack_hp(obstacle)
	var safe := stack_hp(bystander)
	if not fell(trunk()): return
	s.player.global_position = ground(CENTER + FALL * 2.0)
	var health := s.player.health
	advance(12)
	check(stack_hp(obstacle) == intact, "wood frame retains full health during warning lean")
	s.player.global_position = ground(CENTER + Vector3.RIGHT * 6.0)
	var transitions := 0
	var saved := {}
	var previous := intact
	for frame in 360:
		advance(1)
		var hp := stack_hp(obstacle)
		if hp != previous:
			transitions += 1
			if saved.is_empty() and s.save_now(false) == OK: saved = WastelandSave.read(1)
		previous = hp
	var count := 0
	for index in intact.size():
		if previous[index] < intact[index]: count += 1
	check(count == 1 and transitions == 1 and stack_hp(bystander) == safe, "trunk damages only the first struck frame once and spares adjacent column")
	check(s.player.health == health, "stepping sideways during the warning avoids the impact")
	if not check(not saved.get("falling_trees", {}).is_empty(), "post-impact save retains the settling tree"): return
	open_world(saved.settings, saved)
	await physics_frame
	advance(360)
	check(stack_hp(obstacle) == previous and stack_hp(bystander) == safe, "loading during the bounce leaves the same single damaged frame")

func verify_log_pickups() -> void:
	s.fx.simulate(STEP)
	await physics_frame
	var sections := {}
	var bodies := []
	var quantity := 0
	for key: String in s.fx.drop_records:
		var row: Dictionary = s.fx.drop_records[key]
		if not row.items.has("wood"): continue
		if not check(row.has("log_section") and s.fx.drop_live.has(key), "wood saved as a physical log"): return
		var body: StaticBody3D = s.fx.drop_live[key]
		var shape: CollisionShape3D = body.get_node("PickupShape")
		var art: MeshInstance3D = body.get_node("Item")
		var section: Dictionary = row.log_section
		var size := Vector3(2.0 * section.radius, 2.0 * section.radius, section.length)
		var axis: Vector3 = section.axis
		check(section.length > 1.0 and section.radius > 0.05 and (shape.shape as BoxShape3D).size.is_equal_approx(size), "pickup collision matches the cut section's diameter and length")
		check(shape.global_basis.z.dot(axis) > 0.999 and art.global_basis.z.normalized().dot(axis) > 0.999 and art.mesh != null and art.visible, "rendered log and pickup shape follow trunk axis")
		sections[key] = row.point
		bodies.append(body)
		quantity += int(row.items.wood)
	if not check(sections.size() >= 2, "multiple restored log segments are active"): return
	s.player.global_position = ground(CENTER + Vector3.RIGHT * 9.0)
	# A transverse impulse separates rolling from a log sliding down its own axis.
	var middle: Dictionary = s.fx.drop_records[sections.keys()[1]]
	middle.velocity = Vector3(middle.get("velocity", Vector3.ZERO)) + Vector3(middle.log_section.axis).cross(Vector3.UP).normalized() * 1.5
	middle.erase("resting")
	for i in 360: s.fx.simulate(STEP)
	await physics_frame
	var moved := false
	var rolled := false
	for key: String in sections:
		var row: Dictionary = s.fx.drop_records[key]
		var pt: Vector3 = row.point
		var log: Dictionary = row.log_section
		moved = moved or pt.distance_to(sections[key]) > 0.04
		rolled = rolled or absf(float(log.get("roll", 0.0))) > 0.001
		var supported := false
		for fraction in [-0.45, 0.0, 0.45]:
			var sample: Vector3 = pt + Vector3(log.axis) * (log.length * fraction)
			var clearance := float(log.radius) + 0.18
			var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 0.05, sample - Vector3.UP * clearance, 3)
			if not s.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): supported = true
		check(supported, "settled log rests on terrain or stump along its length")
	check(moved and rolled, "physical logs translate and roll under transverse motion")
	var baseline := s.bag.count("wood")
	var end_collected := false
	for key: String in sections:
		if not s.fx.drop_records.has(key): continue
		var row: Dictionary = s.fx.drop_records[key]
		var section: Dictionary = row.log_section
		var axis: Vector3 = section.axis
		var end: Vector3 = row.point + axis * float(section.length) * 0.5
		var collider: StaticBody3D = s.fx.drop_live[key]
		var target: Vector3 = row.point + axis * float(section.length) * 0.38
		var ray := PhysicsRayQueryParameters3D.create(target + Vector3.UP, target - Vector3.UP, WastelandEffects.PICKUP_LAYER)
		check(s.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == collider, "real pickup ray hits the outer end of the oriented log")
		s.player.global_position = ground(end + axis.slide(Vector3.UP).normalized() * 1.1)
		var reach := s.player.global_position + Vector3.UP * s.player.eyes.position.y * 0.45
		var out_of_center_range := reach.distance_to(row.point) > WastelandEffects.PICKUP_RADIUS
		s.fx.collect_nearby()
		if not s.fx.drop_records.has(key):
			end_collected = end_collected or out_of_center_range
		else:
			s.player.global_position = ground(row.point)
			s.fx.collect_nearby()
	check(end_collected and s.bag.count("wood") == baseline + quantity, "approaching an end beyond center pickup range collects the full timber quantity once")
	var reused: StaticBody3D
	for attempt in WastelandEffects.DROPS:
		s.fx.add_items(s.player.global_position, {"stone":1})
		var next: StaticBody3D = s.fx.drop_live.get(str(s.fx.serial))
		if bodies.has(next):
			reused = next
			break
	if not check(reused != null, "ordinary pickup reuses a body that held a log"): return
	var pickup: CollisionShape3D = reused.get_node("PickupShape")
	check(pickup.basis.is_equal_approx(Basis.IDENTITY) and (pickup.shape as BoxShape3D).size.is_equal_approx(Vector3(0.58, 0.34, 0.51)), "pooled former log resets ordinary pickup orientation and bounds")

func marked(label: String) -> bool:
	return s.marker_records.any(func(m): return m.name == label)

func mark(label: String) -> void:
	s.ui_command("marker", [Vector2(CENTER.x, CENTER.z), label])

func host() -> void:
	stage()
	equip_axe()
	s.hordes.next_patrol = INF
	s.hordes.next_herd = INF
	s.simulation_paused = false
	if not check(app.network.listen(port) == OK, "host listens over ENet"): return
	if not check(await until(func(): return is_instance_valid(app.network.member)), "guest joins authority"): return
	var member: WastelandSurvivor = app.network.member
	member.global_position = ground(CENTER + FALL * 3.3)
	stage()
	if not check(await until(func(): return marked("tree-ready")), "guest has standing tree and is in fall path"): return
	var total := wood()
	var before := member.health
	var sticks_before := item_total("stick")
	var leaves_before := item_total("tree_leaf")
	var tree := trunk()
	stage()
	if not is_instance_valid(tree) or not chop(tree): return
	if not check(await until(func(): return marked("tree-cut")), "guest sees first cut before final axe strike"): return
	stage()
	if not is_instance_valid(tree) or not fell(tree): return
	var contacts := []
	active_falls().values()[0].struck.connect(func(id, _damage, _point): contacts.append(id))
	if not check(await until(func(): return marked("tree-landed")), "guest observed replicated fall, hit and wood"): return
	check(member.health < before and contacts.count("guest/" + app.network.member_token) == 1 and not contacts.has("host"), "authority hits exposed guest once and spares cutter")
	check(wood() == total + int(WastelandSession.RESOURCES.oak[2].wood) and active_falls().is_empty(), "one complete host payout across network acknowledgements")
	check(item_total("stick") >= sticks_before + 2 and item_total("tree_leaf") > leaves_before + 1, "host holds both leaf payouts and several canopy sticks")
	mark("canopy-%d-%d" % [item_total("stick"), item_total("tree_leaf")])
	mark("tree-finished")
	await until(func(): return not is_instance_valid(app.network.member), 8000)

func guest() -> void:
	if not check(app.network.connect_to("127.0.0.1", port) == OK, "guest connects to host"): return
	if not check(await until(func(): return is_instance_valid(app.session) and app.session.replica and app.session.stream.active.has(CELL)), "guest streams target cell"): return
	s = app.session
	if not check(await until(func(): return s.player.global_position.distance_to(ground(CENTER + FALL * 3.3)) < 0.6 and trunk() != null), "guest sees intact oak at replicated position"): return
	var total := wood()
	var before := s.player.health
	mark("tree-ready")
	if not check(await until(func(): return is_instance_valid(s) and chunk().timber_visuals.has(INDEX) and trunk() != null and active_falls().is_empty()), "guest mirrors partial notch on the standing oak"): return
	mark("tree-cut")
	if not check(await until(func(): return not active_falls().is_empty()), "guest receives animated fall"): return
	if not check(await until(func(): return s.player.health < before and s.player.injury.last_source == "timber" and stump() != null and active_falls().is_empty() and wood() == total + int(WastelandSession.RESOURCES.oak[2].wood)), "guest sees authoritative timber injury, stump and exactly one timber yield"): return
	mark("tree-landed")
	check(await until(func(): return marked("tree-finished")), "guest receives host confirmation")
	check(await until(func(): return marked("canopy-%d-%d" % [item_total("stick"),item_total("tree_leaf")])), "guest and host agree on exact stick and leaf totals including collected items")
