extends SceneTree
## One reproducible 60 Hz trial. Use run_standing.py for visual pairs and control.

const SCENE := "res://game/actors/physics_character/active_character.tscn"
const HZ := 60
const FRAMES := 60 * HZ
const IMPACT_FRAME := 10 * HZ
const IMPULSE_NS := 2.0
const DIRECTIONS := {"quiet": Vector3.ZERO, "front": Vector3.BACK,
	"back": Vector3.FORWARD, "left": Vector3.RIGHT, "right": Vector3.LEFT}

var _scenario := "quiet"
var _mode := "active"
var _visual := "on"
var _directory := ""
var _out_trace := false
var _actor: Node3D
var _chest: RigidBody3D
var _weight_n := 0.0
var _start_tick := -1
var _prev_tick := 0
var _initial_com: Vector3
var _initial_left: Vector3
var _initial_right: Vector3
var _initial_poses: Dictionary
var _trace: FileAccess
var _hash := HashingContext.new()
var _joint_stats := {}
var _invalid := 0
var _torque_invalid := 0
var _air_frames := 0
var _max_air_frames := 0
var _supported := 0
var _nonfoot := 0
var _fallen := 0
var _first_bad := -1
var _first_reason := ""
var _samples := 0
var _impacts := 0
var _sum_load_n := 0.0
var _min_pelvis := INF
var _min_com := INF
var _worst_tilt := 0.0
var _worst_com := 0.0
var _worst_slip := Vector2.ZERO
var _com_sq := 0.0
var _tilt_sq := 0.0
var _max_torque := 0.0

func _initialize() -> void:
	Engine.physics_ticks_per_second = HZ
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			_scenario = arg.trim_prefix("--case=")
		elif arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--visual="):
			_visual = arg.trim_prefix("--visual=")
		elif arg.begins_with("--out="):
			_directory = arg.trim_prefix("--out=")
		elif arg == "--trace":
			_out_trace = true
		else:
			_abort("Unknown option " + arg)
			return
	if _scenario not in DIRECTIONS or _mode not in ["active", "passive"] or _visual not in ["on", "off"]:
		_abort("Expected --case=quiet|front|back|left|right --mode=active|passive --visual=on|off.")
		return
	if not _directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_abort("An absolute, writable --out=<directory> is required.")
		return
	_start.call_deferred()

func _abort(message: String) -> void:
	printerr("STANDING ERROR ", message)
	quit(2)

func _start() -> void:
	if root.world_3d.direct_space_state.get_class() != &"GodotPhysicsDirectSpaceState3D":
		_abort("GodotPhysics3D is required.")
		return
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_abort("Could not load " + SCENE)
		return
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.position.y = -0.10
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.20, 20)
	var collider := CollisionShape3D.new()
	collider.shape = box
	ground.add_child(collider)
	root.add_child(ground)
	_actor = packed.instantiate()
	_actor.set("active_standing", _mode == "active")
	if _visual == "off":
		_actor.get_node("Visual").free()
	root.add_child(_actor)
	var state = _actor.call("get_state")
	if state == null or not _actor.has_method("get_muscle_telemetry") or not "left_support_load_n" in state or not "right_support_load_n" in state or not "nonfoot_ground_contact" in state:
		_abort("The character must expose measured sole loads, non-foot contact and bounded muscle telemetry.")
		return
	var rig = _actor.get_node("PhysicsRig")
	_chest = rig.bodies[&"chest"]
	if rig.bodies.size() != 16 or rig.joints.size() != 15:
		_abort("Expected 16 dynamic segments and 15 joints.")
		return
	var total_mass := 0.0
	for body: RigidBody3D in rig.bodies.values():
		if body.freeze or body.axis_lock_linear_x or body.axis_lock_linear_y or body.axis_lock_linear_z:
			_abort("A physical segment is frozen or translation-locked.")
			return
		total_mass += body.mass
	_weight_n = total_mass * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_initial_poses = state.body_poses
	_initial_com = state.center_of_mass
	_initial_left = state.left_sole_position
	_initial_right = state.right_sole_position
	for joint: StringName in rig.joints:
		_joint_stats[joint] = {"peak_nm":0.0, "sum_sq":0.0, "limit_min_nm":INF, "limit_max_nm":0.0,
			"saturated":0, "samples":0}
	if _out_trace:
		_trace = FileAccess.open(_path("frames.csv"), FileAccess.WRITE)
		if _trace == null:
			_abort("Cannot open frame CSV.")
			return
		_trace.store_csv_line(["tick", "measured_frame", "com_x", "com_y", "com_z", "pelvis_y", "chest_tilt_deg",
			"com_drift_m", "left_sole_slip_m", "right_sole_slip_m", "left_sole_load_n",
			"right_sole_load_n", "support_mask", "nonfoot_ground_contact", "fallen", "max_torque_nm"])
	_hash.start(HashingContext.HASH_SHA256)
	_actor.connect("state_updated", _observe)

