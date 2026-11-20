extends SceneTree
## Passive observer of the original two-character phase-1 smoke-test ordering.
## -- --physics-hz=60 --out-dir=<existing output folder>
const ARENA := preload("../tests/physics_character_test.tscn")
const CHARACTER := preload("../physics_character.tscn")
const Actor := preload("../physics_character.gd")
const State := preload("../state/physics_character_state.gd")
const Experiment := preload("experiment_config.gd")

var _history := {"standing": [], "released": []}
var _peaks := {"standing": {"m": -1.0}, "released": {"m": -1.0}}
var _hz := 0
var _profile := "baseline"
var _out := "user://rig_stability"
var _io_ok := true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			_out = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--profile="):
			_profile = arg.trim_prefix("--profile=")
	if _profile not in Experiment.PROFILES:
		printerr("Unknown profile: ", _profile)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		quit(2)
		return
	if change_scene_to_packed(ARENA) != OK:
		quit(2)
		return
	await scene_changed
	await physics_frame
	var arena := current_scene
	var standing: Actor = arena.get_node("Character")
	var space := standing.get_world_3d().space
	var iterations := Experiment.iterations(_profile)
	Experiment.configure_space(_profile, space)
	if iterations > 0:
		if roundi(PhysicsServer3D.space_get_param(space, PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS)) != iterations:
			printerr("Space solver setting did not take effect")
			quit(2)
			return
	_observe(standing, "standing")
	var falling: Actor = CHARACTER.instantiate()
	falling.config = Experiment.create(_profile)
	falling.get_node("Visual").free()
	falling.position = Vector3(2.8, 3.0, 1.1)
	falling.rotation = Vector3(0.0, 0.35, 1.32)
	arena.add_child(falling)
	_observe(falling, "released")
	falling.submit_intent(Vector3.RIGHT * 2.0, Vector3.FORWARD, true, true)
	falling.submit_intent(Vector3.RIGHT * 2.0, Vector3.FORWARD, false, true)
	_hz = Engine.physics_ticks_per_second
	for frame in _hz * 4:
		if frame == roundi(_hz * 0.5):
			arena.push_block()
		await physics_frame
	for tag: String in _history:
		_export(tag)
	var maximum := maxf(_peaks.standing.m, _peaks.released.m)
	var reference := 0.1093 if _hz == 60 else 0.0639
	print("PHASE1_REPLAY profile=%s hz=%d peak=%.7f released=%.7f reference=%.4f" % [
		_profile, _hz, maximum, _peaks.released.m, reference])
	unload_current_scene()
	await process_frame
	var matches := _profile != "baseline" or absf(maximum - reference) < 0.0001
	quit(0 if _hz in [60, 120] and matches and _io_ok else 1)

func _observe(actor: Actor, tag: String) -> void:
	var anchors: Array[Dictionary] = []
	var centers := {}
	for segment: Dictionary in actor.config.build_segments():
		centers[segment.id] = segment.position
	for joint: Dictionary in actor.config.build_joints():
		anchors.append({"a": joint.parent, "b": joint.child,
			"offset_a": joint.position - centers[joint.parent], "offset_b": joint.position - centers[joint.child]})
	actor.state_updated.connect(_sample.bind(actor, tag, anchors))

func _sample(frame: State, actor: Actor, tag: String, anchors: Array[Dictionary]) -> void:
	var body_samples := {}
	var errors := {}
	var external_pairs := PackedStringArray()
	var rig := actor.get_node("PhysicsRig")
	for id: StringName in rig.bodies:
		var body: RigidBody3D = rig.bodies[id]
		var direct := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var contacts := {}
		if direct != null:
			for n in direct.get_contact_count():
				var other := direct.get_contact_collider_object(n) as Node
				if other == null:
					continue
				var pair := ("self/" if other.get_parent() == rig else "external/") + str(other.name)
				contacts[pair] = float(contacts.get(pair, 0.0)) + direct.get_contact_impulse(n).length()
				if other.get_parent() != rig:
					var external := String(id) + "/" + String(other.name)
					if not external_pairs.has(external):
						external_pairs.append(external)
		body_samples[id] = {"v": body.linear_velocity, "w": body.angular_velocity, "contacts": contacts}
	for joint: Dictionary in anchors:
		var pa: Vector3 = frame.body_poses[joint.a] * joint.offset_a
		var pb: Vector3 = frame.body_poses[joint.b] * joint.offset_b
		var error := pa.distance_to(pb)
		errors[joint.b] = error
		if error > _peaks[tag].m:
			_peaks[tag] = {"m": error, "tick": frame.tick_index, "parent": joint.a, "child": joint.b}
	_history[tag].append({"tick": frame.tick_index, "bodies": body_samples, "errors": errors,
		"external": ";".join(external_pairs)})

func _export(tag: String) -> void:
	var peak: Dictionary = _peaks[tag]
	var a: StringName = peak.parent
	var b: StringName = peak.child
	var prefix := "phase1" if _profile == "baseline" else "phase1_" + _profile
	var path := _out.path_join("%s_%s_%s.csv" % [prefix, _hz, tag])
	var csv := FileAccess.open(path, FileAccess.WRITE)
	if csv == null:
		printerr("Could not write ", path)
		_io_ok = false
		return
	csv.store_csv_line(PackedStringArray(["hz", "rig", "local_tick", "t_s", "parent", "child", "anchor_m",
		"parent_vx", "parent_vy", "parent_vz", "parent_wx", "parent_wy", "parent_wz",
		"child_vx", "child_vy", "child_vz", "child_wx", "child_wy", "child_wz",
		"relative_center_speed_m_s", "relative_angular_speed_rad_s",
		"parent_contact_impulses_Ns", "child_contact_impulses_Ns", "all_external_contact_pairs"]))
	for frame: Dictionary in _history[tag]:
		var p: Dictionary = frame.bodies[a]
		var c: Dictionary = frame.bodies[b]
		var line := PackedStringArray([str(_hz), tag, str(frame.tick), "%.7f" % (float(frame.tick) / _hz),
			str(a), str(b), "%.8f" % frame.errors[b]])
		for vector: Vector3 in [p.v, p.w, c.v, c.w]:
			line.append_array(PackedStringArray(["%.6f" % vector.x, "%.6f" % vector.y, "%.6f" % vector.z]))
		line.append_array(PackedStringArray(["%.6f" % c.v.distance_to(p.v), "%.6f" % c.w.distance_to(p.w),
			JSON.stringify(p.contacts), JSON.stringify(c.contacts), frame.external]))
		csv.store_csv_line(line)
	print("PEAK ", _hz, " ", tag, " ", peak)
