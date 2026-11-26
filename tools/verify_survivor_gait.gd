extends SceneTree

const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var world := Node3D.new()
var avatar := WastelandPartyAvatar.new()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	root.add_child(world)
	avatar.show_tag = false
	world.add_child(avatar)
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT]:
		_trial(direction * 1.45, 0)
	_trial(Vector3.FORWARD * 4.65, 0)
	_trial(Vector3.FORWARD * 7.3, 0)
	_trial(Vector3(1.2, 0, -1.2), 1)
	for outfit in WastelandPartyAvatar.OUTFITS:
		if outfit == "ranger": continue
		avatar.apply_outfit(outfit)
		_trial(Vector3(0.8, 0, -1.1), 0)
	avatar.apply_outfit("ranger")
	avatar.position = Vector3.ZERO
	for tick in 80: _walk(Vector3.FORWARD * 3.0, 0)
	for tick in 95: _walk(Vector3.ZERO, 0)
	var feet := [avatar.ankle_joints[0].global_position, avatar.ankle_joints[1].global_position]
	var drift := 0.0
	for tick in 60:
		_walk(Vector3.ZERO, 0)
		for i in 2: drift = maxf(drift, avatar.ankle_joints[i].global_position.distance_to(feet[i]))
	check(avatar.gait.feet[0].planted and avatar.gait.feet[1].planted and drift < 0.0002, "both feet finish braking and stand still (%.2f mm drift)" % (drift * 1000))
	for tick in 32:
		avatar.rotate_y(PI / 64.0)
		_walk(Vector3.ZERO, 0)
	for tick in 100: _walk(Vector3.ZERO, 0)
	var face := avatar.rotation.y
	check(absf(angle_difference(avatar.gait.feet[0].heading, face)) < 0.25 and absf(angle_difference(avatar.gait.feet[1].heading, face)) < 0.25, "turning through 90 degrees at rest moves and redirects both feet")
	avatar.rotation.y = 0.0
	var forward_speed := -4.65
	var previous := [avatar.ankle_joints[0].global_position, avatar.ankle_joints[1].global_position]
	var peak := 0.0
	for tick in 108:
		if tick >= 40: forward_speed = move_toward(forward_speed, 4.65, 31.0 * DT)
		_walk(Vector3.BACK * forward_speed, 0)
		for i in 2:
			var ankle := avatar.ankle_joints[i].global_position
			if tick > 40: peak = maxf(peak, ankle.distance_to(previous[i]))
			previous[i] = ankle
	check(peak < 0.235 and avatar.gait.local_velocity.z > 4.5, "braking and reversing at the playable acceleration keeps consecutive ankle positions connected (%.1f mm peak)" % (peak * 1000))
	for tick in 20:
		avatar.position.y += 0.04
		avatar.pose(DT, 3.0, 0, false, Vector3(0, 2.4, -3.0), false)
	check(not avatar.gait.feet[0].planted and not avatar.gait.feet[1].planted and avatar.knees[1].rotation.x < -0.3, "airborne legs release both old contacts and tuck")
	avatar.position += Vector3(14, -0.8, 3)
	_walk(Vector3.ZERO, 0)
	check(avatar.gait.feet[0].sole.distance_to(avatar.position) < 0.25 and avatar.gait.feet[1].sole.distance_to(avatar.position) < 0.25, "a teleport starts both contacts at the new location")
	await _slope()
	await _physical_walk()
	world.queue_free()
	await process_frame
	print("SURVIVOR GAIT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _walk(velocity: Vector3, duck: float, normal := Vector3.UP) -> void:
	avatar.position += velocity * DT
	avatar.pose(DT, velocity.slide(Vector3.UP).length(), duck, false, velocity, true, normal)

func _trial(velocity: Vector3, duck: float) -> void:
	avatar.gait.reset()
	avatar.position = Vector3.ZERO
	_walk(Vector3.ZERO, duck)
	var landings := [0, 0]
	var held := [false, false]
	var starts := [Vector3.ZERO, Vector3.ZERO]
	var longest_slip := 0.0
	var reach_error := 0.0
	var knee_range := Vector2(INF, -INF)
	var foot_range := Vector2(INF, -INF)
	var forward_arm := 0.0
	var stance_samples := 0
	for tick in 240:
		_walk(velocity, duck)
		for i in 2:
			var f := avatar.gait.feet[i]
			var ankle := avatar.ankle_joints[i].global_position
			var sole := ankle - f.normal * (0.104 * avatar.legs[i].scale.y * avatar.pivot.scale.y + maxf(0, -f.roll) * 0.12)
			if tick > 30:
				var angle := avatar.knees[i].rotation.x
				knee_range = Vector2(minf(knee_range.x, angle), maxf(knee_range.y, angle))
				var relative := (sole - avatar.position).dot(velocity.normalized())
				foot_range = Vector2(minf(foot_range.x, relative), maxf(foot_range.y, relative))
				if f.planted:
					stance_samples += 1
					reach_error = maxf(reach_error, f.sole.distance_to(sole))
					if held[i]: longest_slip = maxf(longest_slip, sole.distance_to(starts[i]))
					else:
						starts[i] = sole
						landings[i] += 1
				if velocity.z < -0.5 and duck < 0.1:
					forward_arm += (-avatar.arms[i].rotation.x) * (avatar.position.z - sole.z)
			held[i] = f.planted and tick > 30
	var label := "%s %s, duck %d" % [avatar.outfit, velocity, int(duck)]
	check(landings[0] >= 3 and abs(landings[0] - landings[1]) <= 1 and stance_samples > 55, "alternating real stance intervals at " + label)
	check(longest_slip < 0.002 and reach_error < 0.002, "planted soles at %s: %.1f mm slip, %.1f mm target error" % [label, longest_slip * 1000, reach_error * 1000])
	check(knee_range.y - knee_range.x > 0.20 and foot_range.x < -0.08 and foot_range.y > 0.08, "knees bend as feet pass behind and ahead along the actual route at " + label)
	if velocity.z < -0.5 and duck < 0.1: check(forward_arm > 0.2, "opposite arm and leg advance together at " + label)

func _slope() -> void:
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.16, 12)
	shape.shape = box
	ramp.add_child(shape)
	world.add_child(ramp)
	ramp.rotation.z = 0.24
	var normal := ramp.global_basis.y
	ramp.global_position = -normal * 0.08
	await physics_frame
	await physics_frame
	avatar.motion_world = world
	avatar.first_person_body = true
	avatar.gait.reset()
	avatar.position = Vector3.ZERO
	var maximum := 0.0
	var slope_alignment := 1.0
	for tick in 120:
		var v := Vector3(1.2, tan(0.24) * 1.2, 0)
		avatar.position += v * DT
		# Inspect targets before any active ragdoll motor writes its physical result back.
		avatar._animate_pose(DT, v.x, 0, false, v, true, Vector3.UP)
		for i in 2:
			var f := avatar.gait.feet[i]
			if f.planted and tick > 10:
				maximum = maxf(maximum, absf(f.sole.dot(normal)))
				slope_alignment = minf(slope_alignment, f.normal.dot(normal))
	check(maximum < 0.003 and slope_alignment > 0.997, "feet find the physical ramp without a supplied slope normal (%.1f mm plane error)" % (maximum * 1000))
	ramp.queue_free()
	await process_frame

