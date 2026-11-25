extends "res://tools/verify_combat.gd"

const STATE := WastelandCreatureBrain.State

func _run() -> void:
	WastelandSave.root_override = "user://verification/infected-fsm-%d" % OS.get_process_id()
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	var config: Dictionary = app._default_config()
	config.seed = 77026023
	config.start_id = "seeded"
	app._enter_world(config, {}, 0, false)
	session = app.session
	player = session.player
	session.hordes.next_patrol = INF
	session.hordes.next_herd = INF
	await _ticks(25)
	session.simulation_paused = true
	for actor in session.hordes.alive.duplicate():
		session.hordes.release(actor)
	_make_arena()
	for x: float in [-12.0, 12.0]:
		for z: float in [-12.0, 12.0]:
			session.stream.ensure_landing(anchor + Vector3(x,0,z))
	await _ticks(4)
	await _senses()
	await _regions()
	await _crowd()
	await _cover_and_route()
	await _detour_and_recovery()
	await _fall_and_rage()
	await _terrain_wall()
	await _stairs()
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	print("INFECTED FSM: ", passes, " passed, ", failures.size(), " failed")
	for issue in failures: printerr("FAILED: " + issue)
	quit(0 if failures.is_empty() else 1)

func _senses() -> void:
	var bed := anchor + Vector3(0,0.04,6)
	player.global_position = bed + Vector3.BACK * 4
	player.crouch = 1.0
	var sleeper := _spawn("walker", bed, bed + Vector3.FORWARD, {"sleeping": true, "nest": "ruin", "limb_index": 0})
	session.hordes.add_noise(player.global_position, 1.5)
	await _ticks(42, [sleeper])
	check(sleeper.brain.state == STATE.SLEEPING and sleeper.rig.rotation.z > 1.3 and not sleeper.alerted, "a crouching survivor behind a quiet sleeper stays undetected")
	session.hordes.add_noise(bed,32,false)
	await _ticks(1,[sleeper])
	check(sleeper.brain.state == STATE.SLEEPING,"another infected's scream alone does not wake a sleeper")
	session.hordes.add_noise(player.global_position, 14)
	await _ticks(1, [sleeper])
	check(sleeper.brain.state == STATE.WAKING and sleeper.brain.state_left >= 0.8 and sleeper.brain.state_left <= 1.2, "axe impact starts the timed rising animation immediately")
	var remaining := sleeper.brain.state_left
	await _ticks(ceili(remaining * 60.0) + 1, [sleeper])
	check(sleeper.brain.state in [STATE.CHASE, STATE.INVESTIGATE], "rising finishes before pursuing the last cue")
	session.hordes.release(sleeper)
	sleeper = _spawn("walker", bed, bed + Vector3.FORWARD, {"sleeping":true, "limb_index":0})
	player.crouch = 0.0
	player.headlamp.visible = true
	player.headlamp.look_at(sleeper.brain._eyes())
	var cover := _box(Vector3(0,1.3,8), Vector3(2,2.6,0.2), 2)
	await _ticks(45, [sleeper])
	check(sleeper.brain.state == STATE.SLEEPING, "opaque cover blocks the flashlight channel")
	cover.queue_free()
	await _ticks(2)
	await _ticks(30, [sleeper])
	check(sleeper.brain.state == STATE.SLEEPING, "half a second of clear flashlight exposure is insufficient")
	await _ticks(9, [sleeper])
	check(sleeper.brain.state == STATE.WAKING, "sustained flashlight exposure wakes the sleeper outside its own vision cone")
	player.headlamp.visible = false
	session.hordes.release(sleeper)
	player.global_position = bed + Vector3.FORWARD * 15.0
	var wanderer := _spawn("walker", bed, bed + Vector3.BACK, {"limb_index":0})
	session.hordes.add_noise(bed + Vector3.BACK * 0.6, 5.0)
	await _ticks(4, [wanderer])
	check(wanderer.brain.state == STATE.INVESTIGATE and wanderer.brain.mode == BRAIN.Mode.SEARCH, "unseen noise starts a search on arrival")
	await _ticks(150, [wanderer])
	check(wanderer.brain.state == STATE.INVESTIGATE, "the three-second search holds its position")
	await _ticks(48, [wanderer])
	check(wanderer.brain.state == STATE.WANDER, "an exhausted search returns to wandering")
	session.hordes.release(wanderer)

