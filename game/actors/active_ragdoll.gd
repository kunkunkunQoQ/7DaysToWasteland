class_name WastelandActiveRagdoll
extends "res://game/actors/physical_ragdoll.gd"
## Animation supplies joint targets. The fixed-step motors move the colliding
## bodies, and the resulting transforms drive the same skin used when falling.

signal pose_applied

const Muscle := preload("res://game/actors/physics_character/controllers/joint_muscle_controller.gd")
const Balance := preload("res://game/actors/active_balance.gd")
const GROUP := &"active_character_motion"

var driving := true
var balance: Balance
var _model: Node3D
var _animation: Array[Transform3D] = []
var _targets: Array[Transform3D] = []
var _last_world: Array[Transform3D] = []
var _inverse_bind: Array[Transform3D] = []
var _index_by_bone := {}
var _gravity := 18.0

static func start(owner_node: Node3D, model: Node3D, stream: Node3D, _priority := false) -> WastelandActiveRagdoll:
	var rig := WastelandActiveRagdoll.new()
	owner_node.add_child(rig)
	rig._model = model
	rig._gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity",18.0))
	rig.set_water_source(stream)
	if not rig.begin(model):
		rig.queue_free()
		return null
	rig._remove_from_budget()
	rig.add_to_group(GROUP)
	for part in rig._parts:
		rig._index_by_bone[StringName(String(part.body.name).trim_prefix("Body_"))] = rig._inverse_bind.size()
		part.body.linear_velocity = Vector3.ZERO
		part.body.angular_velocity = Vector3.ZERO
		part.body.can_sleep = false
		# The CharacterBody handles navigation. These shapes make actual limb
		# contacts with the world, without obstructing the character capsule.
		rig._inverse_bind.append(part.bind.affine_inverse())
	rig._animation.resize(rig._parts.size())
	rig._targets.resize(rig._parts.size())
	rig.capture_targets()
	for part in rig._parts: rig._last_world.append(part.body.global_transform)
	rig.balance = Balance.new()
	rig.balance.setup(rig,owner_node.has_method("low_crawl") and (owner_node.type=="crawler" or owner_node.low_crawl()))
	return rig

func restore_targets() -> void:
	if not driving or _released: return
	for i in _parts.size():
		var part := _parts[i]
		if part.node != null: part.node.transform = _animation[i]
		else: _skeleton.set_bone_pose(part.bone,_animation[i])

func rebind_avatar(person: WastelandPartyAvatar) -> void:
	# The physics island stays in the world. Only the meshes receiving its pose change.
	_avatar = person
	_model = person
	_named_parts.hips.node = person.pivot
	_named_parts.torso.node = person.jacket
	_named_parts.head.node = person.neck
	for i in 2:
		var side := "l" if i == 0 else "r"
		_named_parts["arm_" + side].node = person.arms[i]
		_named_parts["elbow_" + side].node = person.elbows[i]
		_named_parts["hand_" + side].node = person.wrist_joints[i]
		_named_parts["leg_" + side].node = person.legs[i]
		_named_parts["knee_" + side].node = person.knees[i]
		_named_parts["ankle_" + side].node = person.ankle_joints[i]
	_sync_model()

func rebind_skeleton(target: Skeleton3D) -> void:
	# The route and fallen meshes for a species use the same joints and bind order.
	_skeleton = target
	_model = target
	_face_model = target.get_parent() if target.get_parent().has_method("sync_head") else null
	_sync_model()

func follow_relocation() -> void:
	var offset := (_model.global_transform * _targets[0]).origin - center()
	if offset.length_squared() <= 2.5 * 2.5: return
	for part in _parts:
		part.body.global_position += offset
		part.body.angular_velocity = Vector3.ZERO
		part.body.linear_velocity = Vector3.ZERO

func limb_deviation(bone: StringName) -> Vector3:
	var i: int = _index_by_bone.get(bone,-1)
	if i < 0 or not driving: return Vector3.ZERO
	var frame := _model.global_transform
	var rest_offset := frame.basis * (_targets[i].origin - _targets[0].origin)
	return _parts[i].body.global_position - _parts[0].body.global_position - rest_offset

func supported_velocity(requested: Vector3) -> Vector3:
	# The capsule plans a walkable route. A blocked physical trunk limits further
	# travel into the obstruction, while lateral movement and backing out stay available.
	if not driving or _targets.is_empty(): return requested
	var lag := ((_model.global_transform * _targets[0]).origin - center()).slide(Vector3.UP)
	var gap := lag.length()
	var slack := maxf(_parts[0].radius * 0.6, 0.075) + requested.slide(Vector3.UP).length() * 0.035
	if gap <= slack or gap > 2.5: return requested
	var ahead := lag / gap
	var closing := maxf(0.0, (requested - motion()).dot(ahead))
	var correction := minf(closing, maxf(0.0, requested.dot(ahead)))
	return requested - ahead * correction * smoothstep(slack, slack + 0.18, gap)

