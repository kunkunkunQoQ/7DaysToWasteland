extends "res://tools/verify_tree_felling.gd"

const SNAG := Vector3(287.262,20.13068,243.4607)
const PINE := Vector3(-62.08575,1.908671,77.78786)

func drop_ids(item: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in s.fx.drop_records:
		if s.fx.drop_records[id].items.has(item) and not s.fx.drop_records[id].get("buoy",false):
			ids.append(id)
	return ids

func simulate_drops(frames: int) -> void:
	for i in frames: s.fx.simulate(STEP)

func settle_drops() -> void:
	# Flush shape rotations to the physics server as they would be in play.
	for batch in 24:
		simulate_drops(30)
		await physics_frame

func load_disk() -> void:
	var state := WastelandSave.read(1)
	open_world(state.settings,state)
	await physics_frame
	await physics_frame

func offline() -> void:
	await physics_frame
	await physics_frame
	stage()
	equip_axe()
	var tree := trunk()
	if not check(is_instance_valid(tree),"seeded living oak is in axe reach"): return
	var wood_before := wood()
	var fiber_before := item_total("fiber")
	var sticks_before := item_total("stick")
	var leaves_before := item_total("tree_leaf")
	if not chop(tree): return
	check(item_total("tree_leaf") == leaves_before, "shallow first notch releases no leaf items")
	if not chop(tree): return
	var partial := drop_ids("tree_leaf")
	if not check(partial.size() == 1 and item_total("tree_leaf") == leaves_before + 1 and trunk() != null and active_falls().is_empty(),"crossing half depth releases one leaf from a still-standing oak"): return
	var leaf: String = partial[0]
	var start: Vector3 = s.fx.drop_records[leaf].point
	check(start.y > CENTER.y + 2.0 and start.distance_to(tree.global_position) < 15.0, "collectible leaf originates above the cut in the crown")
	if not check(s.fx.drop_live.has(leaf),"crown release has a live pickup body"): return
	var art: MeshInstance3D = s.fx.drop_live[leaf].get_node("Item")
	var initial_orientation := art.global_basis
	simulate_drops(24)
	var row: Dictionary = s.fx.drop_records[leaf].duplicate(true)
	var movement := Vector3(row.point) - start
	check(movement.slide(Vector3.UP).length() > 0.025 and not initial_orientation.is_equal_approx(art.global_basis), "airborne leaf travels sideways and changes orientation")
	var half_total := item_total("tree_leaf")
	if not check(s.save_now(false) == OK,"save a half-cut oak and its airborne leaves"): return
	await load_disk()
	if not check(s.fx.drop_records.get(leaf,{}) == row and item_total("tree_leaf") == half_total, "loading restores the same airborne pickup and no extra threshold payout"): return
	stage()
	if not fell(trunk()): return
	check(item_total("tree_leaf") == half_total and item_total("stick") == sticks_before,"repeated cuts above the threshold and the severing blow cannot farm leaves or sticks")
	var during_contact := {}
	for i in 420:
		advance(1)
		if during_contact.is_empty() and item_total("stick") > sticks_before and not active_falls().is_empty():
			if s.save_now(false) == OK: during_contact = WastelandSave.read(1)
	var leaf_total := item_total("tree_leaf")
	var stick_total := item_total("stick")
	check(leaf_total - half_total in range(4,8) and stick_total - sticks_before in range(2,5), "falling oak releases four to seven further leaves and two to four sticks")
	check(wood() == wood_before + int(WastelandSession.RESOURCES.oak[2].wood) and item_total("fiber") == fiber_before + int(WastelandSession.RESOURCES.oak[2].fiber), "original oak wood and fiber yields are preserved")
	if not check(not during_contact.is_empty(), "can save between canopy impact and the final log payout"): return
	open_world(during_contact.settings,during_contact)
	await physics_frame
	await physics_frame
	advance(420)
	check(item_total("tree_leaf") == leaf_total and item_total("stick") == stick_total and wood() == wood_before + int(WastelandSession.RESOURCES.oak[2].wood), "resuming after canopy impact pays no second set of leaves or sticks")
	# Reconstruct the older save format after crown contact, before logs settled.
	var legacy := during_contact.duplicate(true)
	for fall: Dictionary in legacy.falling_trees.values():
		fall.erase("canopy_spent")
		fall.cut.erase("leaf_shaken")
	for id: String in legacy.drops.keys():
		var items: Dictionary = legacy.drops[id].items
		if items.has("tree_leaf") or items.has("stick"): legacy.drops.erase(id)
	open_world(legacy.settings,legacy)
	await physics_frame
	advance(420)
	check(item_total("tree_leaf") == leaf_total - 1 and item_total("stick") == stick_total and wood() == wood_before + int(WastelandSession.RESOURCES.oak[2].wood), "pre-canopy save already past crown contact awards its outstanding branches and leaves on settling")
	await settle_drops()
	await physics_frame
	await collect_canopy("tree_leaf")
	await collect_canopy("stick")
	if not check(s.bag.count("tree_leaf") > 0 and s.bag.count("stick") > 0,"normal proximity pickup transfers the actual canopy materials to inventory"): return
	await verify_motion()
	await verify_tree_model("snag",SNAG,"0")
	await verify_tree_model("pine",PINE,"2")
	await verify_woodland()

func collect_canopy(item: String) -> void:
	await physics_frame
	for id in drop_ids(item):
		if not s.fx.drop_records.has(id): continue
		var row: Dictionary = s.fx.drop_records[id]
		var point: Vector3 = row.point
		var shape: CollisionShape3D = s.fx.drop_live[id].get_node("PickupShape")
		check(row.get("resting",false) and supported(shape),"settled " + item + " rests against a solid surface within its collision footprint")
		s.player.global_position = point
		s.fx.collect_nearby()
		check(not s.fx.drop_records.has(id), "walking up collects " + item)

func supported(shape: CollisionShape3D) -> bool:
	var half: Vector3 = (shape.shape as BoxShape3D).size * 0.5
	for x in [-half.x,0,half.x]:
		for z in [-half.z,0,half.z]:
			var sole := shape.to_global(Vector3(x,-half.y,z))
			var ray := PhysicsRayQueryParameters3D.create(sole + Vector3.UP * 0.08,sole - Vector3.UP * 0.08,3)
			var hit := s.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty(): continue
			# Standing resource boxes end halfway up the render mesh, with no physical branch there.
			if hit.collider.has_meta("tree_pose") and hit.normal.y > 0.55: continue
			return true
	return false

func toss(item: String, feet: Vector3) -> String:
	s.player.global_position = feet
	s.player.rotation.y = 0.0
	s.player.pitch = 0.0
	s.player.eyes.rotation.x = 0.0
	s.discard(item)
	return str(s.fx.serial)

func verify_motion() -> void:
	var deck_at := ground(CENTER) + Vector3.UP * 24.0
	s.stream.ensure_landing(deck_at)
	WastelandLook.solid(s, Vector3(14,0.12,14),deck_at,Color.GRAY)
	await physics_frame
	var leaf := toss("tree_leaf",deck_at + Vector3.UP * 3.0)
	var stick := toss("stick",deck_at + Vector3.UP * 3.0 + Vector3.RIGHT)
	if not check(s.fx.drop_records[leaf].items.has("tree_leaf") and s.fx.drop_records[stick].items.has("stick"), "normal inventory discard makes two independent, visible pickups"): return
	var branch_art: MeshInstance3D = s.fx.drop_live[stick].get_node("Item")
	var branch_start := branch_art.global_basis
	simulate_drops(33)
	check(s.fx.drop_records[leaf].point.y > s.fx.drop_records[stick].point.y + 0.45, "at the same height and impulse a leaf descends slower than a stick")
	check(not branch_start.is_equal_approx(branch_art.global_basis), "airborne branch turns under its throw")
	simulate_drops(80)
	check(not s.fx.drop_records[leaf].get("resting",false) and absf(s.fx.drop_records[stick].point.y - deck_at.y) < 0.25, "stick reaches the deck while the leaf is still airborne")
	await settle_drops()
	check(absf(s.fx.drop_records[leaf].point.y-deck_at.y) < 0.25 and s.fx.drop_records[leaf].get("resting",false), "fallen leaf rests on the elevated collidable deck")
	check(s.fx.drop_records[stick].get("resting",false) and absf(branch_art.global_basis.y.normalized().dot(Vector3.UP)) < 0.12, "fallen branch rests with its long axis parallel to the deck")
	var lake := Vector3(13,0,-46)
	s.stream.refresh(lake,2)
	s.stream.ensure_landing(lake)
	await physics_frame
	await physics_frame
	if not check(s.stream.water_at(lake) and s.stream.ground_at(lake) < -1.0, "water test uses a streamed lake with a submerged bed"): return
	if not check(s.bag.count("tree_leaf") > 0, "a second harvested leaf is available to drop into the water"): return
	leaf = toss("tree_leaf",lake + Vector3.UP * 1.2)
	await settle_drops()
	var floating: Vector3 = s.fx.drop_records[leaf].point
	check(absf(floating.y - WastelandTerrainGen.WATER_LEVEL) < 0.10 and floating.y - s.stream.ground_at(floating) > 0.8, "discarded leaf floats at the lake surface")

func verify_tree_model(model: String, base: Vector3, index: String) -> void:
	s.stream.refresh(base,2)
	s.stream.ensure_landing(base)
	await physics_frame
	await physics_frame
	var cell := WastelandTerrainGen.chunk_at(Vector2(base.x,base.z))
	var target: StaticBody3D = s.stream.active[cell].standing_trees.get(index)
	if not check(is_instance_valid(target) and target.get_meta("tree_model") == model, "seeded " + model + " has a real harvestable trunk"): return
	s.player.global_position = ground(base - FALL * 1.7)
	aim(base + Vector3.UP)
	equip_axe()
	var leaves := item_total("tree_leaf")
	var sticks := item_total("stick")
	var serial := s.fx.serial
	if not fell(target): return
	advance(420)
	if model == "snag":
		check(item_total("tree_leaf") == leaves and item_total("stick") - sticks in range(3,6), "chopping and felling a leafless snag yields three to five sticks and zero leaves")
	else:
		check(item_total("tree_leaf") - leaves in range(4,7) and item_total("stick") - sticks in range(2,5), "pine sheds one sample then three to five more needle units and two to four sticks")
		for id in drop_ids("tree_leaf"):
			if int(id) <= serial: continue
			check(s.fx.drop_records[id].get("leaf_model","") == model, "needle pickup retains the pine appearance")

func verify_woodland() -> void:
	open_world(s.world_settings.duplicate(true),{})
	await physics_frame
	await physics_frame
	stage()
	var leaves := item_total("tree_leaf")
	s.timber.woodland(20)
	var loose := drop_ids("tree_leaf")
	if not check(loose.size() == 1 and item_total("tree_leaf") == leaves + 1 and trunk() != null,"a gust in standing woodland creates one collectible leaf without chopping"): return
	var first: String = loose[0]
	s.clock.hours += 24.0
	s.timber.woodland(20)
	check(drop_ids("tree_leaf") == loose, "the next day's gust leaves the existing uncollected leaf in place")
	await settle_drops()
	await collect_canopy("tree_leaf")
	stage()
	s.timber.woodland(20)
	loose = drop_ids("tree_leaf")
	if not check(loose.size() == 1 and loose[0] != first and item_total("tree_leaf") == leaves + 2, "a later day's gust can replace the collected leaf"): return
	await settle_drops()
	var point: Vector3 = s.fx.drop_records[loose[0]].point
	check(absf(point.y - s.stream.ground_at(point)) < 0.15, "second natural leaf passes the neighboring trunk's artificial top and reaches terrain")
	await collect_canopy("tree_leaf")
	if not check(s.save_now(false) == OK, "save after gathering the day's natural litter"): return
	await load_disk()
	stage()
	s.timber.woodland(20)
	check(drop_ids("tree_leaf").is_empty() and item_total("tree_leaf") == leaves + 2, "reloading and revisiting the same tree cannot renew that day's natural payout")
