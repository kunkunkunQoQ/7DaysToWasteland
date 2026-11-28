extends "res://tools/verify_survivor_fall.gd"

var player: WastelandSurvivor
var rig: WastelandActiveRagdoll
var trace := false
var max_gap := 0.0

class SoleTrack:
	const PATCH_RADIUS := 0.02

	var support: PhysicsBody3D
	var ground_point := Vector3.ZERO
	var shoe_point := Vector3.ZERO
	var max_drift := 0.0
	var contact_ticks := 0
	var compared := false
	var strides: Array[float] = []

	func observe(body: RigidBody3D, planted: bool) -> void:
		if not planted:
			if contact_ticks >= 3 and compared: strides.append(max_drift)
			support = null
			max_drift = 0.0
			contact_ticks = 0
			compared = false
			return
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var marker := body.to_global(shoe_point)
		var strongest := 0.00001
		var contact := -1
		var tracked := false
		for i in state.get_contact_count():
			var normal := state.get_contact_local_normal(i)
			if normal.y < 0.7: continue
			var floor_body := state.get_contact_collider_object(i) as PhysicsBody3D
			if not floor_body or (floor_body.collision_layer & 3) == 0: continue
			var load := state.get_contact_impulse(i).dot(normal)
			if load <= 0.00001: continue
			if load > strongest:
				strongest = load
				contact = i
			# Keep the same material point for as long as it is in a loaded patch.
			# Heel roll can transfer the load to the other end of the same shoe.
			if support == floor_body and marker.distance_squared_to(state.get_contact_local_position(i)) <= PATCH_RADIUS * PATCH_RADIUS:
				max_drift = maxf(max_drift, (marker - support.to_global(ground_point)).slide(normal).length())
				tracked = true
				compared = true
		if contact < 0:
			support = null
			return
		contact_ticks += 1
		if not tracked:
			support = state.get_contact_collider_object(contact) as PhysicsBody3D
			var point := state.get_contact_local_position(contact)
			shoe_point = body.to_local(point)
			ground_point = support.to_local(point)

func run() -> void:
	WastelandSave.root_override = "user://verification/survivor-walk-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 2817
	open_world({})
	session.options.load_options()
	player = session.player
	trace = "--trace" in OS.get_cmdline_user_args()
	# Use the normal session physics loop, including the pause/resume transition at world entry.
	session.controls_enabled = true
	session.simulation_paused = false
	for i in 60:
		await physics_frame
		if trace and i in [2, 5, 10, 20, 40, 58] and is_instance_valid(player.live_avatar):
			rig = player.live_avatar.active_motion
			if is_instance_valid(rig): _trace_feet(i)
	rig = player.live_avatar.active_motion if is_instance_valid(player.live_avatar) else null
	if not is_instance_valid(rig):
		check(false, "the real player has an active physical body after spawning")
		await _done()
		return
	if "--motion" in OS.get_cmdline_user_args():
		await _compare_motion()
		await _done()
		return
	if "--traction" in OS.get_cmdline_user_args():
		await _check_traction()
		await _done()
		return
	var forward := -player.global_basis.z.slide(Vector3.UP).normalized()
	var right := player.global_basis.x.slide(Vector3.UP).normalized()
	var start := _positions()
	_key(KEY_W, true)
	check(session.movement_axis().y < -0.9, "physical W enters the gameplay movement axis")
	var begun := await _sample(45)
	_key(KEY_W, false)
	var start_travel := _travel(start, begun, forward)
	check(start_travel.x > 0.38 and start_travel.y > 0.38 and begun[1].y - begun[0].y > 0.5, "starting upright in the world advances capsule and physical pelvis (%.2f / %.2f m)" % [start_travel.x, start_travel.y])
	# Keep the spawn check in the generated world, then measure continuous travel
	# on an unobstructed surface away from the camp's walls and props.
	var surface := player.global_position + Vector3.UP * 12.0
	_slab(surface - Vector3.UP * 0.20, Vector3(32,0.40,32), false)
	player.global_position = surface + Vector3.UP * 0.06
	for i in 60: await physics_frame
	_key(KEY_W, true)
	begun = await _sample(45)
	var walking := await _sample(60)
	_key(KEY_W, false)
	var stopped := await _sample(45)
	var resting := await _sample(30)
	_key(KEY_D, true)
	check(session.movement_axis().x > 0.9, "physical D enters the gameplay movement axis")
	var turning := await _sample(55)
	_key(KEY_D, false)
	var sustained := _travel(begun, walking, forward)
	var side := _travel(resting, turning, right)
	var capsule_drift := (resting[0] - stopped[0]).slide(Vector3.UP).length()
	var pelvis_drift := (resting[1] - stopped[1]).slide(Vector3.UP).length()
	check(sustained.x > 1.2 and sustained.y > 1.2, "holding W sustains forward travel (%.2f / %.2f m in 1 s)" % [sustained.x, sustained.y])
	check(maxf(capsule_drift, pelvis_drift) < 0.40, "releasing W settles capsule and pelvis (%.2f / %.2f m final half-second drift)" % [capsule_drift, pelvis_drift])
	check(side.x > 0.45 and side.y > 0.45, "switching to D takes both bodies sideways (%.2f / %.2f m)" % [side.x, side.y])
	var wall_x := turning[0].x + 1.65
	_slab(Vector3(wall_x + 0.20, surface.y + 1.5, turning[0].z), Vector3(0.4,3,10), false)
	_key(KEY_D, true)
	var against := await _sample(65)
	_key(KEY_D, false)
	check(against[0].x > wall_x - 0.6 and against[0].x < wall_x and against[1].x < wall_x, "holding D into a wall keeps both capsule and pelvis on the approach side")
	check(max_gap < 0.30, "the capsule follows the actual pelvis (%.2f m peak horizontal separation)" % max_gap)
	await _done()

