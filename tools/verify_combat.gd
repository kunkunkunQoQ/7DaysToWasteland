extends SceneTree

const STEP := 1.0 / 60.0
const BRAIN := preload("res://game/actors/creature_brain.gd")
var app: Node
var session: WastelandSession
var player: WastelandSurvivor
var arena: Node3D
var anchor: Vector3
var nav: NavigationRegion3D
var left_panel: StaticBody3D
var right_panel: StaticBody3D
var passes := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var flags := OS.get_cmdline_user_args()
	WastelandSave.root_override = "user://verification/combat-%d" % OS.get_process_id()
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	app.set_process_input(false)
	app.options.display.dynamic = false
	app.options.display.show_fps = false
	app._enter_world(app._default_config(), {}, 0, false)
	session = app.session
	player = session.player
	session.hordes.next_patrol = 1000.0
	session.hordes.next_herd = 1000.0
	await _ticks(32)
	session.simulation_paused = true
	_verify_feedback()
	if "--capture" in flags and DisplayServer.get_name() != "headless":
		await _capture_feedback()
	_make_arena()
	await _cover_and_route()
	await _melee()
	await _specialists()
	await _infected_variants()
	await _flanking()
	await _wildlife()
	await _reload_hazards()
	await session.stream.quiesce()
	app._remove_session()
	app.queue_free()
	await process_frame
	var audio_finish := Time.get_ticks_msec()+450
	while Time.get_ticks_msec()<audio_finish: await process_frame
	print("COMBAT QA  passed=%d  failed=%d" % [passes, failures.size()])
	for issue in failures:
		printerr("FAILED: " + issue)
	quit(0 if failures.is_empty() else 1)

func _verify_feedback() -> void:
	session.bag.armor = "armor"
	player.health = 64.0
	player.invulnerable = 0.0
	player.clear_damage_feedback()
	var right := player.global_basis.x
	var heading := -player.camera.global_basis.z
	var aim := Vector2(player.rotation.y, player.pitch)
	player.damage(20.0, "claw", player.global_position + right * 4.0)
	check(is_equal_approx(player.health, 49.2) and is_equal_approx(player.injury.last_amount, 14.8)
		and player.injury.trace_health == 64.0, "impact and trailing bar use actual damage after armor")
	check(player.injury.directions.size() == 1 and player.injury.directions[0].bearing.dot(right) > 0.99,
		"an attack to the right provides a stable world bearing")
	player.damage(13.0, "heavy", player.global_position - right)
	check(player.injury.last_source == "claw" and player.injury.directions.size() == 1 and is_equal_approx(player.health, 49.2),
		"invulnerability discards damage and its cues together")
	var original_motion: float = session.options.display.impact_motion
	session.options.display.impact_motion = 1.0
	player.update_damage_feedback(0.048)
	check(absf(player.camera.rotation.z) > 0.008 and player.hand.hurt_dip > 0.1
		and (-player.camera.global_basis.z).is_equal_approx(heading) and Vector2(player.rotation.y, player.pitch) == aim,
		"impact moves the camera and viewmodel while preserving input aim and shot direction")
	session.options.display.impact_motion = 0.0
	player.update_damage_feedback(STEP)
	check(is_zero_approx(player.camera.rotation.z) and is_zero_approx(player.hand.hurt_dip) and player.injury.pulse > 0.0,
		"motion setting leaves non-motion feedback active")
	session.options.display.impact_motion = original_motion
	player.clear_damage_feedback()
	player.invulnerable = 0.0
	player.damage(10.0, "fall")
	check(player.injury.last_source == "fall" and player.injury.directions.is_empty() and player.injury.pulse > 0.0,
		"fall damage shows its cause without a fabricated attacker direction")
	player.clear_damage_feedback()
	player.show_damage(30.0, 2.1, "bleed", Vector3.ZERO, false)
	check(player.injury.last_source == "bleed" and is_zero_approx(player.injury.pulse) and player.injury.directions.is_empty(),
		"continuous injury reports its cause without repeating impact effects")
	player.health = 19.0
	player.update_damage_feedback(STEP)
	check(session.audio.heartbeat.stream != null and player.injury.heart_left > 0.0, "critical health activates the local heartbeat")
	session.bag.armor = ""
	_reset_player()

