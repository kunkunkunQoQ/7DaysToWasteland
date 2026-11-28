extends SceneTree

var session: WastelandSession
var failures := 0
var notices: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	WastelandSave.root_override = "user://verification/survival-%d" % OS.get_process_id()
	var config := WastelandSave.default_world()
	config.terrain_revision=2 # Historic Gray Bay coastal fixture.
	config.seed = WastelandSave.seed_number(str(config.seed_label))
	_open_world(config, {})
	_check(session.bag.counts.is_empty() and session.bag.current().is_empty(), "new survivor starts with empty hands and pack")
	session.message.connect(func(words: String, _duration: float): notices.append(words))
	_deliveries()
	_waves()
	await _ecology()
	await _species_and_morphs()
	await _lake_observations()
	_submerged_ruins()
	await _water_route(config)
	await _profiles(config)
	await _light_and_height()
	await session.stream.quiesce()
	await session.audio.finish_playback()
	session.queue_free()
	await process_frame
	print("SURVIVAL failures=%d" % failures)
	quit(1 if failures else 0)

func _open_world(config: Dictionary, snapshot: Dictionary, appearance: String = "ranger") -> void:
	if is_instance_valid(session):
		session.queue_free()
	session = WastelandSession.new()
	root.add_child(session)
	var options := WastelandSettings.new()
	options.appearance = appearance
	session.configure(config, snapshot, 1, WastelandCatalog.new(), options)
	session.simulation_paused = true

func _deliveries() -> void:
	var orders := session.daily_orders()
	_check(orders.size() == 2, "day one offers two routes")
	var order := orders[0]
	var trade_at := Vector3(WastelandSite.BOARD_POSITION.x, 0, WastelandSite.BOARD_POSITION.y)
	trade_at.y = session.stream.ground_at(trade_at)
	session.player.global_position = trade_at
	session.ui_command("job")
	session.ui_command("deliver", [order.id])
	_check(session.progress.delivery_day == 0 and session.progress.xp == 0, "missing goods leave order open")
	for id in order.inputs:
		session.bag.add(id, int(order.inputs[id]) * 2)
	session.player.global_position += Vector3.RIGHT * 18.0
	session.ui_command("deliver", [order.id])
	_check(session.progress.delivery_day == 0, "delivery requires the lodge")
	session.player.global_position = trade_at
	session.ui_command("deliver", [order.id])
	var settled := session.bag.snapshot()
	var earned := session.progress.xp
	_check(session.progress.delivery_day == 1 and earned == order.xp and session.bag.count("berries") == order.inputs.berries, "delivery spends exactly one basket")
	session.ui_command("deliver", [order.id])
	_check(settled == session.bag.snapshot() and earned == session.progress.xp, "duplicate request pays once")
	_check(session.progress.accepted and session.progress.job == 0, "story commission remains active")
	_check(session.save_now(false) == OK, "settled order saves")
	var saved := WastelandSave.read(1)
	_check(WastelandProgression.new(saved.progress).delivery_day == 1 and WastelandProgression.new({"job":2}).delivery_day == 0, "new and legacy progress restore")
	session.clock.hours += 24.0
	_check(session.daily_orders()[0].id != order.id, "next day rotates routes")
	session.ui_command("deliver", [order.id])
	_check(settled == session.bag.snapshot(), "stale order rejected after midnight")
	var next := session.daily_orders()[0]
	for id in next.inputs:
		session.bag.add(id, int(next.inputs[id]))
	session.ui_command("deliver", [next.id])
	_check(session.progress.delivery_day == 2, "next day can settle independently")

func _waves() -> void:
	var director := session.hordes
	session.clock.hours = 6.0 * 24.0 + 22.0
	director.next_patrol = INF
	director.next_herd = INF
	director.simulate(1.0)
	for wave in range(1, 4):
		for actor in director.alive.duplicate():
			director.release(actor)
		session.clock.elapsed = director.next_wave
		director.simulate(1.0)
		_check(director.wave_index == wave, "wave %d actually arrived" % wave)
		if wave == 1 and not director.alive.is_empty():
			director.defeated(director.alive.front())
		if wave == director.wave_total:
			_check(wave in [3,4], "last scheduled assault ends the finite wave sequence")
			break
		var respite: float = director.next_wave - director.assault_until
		_check(respite >= 15.0 and respite <= 25.0, "assault leaves a 15–25-second recovery interval")
		session.clock.elapsed = director.next_wave - 5.5
		director.simulate(1.0)
		_check(director.approach_announced and notices.back().contains("方传来动静"), "approach warning precedes wave")
		var saved := director.snapshot()
		_check(saved.approach_announced and saved.approach_angle == director.approach_angle and saved.kills == 1, "pending bearing and kills persist")
	session.clock.hours = 7.0 * 24.0 + 4.0
	director.simulate(1.0)
	_check(session.progress.records.get("horde", 0) == 1 and notices.back().contains("击退 1"), "dawn awards cleared night and reports kills")
	director.simulate(1.0)
	_check(session.progress.records.get("horde", 0) == 1, "dawn settlement is idempotent")