func _check_traction() -> void:
	var top := player.global_position + Vector3.UP * 12.0
	_slab(top - Vector3.UP * 0.2, Vector3(52,0.4,52), false)
	for sprint: bool in [false, true]:
		player.global_position = top + Vector3.UP * 0.06
		await _sample(65)
		_key(KEY_W, true)
		if sprint: _key(KEY_SHIFT, true)
		await _sample(45)
		var start := player.global_position
		var tracks := [SoleTrack.new(), SoleTrack.new()]
		var shoes := [rig.body_for(&"ankle_l"), rig.body_for(&"ankle_r")]
		var sampled_ticks := 0
		# Finish a stance cut by the sample boundary so every foot contributes
		# four measurable steps, including at the sprint's shorter duty cycle.
		for tick in 178:
			await physics_frame
			sampled_ticks += 1
			for side in 2:
				tracks[side].observe(shoes[side], player.live_avatar.gait.feet[side].planted)
			if sampled_ticks >= 145 and tracks[0].strides.size() >= 4 and tracks[1].strides.size() >= 4: break
		var speed := (player.global_position - start).slide(Vector3.UP).length() * Engine.physics_ticks_per_second / sampled_ticks
		var mode := "sprint" if sprint else "brisk walk"
		check(player.sprinting == sprint and speed > (5.2 if sprint else 3.6), "%s advances at %.2f m/s" % [mode, speed])
		for side in 2:
			var strides: Array[float] = tracks[side].strides
			strides.sort()
			var median := strides[strides.size() / 2] if not strides.is_empty() else INF
			check(strides.size() >= 4 and median < 0.055, "%s %s shoe holds the floor (%.1f cm median maximum drift, %d loaded strides)" % [
				mode, "left" if side == 0 else "right", median * 100.0, strides.size()])
		if sprint:
			# Tap at toe-off, between the old support and the next heel strike.
			var previous_support := false
			for tick in 25:
				await physics_frame
				var gripping := false
				for foot in rig._ground._loaded:
					gripping = gripping or foot.grip.is_valid()
				if previous_support and not gripping: break
				previous_support = gripping
			_key(KEY_SPACE, true)
			var height := 0.0
			var buffered := false
			for tick in 25:
				await physics_frame
				if tick == 1: _key(KEY_SPACE, false)
				buffered = buffered or player.jump_buffer > 0.0
				height = maxf(height, player.global_position.y - top.y)
			check(buffered and height > 0.30, "a toe-off jump tap waits for support and clears the floor (%.2f m)" % height)
		_key(KEY_W, false)
		if sprint: _key(KEY_SHIFT, false)
		await _sample(55)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _positions() -> Array[Vector3]:
	return [player.global_position, rig.center()]