func _capture_feedback() -> void:
	player.health = 39.0
	var source := player.global_position + (player.global_basis.x * 0.71 - player.global_basis.z * 0.70) * 2.3
	source.y = session.stream.ground_at(source) + 0.08
	var actor := _spawn("walker", source, player.global_position)
	actor.attack = 0.91
	actor.alerted = true
	actor._pose(0.04, 2.0)
	player.damage(22.0, "claw", source)
	player.update_damage_feedback(0.056)
	player.hand.animate(0.06, 0.0, 0.0, session.atmosphere.sun_strength, 0.0)
	session.simulation_paused = false
	await process_frame
	await RenderingServer.frame_post_draw
	var dir := "res://build/qa/compatibility" if "--compat-capture" in OS.get_cmdline_user_args() else "res://build/qa"
	DirAccess.make_dir_recursive_absolute(dir)
	check(root.get_texture().get_image().save_png(dir + "/10-damage-feedback.png") == OK, "capture directional and critical health feedback")
	session.simulation_paused = true
	session.hordes.release(actor)
	_reset_player()

func _make_arena() -> void:
	anchor = player.global_position + Vector3.UP * 22.0
	arena = Node3D.new()
	session.add_child(arena)
	arena.global_position = anchor
	_box(Vector3(0, -0.5, 0), Vector3(24, 1, 24), 1)
	left_panel = _box(Vector3(-5.0, 1.4, 0), Vector3(14, 2.8, 0.5), 2, 480.0)
	right_panel = _box(Vector3(8.0, 1.4, 0), Vector3(8, 2.8, 0.5), 2, 480.0)
	nav = NavigationRegion3D.new()
	arena.add_child(nav)
	_set_nav(true)