func _ecology() -> void:
	var director := session.hordes
	for actor in director.alive.duplicate():
		director.release(actor)
	var lodge := Vector3(-16.0, 0.0, 48.0)
	session.stream.ensure_landing(lodge)
	session.player.global_position = lodge
	session._discover_site(session.player)
	session._discover_site(session.player)
	_check(session.progress.records.get("visit_lodge", 0) == 1, "entering a new site type records a single discovery")
	session.clock.hours = 7.5
	var spawn := session.start_position()
	for z in [-1, 0, 1]:
		for x in [-1, 0, 1]:
			session.stream.ensure_landing(spawn + Vector3(x * 32, 0, z * 32))
	for attempt in 30:
		director._new_herd(spawn, 4)
		if director.alive.any(func(actor): return actor.type == "stag"):
			break
		for actor in director.alive.duplicate():
			director.release(actor)
	var deer := director.alive.filter(func(actor): return actor.type == "stag")
	_check(deer.size() >= 2 and deer.size() <= 4, "twilight shores generate a group of deer")
	if deer.size() < 2:
		return
	var subject: WastelandCreature = deer[0]
	var sibling: WastelandCreature = deer[1]
	_check(subject.brain.herd > 0 and sibling.brain.herd == subject.brain.herd and sibling.brain.home == subject.brain.home and subject.serialize().home == subject.brain.home, "herd shares a saved feeding ground")
	_check(director.wildlife_activity("stag") == "沿岸饮水", "deer use water at twilight")
	var home := subject.brain.home
	session.clock.hours = 23
	_check(director.wildlife_activity("stag") == "隐入密林" and director.wildlife_activity("boar") == "林地拱食" and "stag" not in director._candidates_at(home), "nocturnal schedule favors boar")
	director._spawn("walker", subject.global_position + Vector3.RIGHT * 3, false)
	_check(director.wildlife_danger(subject).is_finite(), "infected presence alarms nearby wildlife")
	subject.global_position = spawn + Vector3(0, 13, -13)
	session.player.global_position = spawn + Vector3.UP * 13
	session.player.camera.look_at(subject.global_position + Vector3.UP * 0.8)
	await physics_frame
	session._use()
	session._use()
	_check(session.progress.records.get("observe_stag", 0) == 1, "observation at a distance records the animal once")

