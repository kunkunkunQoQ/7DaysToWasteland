extends SceneTree
## One process, one freshly constructed world, one perturbation/profile/rate.
const Rig := preload("../body/physics_rig.gd")
const Experiment := preload("experiment_config.gd")
const Meter := preload("joint_telemetry.gd")
const Penetration := preload("penetration_probe.gd")
const CASES := ["drop_low", "drop_front", "drop_back", "drop_side_l", "drop_side_r",
	"drop_prone_first", "drop_supine_first", "hit_front", "hit_back", "hit_left", "hit_right", "hit_arm", "hit_leg", "hit_repeat"]
const DEFAULT_DURATION_S := 5

class Shot:
	var body: RigidBody3D
	var target: StringName
	var direction: Vector3
	var launch_tick: int
	var first_tick := -1
	var first_parts: Array[String] = []
	var alignment := -1.0
	var max_contact_impulse := 0.0

	func observe(tick: int) -> void:
		if not is_instance_valid(body):
			return
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		for i in state.get_contact_count():
			var other := state.get_contact_collider_object(i) as RigidBody3D
			if other == null:
				continue
			if first_tick == -1:
				first_tick = tick
			if first_tick == tick and String(other.name) not in first_parts:
				first_parts.append(String(other.name))
			if other.name == target:
				if first_tick == tick:
					alignment = maxf(alignment, -state.get_contact_local_normal(i).dot(direction))
				max_contact_impulse = maxf(max_contact_impulse, state.get_contact_impulse(i).length())

	func row(hz: int, require_single: bool) -> Dictionary:
		var ok := first_tick >= 0 and String(target) in first_parts and alignment > 0.2 and max_contact_impulse > 0.0
		if require_single:
			ok = ok and first_parts.size() == 1
		return {"target":String(target), "launch_tick":launch_tick, "first_contact_tick":first_tick,
			"first_parts":"|".join(first_parts), "direction_world":str(direction), "normal_alignment":alignment,
			"max_target_contact_impulse_ns":max_contact_impulse, "latency_s":float(first_tick-launch_tick)/hz if first_tick >= 0 else -1.0,
			"hit_pass":ok}

var _rig: Rig
var _ground: StaticBody3D
var _arena := Node3D.new()
var _shots: Array[Shot] = []

func _initialize() -> void:
	# Select the tick frequency before the first main-loop iteration. Changing
	# it from deferred setup can give the newborn bodies one 60 Hz step on a
	# 120 Hz run; the timing then depends on the idle/render pacing.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			var rate := int(arg.trim_prefix("--hz="))
			if rate in [60, 120]:
				Engine.physics_ticks_per_second = rate
	_run.call_deferred()