func _travel(a: Array[Vector3], b: Array[Vector3], axis: Vector3) -> Vector2:
	return Vector2((b[0] - a[0]).dot(axis), (b[1] - a[1]).dot(axis))

func _trace_feet(tick: int) -> void:
	var details := PackedStringArray()
	for label: StringName in [&"ankle_l", &"ankle_r"]:
		var body := rig.body_for(label)
		if not body: continue
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var contacts := PackedStringArray()
		if state:
			for i in state.get_contact_count():
				var other := state.get_contact_collider_object(i) as PhysicsBody3D
				contacts.append("%s:%s" % [other.collision_layer if other else -1, state.get_contact_local_normal(i)])
		var clearance := body.global_position.y - session.stream.ground_at(body.global_position)
		details.append("%s height=%.3f contacts=%s/%d" % [label, clearance, contacts, body.max_contacts_reported])
	print("feet ", tick, " hip height=", rig.center().y - player.global_position.y, " capsule floor=", player.is_on_floor(), " ", " | ".join(details))

func _sample(ticks: int) -> Array[Vector3]:
	for i in ticks:
		await physics_frame
		max_gap = maxf(max_gap, (rig.center() - player.global_position).slide(Vector3.UP).length())
		if trace and i % 15 == 0:
			var driver = rig._ground
			print("walk ", player.global_position, " hip ", rig.center(), " v ", rig.motion(), " floor ", player.is_on_floor(), " input ", player.moving,
				" stance ", player.live_avatar.gait.supporting_ankles(), " loaded ", driver._loaded.size() if driver else -1, " goal ", driver.desired if driver else Vector3.ZERO)
	return _positions()

func _compare_motion() -> void:
	var floor_at := player.global_position + Vector3.UP * 12.0
	_slab(floor_at - Vector3.UP * 0.2, Vector3(36,0.4,36), false)
	player.global_position = floor_at + Vector3.UP * 0.06
	for i in 70: await physics_frame
	check(is_instance_valid(player.hand.right_hand) and is_instance_valid(player.hand.resting_left), "both empty hands visible in first person")
	if failures > 0: return
	await _measure_motion("idle")
	_key(KEY_W, true)
	await _sample(35)
	await _measure_motion("walk")
	_key(KEY_W, false)
	await _sample(50)
	await _measure_motion("stopped")

