class_name WastelandActiveRagdoll
extends "res://game/actors/physical_ragdoll.gd"
## Animation supplies joint targets. The fixed-step motors move the colliding
## bodies, and the resulting transforms drive the same skin used when falling.

signal pose_applied

const Muscle := preload("res://game/actors/physics_character/controllers/joint_muscle_controller.gd")
const Balance := preload("res://game/actors/active_balance.gd")
const GroundLocomotion := preload("res://game/actors/ground_locomotion.gd")
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
var _creature_stance_ik := false
var _ground: GroundLocomotion
var _paused_motion := PackedVector3Array()

func _exit_tree() -> void:
	if _ground: _ground.airborne()

static func start(owner_node: Node3D, model: Node3D, stream: Node3D, _priority := false) -> WastelandActiveRagdoll:
	var rig := WastelandActiveRagdoll.new()
	owner_node.add_child(rig)
	rig._model = model
	rig._creature_stance_ik = owner_node is WastelandCreature
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
	stop_ground_drive()
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
	stop_ground_drive()
	_skeleton = target
	_model = target
	_face_model = target.get_parent() if target.get_parent().has_method("sync_head") else null
	_sync_model()

func follow_relocation() -> void:
	var offset := (_model.global_transform * _targets[0]).origin - center()
	if offset.length_squared() <= 2.5 * 2.5: return
	if _ground: _ground.airborne()
	for part in _parts:
		part.body.global_position += offset
		part.body.angular_velocity = Vector3.ZERO
		part.body.linear_velocity = Vector3.ZERO

func hand_contact_offset(bone: StringName) -> Vector3:
	var i: int = _index_by_bone.get(bone,-1)
	if i < 0 or not driving or _released: return Vector3.ZERO
	var body := _parts[i].body
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var weight := balance.impact_weight(i)
	if state and state.get_contact_count() > 0: weight = 1.0
	# A free wrist naturally trails the shoulder as the arms swing. Only a
	# contacting or struck limb should displace the separate first-person grip.
	if weight <= 0.0: return Vector3.ZERO
	var frame := _model.global_transform
	var rest_offset := frame.basis * (_targets[i].origin - _targets[0].origin)
	return (body.global_position - center() - rest_offset) * weight

func set_ground_drive(desired: Vector3, planted: Array[StringName], _dt: float, floor_normal := Vector3.UP) -> Vector3:
	if not driving or _released: return Vector3.ZERO
	if _ground == null: _ground = GroundLocomotion.new(self)
	_ground.plan(self, desired, planted, floor_normal)
	return motion().slide(Vector3.UP)

func ground_follow_velocity(dt: float) -> Vector3:
	return airborne_follow_velocity(dt).slide(Vector3.UP)

func limit_blocked_travel(blocked: Vector3) -> void:
	if _ground == null or blocked.length_squared() < 0.000001: return
	var outward := blocked.normalized()
	var anchor := (_model.global_transform * _targets[0]).origin
	var excess := (center() - anchor).dot(outward) - 0.035
	if excess <= 0.0: return
	# The wider capsule hit an obstacle that the pelvis could fit past.
	# Project only the rejected component; leave tangential motion and the pose intact.
	for part in _parts:
		var body := part.body
		body.global_position -= outward * excess
		body.linear_velocity -= outward * maxf(0.0, body.linear_velocity.dot(outward))

func airborne_follow_velocity(dt: float) -> Vector3:
	if _ground == null or dt <= 0.0: return Vector3.ZERO
	var expected := (_model.global_transform * _targets[0]).origin
	var travel := center() - expected
	if travel.length_squared() > 2.5 * 2.5: return Vector3.ZERO
	return travel / dt

func set_airborne_drive() -> void:
	if not driving or _released: return
	if _ground == null: _ground = GroundLocomotion.new(self)
	_ground.airborne()

func landing_normal() -> Vector3:
	if _ground == null: return Vector3.ZERO
	return _ground.landing_normal(self)

func landing_surface_velocity() -> Vector3:
	return _ground.landing_surface_velocity if _ground else Vector3.ZERO

func supports_step(top: Vector3, forward: Vector3) -> bool:
	return _ground != null and _ground.supports_step(_parts[0].body, top, forward)

func try_ground_jump(up_speed: float) -> bool:
	if _ground == null or not _ground.jump(self, up_speed): return false
	stop_ground_drive()
	return true

func stop_ground_drive() -> void:
	if _ground == null: return
	set_locomotion_paused(false)
	_ground.clear()
	_ground = null

func set_locomotion_paused(paused: bool) -> void:
	if _ground == null or paused == (not _paused_motion.is_empty()): return
	if paused:
		for part in _parts:
			_paused_motion.append(part.body.linear_velocity)
			_paused_motion.append(part.body.angular_velocity)
			part.body.freeze = true
	else:
		for i in _parts.size():
			var body := _parts[i].body
			body.freeze = false
			body.linear_velocity = _paused_motion[2 * i]
			body.angular_velocity = _paused_motion[2 * i + 1]
		_paused_motion.clear()

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
	if not _paused_motion.is_empty(): return
	var frame := _model.global_transform
	var hub_goal := frame * _targets[0]
	var hub_step := hub_goal.origin - _last_world[0].origin
	var pose_offset := center() - hub_goal.origin if _ground else Vector3.ZERO
	var velocity_offset := motion() - hub_step / dt if _ground else Vector3.ZERO
	if _ground and _ground.on_ground:
		# Keep the standing height and foot targets relative to the floor. Following
		# a sinking pelvis vertically pulls the legs up and prevents their next contact.
		pose_offset.y = 0.0
		velocity_offset.y = 0.0
	# A respawn, a network correction or a floating-origin relocation should
	# relocate the whole rig instead of dragging it across the intervening map.
	var teleported := hub_goal.origin.distance_squared_to(_last_world[0].origin) > 2.5 * 2.5
	if teleported:
		balance.reset()
		if _ground: _ground.airborne()
	else:
		balance.advance(dt)
		if _ground: _ground.push(self, hub_goal.origin, _gravity, dt)
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
			_drive_limb(part,goal,last,dt,balance.frequency_scale(i),pose_offset,velocity_offset)
		_last_world[i] = goal
	_sync_model()
	physics_pose_written.emit(dt)
	pose_applied.emit()