func _path(suffix: String) -> String:
	return _directory.path_join("%s_%s_%s_%s" % [_mode, _scenario, _visual, suffix])

func _flag(tick: int, reason: String) -> void:
	if _first_bad < 0:
		_first_bad = tick
		_first_reason = reason

func _horizontal(delta: Vector3) -> float:
	return Vector2(delta.x, delta.z).length()

func _record_joints(tick: int, record: bool, fingerprint: PackedFloat32Array) -> float:
	var values: Dictionary = _actor.call("get_muscle_telemetry")
	if _mode == "active" and values.size() != 15:
		_torque_invalid += 1
		_flag(tick, "missing_torque")
	var largest := 0.0
	for joint: StringName in _joint_stats:
		if not values.has(joint):
			if _mode == "active":
				_torque_invalid += 1
				_flag(tick, "missing_joint_torque")
			continue
		var entry: Dictionary = values[joint]
		if typeof(entry.get("torque_world_nm")) != TYPE_VECTOR3 or not entry.has("limit_nm"):
			_torque_invalid += 1
			_flag(tick, "bad_torque_record")
			continue
		var torque: Vector3 = entry.torque_world_nm
		var limit: float = entry.limit_nm
		var magnitude := torque.length()
		if not torque.is_finite() or not is_finite(limit) or limit < 0 or (_mode == "active" and limit <= 0) or magnitude > limit * 1.00001 + 0.0001:
			_torque_invalid += 1
			_flag(tick, "torque_limit")
		largest = maxf(largest, magnitude)
		fingerprint.append_array(PackedFloat32Array([torque.x, torque.y, torque.z, limit]))
		if record:
			var stats: Dictionary = _joint_stats[joint]
			stats.peak_nm = maxf(stats.peak_nm, magnitude)
			stats.sum_sq += magnitude * magnitude
			stats.limit_min_nm = minf(stats.limit_min_nm, limit)
			stats.limit_max_nm = maxf(stats.limit_max_nm, limit)
			stats.saturated += int(limit > 0 and magnitude >= 0.99 * limit)
			stats.samples += 1
	return largest

func _observe(state) -> void:
	var tick: int = state.tick_index
	if tick != _prev_tick + 1 or not is_equal_approx(state.step_seconds, 1.0 / HZ):
		_invalid += 1
		_flag(tick, "physics_clock")
	_prev_tick = tick
	var com: Vector3 = state.center_of_mass
	var pelvis_y: float = state.pelvis_position.y
	var left: float = state.left_support_load_n
	var right: float = state.right_support_load_n
	var supported: bool = state.grounded and left + right >= 0.02 * _weight_n
	if _start_tick < 0:
		if supported:
			_start_tick = tick
		elif tick >= HZ / 2:
			_start_tick = tick
			_flag(tick, "no_initial_sole_load")
	var recording := _start_tick >= 0
	var fingerprint := PackedFloat32Array()
	for id: StringName in _initial_poses:
		var pose: Transform3D = state.body_poses[id]
		if not pose.is_finite():
			_invalid += 1
			_flag(tick, "nonfinite_pose")
		for vec: Vector3 in [pose.basis.x, pose.basis.y, pose.basis.z, pose.origin]:
			fingerprint.append_array(PackedFloat32Array([vec.x, vec.y, vec.z]))
	var frame_torque := _record_joints(tick, recording, fingerprint)
	var tilt := rad_to_deg((state.body_poses[&"chest"] as Transform3D).basis.y.angle_to(Vector3.UP))
	var drift := _horizontal(com - _initial_com)
	var slip := Vector2(_horizontal(state.left_sole_position - _initial_left), _horizontal(state.right_sole_position - _initial_right))
	if not com.is_finite() or not is_finite(pelvis_y) or not is_finite(left) or not is_finite(right) or left < 0 or right < 0:
		_invalid += 1
		_flag(tick, "nonfinite_or_negative_measurement")
	fingerprint.append_array(PackedFloat32Array([com.x, com.y, com.z, left, right, float(state.support_feet),
		float(state.nonfoot_ground_contact), float(state.fallen)]))
	_hash.update(fingerprint.to_byte_array())
	_min_com = minf(_min_com, com.y)
	_min_pelvis = minf(_min_pelvis, pelvis_y)
	_worst_tilt = maxf(_worst_tilt, tilt)
	_worst_com = maxf(_worst_com, drift)
	_worst_slip = _worst_slip.max(slip)
	_max_torque = maxf(_max_torque, frame_torque)
	_fallen += int(state.fallen)
	_nonfoot += int(state.nonfoot_ground_contact)
	if state.fallen or state.nonfoot_ground_contact or com.y < 0.72 or pelvis_y < 0.72 or tilt > 25.0:
		_flag(tick, "posture_or_nonfoot_support")
	if drift > 0.15 or slip.x > 0.10 or slip.y > 0.10:
		_flag(tick, "com_or_foot_drift")
	if recording:
		_samples += 1
		_sum_load_n += left + right
		_com_sq += drift * drift
		_tilt_sq += tilt * tilt
		_supported += int(supported)
		_air_frames = 0 if supported else _air_frames + 1
		_max_air_frames = maxi(_air_frames, _max_air_frames)
		if _air_frames > 6:
			_flag(tick, "lost_load_over_100ms")
		if _samples == IMPACT_FRAME and DIRECTIONS[_scenario] != Vector3.ZERO:
			# Instrumented external strike; no changes to velocity or pose.
			_chest.apply_central_impulse(DIRECTIONS[_scenario] * IMPULSE_NS)
			_impacts += 1
	if _trace != null:
		_trace.store_csv_line(PackedStringArray([str(tick), str(_samples), str(com.x), str(com.y), str(com.z), str(pelvis_y),
			str(tilt), str(drift), str(slip.x), str(slip.y), str(left), str(right), str(state.support_feet),
			str(state.nonfoot_ground_contact), str(state.fallen), str(frame_torque)]))
	if _samples == FRAMES:
		_actor.disconnect("state_updated", _observe)
		_finish.call_deferred()