func _run() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1] if pair.size() == 2 else "true"
	var scenario := str(options.get("case", "drop_side_l"))
	var profile := str(options.get("profile", "baseline"))
	var hz := int(options.get("hz", 60))
	var duration_s := int(options.get("duration-s", DEFAULT_DURATION_S))
	var allow_sleep := options.has("allow-sleep")
	if scenario not in CASES or profile not in Experiment.PROFILES or hz not in [60, 120] or duration_s < 5 or duration_s > 30:
		printerr("Expected --case=<matrix case>, --profile=<experiment profile>, --hz=60|120.")
		_arena.free()
		quit(2)
		return
	var out := ProjectSettings.globalize_path(str(options.get("out", "user://physics_character_stability")))
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		printerr("Cannot create output directory ", out)
		_arena.free()
		quit(2)
		return
	var prefix := out.path_join("%s_%s_%s" % [scenario, profile, hz])
	if duration_s != DEFAULT_DURATION_S:
		prefix += "_%ds" % duration_s
	if allow_sleep:
		prefix += "_sleep"
	Engine.physics_ticks_per_second = hz
	root.add_child(_arena)
	var world := _arena.get_world_3d()
	if world.direct_space_state.get_class() != &"GodotPhysicsDirectSpaceState3D":
		printerr("The stability matrix requires GodotPhysics3D. Current space: ", world.direct_space_state.get_class())
		_arena.free()
		quit(2)
		return
	var space := world.space
	var solver := PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS
	var iterations := Experiment.iterations(profile)
	Experiment.configure_space(profile, space)
	var actual_iterations := roundi(PhysicsServer3D.space_get_param(space, solver))
	if iterations > 0 and actual_iterations != iterations:
		printerr("Space did not apply the requested iteration count")
		quit(2)
		return
	_build_floor()
	var config := Experiment.create(profile)
	_rig = Rig.new()
	_rig.name = "PhysicsRig"
	_rig.position = Vector3(0.0, 0.25, 0.0)
	if scenario.begins_with("drop_") and scenario != "drop_low":
		_rig.position = Vector3(2.8, 3.0, 1.1)
		# +Z tilt puts the left side of the rig below its right; local -Z is front.
		match scenario:
			"drop_front": _rig.rotation = Vector3(-1.32, 0.35, 0.0)
			"drop_back": _rig.rotation = Vector3(1.32, 0.35, 0.0)
			"drop_prone_first": _rig.rotation = Vector3(-1.75, 0.35, 0.0)
			"drop_supine_first": _rig.rotation = Vector3(1.75, 0.35, 0.0)
			"drop_side_l": _rig.rotation = Vector3(0.0, 0.35, 1.32)
			"drop_side_r": _rig.rotation = Vector3(0.0, 0.35, -1.32)
	if scenario == "hit_repeat":
		_rig.position.y = 1.7
	_arena.add_child(_rig)
	_rig.build(config)
	if allow_sleep:
		for body: RigidBody3D in _rig.bodies.values():
			body.can_sleep = true
	var pen := Penetration.new()
	pen.setup(_rig, config)
	if options.has("trace"):
		pen.trace = FileAccess.open(prefix + "_penetration.csv", FileAccess.WRITE)
		if pen.trace == null:
			printerr("Cannot create penetration trace CSV")
			quit(2)
			return
	pen.sample(0, false)
	var meter := Meter.new()
	var trace: FileAccess
	if options.has("trace"):
		trace = FileAccess.open(prefix + "_trace.csv", FileAccess.WRITE)
		if trace == null:
			printerr("Cannot create trace CSV")
			quit(2)
			return
	meter.setup(_rig, config, hz, trace)
	var last_impact := -1
	var first_ground := -1
	var first_ground_parts: Array[String] = []
	var release_face := Vector3.ZERO
	match scenario:
		"drop_low": release_face = Vector3.DOWN
		"drop_front", "drop_prone_first": release_face = Vector3.FORWARD
		"drop_back", "drop_supine_first": release_face = Vector3.BACK
		"drop_side_l": release_face = Vector3.LEFT
		"drop_side_r": release_face = Vector3.RIGHT
	var chest: RigidBody3D = _rig.bodies[&"chest"]
	var release_alignment := (chest.global_basis * release_face).dot(Vector3.DOWN)
	var previous_alignment := release_alignment
	var landing_alignment := 0.0
	var n := duration_s * hz
	for tick in range(1, n + 1):
		_launch_if_due(scenario, tick - 1, hz)
		await physics_frame
		for shot in _shots:
			shot.observe(tick)
			if shot.first_tick == tick:
				last_impact = tick
			if tick - shot.launch_tick >= roundi(0.16 * hz) and is_instance_valid(shot.body):
				shot.body.free()
		if first_ground == -1:
			first_ground_parts = _floor_parts()
			if not first_ground_parts.is_empty():
				first_ground = tick
				last_impact = tick
				# GodotPhysics reports contacts from the preceding pose.
				landing_alignment = previous_alignment
		previous_alignment = (chest.global_basis * release_face).dot(Vector3.DOWN)
		meter.sample(tick, last_impact)
		pen.sample(tick, tick > n - roundi(0.5 * hz))
	var report: Dictionary = meter.finish()
	var summary: Dictionary = report.body
	summary.merge(pen.finish(hz))
	summary["first_floor_tick"] = first_ground
	summary["first_floor_parts"] = "|".join(first_ground_parts)
	summary["release_facing_down_dot"] = release_alignment
	summary["landing_facing_down_dot"] = landing_alignment
	summary["final_impact_tick"] = last_impact
	summary["shots"] = _shots.size()
	summary["duration_s"] = duration_s
	summary["allow_sleep"] = allow_sleep
	var asleep := 0
	for body: RigidBody3D in _rig.bodies.values():
		asleep += int(body.sleeping)
	summary["final_sleeping_bodies"] = asleep
	var passed_shots := 0
	var events: Array[Dictionary] = []
	var context := {"case":scenario, "profile":profile, "hz":hz, "solver_iterations":actual_iterations,
		"contact_max_separation_m":PhysicsServer3D.space_get_param(space, PhysicsServer3D.SPACE_PARAM_CONTACT_MAX_SEPARATION),
		"contact_max_allowed_penetration_m":PhysicsServer3D.space_get_param(space, PhysicsServer3D.SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION)}
	for index in _shots.size():
		var event := _shots[index].row(hz, scenario in ["hit_arm", "hit_leg"])
		event["shot"] = index + 1
		if event.hit_pass:
			passed_shots += 1
		event.merge(context)
		events.append(event)
	summary["hits_verified"] = passed_shots
	var orientation_ok := release_face == Vector3.ZERO or landing_alignment >= 0.65
	var strict_torso := scenario in ["drop_prone_first", "drop_supine_first"]
	var torso_contact_ok := not strict_torso or ("chest" in first_ground_parts or "head" in first_ground_parts)
	summary["orientation_pass"] = orientation_ok
	summary["first_contact_pass"] = first_ground > 0 and torso_contact_ok
	var expected_shots := int(scenario.begins_with("hit_"))
	if scenario == "hit_repeat":
		expected_shots = 3
	summary["excitation_pass"] = _shots.size() == expected_shots and passed_shots == expected_shots and summary.first_contact_pass and orientation_ok
	summary["matrix_pass"] = summary.excitation_pass and summary.penetration_pass and bool(summary["pass"])
	summary.merge(context)
	for row: Dictionary in report.joints:
		row.merge(context)
	var wrote := _write(prefix + "_body.csv", [summary]) and _write(prefix + "_joints.csv", report.joints)
	if not events.is_empty():
		wrote = _write(prefix + "_impacts.csv", events) and wrote
	if trace != null:
		trace.close()
		pen.trace.close()
	print("STABILITY ", scenario, " ", profile, " ", hz, "Hz peak=", summary.max_anchor_m, " pass=", summary.matrix_pass, " hits=", passed_shots, "/", _shots.size())
	_arena.free()
	quit(0 if wrote and summary.matrix_pass else 1)