func _species_and_morphs() -> void:
	var director := session.hordes
	for actor in director.alive.duplicate():
		director.release(actor)
	var seen := {}
	var origin := session.start_position()
	var forest := Vector3.INF
	for z in range(-224, 225, 24):
		for x in range(-224, 225, 24):
			if session.stream.generator.biome(x, z) == 1 and session.stream.generator.ground(x, z) > 1.5:
				var candidate := Vector3(x, 0, z)
				if not forest.is_finite() or origin.distance_squared_to(candidate) < origin.distance_squared_to(forest):
					forest = candidate
	_check(forest.is_finite(), "world seed contains a woodland habitat")
	if not forest.is_finite():
		return
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		session.stream.ensure_landing(forest + Vector3(offset.x * 32, 0, offset.y * 32))
	for hour in [7.5, 13.0, 17.5, 22.0]:
		session.clock.hours = hour
		for attempt in 22:
			director._new_herd(origin if attempt % 2 == 0 else forest, 4)
			for animal in director.alive.duplicate():
				seen[animal.type] = true
				director.release(animal)
	_check(["stag","boar","fox","hare","wolf","badger"].all(func(id):return seen.has(id)), "all six Gray Bay wildlife species can form groups across shore, woodland and day cycle")
	var arena := origin + Vector3.UP * 12
	director._spawn("wolf", arena, false, {"morph":"local"})
	var wolf: WastelandCreature = director.alive.back()
	director._spawn("hare", arena + Vector3.RIGHT, false, {"morph":"young"})
	var hare: WastelandCreature = director.alive.back()
	_check(wolf.display_name().contains("地方色") and hare.display_name().contains("幼年") and hare.max_health() < float(hare.spec.hp) * float(session.world_settings.difficulty), "wildlife morphs carry distinct names and health")
	_check(director.hunt_target(wolf, wolf.spec.ecology.prey) == hare and director.wildlife_danger(hare).is_finite(), "predator recognizes prey and prey recognizes predator")
	wolf.brain.cooldown = 0
	var hp := hare.hp
	wolf.brain._pursue(hare)
	_check(hare.hp < hp and not session.progress.records.has("kill_hare"), "pursuit affects prey without crediting the player")
	if hare.hp > 0.0:
		director.defeated(hare)
	else:
		director._spawn("hare", arena, false, {"morph":"young"})
		director.defeated(director.alive.back())
	var remains: Dictionary = session.fx.drop_records[str(session.fx.serial)].items
	_check(remains.raw_meat in [1, 2] and int(remains.get("leather", 0)) <= 1 and session.progress.records.get("kill_hare_young", 0) == 1, "hare has species-sized harvest and individual morph record")
	var genetics := {}
	for i in 100:
		genetics[director._roll_morph(false)] = true
	_check(genetics.has_all(["","armored","swift"]), "natural infection population can produce all three morphs")
	director._spawn("walker", arena, false, {"morph":"armored"})
	var armored: WastelandCreature = director.alive.back()
	var record := armored.serialize()
	director.release(armored)
	director._spawn("walker", arena, false, record)
	var restored: WastelandCreature = director.alive.back()
	_check(restored.morph == "armored" and restored.hp == restored.max_health(), "morph survives save and health restoration")
	director.defeated(restored)
	_check(session.progress.records.get("kill_walker_armored", 0) == 1, "infected kill records include morph")
	for i in WastelandHordes.CAP:
		director._spawn("walker", arena, true, {"hp":35})
	_check(director.alive.size() - director.wildlife_count == WastelandHordes.CAP and director._spawn("fox", arena, false), "full infected pool leaves free wildlife capacity")
	for actor in director.alive.duplicate():
		director.release(actor)

func _lake_observations() -> void:
	var lake := session.stream.lake_wildlife
	_check(not lake.habitats.is_empty(), "lake wildlife has observation habitats")
	if lake.habitats.is_empty():
		return
	var patch = lake.habitats[0]
	var bird: Vector3 = patch.bird.global_position + Vector3.UP * 0.94
	session.stream.ensure_landing(bird)
	session.player.global_position = bird + Vector3.UP * 8.0
	session.player.camera.look_at(bird, Vector3.FORWARD)
	var barrier := WastelandLook.solid(session, Vector3(3,0.5,3), bird + Vector3.UP * 5.0, Color.BROWN)
	await physics_frame
	session._use()
	_check(not session.progress.records.has("observe_heron"), "opaque cover blocks observation")
	barrier.queue_free()
	await physics_frame
	await physics_frame
	session._use()
	_check(session.progress.records.get("observe_heron", 0) == 1, "unobstructed bird enters field notes")
	session.clock.elapsed += 1
	lake.countdown = 0.0
	lake._process(1.0)
	var fish: Vector3 = patch.fish_center
	if fish.is_finite():
		session.player.global_position = fish + Vector3.UP * 6.0
		session.player.camera.look_at(fish, Vector3.FORWARD)
		session._use()
	_check(session.progress.records.get("observe_lake_fish", 0) == 1, "fish can be observed through the lake surface")

func _submerged_ruins() -> void:
	var sites := WastelandSunkenSites.landmarks(session.stream.generator)
	for id in ["ferry", "pump", "bridge"]:
		if not sites.has(id):
			_check(false, id + " generated")
			continue
		var point: Vector3 = sites[id]
		session.stream.ensure_landing(point)
		var chunk: WastelandChunk = session.stream.active[WastelandTerrainGen.chunk_at(Vector2(point.x, point.z))]
		var recovered := false
		for body in chunk.decoration_root.get_children():
			if body.get_meta("submerged_site", "") == id:
				preload("res://tools/chest_actions.gd").take_all(session,body)
				preload("res://tools/chest_actions.gd").take_all(session,body)
				recovered = session.progress.records.get("recover_" + id, 0) == 1
				break
		_check(recovered, id + " remains record first successful recovery only")