func _finish() -> void:
	var coverage := float(_supported) / FRAMES
	var load_fraction := _sum_load_n / (FRAMES * _weight_n)
	if coverage < 0.95 or absf(load_fraction - 1.0) > 0.15:
		_flag(_prev_tick, "insufficient_support")
	if _impacts != int(_scenario != "quiet"):
		_flag(_prev_tick, "missing_impact")
	if _mode == "active":
		for joint: StringName in [&"spine", &"thigh_l", &"thigh_r", &"calf_l", &"calf_r", &"foot_l", &"foot_r"]:
			if _joint_stats[joint].peak_nm < 0.001:
				_flag(_prev_tick, "missing_stance_actuator")
	var stood := _first_bad < 0
	var passed := stood if _mode == "active" else not stood and _fallen > 0 and _max_torque == 0.0 and _invalid == 0 and _torque_invalid == 0
	var summary := {"mode":_mode, "case":_scenario, "visual":_visual, "hz":HZ, "samples":_samples,
		"first_measured_tick":_start_tick, "first_failed_tick":_first_bad, "first_failure":_first_reason,
		"posture_pass":stood, "test_pass":passed, "direction":str(DIRECTIONS[_scenario]), "external_impulses":_impacts,
		"impulse_ns":IMPULSE_NS if _impacts else 0.0, "com_drift_peak_m":_worst_com,
		"com_drift_rms_m":sqrt(_com_sq/FRAMES), "pelvis_min_m":_min_pelvis, "com_min_m":_min_com,
		"chest_tilt_peak_deg":_worst_tilt, "chest_tilt_rms_deg":sqrt(_tilt_sq/FRAMES),
		"left_sole_drift_peak_m":_worst_slip.x, "right_sole_drift_peak_m":_worst_slip.y,
		"supported_fraction":coverage, "max_consecutive_unloaded_s":float(_max_air_frames)/HZ,
		"support_impulse_over_weight_impulse":load_fraction, "nonfoot_contact_frames":_nonfoot,
		"fallen_frames":_fallen, "peak_torque_nm":_max_torque, "invalid_samples":_invalid,
		"invalid_torque_samples":_torque_invalid, "physics_sha256":_hash.finish().hex_encode()}
	var file := FileAccess.open(_path("summary.json"), FileAccess.WRITE)
	var joints := FileAccess.open(_path("joints.csv"), FileAccess.WRITE)
	if file == null or joints == null:
		_abort("Could not write results.")
		return
	file.store_line(JSON.stringify(summary))
	joints.store_csv_line(["joint", "samples", "peak_nm", "rms_nm", "min_limit_nm", "max_limit_nm", "saturated_frames"])
	for id: StringName in _joint_stats:
		var stats: Dictionary = _joint_stats[id]
		var n := int(stats.samples)
		joints.store_csv_line(PackedStringArray([String(id), str(n), str(stats.peak_nm), str(sqrt(stats.sum_sq / maxi(1, n))),
			str(stats.limit_min_nm if n else 0.0), str(stats.limit_max_nm), str(stats.saturated)]))
	file.close()
	joints.close()
	if _trace:
		_trace.close()
	print("STANDING ", JSON.stringify(summary))
	quit(0 if passed else 1)