func _physical_walk() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(15, 0.2, 25)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)
	floor_body.position.y = -0.1
	avatar.motion_world = null
	avatar.gait.reset()
	avatar.position = Vector3.ZERO
	avatar.pose(0, 0, 0, false, Vector3.ZERO, true)
	var rig := WastelandActiveRagdoll.start(avatar, avatar, null, true)
	var ankles := [rig.body_for(&"ankle_l"), rig.body_for(&"ankle_r")]
	for ankle: RigidBody3D in ankles:
		ankle.max_contacts_reported = 4
		ankle.contact_monitor = true
	var stance_age := [0, 0]
	var start := [Vector3.ZERO, Vector3.ZERO]
	var samples := 0
	var contacts := 0
	var slip := 0.0
	for tick in 225:
		await physics_frame
		for i in 2:
			var ankle: RigidBody3D = ankles[i]
			if tick < 70 or not avatar.gait.feet[i].planted:
				stance_age[i] = 0
				continue
			stance_age[i] += 1
			if stance_age[i] == 6: start[i] = ankle.global_position
			elif stance_age[i] > 6:
				samples += 1
				if ankle.get_colliding_bodies().has(floor_body): contacts += 1
				slip = maxf(slip, (ankle.global_position - start[i]).slide(Vector3.UP).length())
		rig.restore_targets()
		_walk(Vector3.FORWARD * 1.45 if tick > 30 else Vector3.ZERO, 0)
		rig.capture_targets()
	check(samples > 70 and contacts > int(samples * 0.4), "active ankle bodies contact the static floor during stance (%d / %d)" % [contacts, samples])
	check(slip < 0.11, "actual driven ankles remain within %.1f mm of their loaded position" % (slip * 1000))
	rig.stop_driving()