func _water_route(config: Dictionary) -> void:
	_check(session.vehicles.has("landing_boat") and session.fx.drop_records.size() >= 2, "new coast starts with a boat and supplies")
	if not session.vehicles.has("landing_boat") or not session.fx.drop_records.has("shore_float"):
		return
	var boat: WastelandVehicle = session.vehicles.landing_boat
	session.stream.ensure_landing(boat.global_position)
	_check(session.stream.water_at(boat.global_position) and session.stream.ground_at(boat.global_position) < -0.9 and boat.record.needs_repair and boat.repair_marker.visible, "new boat is visibly damaged in navigable water")
	session.player.global_position = boat.global_position + Vector3.RIGHT * 2.0
	session.player.ride(boat)
	session.ui_command("vehicle", ["landing_boat", true])
	_check(not boat.occupied and session.vehicle_records.has("landing_boat") and session.bag.count("boat") == 0, "wreck cannot be boarded or packed")
	session.bag.spend({"wood":session.bag.count("wood")})
	session.ui_command("repair_vehicle", ["landing_boat"])
	_check(boat.record.needs_repair, "missing repair materials leave hull damaged")
	for material in WastelandSession.BOAT_REPAIR:
		session.bag.add(material, int(WastelandSession.BOAT_REPAIR[material]) * 2)
	var wood := session.bag.count("wood")
	var fuel := session.bag.count("fuel")
	session.ui_command("repair_vehicle", ["landing_boat"])
	session.ui_command("repair_vehicle", ["landing_boat"])
	_check(not boat.record.needs_repair and not boat.repair_marker.visible and session.bag.count("wood") == wood - 6 and session.bag.count("fuel") == fuel and session.progress.records.get("repair_boat") == 1, "repair consumes materials once and unlocks the hull")
	var buoy: Vector3 = session.fx.drop_records.shore_float.point
	session.stream.ensure_landing(buoy)
	_check(session.stream.water_at(buoy) and session.fx.drop_live.has("shore_float"), "nearby floating cache is visible and over water")
	session.player.ride(boat)
	boat.global_position = buoy + Vector3(0, -0.15, 2.6)
	session.player.global_position = boat.global_position + Vector3.UP * boat.seat_height()
	session.player.camera.look_at(buoy + Vector3.UP * 0.45)
	await physics_frame
	var original_bag := session.bag
	session.bag = WastelandBag.new(session.catalog, {"counts":{"scrap":3465, "clean_water":9}})
	for slot in WastelandBag.HOTBAR_SIZE: session.bag.put_from_pack("scrap",slot,session.bag.stack_size("scrap"))
	session._use()
	_check(session.bag.count("clean_water") == 10 and session.fx.drop_records.shore_float.items.clean_water == 1 and not session.progress.records.has("salvage_buoy"), "partial salvage keeps unclaimed supplies and defers completion")
	session._use()
	_check(session.fx.drop_records.shore_float.items.clean_water == 1, "full bag preserves remaining cargo")
	session.bag = original_bag
	var count := session.bag.count("tape")
	session._use()
	_check(session.player.mount_vehicle == boat and not session.fx.drop_records.has("shore_float") and session.bag.count("tape") == count + 2, "use from helm recovers cargo and remains aboard")
	session.fx.take_drop("shore_float")
	_check(session.progress.records.get("salvage_buoy", 0) == 1 and session.bag.count("tape") == count + 2, "emptied cache cannot pay twice")
	session.player.dismount()
	_check(not is_instance_valid(session.player.mount_vehicle), "can leave boat in open water")
	session.vehicle_service("landing_boat", true)
	_check(not session.vehicle_records.has("landing_boat"), "boat packs back into inventory")
	session.save_now(false)
	var saved := WastelandSave.read(1)
	await session.stream.quiesce()
	_open_world(config, saved)
	_check(not session.vehicle_records.has("landing_boat") and not session.fx.drop_records.has("shore_float") and session.fx.drop_records.has("survey_float"), "reload preserves claimed cache, packed boat and unopened cache")
	var legacy := config.duplicate()
	legacy.erase("terrain_revision")
	await session.stream.quiesce()
	_open_world(legacy, {})
	_check(not session.vehicle_records.has("landing_boat") and session.fx.drop_records.is_empty(), "legacy shoreline keeps original assets")