func _write(path: String, rows: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + path)
		return false
	Meter.write_table(file, rows)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

func _build_floor() -> void:
	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	_ground.position.y = -0.1
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	var collider := CollisionShape3D.new()
	collider.shape = box
	_ground.add_child(collider)
	_arena.add_child(_ground)

func _floor_parts() -> Array[String]:
	var parts: Array[String] = []
	for body: RigidBody3D in _rig.bodies.values():
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		for i in state.get_contact_count():
			if state.get_contact_collider_object(i) == _ground:
				parts.append(String(body.name))
				break
	return parts

func _launch_if_due(scenario: String, tick: int, hz: int) -> void:
	if scenario == "hit_repeat":
		# Three distinct strikers; the current pose supplies the launch point only.
		if tick == 0 or tick == roundi(0.12 * hz) or tick == roundi(0.24 * hz):
			_launch(&"chest", Vector3.BACK, Vector3.ZERO, tick)
		return
	if tick != 0:
		return
	match scenario:
		"hit_front": _launch(&"chest", Vector3.BACK, Vector3.ZERO, tick)
		"hit_back": _launch(&"chest", Vector3.FORWARD, Vector3.ZERO, tick)
		"hit_left": _launch(&"pelvis", Vector3.RIGHT, Vector3(0,-0.035,0.082), tick)
		"hit_right": _launch(&"pelvis", Vector3.LEFT, Vector3(0,-0.035,0.082), tick)
		"hit_arm": _launch(&"lower_arm_l", Vector3.RIGHT, Vector3.ZERO, tick)
		"hit_leg": _launch(&"calf_r", Vector3.LEFT, Vector3.ZERO, tick)

func _launch(id: StringName, direction: Vector3, offset: Vector3, tick: int) -> void:
	var segment: RigidBody3D = _rig.bodies[id]
	var shot := Shot.new()
	shot.target = id
	shot.direction = direction
	shot.launch_tick = tick
	shot.body = RigidBody3D.new()
	shot.body.name = "Striker%d" % (_shots.size() + 1)
	shot.body.mass = 4.0
	shot.body.collision_layer = 2
	shot.body.collision_mask = 4
	shot.body.continuous_cd = true
	shot.body.max_contacts_reported = 16
	var sphere := SphereShape3D.new()
	sphere.radius = 0.032
	var collider := CollisionShape3D.new()
	collider.shape = sphere
	shot.body.add_child(collider)
	# Start the striker outside the actual target shape's supporting plane.
	var geom := segment.get_node("Collider") as CollisionShape3D
	var along := segment.global_basis.inverse() * direction
	var extent: float
	if geom.shape is BoxShape3D:
		extent = along.abs().dot((geom.shape as BoxShape3D).size * 0.5)
	else:
		var capsule := geom.shape as CapsuleShape3D
		extent = capsule.radius + absf(along.y) * (capsule.height * 0.5 - capsule.radius)
	shot.body.position = segment.to_global(offset) - direction * (extent + sphere.radius + 0.045)
	_arena.add_child(shot.body)
	shot.body.apply_central_impulse(shot.body.mass * (segment.linear_velocity + direction * 4.0))
	_shots.append(shot)