func _measure_motion(stage: String) -> void:
	var avatar := player.live_avatar
	var series := {"wrist_L":[], "wrist_R":[], "view_L":[], "view_R":[], "camera":[]}
	var ankle := [rig.body_for(&"ankle_l"), rig.body_for(&"ankle_r")]
	var thighs := [rig.body_for(&"leg_l"), rig.body_for(&"leg_r")]
	var shins := [rig.body_for(&"knee_l"), rig.body_for(&"knee_r")]
	var knee_flexion := Vector2.ZERO
	var hands := [player.hand.resting_left, player.hand.right_hand]
	var first := player.global_position
	var previous := first
	var path_length := 0.0
	var camera_start := player.camera.global_position
	var last_phase := avatar.gait.phase
	var cycles := 0.0
	var slide_distance := 0.0
	var loaded := 0
	var sole_frames := [0, 0]
	var landings := [0, 0]
	var up_ticks := [0, 0]
	var dt := 1.0 / Engine.physics_ticks_per_second
	for tick in 120:
		await physics_frame
		path_length += (player.global_position - previous).slide(Vector3.UP).length()
		previous = player.global_position
		var basis := player.global_basis.orthonormalized().transposed()
		series.camera.append(basis * (player.camera.global_position - camera_start))
		cycles += fposmod(avatar.gait.phase - last_phase, 1.0)
		last_phase = avatar.gait.phase
		for side in 2:
			var knee_angle: float = (thighs[side].global_basis.inverse() * shins[side].global_basis).get_euler().x
			knee_flexion[side] = maxf(knee_flexion[side], -knee_angle)
			var suffix := "_L" if side == 0 else "_R"
			var arm := avatar.wrist_joints[side].global_position - avatar.arms[side].global_position
			series["wrist" + suffix].append(basis * arm)
			# Track the same point on each visible fist mesh in actual camera space.
			var palm: Vector3 = hands[side].to_global(Vector3(0.129,-0.035,-0.18))
			series["view" + suffix].append(player.camera.to_local(palm))
			var state := PhysicsServer3D.body_get_direct_state(ankle[side].get_rid())
			var contact := -1
			for i in state.get_contact_count():
				var ground := state.get_contact_collider_object(i) as PhysicsBody3D
				if ground and ground.collision_layer & 3 and state.get_contact_local_normal(i).y > 0.7:
					contact = i
					break
			if contact < 0:
				up_ticks[side] += 1
				continue
			if up_ticks[side] >= 3: landings[side] += 1
			up_ticks[side] = 0
			sole_frames[side] += 1
			var relative := state.get_contact_local_velocity_at_position(contact) - state.get_contact_collider_velocity_at_position(contact)
			slide_distance += relative.slide(state.get_contact_local_normal(contact)).length() * dt
			loaded += 1
	var speed := (player.global_position - first).slide(Vector3.UP).length() / (120 * dt)
	print("MOTION ",stage," net_m_s=",snappedf(speed,0.01)," path_m_s=",snappedf(path_length / (120 * dt),0.01)," phase_cycles=",snappedf(cycles,0.01)," feet_contact_frames=",sole_frames," replants=",landings," contact_slip_m_s=",snappedf(slide_distance / maxf(dt * loaded,dt),0.01))
	var bands := {}
	for channel: String in series:
		var band := _motion_bands(series[channel],dt)
		bands[channel] = band
		print("MOTION ",stage," ",channel," gait_RMS_mm=",snappedf(band.x,0.01)," jitter_RMS_mm=",snappedf(band.y,0.01))
	check(speed > 1.2 if stage == "walk" else speed < 0.25, stage + " uses the expected native player input and speed")
	check(maxf(bands.view_L.y,bands.view_R.y) < 6.0, stage + " first-person palms stay below 6 mm of high-frequency vibration")
	if stage == "walk":
		check(minf(knee_flexion.x,knee_flexion.y)>deg_to_rad(35.0), "both physical knees bend during the stride (%.0f / %.0f degrees)" % [rad_to_deg(knee_flexion.x),rad_to_deg(knee_flexion.y)])
		check(minf(bands.wrist_L.x,bands.wrist_R.x) > 40.0 and maxf(bands.wrist_L.y,bands.wrist_R.y) < 12.0, "both third-person arms retain their gait swing with limited high-frequency jitter")
		check(landings[0] > 0 and landings[1] > 0, "both physical feet leave the floor and land again during the walk")
	else:
		check(cycles < 0.25, stage + " feet finish settling without cycling through another step")

func _motion_bands(points: Array, dt: float) -> Vector2:
	# Remove linear travel, then measure 0.5–4 Hz gait and 8–30 Hz vibration separately.
	# A Hann window reduces leakage from arm swings that end part-way through a cycle.
	var values := PackedVector3Array()
	var energy := 0.0
	for i in points.size():
		var t := float(i) / (points.size() - 1)
		var window := 0.5 - 0.5 * cos(TAU * t)
		var baseline: Vector3 = points.front().lerp(points.back(),t)
		values.append((points[i] - baseline) * window)
		energy += window * window
	var power := Vector2.ZERO
	for k in range(1, floori(values.size()*0.5)+1):
		var hz := k / (values.size()*dt)
		if hz > 4.0 and hz < 8.0: continue
		var c := Vector3.ZERO
		var s := Vector3.ZERO
		for i in values.size():
			var angle := TAU*k*i/values.size()
			c += cos(angle)*values[i]
			s += sin(angle)*values[i]
		var scale := 1.0 if k * 2 == values.size() else 2.0
		power[0 if hz <= 4.0 else 1] += scale * (c.length_squared() + s.length_squared()) / (values.size()*energy)
	return Vector2(sqrt(power.x),sqrt(power.y))*1000.0

func _done() -> void:
	session.controls_enabled = false
	session.simulation_paused = true
	await close_world()
	print("SURVIVOR WALK: %d passed, %d failed" % [passed, failures])
	quit(1 if failures else 0)
