class_name WastelandActiveRagdoll
extends "res://game/actors/physical_ragdoll.gd"
## Animation supplies joint targets. The fixed-step motors move the colliding
## bodies, and the resulting transforms drive the same skin used when falling.

signal pose_applied

const Muscle := preload("res://game/actors/physics_character/controllers/joint_muscle_controller.gd")
const GROUP := &"active_character_motion"
const NEAR_BUDGET := 12
const VIEW_DISTANCE := 28.0

var driving := true
var _model: Node3D
var _animation: Array[Transform3D] = []
var _targets: Array[Transform3D] = []
var _last_world: Array[Transform3D] = []
var _inverse_bind: Array[Transform3D] = []
var _index_by_bone := {}
var _priority := false
var _yield_slot := false
var _gravity := 18.0

static func wanted(world: Node3D, at: Vector3, existing: Node3D, priority := false) -> bool:
	if priority: return true
	if not is_instance_valid(world) or not world.is_inside_tree(): return false
	var camera := world.get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return false
	var distance := camera.global_position.distance_squared_to(at)
	var keep := is_instance_valid(existing)
	var base_reach := VIEW_DISTANCE + (4.0 if keep else 0.0)
	var reach := base_reach * clampf(76.0 / camera.fov,1.0,2.2)
	var in_view := distance < reach * reach and (distance < 7.0 * 7.0 or camera.is_position_in_frustum(at + Vector3.UP * 0.4))
	var guest_views: Array[Vector3] = []
	if world is WastelandSession and is_instance_valid(world.network) and world.network.server():
		for member: WastelandLan.MemberState in world.network.members.values():
			if member.downed or not is_instance_valid(member.survivor): continue
			var eyes := member.survivor.camera
			guest_views.append(eyes.global_position)
			var gap := eyes.global_position.distance_squared_to(at)
			var guest_reach := base_reach * clampf(76.0 / eyes.fov,1.0,2.2)
			if gap < guest_reach * guest_reach and (gap < 7.0 * 7.0 or eyes.is_position_in_frustum(at + Vector3.UP * 0.4)):
				distance = minf(distance,gap)
				in_view = true
	if not in_view: return false
	if keep: return not existing._yield_slot
	if world.get_tree().get_node_count_in_group(GROUP) < NEAR_BUDGET: return true
	var farthest: Node3D
	var previous := distance + 4.0 * 4.0
	var used := 0
	for rig in world.get_tree().get_nodes_in_group(GROUP):
		if rig.get_world_3d() != world.get_world_3d(): continue
		used += 1
		if rig._priority or rig._yield_slot: continue
		var other := camera.global_position.distance_squared_to(rig.center())
		for eye in guest_views: other = minf(other,eye.distance_squared_to(rig.center()))
		if other > previous:
			previous = other
			farthest = rig
	if used < NEAR_BUDGET: return true
	if farthest != null and used == NEAR_BUDGET:
		farthest._yield_slot = true
		return true
	return false

static func start(owner_node: Node3D, model: Node3D, stream: Node3D, priority := false) -> WastelandActiveRagdoll:
	var rig := WastelandActiveRagdoll.new()
	owner_node.add_child(rig)
	rig._model = model
	rig._priority = priority
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
	return rig

func restore_targets() -> void:
	if not driving or _released: return
	for i in _parts.size():
		var part := _parts[i]
		if part.node != null: part.node.transform = _animation[i]
		else: _skeleton.set_bone_pose(part.bone,_animation[i])

func limb_deviation(bone: StringName) -> Vector3:
	var i: int = _index_by_bone.get(bone,-1)
	if i < 0 or not driving: return Vector3.ZERO
	var frame := _model.global_transform
	var rest_offset := frame.basis * (_targets[i].origin - _targets[0].origin)
	return _parts[i].body.global_position - _parts[0].body.global_position - rest_offset

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
			_drive_limb(part,goal,last,dt)
		_last_world[i] = goal
	_sync_model()
	pose_applied.emit()

func _add_to_budget() -> void:
	if not driving: super._add_to_budget()

func _drive_limb(part: Segment, goal: Transform3D, last: Transform3D, dt: float) -> void:
	var body := part.body
	var root_part := part.parent < 0
	var hz := 52.0 if root_part else 30.0
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
	if is_in_group(GROUP): remove_from_group(GROUP)
	for part in _parts: part.body.can_sleep = true
	if at.is_finite() or not bone.is_empty(): kick_at(impact,at,bone)
	else: kick(impact)
	return self

func stop_driving() -> void:
	if _released: return
	if is_in_group(GROUP): remove_from_group(GROUP)
	# Return the current action target to the animator when changing distance tiers.
	if driving:
		for i in _parts.size(): _parts[i].original = _animation[i]
	release()