func _set_nav(door_open: bool) -> void:
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	for z: float in [-11.5, -0.70, 0.70, 11.5]:
		for x: float in [-11.5, 2.43, 3.57, 11.5]:
			vertices.append(Vector3(x, 0, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if z == 1 and (x != 1 or not door_open):
				continue
			var first := z * 4 + x
			mesh.add_polygon(PackedInt32Array([first, first + 1, first + 5, first + 4]))
	nav.navigation_mesh = mesh

func _box(point: Vector3, size: Vector3, layer: int, hp: float = 0.0) -> StaticBody3D:
	var block := StaticBody3D.new()
	block.collision_layer = layer
	if hp > 0.0:
		block.set_meta("kind", "poi_wall")
		block.set_meta("hp", hp)
		block.set_meta("site_id", "combat_%s" % point)
		block.set_meta("cell", WastelandTerrainGen.chunk_at(Vector2(anchor.x + point.x, anchor.z + point.z)))
	arena.add_child(block)
	block.position = point
	WastelandLook.collider(block, size, Vector3.ZERO)
	return block

func _cover_and_route() -> void:
	player.global_position = anchor + Vector3(0, 0.04, 3.0)
	var actor := _spawn("walker", anchor + Vector3(0, 0.04, -3.2), player.global_position)
	await _ticks(4)
	await _ticks(22, [actor])
	check(actor.brain.seen == null and actor.brain.mode == BRAIN.Mode.ROAM, "opaque cover breaks sight even at close range")
	session.hordes.add_noise(player.global_position + Vector3.UP * 0.72, 7.0)
	await _ticks(22, [actor])
	check(actor.brain.mode == BRAIN.Mode.ROAM, "a wall muffles a footstep outside the reduced hearing range")
	var heard := player.global_position + Vector3.UP * 0.36
	session.hordes.add_noise(heard, 36.0)
	await _ticks(22, [actor])
	check(actor.brain.seen == null and actor.brain.mode == BRAIN.Mode.INVESTIGATE and actor.brain.interest == heard,
		"a loud noise behind cover creates a search location")
	player.global_position += Vector3.LEFT * 2.2
	await _ticks(21, [actor])
	check(actor.brain.interest == heard, "unseen movement does not update the last known location")
	player.global_position = anchor + Vector3(0, 0.04, 3.0)
	var reached := false
	for i in 370:
		await _ticks(1, [actor])
		if actor.global_position.z > anchor.z + 0.95:
			reached = true
			break
	check(reached and float(left_panel.get_meta("hp")) == 480.0, "a walker uses the navigation opening instead of damaging a wall")
	session.hordes.release(actor)
	_set_nav(false)
	var weak := _box(Vector3(3.0, 1.4, 0), Vector3(2.04, 2.8, 0.5), 2, 63.0)
	player.global_position = anchor + Vector3(3.0, 0.04, 2.8)
	actor = _spawn("brute", anchor + Vector3(2.63, 0.04, -2.0), player.global_position,
		{"interest": player.global_position, "memory": 16.0})
	await _ticks(4)
	await _ticks(27, [actor])
	check(is_instance_valid(weak) and actor.brain.breach_wall == weak and actor.brain.action == BRAIN.Action.SMASH and float(weak.get_meta("hp")) == 63.0,
		"an isolated brute targets the weakest accessible panel and winds up")
	await _ticks(180, [actor])
	check(not is_instance_valid(weak) and float(left_panel.get_meta("hp")) == 480.0 and float(right_panel.get_meta("hp")) == 480.0,
		"the brute opens the weak panel while neighboring panels stay intact")
	await _ticks(159, [actor])
	check(actor.global_position.z > anchor.z + 0.42, "a creature uses the newly opened breach")
	session.hordes.release(actor)
	var knee_wall := _box(Vector3(3.0, 0.27, 0), Vector3(2.04, 0.54, 0.5), 2, 58.0)
	actor = _spawn("brute", anchor + Vector3(3.0, 0.04, -2.6), player.global_position)
	await _ticks(238, [actor])
	check(not is_instance_valid(knee_wall), "a low wall that blocks movement can also be breached")
	session.hordes.release(actor)
	left_panel.queue_free()
	right_panel.queue_free()
	_set_nav(true)
	await _ticks(4)

func _melee() -> void:
	_reset_player()
	player.global_position = anchor + Vector3(0, 0.04, 4.0)
	var brute := _spawn("brute", player.global_position + Vector3.FORWARD * 1.64, player.global_position)
	await _ticks(4)
	await _ticks(13, [brute])
	check(brute.brain.action == BRAIN.Action.MELEE and brute.windup > 0.15 and player.health == 100.0,
		"heavy melee has a readable windup before any damage")
	player.global_position += Vector3.RIGHT * 2.9
	await _ticks(40, [brute])
	check(player.health == 100.0, "sidestepping the committed swing avoids damage")
	player.global_position = anchor + Vector3(0, 0.04, 4.0)
	brute.global_position = player.global_position + Vector3.FORWARD * 1.62
	brute.rotation.y = PI
	brute.brain.cooldown = 0.0
	brute.brain.sense_left = 0.0
	await _ticks(15, [brute])
	var cover := _box(Vector3(0, 1.35, 3.3), Vector3(2.0, 2.7, 0.20), 2)
	await _ticks(39, [brute])
	check(player.health == 100.0, "a committed strike is blocked by cover on the impact frame")
	cover.queue_free()
	await _ticks(4)
	player.global_position = anchor + Vector3(0, 0.04, 4.0)
	brute.global_position = player.global_position + Vector3.FORWARD * 1.62
	brute.rotation.y = PI
	brute.brain.cooldown = 0.0
	brute.brain.sense_left = 0.0
	await _ticks(58, [brute])
	check(player.health == 75.0 and player.fracture == 100.0 and player.injury.last_source == "heavy",
		"a connected heavy attack applies damage, fracture and directional feedback")
	session.hordes.release(brute)
	_reset_player()

func _specialists() -> void:
	player.global_position = anchor + Vector3(0, 0.04, 5.0)
	var spitter := _spawn("spitter", player.global_position + Vector3.FORWARD * 7.8, player.global_position)
	await _ticks(3)
	await _ticks(18, [spitter], true)
	check(spitter.brain.action == BRAIN.Action.SPIT and not _acid_active(), "ranged attacker winds up from a clear firing lane")
	await _ticks(56, [spitter], true)
	check(player.injury.last_source == "acid" and player.injury.directions.size() == 1 and player.health < 93.0,
		"acid follows a physical arc and reports its origin on impact")
	session.hordes.release(spitter)
	_reset_player()
	spitter = _spawn("spitter",player.global_position + Vector3.FORWARD*7.8,player.global_position)
	await _ticks(19,[spitter],true)
	var cover := _box(Vector3(0,1.45,2.3),Vector3(4,2.9,0.3),2)
	await _ticks(65,[spitter],true)
	check(player.health == 100.0 and not _acid_active(),"a wall inserted after the spit tell intercepts the acid in flight")
	session.hordes.release(spitter)
	cover.queue_free()
	await _ticks(3)
	spitter = _spawn("spitter",player.global_position + Vector3.FORWARD*7.8,player.global_position)
	await _ticks(19,[spitter],true)
	player.global_position += Vector3.RIGHT*2.6
	await _ticks(66,[spitter],true)
	check(player.health == 100.0 and player.infection == 0.0,"sidestepping a committed poison shot avoids damage and infection")
	session.hordes.release(spitter)
	player.global_position = anchor + Vector3(0,0.04,5.0)
	var caller := _spawn("screamer", player.global_position + Vector3.FORWARD * 7.5, player.global_position)
	await _ticks(5, [caller])
	check(caller.brain.action == BRAIN.Action.SCREAM and not caller.screamed, "screamer telegraphs a call before summoning")
	caller.take_hit(1.0, player.global_position, true)
	caller.brain.cooldown = 2.0
	await _ticks(63, [caller])
	check(not caller.screamed and session.hordes.alive.size() == 1, "stagger interrupts the call completely")
	var call_at := player.global_position
	caller.brain.cooldown = 0.0
	await _ticks(70, [caller])
	var called := session.hordes.alive.filter(func(other): return other != caller)
	check(caller.screamed and not called.is_empty() and called.all(func(other): return not other.wave and other.brain.interest == call_at),
		"reinforcements investigate the player's last seen position rather than receiving a live target")
	for enemy in session.hordes.alive.duplicate():
		session.hordes.release(enemy)

func _flanking() -> void:
	player.global_position = anchor + Vector3(0, 0.04, 5.0)
	var mutant := _spawn("radiant", player.global_position + Vector3.FORWARD * 9.0, player.global_position)
	await _ticks(13, [mutant])
	check(mutant.brain.mode == BRAIN.Mode.FLANK and absf(mutant.brain.goal.x - player.global_position.x) > 3.0,
		"an aggressive mutant chooses a lateral approach in the open")
	await _ticks(128, [mutant])
	check(mutant.brain.mode != BRAIN.Mode.ROAM and mutant.global_position.distance_to(player.global_position) < 6.6,
		"the lateral approach closes the distance instead of circling indefinitely")
	session.hordes.release(mutant)
	_reset_player()

func _infected_variants() -> void:
	_reset_player()
	player.global_position = anchor + Vector3(0,0.04,3)
	var p := player.global_position + Vector3.FORWARD*2
	var initial_kills := int(session.progress.records.get("kill_bloater",0))
	var body := _spawn("bloater",p,player.global_position)
	var old_drop_serial := session.fx.serial
	body.take_hit(999,p)
	body.take_hit(999,p)
	await _ticks(26,[body])
	check(body.active and body.hp == 0.0 and body.blast_ring.visible and player.health == 100.0,"lethal bloater hit starts one visible fuse before damage or loot")
	var saved := body.serialize()
	session.hordes.release(body)
	body = _spawn("bloater",p,player.global_position,saved)
	check(is_equal_approx(body.fuse_left,float(saved.fuse)),"loaded corpse keeps the remaining fuse")
	await _ticks(85,[body])
	check(body.active and body.brain.state == BRAIN.State.DEAD and player.injury.last_source == "rupture" and player.health < 85 and int(session.progress.records.get("kill_bloater",0)) == initial_kills+1,"restored blast damages exposed survivor and awards a single kill before corpse cleanup")
	check(session.fx.drop_records.get(str(old_drop_serial+1),{}).get("items",{}).get("powder",0)>0,"ruptured body leaves its documented salvage")
	_reset_player()
	var wall := _box(Vector3(0,1.4,2),Vector3(2.8,2.8,0.22),2)
	await _ticks(2)
	body = _spawn("bloater",p,player.global_position)
	body.take_hit(999,p)
	await _ticks(103,[body])
	check(player.health == 100.0,"solid cover stops the death blast")
	wall.queue_free()
	await _ticks(2)
	body = _spawn("bloater",p,player.global_position)
	body.take_hit(999,p)
	player.global_position += Vector3.RIGHT*6
	await _ticks(103,[body])
	check(player.health == 100.0,"moving beyond the marked radius during the fuse avoids the blast")
	var guard := _spawn("bulwark",p,p+Vector3.FORWARD)
	guard.take_hit(10,p+Vector3.FORWARD)
	var after_front := guard.hp
	guard.take_hit(10,p+Vector3.BACK)
	check(is_equal_approx(guard.max_health()-after_front,3) and is_equal_approx(after_front-guard.hp,10),"shield plates absorb frontal hits and leave the rear exposed")
	player.global_position = p+Vector3.FORWARD*7
	var medic := _spawn("rimecaller",p+Vector3.RIGHT*2,player.global_position)
	var wounded := guard.hp
	await _ticks(14,[medic])
	check(medic.attack_kind == BRAIN.Action.MEND and guard.hp == wounded,"rimecaller visibly channels before repairing its ally")
	medic.take_hit(1,player.global_position)
	await _ticks(83,[medic])
	check(guard.hp == wounded,"stagger cancels a repair")
	medic.brain.mend_left = 0
	medic.brain.cooldown = 0
	await _ticks(90,[medic])
	check(guard.hp > wounded and guard.hp <= guard.max_health(),"completed repair restores an injured ally up to maximum health")
	session.hordes.release(medic)
	session.hordes.release(guard)
	player.global_position = p+Vector3.FORWARD*4
	var runner := _spawn("sandrunner",p,player.global_position,{"limb_index":0})
	await _ticks(12,[runner])
	check(runner.attack_kind == BRAIN.Action.CHARGE,"sandrunner commits to a visible straight rush at midrange")
	var heading := runner.brain.attack_heading
	player.global_position += Vector3.RIGHT*3
	await _ticks(81,[runner])
	check(player.health == 100.0 and (runner.global_position-p).dot(heading)>2.0,"sidestep lets the rush pass without homing")
	session.hordes.release(runner)
	var floor_point := anchor + Vector3(0,0.9,4)
	player.global_position = floor_point + Vector3.RIGHT*3
	session.fx.projectile(floor_point,Vector3.DOWN*4,null,"acid",12)
	await _ticks(24,[],true)
	check(not session.fx.acid_snapshot().is_empty(),"physical ground impact leaves an active acid patch")
	var patch: Vector3 = session.fx.acid_snapshot().front().at
	player.global_position = patch
	await _ticks(57,[],true)
	check(player.injury.last_source == "residue","remaining in visible acid burns after the warning interval")
	player.global_position += Vector3.RIGHT*3
	var previous := player.health
	await _ticks(190,[],true)
	check(player.health == previous and session.fx.acid_snapshot().is_empty(),"leaving the patch avoids later ticks and the patch expires")
	_reset_player()

func _wildlife() -> void:
	player.global_position = anchor + Vector3(0, 0.04, 6.7)
	var deer := _spawn("stag", player.global_position + Vector3.FORWARD * 4.6, player.global_position)
	var before := deer.global_position.distance_to(player.global_position)
	await _ticks(58, [deer])
	check(deer.brain.mode == BRAIN.Mode.FLEE and deer.global_position.distance_to(player.global_position) > before + 2.0,
		"a deer remembers danger and flees away across safe ground")
	session.hordes.release(deer)
	var boar := _spawn("boar", player.global_position + Vector3.FORWARD * 2.38, player.global_position, {"hp": 28.0})
	await _ticks(19, [boar])
	check(boar.brain.action == BRAIN.Action.CHARGE and player.health == 100.0, "a threatened wounded boar braces before charging")
	await _ticks(54, [boar])
	check(player.injury.last_source == "boar" and player.health < 95.0, "a committed boar charge can hit the player")
	session.hordes.release(boar)

func _acid_active() -> bool:
	return session.fx.shots.any(func(shot): return shot.kind == "acid" and shot.life > 0.0)

func _reload_hazards() -> void:
	var at := player.global_position + Vector3.RIGHT*5
	var corpse := _spawn("bloater",at,player.global_position)
	var corpse_id := corpse.spawn_serial
	corpse.take_hit(999,at)
	session.hordes.infected_effect("residue",at+Vector3.UP*0.03)
	var landed := at + Vector3.BACK*2
	landed.y = session.stream.ground_at(landed)
	var shooter := _spawn("spitter",landed+Vector3.LEFT*2,landed)
	var shooter_id := shooter.spawn_serial
	session.fx.projectile(landed+Vector3.UP*2.4,Vector3(0.09,0.15,0.05),shooter,"acid",16)
	await _ticks(23,[corpse],true)
	var remaining := corpse.fuse_left
	var patch: Dictionary = session.fx.acid_snapshot().back()
	var flight: Dictionary = session.fx.acid_flights().back()
	session.slot = 1
	check(session.save_now(false)==OK,"live fuse and acid patch save to disk")
	var saved := WastelandSave.read(1)
	await session.stream.quiesce()
	app._enter_world(saved.settings,saved,1,false)
	session = app.session
	player = session.player
	session.simulation_paused = true
	session.hordes.next_patrol = INF
	session.hordes.next_herd = INF
	session.stream.ensure_landing(at)
	session.hordes.simulate(STEP)
	var restored := session.hordes.alive.filter(func(actor): return actor.spawn_serial==corpse_id and actor.type=="bloater" and actor.hp==0)
	check(restored.size()==1 and is_equal_approx(restored[0].fuse_left,remaining) and restored[0].blast_ring.visible,"world reload resumes the same corpse and its warning")
	var patches := session.fx.acid_snapshot()
	check(patches.size()==1 and is_equal_approx(patches[0].life,patch.life) and is_equal_approx(patches[0].next,patch.next),"world reload preserves acid lifetime and time to next burn")
	var flights := session.fx.acid_flights()
	check(flights.size()==1 and flights[0]==flight and flight.at.distance_to(flight.origin)>0.05,"disk reload preserves the exact in-flight poison position, velocity, lifetime, damage, ID and origin")
	var restored_shooter: WastelandCreature = session.hordes.actors_by_serial.get(shooter_id)
	check(is_instance_valid(restored_shooter) and restored_shooter.type=="spitter" and flight.shooter==shooter_id,"restored projectile identifies its original shooter across pool reconstruction")
	if is_instance_valid(restored_shooter):
		restored_shooter.global_position=landed+Vector3.UP*0.02
	player.global_position = at+Vector3.RIGHT*5
	await _ticks(78,[],true)
	var impacts:=session.fx.acid_snapshot().filter(func(row): return row.at.distance_to(landed)<0.80)
	check(session.fx.acid_flights().is_empty() and impacts.size()==1,"restored projectile passes through its shooter and deposits exactly one patch on the ground")
	session.fx.receive_acid(flight)
	check(session.fx.acid_flights().is_empty(),"an already-resolved shot ID cannot replay its hit")

func _spawn(id: String, at: Vector3, face: Vector3, previous: Dictionary = {}) -> WastelandCreature:
	var spawn_state := previous.duplicate()
	var heading := WastelandCreatureRoute.planar(face - at)
	spawn_state.facing = atan2(-heading.x, -heading.z)
	session.hordes._spawn(id, at, false, spawn_state)
	var actor: WastelandCreature = session.hordes.alive.back()
	actor.brain.cooldown = 0.0
	actor.brain.sense_left = 0.0
	return actor

func _reset_player() -> void:
	player.health = 100.0
	player.invulnerable = 0.0
	player.bleed = 0.0
	player.infection = 0.0
	player.fracture = 0.0
	player.clear_damage_feedback()

func _ticks(count: int, actors: Array[WastelandCreature] = [], projectiles: bool = false) -> void:
	for i in count:
		await physics_frame
		if not actors.is_empty():
			session.clock.elapsed += STEP
		session.hordes.path_budget = WastelandHordes.PATHS_PER_TICK
		for actor in actors:
			actor.think(STEP, player)
		if projectiles:
			session.fx.simulate_projectiles(STEP)

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS " + label)
	else:
		failures.append(label)