func _regions() -> void:
	var at := anchor + Vector3(0,0.04,5)
	var actor := _spawn("walker", at, at + Vector3.FORWARD, {"limb_index":0})
	await _ticks(3)
	for zone: String in ["head","torso","legs"]:
		var area: Area3D = actor.hurtboxes.areas[zone]
		var point: Vector3 = area.get_child(0).global_position
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.FORWARD * 1.2, point, 32)
		ray.collide_with_areas = true
		var result := actor.get_world_3d().direct_space_state.intersect_ray(ray)
		check(result.get("collider") == area, "a physical ray picks the " + zone + " zone independently")
	var before := actor.hp
	actor.hit_zone("head", 3.0, at + Vector3.FORWARD)
	check(is_equal_approx(before - actor.hp,6.0) and actor.brain.state in [STATE.STAGGER,STATE.KNOCKDOWN], "headshot doubles damage and interrupts movement")
	session.hordes.release(actor)
	actor = _spawn("walker",at,at + Vector3.FORWARD,{"limb_index":0,"sleeping":true})
	before = actor.hp
	actor.hit_zone("head",3.0,at+Vector3.BACK,false,true)
	check(is_equal_approx(before - actor.hp,9.0), "an unnoticed stealth headshot triples base damage")
	session.hordes.release(actor)
	actor = _spawn("walker",at,at + Vector3.FORWARD,{"limb_index":0})
	var speed := actor.max_move_speed()
	before = actor.hp
	actor.hit_zone("legs",3.0,at)
	actor.hit_zone("legs",3.0,at)
	check(is_equal_approx(before - actor.hp,4.8) and is_equal_approx(actor.max_move_speed(),speed * 0.5) and is_equal_approx(actor.limp_left,3.5) and actor.brain.state == STATE.KNOCKDOWN, "two leg strikes knock down and halve speed for 3.5 seconds")
	actor.take_hit(999,at)
	check(actor.active and actor.brain.state == STATE.DEAD and actor.hurtboxes.areas.head.collision_layer == 0, "the corpse persists with all hitboxes disabled")
	actor.think(WastelandCreature.CORPSE_SECONDS-0.2,session.player)
	check(actor.active and session.hordes.corpses.has(actor),"a dead infected still occupies its corpse slot shortly before expiry")
	actor.think(0.25,session.player)
	check(not actor.active, "the corpse returns to its object pool")
	var reused := _spawn("walker", at, at + Vector3.FORWARD, {"limb_index":0})
	check(reused == actor and is_zero_approx(reused.limp_left) and reused.brain.state == STATE.WANDER and reused.hurtboxes.areas.head.collision_layer == 32, "pool reuse restores health zones and clears injury and AI timers")
	session.hordes.release(reused)
	var runner := _spawn("feral_runner",at,at + Vector3.FORWARD,{"limb_index":0})
	session.clock.hours = 12
	var daylight := runner.max_move_speed()
	session.clock.hours = 23
	check(is_equal_approx(daylight,runner.max_move_speed()) and daylight > 4.0, "feral runners sprint during daylight and at night")
	session.hordes.release(runner)