func _add_to_budget() -> void:
	if not driving: super._add_to_budget()

func _drive_limb(part: Segment, goal: Transform3D, last: Transform3D, dt: float, frequency_scale: float,
		pose_offset: Vector3, velocity_offset: Vector3) -> void:
	var body := part.body
	var root_part := part.parent < 0
	var standing: bool = _ground != null and _ground.on_ground
	var world_foot := standing and ((_avatar != null and _avatar.ankle_joints.has(part.node))
		or (_creature_stance_ik and _ground.is_planned_stance(body)))
	var hz := (52.0 if root_part or world_foot else 30.0)*frequency_scale
	var error := goal.origin - body.global_position
	var target_velocity := (goal.origin - last.origin) / dt
	# Stance IK already supplies a world-space sole or paw target. Adding the
	# pelvis correction again carries that contact along with the body.
	if not world_foot:
		error += pose_offset
		target_velocity += velocity_offset
	var sole: bool = standing and _ground.is_stance(body)
	if sole: error.y -= minf(0.032, part.extents.y * 0.42)
	var parent_body: RigidBody3D
	if not root_part: parent_body = _parts[part.parent].body
	# Backward-Euler spring gains keep the same response at different physics rates.
	var damping := 2.0 * hz
	var gain := 1.0 / (1.0 + damping * dt + hz * hz * dt * dt)
	var acceleration := (error * hz * hz +
		(target_velocity.limit_length(16.0) - body.linear_velocity) * (damping + hz * hz * dt)) * gain
	if _ground == null:
		acceleration += Vector3.UP * _gravity * body.gravity_scale
		body.apply_central_impulse(acceleration.limit_length(240.0 if root_part else 120.0) * body.mass * dt)
	else:
		if standing:
			# Stance servos hold the torso upright and load the soles. Horizontal
			# travel still requires a measured ground reaction at a foot.
			var lift := acceleration.y + (0.0 if sole else _gravity * body.gravity_scale)
			body.apply_central_impulse(Vector3.UP * clampf(lift,-100.0,140.0) * body.mass * dt)
			acceleration.y = 0.0
		if parent_body:
			var internal := acceleration.limit_length(95.0) * body.mass * dt
			body.apply_central_impulse(internal)
			parent_body.apply_central_impulse(-internal)
	var desired := goal.basis
	var omega := body.angular_velocity
	var target_omega := (Muscle.rotation_error(goal.basis,last.basis) / dt).limit_length(20.0)
	var mobility := body.get_inverse_inertia_tensor()
	var aim_weight := 0.0
	if _avatar != null and part.node == _avatar.wrist_joints[1]:
		aim_weight = _avatar.aim_stability * smoothstep(0.60,1.0,frequency_scale)
	if parent_body:
		if not world_foot:
			var parent_goal := _last_world[part.parent].basis
			desired = parent_body.global_basis.orthonormalized() * parent_goal.transposed() * goal.basis
			if aim_weight>0.0:
				# Aiming counters the forearm's roll while the physical joint still reacts to obstructions.
				desired = desired.slerp(goal.basis,aim_weight)
		var parent_inverse := parent_body.get_inverse_inertia_tensor()
		var relative_weight := 1.0-aim_weight
		mobility = Basis(mobility.x + parent_inverse.x*relative_weight,mobility.y + parent_inverse.y*relative_weight,mobility.z + parent_inverse.z*relative_weight)
	var rotation_gap := Muscle.rotation_error(desired,body.global_basis.orthonormalized())
	if aim_weight>0.0:
		hz = lerpf(hz,84.0*frequency_scale,aim_weight)
		damping = 2.0*hz
		gain = 1.0/(1.0+damping*dt+hz*hz*dt*dt)
	var angular_change := ((rotation_gap * hz * hz + (target_omega - omega) * damping) * gain * dt).limit_length(6.0)
	if absf(mobility.determinant()) > 0.000001 and (parent_body or _ground == null or standing):
		var angular_impulse := mobility.inverse() * angular_change
		if root_part and _ground:
			_ground.balance_torque(body, angular_impulse)
		else:
			body.apply_torque_impulse(angular_impulse)
			if parent_body: parent_body.apply_torque_impulse(-angular_impulse)

func let_go(impact := Vector3.ZERO, at := Vector3.INF, bone: StringName = &"") -> Node3D:
	stop_ground_drive()
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
	stop_ground_drive()
	if is_in_group(GROUP): remove_from_group(GROUP)
	# Restore the authored pose when the model releases this rig.
	if driving:
		for i in _parts.size(): _parts[i].original = _animation[i]
	release()
