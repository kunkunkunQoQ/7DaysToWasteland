extends "res://tools/verify_tree_felling.gd"

const Planting := preload("res://game/sim/sapling_planting.gd")
const Art := preload("res://game/art/sapling_art.gd")
const MODELS := ["birch", "pine", "oak", "frost_fir", "snow_fir"]
const NETWORK_MODEL := "frost_fir"
const AWAY := Vector3(420, 0, 800)
var planted_ids := {}

func frames(count: int) -> void:
	for i in count: await physics_frame

func mouse_button(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func press_main() -> void:
	mouse_button(true)
	await frames(5)
	mouse_button(false)
	await frames(4)

func face_soil(point: Vector3) -> void:
	s.player.global_position = ground(point + Vector3.BACK * 1.85)
	s.player.velocity = Vector3.ZERO
	aim(point)

func find_soil() -> Vector3:
	var origin := chunk().global_position
	for z in range(3, 29, 5):
		for x in range(3, 29, 5):
			var point := ground(origin + Vector3(x, 0, z))
			face_soil(point)
			var hit := Planting.aim(s)
			if Planting.obstruction(s, hit).is_empty() and point.distance_to(hit.position) < 0.3:
				return hit.position
	return Vector3.INF

func rows() -> Dictionary:
	return s.stream.chunk_diff(CELL).get("planted_trees", {})

func id_for(model: String) -> String:
	for id: String in rows():
		if rows()[id].model == model: return id
	return ""

func plant_body(model: String) -> StaticBody3D:
	if not s.stream.active.has(CELL): return null
	return chunk().planted.get(id_for(model))

func check_leaf_rolls(model: String) -> bool:
	var item := "sapling_" + model
	var pose := Transform3D(Basis.IDENTITY, ground(CENTER))
	s.player.global_position = pose.origin
	var misses := 0
	var hits := 0
	for salt in 256:
		var previous := s.fx.serial
		s.timber._drop_leaves(model, 0, pose, salt, 1, Vector3.ZERO)
		var seeds := 0
		var leaves := 0
		for serial in range(previous + 1, s.fx.serial + 1):
			var id := str(serial)
			var row: Dictionary = s.fx.drop_records[id]
			leaves += int(row.items.get("tree_leaf", 0))
			for drop: String in row.items:
				if s.catalog.items[drop].get("kind", "") == "sapling":
					if not check(drop == item and int(row.items[drop]) == 1, model + " crown releases exactly one matching seedling"): return false
					seeds += 1
					if not check(s.fx.drop_live.has(id), model + " seedling has a physical pickup"): return false
			# Walk the survivor's pickup radius through the crown sample. A
			# sibling pickup can be collected concurrently by the same scan.
			if seeds == 0: s.fx.take_drop(id, true)
			else:
				s.player.global_position = Vector3(row.point) - Vector3.UP * s.player.eyes.position.y * 0.40
				s.fx.collect_nearby()
		if not check_leaf_sample(leaves, seeds, model): return false
		hits += seeds
		if seeds == 0: misses += 1
		if hits > 0 and misses > 0: break
	return check(hits > 0 and misses > 0 and s.bag.count(item) == hits, model + " leaves can drop a seedling and can drop alone")

func check_leaf_sample(leaves: int, seeds: int, model: String) -> bool:
	if leaves == 1 and seeds <= 1: return true
	return check(false, "%s crown sample yielded %d leaves and %d seedlings" % [model, leaves, seeds])

func offline() -> void:
	await frames(2)
	var starting_height := {}
	s.hordes.next_patrol = INF
	s.hordes.next_herd = INF
	for model: String in MODELS:
		if not check_leaf_rolls(model): return
	for model: String in MODELS:
		var item := "sapling_" + model
		s.simulation_paused = false
		while s.action_lock > 0.0: await physics_frame
		s.simulation_paused = true
		s.bag.assign(item, 0)
		s.bag.active = 0
		var point := find_soil()
		if not check(point.is_finite(), model + " has an open planting site"): return
		var before := s.bag.count(item)
		s.simulation_paused = false
		await press_main()
		s.simulation_paused = true
		var body := plant_body(model)
		if not check(s.bag.count(item) == before - 1 and is_instance_valid(body) and body.get_meta("kind", "") == "sapling", model + " left-click spends one held seedling and plants one juvenile"):
			print("Plant target ", point, " final feet ", s.player.global_position, " held ", s.bag.current(), " rejection ", Planting.obstruction(s, Planting.aim(s)), " counts ", [before, s.bag.count(item)])
			return
		if not check(body.global_position.distance_to(point) < 0.5 and not chunk().standing_trees.has(id_for(model)), model + " starts at the targeted position and cannot be felled yet"): return
		planted_ids[model] = id_for(model)
		starting_height[model] = (body.get_child(0).shape as BoxShape3D).size.y

	if not check(rows().size() == MODELS.size(), "five mouse presses leave five independent planting records"): return
	var original := rows().duplicate(true)
	var time_start: float = original[planted_ids.oak].planted_at
	s.player.global_position = ground(AWAY)
	s.stream.refresh(s.player.global_position, 2)
	if not check(not s.stream.active.has(CELL), "grove's chunk is unloaded before time advances"): return
	s.clock.hours = time_start + 24.0
	s.grove.tick(2.0)
	if not check(s.save_now(false) == OK, "save while the planted grove is unloaded"): return
	var saved := WastelandSave.read(1)
	s.clock.hours = time_start + 24.0 * 8.0
	s.grove.tick(2.0)
	if not check(not s.stream.active.has(CELL) and s.save_now(false) == OK, "all five maturation deadlines can pass while the grove stays unloaded"): return
	var distant_save := WastelandSave.read(1)
	open_world(distant_save.settings, distant_save)
	await frames(2)
	for model: String in MODELS:
		var restored_tree: StaticBody3D = chunk().standing_trees.get(planted_ids[model])
		if not check(is_instance_valid(restored_tree) and restored_tree.get_meta("tree_model", "") == model, model + " materializes mature on first return to the distant grove"): return
	# Resume the earlier one-day snapshot to observe the deadlines separately.
	open_world(saved.settings, saved)
	await frames(2)
	if not check(rows() == original and is_equal_approx(s.clock.hours, time_start + 24.0), "disk round-trip retains all five positions, variants and planting times"): return
	for model: String in MODELS:
		var body := plant_body(model)
		if not check(is_instance_valid(body) and body.get_meta("kind", "") == "sapling", model + " remains juvenile at one day"): return
		if not check((body.get_child(0).shape as BoxShape3D).size.y > starting_height[model] + 0.10, model + " has grown measurably taller on return"): return
	# Straddle each species' maturity time. Advancing the clock keeps physics and rendering
	# on the same code path without waiting for several real-time play sessions.
	for model: String in MODELS:
		var row: Dictionary = original[planted_ids[model]]
		var due := float(row.planted_at) + Art.duration_days(model) * 24.0
		s.clock.hours = due - 0.1
		s.grove.tick(2.0)
		if not check(plant_body(model).get_meta("kind", "") == "sapling", model + " stays juvenile until its own deadline"): return
		s.clock.hours = due + 0.1
		s.grove.tick(2.0)
		await frames(2)
		var tree: StaticBody3D = chunk().standing_trees.get(planted_ids[model])
		if not check(is_instance_valid(tree) and tree.get_meta("kind", "") == "resource" and tree.get_meta("tree_model", "") == model, model + " joins the normal standing-tree registry at maturity"): return
		for later in range(MODELS.find(model) + 1, MODELS.size()):
			if not check(plant_body(MODELS[later]).get_meta("kind", "") == "sapling", MODELS[later] + " is still growing when " + model + " matures"): return
	if not check(s.save_now(false) == OK, "save mature grove"): return
	saved = WastelandSave.read(1)
	open_world(saved.settings, saved)
	await frames(2)
	equip_axe()
	for model: String in MODELS:
		var tree: StaticBody3D = chunk().standing_trees.get(planted_ids[model])
		if not check(is_instance_valid(tree), model + " mature trunk restores from disk"): return
		var resource: String = tree.get_meta("resource")
		var base: Vector3 = chunk().to_global(Transform3D(tree.get_meta("tree_pose")).origin)
		var before := wood()
		var ready := false
		for turn in 8:
			var direction := Vector3.BACK.rotated(Vector3.UP, TAU * turn / 8.0)
			s.player.global_position = ground(base + direction * 1.8)
			aim(base + Vector3.UP)
			if s._trace(s.catalog.items.stone_axe.reach, 15, false, true, true).get("collider") == tree:
				ready = true
				break
		if not check(ready, model + " restored trunk has a reachable axe collider"): return
		if model == "birch":
			if not chop(tree): return
			var id: String = planted_ids[model]
			var partial: Dictionary = s.stream.chunk_diff(CELL).tree_cuts[id].duplicate(true)
			var hp: float = s.stream.chunk_diff(CELL).resources[id]
			if not check(partial.progress > 0 and partial.progress < 1 and s.save_now(false) == OK, "save a partially notched planted birch"): return
			saved = WastelandSave.read(1)
			open_world(saved.settings, saved)
			await frames(2)
			tree = chunk().standing_trees.get(id)
			if not check(is_instance_valid(tree) and chunk().timber_visuals.has(id) and not tree.get_node("Standing").visible and s.stream.chunk_diff(CELL).tree_cuts[id] == partial and s.stream.chunk_diff(CELL).resources[id] == hp, "load retains one visible notch, its bearing and remaining work"): return
			aim(base + Vector3.UP)
		if not fell(tree): return
		advance(420)
		if not check(wood() == before + int(WastelandSession.RESOURCES[resource][2].wood), model + " falls and releases its normal wood yield exactly once"): return
	s.stream.refresh(AWAY, 2)
	s.stream.refresh(CENTER, 2)
	s.stream.ensure_landing(CENTER)
	for model: String in MODELS:
		if not check(not chunk().standing_trees.has(planted_ids[model]), model + " remains felled after re-streaming"): return
	await verify_uproot()

func verify_uproot() -> void:
	open_world(s.world_settings.duplicate(true), {})
	await frames(2)
	var item := "sapling_birch"
	s.bag.add(item, 1)
	s.bag.assign(item, 0)
	s.bag.active = 0
	var point := find_soil()
	if not check(point.is_finite(), "find dry soil for the transplant"): return
	aim(s.player.camera.global_position + Vector3(0, 6, -1))
	s.simulation_paused = false
	await press_main()
	if not check(s.bag.count(item) == 1 and rows().is_empty(), "clicking the sky preserves the seedling"): return
	while s.action_lock > 0.0: await physics_frame
	face_soil(point)
	await press_main()
	s.simulation_paused = true
	var body := plant_body("birch")
	if not check(is_instance_valid(body), "seedling is available to transplant"): return
	var old_id := id_for("birch")
	var anchor: Vector3 = body.get_node("Standing").global_position
	s.bag.add("shovel", 1)
	s.bag.assign("shovel", 1)
	s.bag.active = 1
	aim(body.global_position)
	var tool: Dictionary = s.catalog.items.shovel
	if not check(s._trace(tool.reach, 15, false, true, true).get("collider") == body, "equipped shovel reaches juvenile stem"): return
	s._melee(tool, 1.0)
	if not check(rows().is_empty() and item_total(item) == 1 and s.bag.count(item) == 0, "uprooting removes the planted record and returns one physical birch seedling"): return
	s.player.global_position = ground(anchor)
	s.fx.collect_nearby()
	if not check(s.bag.count(item) == 1, "survivor picks up transplanted seedling"): return
	s.bag.assign(item, 0)
	s.bag.active = 0
	face_soil(anchor)
	s.simulation_paused = false
	while s.action_lock > 0.0: await physics_frame
	await press_main()
	s.simulation_paused = true
	body = plant_body("birch")
	if not check(is_instance_valid(body) and id_for("birch") != old_id and item_total(item) == 0, "the same seedling can be replanted on its original spot with a fresh identity"): return
	anchor = body.get_node("Standing").global_position
	s.stream.excavate(anchor, 1.0)
	if not check(await until(func(): return s.stream.ground_at(anchor) < anchor.y - 0.38, 8000), "digging lowers the real ground beneath the planted roots"): return
	check(await until(func(): return rows().is_empty() and item_total(item) == 1, 3500), "undercutting the root releases exactly one transplant after the terrain settles")

func host() -> void:
	await frames(2)
	var point := find_soil()
	if not check(point.is_finite(), "prepare a real planting site for guest"): return
	var feet := s.player.global_position
	s.player.global_position = ground(point + Vector3.RIGHT * 7.0)
	var item := "sapling_" + NETWORK_MODEL
	s.bag.add(item, 2)
	s.bag.assign(item, 0)
	s.bag.active = 1
	s.hordes.next_patrol = INF
	s.hordes.next_herd = INF
	s.simulation_paused = false
	if not check(app.network.listen(port) == OK, "sapling authority listens on ENet"): return
	if not check(await until(func(): return not app.network.joined_members().is_empty()), "guest joins authority"): return
	var inventory: WastelandBag = app.network.joined_members()[0].bag
	inventory.add(item, 2)
	app.network.joined_members()[0].survivor.global_position = feet
	app.network.joined_members()[0].survivor.velocity = Vector3.ZERO
	s.ui_command("marker", [Vector2(point.x, point.z), "plant-here"])
	if not check(await until(func(): return is_instance_valid(plant_body(NETWORK_MODEL))), "guest main-hand press plants on authority"): return
	if not check(inventory.count(item) == 1 and s.bag.count(item) == 2 and rows().size() == 1 and s.bag.active == 1, "planting charges only the guest's sapling"): return
	if not check(await until(func(): return marked("juvenile-seen")), "guest acknowledges the young tree"): return
	s.clock.hours += Art.duration_days(NETWORK_MODEL) * 24.0 + 1.0
	if not check(await until(func(): return chunk().standing_trees.has(id_for(NETWORK_MODEL))), "authority advances seedling into a real fir"): return
	if not check(await until(func(): return marked("fir-seen")), "guest acknowledges the mature species"): return
	mark("cycle-done")
	if not check(await until(func(): return marked("rejoined-fir")), "returning guest observes the same frost fir"): return
	mark("rejoin-done")
	await until(func(): return app.network.joined_members().is_empty(), 8000)

func guest() -> void:
	app.network.local_token = Crypto.new().generate_random_bytes(16).hex_encode()
	if not check(app.network.connect_to("127.0.0.1", port) == OK, "connect to real ENet sapling host"): return
	if not check(await until(func(): return is_instance_valid(app.session) and app.session.replica and app.session.stream.active.has(CELL)), "guest bootstraps seeded world"): return
	s = app.session
	if not check(await until(func(): return marked("plant-here") and s.bag.current() == "sapling_" + NETWORK_MODEL), "guest receives selected seedling and host marker"): return
	var target := Vector3.ZERO
	for marker: Dictionary in s.marker_records:
		if marker.name == "plant-here": target = ground(Vector3(marker.at.x, 0, marker.at.y))
	if not check(await until(func(): return s.player.global_position.distance_to(ground(target + Vector3.BACK * 1.85)) < 0.5), "guest is standing at the intended site"): return
	aim(target)
	await frames(14)
	await press_main()
	if not check(await until(func(): return is_instance_valid(plant_body(NETWORK_MODEL)) and s.bag.count("sapling_" + NETWORK_MODEL) == 1), "guest sees one personal debit and the planted juvenile"): return
	if not check(plant_body(NETWORK_MODEL).get_meta("kind", "") == "sapling" and rows().size() == 1, "guest sees only one young tree"): return
	mark("juvenile-seen")
	if not check(await until(func(): return chunk().standing_trees.has(id_for(NETWORK_MODEL))), "mature trunk replicates without reconnecting"): return
	var tree: StaticBody3D = chunk().standing_trees[id_for(NETWORK_MODEL)]
	if not check(tree.get_meta("tree_model", "") == NETWORK_MODEL and tree.collision_layer > 0 and tree.global_position.distance_to(target) < 2.5, "guest sees collidable mature frost fir at the planted location"): return
	mark("fir-seen")
	if not check(await until(func(): return marked("cycle-done")), "host and guest completed one growth cycle"): return
	var planted := rows().duplicate(true)
	app.leave_world()
	if not check(await until(func(): return app.session.preview_only), "guest leaves to title"): return
	if not check(app.network.connect_to("127.0.0.1", port) == OK, "same guest reconnects over ENet"): return
	if not check(await until(func(): return app.session.replica and app.session.stream.active.has(CELL)), "new guest session restores the selected world"): return
	s = app.session
	if not check(await until(func(): return rows() == planted and chunk().standing_trees.has(id_for(NETWORK_MODEL)) and s.bag.count("sapling_" + NETWORK_MODEL) == 1), "rejoining restores one mature frost fir with original variant and planting time"): return
	mark("rejoined-fir")
	check(await until(func(): return marked("rejoin-done")), "authority acknowledges the rejoined guest")