func _crowd() -> void:
	# Measure the eight open-ground stations independently from the adjacent-wall overflow test.
	left_panel.collision_layer = 0
	right_panel.collision_layer = 0
	await _ticks(2)
	player.global_position = anchor + Vector3(0,0.04,6)
	var actors: Array[WastelandCreature] = []
	for i in 10:
		for inactive in session.hordes.pool:
			if not inactive.active: inactive.actor_rng.seed = 3100 + i
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 10.0)
		actors.append(_spawn("walker", player.global_position + direction * 3.6, player.global_position, {"limb_index":0}))
	await _ticks(45, actors)
	var slots := {}
	var waiting := 0
	var nearest := INF
	var assigned := []
	for subject in actors:
		assigned.append([subject.spawn_serial, subject.brain.slot, subject.brain.state, subject.brain.seen == player])
		if subject.brain.slot >= 0: slots[subject.brain.slot] = true
		if subject.brain.overflow: waiting += 1
		for other in actors:
			if subject != other: nearest = minf(nearest, subject.global_position.distance_to(other.global_position))
	check(slots.size() == 8 and waiting == 2 and nearest > 0.48, "ten attackers use eight slots and two outer stations (%d slots, %d waiting, %.2fm spacing)" % [slots.size(), waiting, nearest])
	if slots.size() != 8 or waiting != 2: printerr("Observed assignments: ", assigned)
	var waiting_actors := actors.filter(func(subject): return subject.brain.overflow)
	if not waiting_actors.is_empty():
		var outer: WastelandCreature = waiting_actors.front()
		var toward := WastelandCreatureRoute.planar(outer.brain.goal - outer.global_position).normalized()
		var point := arena.to_local(outer.global_position + toward * 1.28)
		var neighboring := _box(Vector3(point.x,0.75,point.z),Vector3(0.84,1.50,0.84),2,45)
		await _ticks(2)
		outer.brain.route.path_delay = 0.0
		player.invulnerable = 6.0
		var occupied_wall := false
		for frame in 65:
			await _ticks(1, actors)
			if is_instance_valid(neighboring) and outer.brain.breach_wall == neighboring:
				occupied_wall = true
				break
		check(occupied_wall, "an outer attacker diverts to a neighboring barricade while the eight inner stations are occupied")
		if is_instance_valid(neighboring): neighboring.queue_free()
	for subject in actors:
		session.hordes.release(subject)
	left_panel.collision_layer = 2
	right_panel.collision_layer = 2
	await _ticks(2)
	_reset_player()

func _detour_and_recovery() -> void:
	var isolated := SubViewport.new()
	isolated.world_3d = World3D.new()
	isolated.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(isolated)
	arena.reparent(isolated)
	# Offset the only navigation opening to the far end of the physical wall.
	var mesh := NavigationMesh.new()
	var points := PackedVector3Array()
	for z in range(-4, 5):
		for x in range(-10, 12):
			points.append(Vector3(x,0,z))
	mesh.vertices = points
	for z in 8:
		for x in 21:
			if z in [3,4] and x < 20: continue
			var first := z * 22 + x
			mesh.add_polygon(PackedInt32Array([first,first+1,first+23,first+22]))
	nav.queue_free()
	await _ticks(3)
	nav = NavigationRegion3D.new()
	nav.navigation_mesh = mesh
	arena.add_child(nav)
	var map := nav.get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_force_update(map)
	var wall := _box(Vector3(-1.5,1.4,0),Vector3(21,2.8,0.45),2,52.0)
	var origin := anchor + Vector3(-3,0.04,-2)
	var destination := anchor + Vector3(-3,0.04,2)
	var actor := _spawn("walker",origin,destination,{"limb_index":0})
	actor.reparent(arena)
	for frame in 180:
		await physics_frame
		if NavigationServer3D.map_get_path(map,origin,destination,true).size() > 2: break
	session.hordes.path_budget = 3
	actor.brain.route._plan(destination,false,true,actor.brain.reach)
	var route := actor.brain.route
	var detour := 0.0
	for i in range(1,route.path.size()):
		detour += route.path[i-1].distance_to(route.path[i])
	check(detour > 20.0 and detour > 2.2 * origin.distance_to(destination) and route.wall == wall, "a valid long detour over twenty metres selects a breach (%.2fm, %d corners, target=%s)" % [detour, route.path.size(), route.wall == wall])
	route.clear_plan()
	actor.brain.goal = destination
	route.wants_motion = true
	route.progress_heading = Vector3.BACK
	for i in 123:
		route.moved(STEP,Vector3.ZERO,2.0)
	check(route.wall == wall and actor.brain.state == STATE.ATTACK_BLOCK, "two seconds of under 0.3m progress locks the front obstruction")
	actor.reparent(session.hordes)
	session.hordes.release(actor)
	wall.queue_free()
	await _ticks(3)
	var walker := _spawn("walker", origin, destination, {"limb_index":0})
	walker.reparent(arena)
	await _ticks(6,[walker])
	walker.brain.goal = destination
	var trail := walker.brain.route
	trail.wants_motion = true
	trail.progress_heading = Vector3.BACK
	for i in 123:
		trail.moved(STEP,Vector3.ZERO,2.0)
	check(walker.velocity.y >= 4.0 or (trail.steered.dot(Vector3.BACK) < 0.9 and trail.steered != Vector3.ZERO), "stalled movement at terrain resamples a lateral heading or jumps")
	walker.reparent(session.hordes)
	session.hordes.release(walker)
	arena.reparent(session)
	isolated.queue_free()

