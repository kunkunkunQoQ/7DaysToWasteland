extends SceneTree
## Run with --script res://game/actors/physics_character/tests/verify_phase1.gd

const ARENA := preload("res://game/actors/physics_character/tests/physics_character_test.tscn")
const CHARACTER := preload("res://game/actors/physics_character/physics_character.tscn")
const Character := preload("../physics_character.gd")
const Rig := preload("../body/physics_rig.gd")
const State := preload("../state/physics_character_state.gd")
const Intent := preload("../controllers/physics_character_intent.gd")

var _passed := 0
var _failed := 0
var _previous_hz: int
var _intent_samples: Array[Intent] = []

func _initialize() -> void:
	_previous_hz = Engine.physics_ticks_per_second
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	var requested_hz := _previous_hz
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--physics-hz="):
			requested_hz = arg.trim_prefix("--physics-hz=").to_int()
	if requested_hz not in [60, 120]:
		printerr("Run this suite at 60 or 120 Hz.")
		quit(2)
		return
	_check(ProjectSettings.get_setting("physics/3d/physics_engine") in ["DEFAULT", "GodotPhysics3D"],
		"project uses GodotPhysics3D on the supported 4.6.3 build")
	if change_scene_to_packed(ARENA) != OK:
		printerr("Could not load the independent test arena.")
		quit(1)
		return
	await scene_changed
	await physics_frame
	var arena := current_scene
	var actor: Character = arena.get_node("Character")
	var rig: Rig = actor.get_node("PhysicsRig")
	var skeleton: Skeleton3D = actor.get_node("Visual/Skeleton3D")
	var initial := actor.get_state()
	_check(Engine.physics_ticks_per_second == requested_hz, "arena selected the requested tick rate")
	_check(rig.bodies.size() == 16 and rig.joints.size() == 15, "sixteen bodies and fifteen joints")
	_check(_structure_ok(actor, rig), "dynamic bodies have colliders and the fifteen passive joints match the configured topology")
	_check(skeleton.get_bone_count() == 16, "visual skeleton contains one bone per segment")
	_check(initial.body_poses.is_read_only() and initial.body_poses.size() == 16, "value-only pose map is read-only")

	# A second instance starts already tilted, in free fall, without any visual
	# or debug node. Its initial transform is only assigned before initialization.
	var falling: Character = CHARACTER.instantiate()
	falling.get_node("Visual").free()
	falling.position = Vector3(2.8, 3.0, 1.1)
	falling.rotation = Vector3(0.0, 0.35, 1.32)
	arena.add_child(falling)
	var first := falling.get_state()
	var archived_com := first.center_of_mass
	var archived_poses := first.body_poses.duplicate()
	_check(first.tick_index == 0 and first.step_seconds == 0.0, "initial snapshot is available at spawn")
	_check(not first.body_grounded and not first.grounded and not first.fallen, "tilted airborne spawn has neither contact nor a ground fall")
	_check(first.eye_position.is_equal_approx(first.body_poses[&"head"] * falling.config.eye_offset)
		and first.foot_position.is_equal_approx((first.body_poses[&"foot_l"] * falling.config.sole_offset
		+ first.body_poses[&"foot_r"] * falling.config.sole_offset) * 0.5),
		"eye and sole landmarks include the rotated and translated spawn transform")
	var controls := falling.get_node("Controller")
	var collect_intent := func(_frame: State, intent: Intent, _dt: float) -> void:
		if _intent_samples.size() < 2:
			_intent_samples.append(intent)
	controls.control_step.connect(collect_intent)
	falling.submit_intent(Vector3.RIGHT * 2.0, Vector3.FORWARD, true, true)
	falling.submit_intent(Vector3.RIGHT * 2.0, Vector3.FORWARD, false, true)

	var feet_touched := false
	var tilt_contact_fall := false
	var gravity_observed := false
	var valid_frames := true
	var worst_link_error := 0.0
	var anchors := _joint_anchors(actor)
	var start_tick := initial.tick_index
	var last_tick := start_tick
	var measured_dt := 0.0
	var block: RigidBody3D = arena.get_node("TestBlock")
	var block_start := block.global_position
	var frames := requested_hz * 4
	for frame in frames:
		if frame == roundi(requested_hz * 0.5):
			arena.push_block()
		await physics_frame
		var state := actor.get_state()
		var dropped := falling.get_state()
		measured_dt = state.step_seconds
		valid_frames = valid_frames and state.tick_index == last_tick + 1 and is_equal_approx(measured_dt, 1.0 / requested_hz)
		valid_frames = valid_frames and _finite_and_bounded(state) and _finite_and_bounded(dropped)
		worst_link_error = maxf(worst_link_error, _max_joint_separation(anchors, state))
		worst_link_error = maxf(worst_link_error, _max_joint_separation(anchors, dropped))
		last_tick = state.tick_index
		feet_touched = feet_touched or (state.body_grounded and state.grounded and state.support_feet != State.SupportFoot.NONE)
		gravity_observed = gravity_observed or (dropped.linear_velocity.y < -0.5 and not dropped.grounded and not dropped.fallen)
		tilt_contact_fall = tilt_contact_fall or (dropped.fallen and dropped.body_grounded)
	_check(valid_frames and last_tick - start_tick == frames, "each real physics step produces one finite, correctly timed observation")
	_check(first.tick_index == 0 and first.center_of_mass == archived_com and first.body_poses == archived_poses,
		"old snapshots retain their original values as the bodies move")
	_check(_intent_samples.size() == 2 and _intent_samples[0].jump_pressed and not _intent_samples[1].jump_pressed
		and _intent_samples[1].grab_held and _intent_samples[1].desired_velocity == Vector3.RIGHT * 2.0,
		"controller latches jump once and preserves held intent")
	_check(gravity_observed, "visual-free character accelerates downward under gravity")
	_check(feet_touched, "floor contact reaches the public support-foot state")
	_check(tilt_contact_fall, "tilted visual-free character reports a fall after ground contact")
	_check(worst_link_error < 0.18, "joint anchors remain within the gross initialization-smoke tolerance")
	_check(block.global_position.distance_to(block_start) > 0.15 and arena.block_hit_character,
		"the dynamic test block moves and contacts the character")
	var state := actor.get_state()
	_check(_com_matches(rig, state), "reported COM matches an independent mass-weighted sum")
	var visual_error := 0.0
	for id: StringName in state.body_poses:
		var index := skeleton.find_bone(String(id))
		var visual_pose := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		visual_error = maxf(visual_error, visual_pose.origin.distance_to(state.body_poses[id].origin))
	_check(visual_error < 0.0001, "all sixteen visual bones follow the published jointed body")
	var timing: Label = arena.get_node("Telemetry").get_node("%Timing")
	_check(timing.text.begins_with("%d Hz" % requested_hz), "telemetry displays the sampled tick rate")
	print("OBS hz=%d frames=%d dt=%.7f max_anchor_error_m=%.4f support=%s fall=%s block_contact=%s" %
		[requested_hz, frames, measured_dt, worst_link_error, feet_touched, tilt_contact_fall, arena.block_hit_character])
	unload_current_scene()
	await process_frame
	_check(Engine.physics_ticks_per_second == _previous_hz, "leaving the test arena restores the entry tick rate")
	print("PHASE1 passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed else 0)

func _structure_ok(actor: Character, rig: Rig) -> bool:
	for body: RigidBody3D in rig.bodies.values():
		if body.freeze or body.mass <= 0.0 or body.get_child_count() == 0:
			return false
		var shapes := body.find_children("*", "CollisionShape3D", false, false)
		if shapes.size() != 1 or shapes[0].shape == null:
			return false
	for row: Dictionary in actor.config.build_joints():
		var joint: Joint3D = rig.joints.get(row.child)
		if joint == null or not joint.exclude_nodes_from_collision:
			return false
		if joint.get_node_or_null(joint.node_a) != rig.bodies[row.parent] or joint.get_node_or_null(joint.node_b) != rig.bodies[row.child]:
			return false
		if row.kind == &"hinge":
			var hinge := joint as HingeJoint3D
			if hinge == null or not hinge.get_flag(HingeJoint3D.FLAG_USE_LIMIT) or hinge.get_flag(HingeJoint3D.FLAG_ENABLE_MOTOR):
				return false
		else:
			var multi_axis := joint as Generic6DOFJoint3D
			if multi_axis == null:
				return false
			for axis in ["x", "y", "z"]:
				if not multi_axis.get("angular_limit_%s/enabled" % axis) or multi_axis.get("angular_motor_%s/enabled" % axis):
					return false
	return true

func _finite_and_bounded(frame: State) -> bool:
	if not frame.center_of_mass.is_finite() or not frame.linear_velocity.is_finite() or not frame.angular_velocity.is_finite():
		return false
	for pose: Transform3D in frame.body_poses.values():
		if not pose.is_finite() or pose.origin.distance_to(frame.pelvis_position) > 2.5:
			return false
	return true

func _joint_anchors(actor: Character) -> Array[Dictionary]:
	var centers: Dictionary = {}
	for segment: Dictionary in actor.config.build_segments():
		centers[segment.id] = segment.position
	var anchors: Array[Dictionary] = []
	for joint: Dictionary in actor.config.build_joints():
		anchors.append({"parent": joint.parent, "child": joint.child,
			"a": joint.position - centers[joint.parent], "b": joint.position - centers[joint.child]})
	return anchors

func _max_joint_separation(anchors: Array[Dictionary], frame: State) -> float:
	var worst := 0.0
	for joint: Dictionary in anchors:
		var a: Vector3 = frame.body_poses[joint.parent] * joint.a
		var b: Vector3 = frame.body_poses[joint.child] * joint.b
		worst = maxf(worst, a.distance_to(b))
	return worst

func _com_matches(rig: Rig, frame: State) -> bool:
	var total := 0.0
	var center := Vector3.ZERO
	for id: StringName in rig.bodies:
		var body: RigidBody3D = rig.bodies[id]
		total += body.mass
		center += (frame.body_poses[id] * body.center_of_mass) * body.mass
	return frame.center_of_mass.distance_to(center / total) < 0.0001