func kick_at(velocity: Vector3, at: Vector3, bone: StringName = &"") -> void:
	super.kick_at(velocity,at,bone)
	if driving and balance and not _released: balance.hit(velocity,at,bone)

func capture_targets() -> void:
	if not driving or _released: return
	var frame := _model.global_transform.affine_inverse()
	for i in _parts.size():
		var part := _parts[i]
		if part.node != null:
			_animation[i] = part.node.transform
			_targets[i] = frame * part.node.global_transform * _inverse_bind[i]
		else:
			_animation[i] = _skeleton.get_bone_pose(part.bone)
			_targets[i] = frame * _skeleton.global_transform * _skeleton.get_bone_global_pose(part.bone) * _inverse_bind[i]
	_sync_model()
	pose_applied.emit()

func _physics_process(dt: float) -> void:
	if not driving:
		super._physics_process(dt)
		return
	if _released or not is_instance_valid(_model) or _model.is_queued_for_deletion():
		queue_free()
		return
	var frame := _model.global_transform
	var hub_goal := frame * _targets[0]
	# A respawn, a network correction or a floating-origin relocation should
	# relocate the whole rig instead of dragging it across the intervening map.
	var teleported := hub_goal.origin.distance_squared_to(_last_world[0].origin) > 2.5 * 2.5
	if teleported: balance.reset()
	else: balance.advance(dt)
	for i in _parts.size():
		var part := _parts[i]
		var body := part.body
		var goal := (frame * _targets[i]).orthonormalized()
		var last := _last_world[i]
		if teleported:
			body.global_transform = goal
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
		else:
			goal = balance.target(i,goal)
			_drive_limb(part,goal,last,dt,balance.frequency_scale(i))
		_last_world[i] = goal
	_sync_model()
	physics_pose_written.emit(dt)
	pose_applied.emit()

func _add_to_budget() -> void:
	if not driving: super._add_to_budget()

func _drive_limb(part: Segment, goal: Transform3D, last: Transform3D, dt: float, frequency_scale: float) -> void:
	var body := part.body
	var root_part := part.parent < 0
	var hz := (52.0 if root_part else 30.0)*frequency_scale
	var target_velocity := ((goal.origin - last.origin) / dt).limit_length(16.0)
	# Backward-Euler spring gains keep the same response at different physics rates.
	var damping := 2.0 * hz
	var gain := 1.0 / (1.0 + damping * dt + hz * hz * dt * dt)
	var acceleration := ((goal.origin - body.global_position) * hz * hz +
		(target_velocity - body.linear_velocity) * (damping + hz * hz * dt)) * gain
	acceleration += Vector3.UP * _gravity * body.gravity_scale
	body.apply_central_impulse(acceleration.limit_length(240.0 if root_part else 120.0) * body.mass * dt)
	var desired := goal.basis
	var omega := body.angular_velocity
	var target_omega := (Muscle.rotation_error(goal.basis,last.basis) / dt).limit_length(20.0)
	var mobility := body.get_inverse_inertia_tensor()
	var parent_body: RigidBody3D
	if not root_part:
		parent_body = _parts[part.parent].body
		var parent_goal := _last_world[part.parent].basis
		desired = parent_body.global_basis.orthonormalized() * parent_goal.transposed() * goal.basis
		var parent_inverse := parent_body.get_inverse_inertia_tensor()
		mobility = Basis(mobility.x + parent_inverse.x,mobility.y + parent_inverse.y,mobility.z + parent_inverse.z)
	var rotation_gap := Muscle.rotation_error(desired,body.global_basis.orthonormalized())
	var angular_change := ((rotation_gap * hz * hz + (target_omega - omega) * damping) * gain * dt).limit_length(6.0)
	if absf(mobility.determinant()) > 0.000001:
		var angular_impulse := mobility.inverse() * angular_change
		body.apply_torque_impulse(angular_impulse)
		if parent_body: parent_body.apply_torque_impulse(-angular_impulse)

func let_go(impact := Vector3.ZERO, at := Vector3.INF, bone: StringName = &"") -> Node3D:
	driving = false
	if balance: balance.stop()
	if is_in_group(GROUP): remove_from_group(GROUP)
	for part in _parts: part.body.can_sleep = true
	if at.is_finite() or not bone.is_empty(): kick_at(impact,at,bone)
	else: kick(impact)
	return self

func resume_driving() -> void:
	if driving or _released: return
	kick(Vector3.ZERO)
	_remove_from_budget()
	driving = true
	if not is_in_group(GROUP): add_to_group(GROUP)
	for i in _parts.size():
		var body := _parts[i].body
		body.can_sleep = false
		body.gravity_scale = 1.0
		body.linear_damp = 0.28
		body.angular_damp = 3.5
		_last_world[i] = body.global_transform
	_submerged = false
	balance.resume()
	restore_targets()

func stop_driving() -> void:
	if _released: return
	if is_in_group(GROUP): remove_from_group(GROUP)
	# Restore the authored pose when the model releases this rig.
	if driving:
		for i in _parts.size(): _parts[i].original = _animation[i]
	release()
