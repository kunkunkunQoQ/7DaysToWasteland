extends "res://tools/verify_survivor_fall.gd"

# Integrate the tangential travel of the loaded contact patch one physics step
# at a time. The heel can roll off onto the toe during the same stance.
class Track:
	var on_floor := Vector3.INF
	var on_sole := Vector3.ZERO
	var drift := 0.0
	var contact_ticks := 0
	var planted_frames := 0
	var loaded_frames := 0
	var steps: Array[float] = []

	func sample(body: RigidBody3D, planted: bool, surface: StaticBody3D) -> void:
		if not planted:
			if contact_ticks >= 3: steps.append(drift)
			on_floor = Vector3.INF
			drift = 0.0
			contact_ticks = 0
			return
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		planted_frames += 1
		var strongest := 0.00001
		var contact := -1
		for i in state.get_contact_count():
			if state.get_contact_collider_object(i) != surface or state.get_contact_local_normal(i).y < 0.7: continue
			var load := state.get_contact_impulse(i).dot(state.get_contact_local_normal(i))
			if load > strongest:
				strongest = load
				contact = i
		if contact < 0:
			on_floor = Vector3.INF
			return
		if on_floor.is_finite():
			var step := body.to_global(on_sole) - surface.to_global(on_floor)
			if absf(step.y) < 0.035: drift += step.slide(Vector3.UP).length()
		var point := state.get_contact_local_position(contact)
		on_floor = surface.to_local(point)
		on_sole = body.to_local(point)
		contact_ticks += 1
		loaded_frames += 1

var floor_body: StaticBody3D
var top := Vector3.ZERO
var summary := {}

func run() -> void:
	WastelandSave.root_override = "user://verification/surface-traction-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 2817
	for surface: String in ["firm", "snow"]:
		seed(2817)
		open_world({})
		session.options.load_options()
		session.clock.hours = 12.0
		session.hordes.next_sim = 1000.0
		top = session.player.global_position + Vector3.UP * 12.0
		floor_body = StaticBody3D.new()
		floor_body.collision_layer = 2
		# Both decks have identical geometry and native physics. Sample the same
		# surface identifiers that gameplay uses for rock and snow.
		floor_body.set_meta("salvage_material", "stone" if surface == "firm" else "packed_snow")
		session.add_child(floor_body)
		floor_body.global_position = top - Vector3.UP * 0.2
		WastelandLook.collider(floor_body, Vector3(36, 0.4, 58), Vector3.ZERO)
		session.controls_enabled = true
		session.simulation_paused = false
		summary[surface] = {}
		for kind: String in ["player", "feral_runner", "wolf"]:
			summary[surface][kind] = await _run_lane(surface, kind)
		await close_world()
	for kind: String in summary.firm:
		var hard: float = summary.firm[kind]
		var snow: float = summary.snow[kind]
		# A wolf splits its load across short paw stances; scale the difference
		# to its own firm-ground travel, above a two-millimeter noise floor.
		check(hard < 0.055 and snow > maxf(hard * 1.4, hard + 0.002), "%s planted sole travels further on snow (firm %.1f cm, snow %.1f cm)" % [kind, 100.0 * hard, 100.0 * snow])
	print("SURFACE TRACTION: ", passed, " passed, ", failures, " failed")
	quit(int(failures > 0))

func _run_lane(surface: String, kind: String) -> float:
	var player := session.player
	player.rotation.y = 0.0
	player.global_position = top + Vector3.UP * 0.06
	for tick in 60: await physics_frame
	var actor: WastelandCreature
	var rig := player.live_avatar.active_motion
	var feet: Array[StringName] = [&"ankle_l", &"ankle_r"]
	if kind == "player":
		Input.action_press("up")
		Input.action_press("sprint")
	else:
		var saved := {"serial":7001 if kind == "wolf" else 7000, "facing":0.0, "wardrobe_index":0,
			"limb_index":0, "look_index":0, "stride_phase":0.0, "wildlife_cycle":0.0}
		if kind == "wolf": saved.hp = float(session.catalog.enemies[kind].hp) * 0.45
		session.hordes.acquire_actor(kind).actor_rng.seed = saved.serial
		if not session.hordes._spawn(kind, top+Vector3.BACK*5.35+Vector3.UP*0.04, false, saved):
			check(false, kind+" spawns in the pursuit lane")
			return INF
		actor = session.hordes.alive.back()
		rig = actor.active_motion
		if kind == "wolf": feet = [&"paw0", &"paw1", &"paw2", &"paw3"]
	var tracks: Array[Track] = []
	var bodies: Array[RigidBody3D] = []
	for bone in feet:
		tracks.append(Track.new())
		bodies.append(rig.body_for(bone))
	var travel := 0.0
	var measured := 0
	for tick in 200:
		var previous := rig.center()
		await physics_frame
		var pursuing := player.sprinting
		if actor:
			# Let the real player run ahead when the animal gets close enough to attack.
			var gap := (player.global_position-actor.global_position).slide(Vector3.UP).length()
			if gap < 3.0: Input.action_press("up")
			elif gap > 4.3: Input.action_release("up")
			pursuing = actor.brain.seen == player and actor.brain.mode in [WastelandCreatureBrain.Mode.CHASE, WastelandCreatureBrain.Mode.FLANK] and actor.ground_intent.dot(Vector3.FORWARD) > 0.3
		if pursuing and tick >= 36:
			travel += (rig.center()-previous).dot(Vector3.FORWARD)
			measured += 1
		for side in feet.size():
			var planted := feet[side] in actor.foot_contacts.stance_bones if actor else player.live_avatar.gait.feet[side].planted
			tracks[side].sample(bodies[side], pursuing and tick >= 36 and planted, floor_body)
	Input.action_release("up")
	Input.action_release("sprint")
	var strides: Array[float] = []
	var counts: Array[int] = []
	var planned := 0
	var loaded := 0
	for i in feet.size():
		tracks[i].sample(bodies[i], false, floor_body)
		counts.append(tracks[i].steps.size())
		strides.append_array(tracks[i].steps)
		planned += tracks[i].planted_frames
		loaded += tracks[i].loaded_frames
	strides.sort()
	var median := strides[strides.size()/2] if not strides.is_empty() else INF
	var speed := travel * Engine.physics_ticks_per_second / maxi(measured, 1)
	var pace := 5.0 if not actor else 2.0
	check(measured >= 45 and speed > pace and strides.size() >= 4 and counts.min() > 0,
		"%s %s moves on loaded feet at %.2f m/s (%d active frames, strides by foot %s, contact %d/%d frames, median %.2f cm)" % [
		surface, kind, speed, measured, counts, loaded, planned, median*100.0])
	if actor: session.hordes.release(actor)
	return median
