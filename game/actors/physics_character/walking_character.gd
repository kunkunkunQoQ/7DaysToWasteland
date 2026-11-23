extends "active_character.gd"

const Gait := preload("controllers/gait_generator.gd")
const WalkingBalance := preload("controllers/walking_balance.gd")
const MovingMuscles := preload("controllers/walking_muscles.gd")
## Empirical release threshold for a foot already carrying weight, in rad/s.
## A release is recorded as a failed gait trial, including when the fall settles.
const LOADED_FOOT_SPEED_LIMIT := 14.0
var _moving_muscles := MovingMuscles.new()
var _gait := Gait.new()
var _balance := WalkingBalance.new()
var _own_colliders: Array[RID] = []
var _walk_started := false
var _joint_mounts: Array[Dictionary] = []
var _release_reason := ""
var _release_tick := -1
var _unloaded_tilt_steps := 0
var _body_weight_n := 0.0

func _ready() -> void:
	_muscles = _moving_muscles
	super._ready()
	if config == null:
		return
	_balance.setup(config)
	_gait.setup(float(ProjectSettings.get_setting("physics/3d/default_gravity")), _probe_ground)
	for body: RigidBody3D in _rig.bodies.values():
		_own_colliders.append(body.get_rid())
	for id in [&"foot_l",&"foot_r"]:
		_rig.bodies[id].use_witness_pose = true
	var centers := {}
	for row in config.build_segments():
		centers[row.id] = row.position
		_body_weight_n += float(row.mass) * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	for joint in config.build_joints():
		_joint_mounts.append({"parent":joint.parent,"child":joint.child,
			"a":joint.position-centers[joint.parent],"b":joint.position-centers[joint.child]})

func _probe_ground(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.40, point + Vector3.DOWN * 0.60, config.body_mask, _own_colliders)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < config.min_ground_up_dot:
		return {}
	return {"position":hit.position,"normal":hit.normal}

func _actuate(state: State, intent: IntentFrame, delta: float) -> void:
	if not active_standing:
		return
	if _walk_started and _release_reason.is_empty():
		var tilted := state.body_poses[&"chest"].basis.y.dot(Vector3.UP) < cos(deg_to_rad(30.0))
		var unloaded := state.left_support_load_n + state.right_support_load_n < 0.12 * _body_weight_n
		_unloaded_tilt_steps = _unloaded_tilt_steps + 1 if tilted and unloaded else 0
		if _loaded_foot_overspeed(state):
			_release_reason = "foot_overspeed"
		elif state.fallen:
			_release_reason = "fallen"
		elif _unloaded_tilt_steps >= 2:
			_release_reason = "tilted_without_support"
		else:
			for mount in _joint_mounts:
				var a: Vector3 = state.body_poses[mount.parent] * Vector3(mount.a)
				var b: Vector3 = state.body_poses[mount.child] * Vector3(mount.b)
				if a.distance_squared_to(b) > 0.08 * 0.08:
					_release_reason = "anchor_" + String(mount.child)
					break
	if not _release_reason.is_empty():
		if _release_tick < 0:
			_release_tick = state.tick_index
		_muscles.step(delta,{}, {},0.0)
		return
	var command := _gait.advance(state,intent.desired_velocity,intent.desired_facing,delta)
	if _gait.phase != &"stop":
		_walk_started = true
	if not _walk_started:
		super._actuate(state,intent,delta)
		return
	_balance.plan_step(state,intent.desired_facing,delta,command)
	_coordinate_arms(state,command.heading)
	_moving_muscles.step_walk(delta,_balance.relative_targets,_balance.feedforward_world_nm,
		command.phase,command.support)

func _loaded_foot_overspeed(state: State) -> bool:
	var min_load := 0.03 * _body_weight_n
	return ((state.left_support_load_n >= min_load and state.body_angular_velocities[&"foot_l"].length() > LOADED_FOOT_SPEED_LIMIT)
		or (state.right_support_load_n >= min_load and state.body_angular_velocities[&"foot_r"].length() > LOADED_FOOT_SPEED_LIMIT))

func _coordinate_arms(state: State, heading: Basis) -> void:
	# Counter the measured fore-aft leg separation and give the passing thigh
	# clearance. Shoulder torque still reacts on the moving chest.
	var stride := clampf((state.left_sole_position-state.right_sole_position).dot(-heading.z),-0.38,0.38)
	for side in [-1.0,1.0]:
		var suffix := "_l" if side < 0 else "_r"
		_balance.relative_targets["upper_arm"+suffix] = Basis(Vector3.BACK,side*0.14) * Basis(Vector3.RIGHT,side*0.55*stride)
		_balance.relative_targets["lower_arm"+suffix] = Basis(Vector3.RIGHT,0.18)

func get_gait_telemetry() -> Dictionary:
	return {"phase":_gait.phase if _release_reason.is_empty() else &"released",
		"release_reason":_release_reason,"release_tick":_release_tick,"support":_gait.support,"switches":_gait.switches,
		"target_velocity":_gait.target_velocity if _release_reason.is_empty() else Vector3.ZERO,"ground_probe":_gait.ground_probe.duplicate(),
		"com_target":_gait.commanded_center,"left_target":_gait.commanded_left,
		"right_target":_gait.commanded_right,"capture_point":_gait.capture_point}