func _profiles(config: Dictionary) -> void:
	var profiles := preload("res://game/core/survivor_profiles.gd").STATS
	var player := session.player
	var full_caps := true
	for id in profiles:
		player.set_profile(id)
		var spec: Dictionary = profiles[id]
		full_caps = full_caps and player.max_health() == spec.health and player.max_stamina() == spec.stamina and player.max_breath() == spec.breath
		full_caps = full_caps and player.health == player.max_health() and player.stamina == player.max_stamina() and player.breath == player.max_breath()
	_check(profiles.size() == WastelandPartyAvatar.OUTFITS.size() and profiles.has("bronx") and full_caps, "all selectable characters expose distinct capacities and a fresh survivor starts full")
	player.health *= 0.43
	player.stamina *= 0.25
	player.breath *= 0.40
	var preserved := true
	for i in 12:
		for id in profiles:
			player.set_profile(id)
			preserved = preserved and is_equal_approx(player.health / player.max_health(), 0.43) and is_equal_approx(player.stamina / player.max_stamina(), 0.25) and is_equal_approx(player.breath / player.max_breath(), 0.40)
	_check(preserved, "repeated switches preserve injury, exhaustion and air ratios")
	player.set_profile("medic")
	session.save_now(false)
	var saved := WastelandSave.read(1)
	await session.stream.quiesce()
	_open_world(config, saved, "ferryman")
	player = session.player
	_check(player.profile == "ferryman" and is_equal_approx(player.health, 105.0 * 0.43) and is_equal_approx(player.breath, 10.0), "cross-character reload preserves fractions using saved capacities")
	session.progress.skills.fitness = 2
	var expected_stamina := (90.0 + 24.0) * 0.5
	player.restore_vitals({"health":50.0, "stamina":62.0, "breath":9.0})
	_check(is_equal_approx(player.health, 52.5) and is_equal_approx(player.stamina, expected_stamina) and is_equal_approx(player.breath, 12.5), "legacy save converts the original capacities including fitness ranks")
	player.health = 0.0
	player.set_profile("climber")
	_check(is_zero_approx(player.health), "switching does not revive a downed player")
	session.respawn()
	_check(player.health == player.max_health() and player.stamina == player.max_stamina() and player.breath == player.max_breath() and session.bag.count("club") == 0, "revive uses current capacities without granting a weapon")

func _light_and_height() -> void:
	var player := session.player
	player.toggle_lamp()
	_check(not player.flashlight and not player.headlamp.visible, "no free light without a lantern")
	var recipe: Dictionary = session.catalog.recipes.torch
	for id in recipe.inputs:
		session.bag.add(id,int(recipe.inputs[id]))
	session.ui_command("craft", ["torch", 1, null])
	if not session.hand_queue.is_empty():
		session.clock.elapsed = float(session.hand_queue.front().done) + 0.1
		session._finish_crafting()
	_check(session.bag.count("torch") == 1, "basic materials produce a lantern by hand")
	session.bag.assign("torch",0)
	player.sync_lamp(session.bag.current())
	_check(player.headlamp.visible, "equipping a crafted lantern lights it")
	player.toggle_lamp()
	player.sync_lamp(session.bag.current())
	_check(not player.headlamp.visible, "held lantern can be switched off")
	player.toggle_lamp()
	session.discard("torch")
	_check(session.bag.count("torch")==1,"first discard protects the held lantern")
	session.discard("torch")
	player.sync_lamp(session.bag.current())
	_check(not player.headlamp.visible and not player.flashlight, "dropping lantern extinguishes the light")
	var at := session.start_position() + Vector3.UP * 15
	player.global_position = at
	player.crouch = 0
	player.set_profile("medic")
	_check(is_equal_approx(player.eyes.position.y, 1.62 * player.stature()) and is_equal_approx(player.stand_shape.height, 1.78 * player.stature()), "standing eye and capsule use chosen stature")
	var roof := WastelandLook.solid(session,Vector3(2,0.20,2),at + Vector3.UP * 1.76,Color.BROWN)
	await physics_frame
	await physics_frame
	player.set_profile("climber")
	_check(player.stand_shape.height < 1.66 and player.crouch > 0.9 and player.eyes.position.y < player.stand_shape.height, "taller character crouches under a low overhang")
	roof.queue_free()
	await physics_frame
	await physics_frame
	player.crouch = 0.0
	player._apply_posture(false)
	_check(is_equal_approx(player.stand_shape.height, 1.78 * player.stature()), "tall capsule reaches full height in open space")
	player._apply_posture(true)
	_check(is_equal_approx(player.eyes.position.y, 1.45 * player.stature()), "seated eye height scales with character")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)