func _fall_and_rage() -> void:
	var at := anchor + Vector3(1,0.06,6)
	var actor := _spawn("walker",at + Vector3.UP * 3.2,at + Vector3.FORWARD,{"limb_index":0})
	actor.brain.interrupt(false,1.0)
	# Choose the first RNG draw inside the documented 30% trigger band.
	var draw := RandomNumberGenerator.new()
	for key in range(1,128):
		draw.seed = key
		if draw.randf() < 0.3:
			actor.actor_rng.seed = key
			break
	var base := actor.max_move_speed()
	await _ticks(48,[actor])
	check(actor.is_on_floor() and actor.brain.rage_left > 4.5 and is_equal_approx(actor.max_move_speed(),1.25 * base), "landing after a 3.2m fall rolls the five-second 25% rage bonus")
	await _ticks(16,[actor])
	check(actor.brain.state == STATE.RAGE, "rage takes over movement once the hard stagger has elapsed")
	await _ticks(294,[actor])
	check(is_zero_approx(actor.brain.rage_left) and is_equal_approx(actor.max_move_speed(),base), "rage expires and normal movement resumes")
	session.hordes.release(actor)

func _terrain_wall() -> void:
	var point := session.start_position() + Vector3.RIGHT * 7.0
	point.y = session.stream.ground_at(point) + 0.035
	var subject := _spawn("walker",point,point + Vector3.FORWARD,{"limb_index":0})
	var before := subject.global_position
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	session.add_child(wall)
	wall.global_position = point + Vector3(0,0.9,-0.50)
	WastelandLook.collider(wall,Vector3(1.5,2.2,0.10),Vector3.ZERO)
	await physics_frame
	await physics_frame
	var next := before + Vector3.FORWARD * 0.36
	check(not subject._walk_surface(before,next) and before == subject.global_position,"a thin newly placed wall blocks the full terrain-walking capsule")
	wall.queue_free()
	await physics_frame
	await physics_frame
	check(subject._walk_surface(before,next) and absf(subject.global_position.y - session.stream.ground_at(next)) < 0.05,"an open surface step follows the rendered terrain after the obstruction is removed")
	session.hordes.release(subject)

func _stairs() -> void:
	for i in 8:
		var height := (i + 1) * 0.09
		_box(Vector3(0,height * 0.5,4.0 + i * 0.30),Vector3(2.6,height,0.30),2)
	_box(Vector3(0,0.36,8.26),Vector3(2.6,0.72,4.0),2)
	var foot := anchor + Vector3(0,0.04,3.2)
	player.global_position = anchor + Vector3(0,0.77,8.4)
	var subject := _spawn("walker",foot,player.global_position,{"limb_index":0})
	await _ticks(3)
	check(not subject._walk_surface(foot,foot + Vector3.BACK * 0.16), "a raised floor uses full physics instead of terrain projection")
	await _ticks(210,[subject])
	check(subject.global_position.z > anchor.z + 6.3 and subject.global_position.y > anchor.y + 0.68, "a walker follows eight physical stair treads onto the upper landing")
	session.hordes.release(subject)
