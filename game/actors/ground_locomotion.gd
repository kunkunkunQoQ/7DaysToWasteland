extends RefCounted
## A supporting sole transmits a tangential reaction to the articulated body.
## Movable ground receives the opposite impulse at the measured contact point.

const GroundTraction := preload("res://game/world/ground_traction.gd")

class Foot:
	var body: RigidBody3D
	var original_contacts: int
	var native_friction: float
	var sole_friction: float
	var normal: Vector3
	var point: Vector3
	var surface_velocity: Vector3
	var surface: PhysicsBody3D
	var load_weight: float
	var wants_grip := false
	var grip: RID
	var grip_surface: PhysicsBody3D
	var sole_anchor := Vector3.ZERO
	var sampled_surface: PhysicsBody3D
	var sample_at := Vector3.INF
	var traction := 1.0
	var grip_traction := -1.0
	var motor_force := -1.0

	func set_friction(friction: float) -> void:
		if is_equal_approx(friction, sole_friction): return
		PhysicsServer3D.body_set_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION, friction)
		sole_friction = friction

	func release_grip() -> void:
		if grip.is_valid():
			PhysicsServer3D.free_rid(grip)
			grip = RID()
		grip_surface = null
		grip_traction = -1.0
		motor_force = -1.0

var desired := Vector3.ZERO
var on_ground := false
var floor_normal := Vector3.UP
var landing_surface_velocity := Vector3.ZERO
var _landing_feet := 0
var _feet := {}
var _stance: Array[Foot] = []
var _loaded: Array[Foot] = []
var _mass := 0.0
var _gravity := 18.0

func _init(rig: Node3D) -> void:
	_gravity = rig._gravity
	for part in rig._parts: _mass += part.body.mass
	for index: int in rig.balance._feet:
		if index >= 0: _track_foot(rig._parts[index].body)

func _track_foot(body: RigidBody3D) -> Foot:
	var foot: Foot = _feet.get(body)
	if foot == null:
		foot = Foot.new()
		foot.body = body
		foot.original_contacts = body.max_contacts_reported
		foot.native_friction = PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION)
		foot.sole_friction = foot.native_friction
		body.max_contacts_reported = maxi(4, body.max_contacts_reported)
		_feet[body] = foot
	return foot

func plan(rig: Node3D, request: Vector3, planted: Array[StringName], normal: Vector3) -> void:
	on_ground = true
	desired = request.slide(Vector3.UP)
	floor_normal = normal.normalized() if normal.y > 0.0 else Vector3.UP
	_stance.clear()
	for bone in planted:
		var body: RigidBody3D = rig.body_for(bone)
		if body == null: continue
		var foot := _track_foot(body)
		if not _stance.has(foot): _stance.append(foot)
	var striding := desired.length_squared() > 0.04
	for foot: Foot in _feet.values():
		foot.wants_grip = striding and _stance.has(foot)
		if not foot.wants_grip: foot.release_grip()

func clear() -> void:
	airborne()
	for foot: Foot in _feet.values():
		foot.body.max_contacts_reported = foot.original_contacts
	_feet.clear()

func airborne() -> void:
	on_ground = false
	desired = Vector3.ZERO
	_stance.clear()
	_loaded.clear()
	for foot: Foot in _feet.values():
		foot.release_grip()
		if is_instance_valid(foot.body): foot.set_friction(foot.native_friction)

func landing_normal(rig: Node3D) -> Vector3:
	# A sole can touch the ground before the follower capsule does.
	var normal := Vector3.ZERO
	landing_surface_velocity = Vector3.ZERO
	_landing_feet = 0
	for foot: Foot in _feet.values():
		normal += _floor_contact(foot.body)
	if _landing_feet == 0: return Vector3.ZERO
	landing_surface_velocity /= float(_landing_feet)
	var relative: Vector3 = rig.motion() - landing_surface_velocity
	if relative.dot(normal.normalized()) > 0.45: return Vector3.ZERO
	return normal.normalized()

func _floor_contact(body: RigidBody3D) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var contact := _support_contact(state, Vector3.UP)
	if contact < 0: return Vector3.ZERO
	_landing_feet += 1
	landing_surface_velocity += state.get_contact_collider_velocity_at_position(contact)
	return state.get_contact_local_normal(contact)

func _support_contact(state: PhysicsDirectBodyState3D, reference: Vector3, prefer_load := false) -> int:
	if state == null: return -1
	var best := 0.0
	var best_load := -1.0
	var contact := -1
	for i in state.get_contact_count():
		var normal := state.get_contact_local_normal(i)
		var score := normal.dot(reference)
		if normal.y < 0.48 or score <= 0.0: continue
		var load := state.get_contact_impulse(i).dot(normal) if prefer_load else 0.0
		# Among equally walkable patches, anchor where the shoe actually carries the weight.
		if score < best - 0.015 or (score <= best + 0.015 and load <= best_load): continue
		var other := state.get_contact_collider_object(i) as PhysicsBody3D
		if other and (other.collision_layer & (1 | 2 | 8)) != 0:
			var relative := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
			if relative.dot(normal) > 0.45: continue
			best = score
			best_load = load
			contact = i
	return contact

func _contacts(hip: RigidBody3D) -> void:
	_loaded.clear()
	if not on_ground: return
	var weight_sum := 0.0
	for foot in _stance:
		weight_sum += _load_foot(foot, hip)
	if _loaded.is_empty():
		# At handoff the trailing foot can still carry the body while the
		# planned leading foot has yet to reach the ground.
		for foot: Foot in _feet.values():
			if not _stance.has(foot): weight_sum += _load_foot(foot, hip)
	for foot in _loaded:
		foot.load_weight /= weight_sum
		if foot.wants_grip: _update_grip(foot)
	for foot: Foot in _feet.values():
		if not _loaded.has(foot): foot.set_friction(foot.native_friction)

func _load_foot(foot: Foot, hip: RigidBody3D) -> float:
	var state := PhysicsServer3D.body_get_direct_state(foot.body.get_rid())
	var contact := _support_contact(state, floor_normal, foot.wants_grip)
	if contact < 0:
		if foot.grip.is_valid(): foot.release_grip()
		foot.sampled_surface = null
		return 0.0
	foot.normal = state.get_contact_local_normal(contact)
	foot.surface_velocity = state.get_contact_collider_velocity_at_position(contact)
	foot.surface = state.get_contact_collider_object(contact) as PhysicsBody3D
	foot.point = state.get_contact_local_position(contact)
	# A chunk can contain both snow and exposed rock on a single collision mesh.
	var ground_point := state.get_contact_collider_position(contact)
	if foot.sampled_surface != foot.surface or ground_point.distance_squared_to(foot.sample_at) > 0.12 * 0.12:
		foot.traction = GroundTraction.coefficient(foot.surface, ground_point, foot.normal)
		foot.sample_at = ground_point
		foot.sampled_surface = foot.surface
	# A single terrain collider has one native material. Give each loaded sole
	# the friction at its own contact, without changing the chunk or other actors.
	foot.set_friction(foot.native_friction * foot.traction)
	var reach := maxf(0.12, absf(hip.global_position.y - foot.point.y))
	var horizontal := (hip.global_position - foot.point).slide(Vector3.UP)
	foot.load_weight = 1.0 / (1.0 + horizontal.length_squared() / (reach * reach))
	# Load the trailing leg to accelerate and the forward leg to brake.
	var stride := desired - (hip.linear_velocity - foot.surface_velocity).slide(Vector3.UP)
	foot.load_weight *= 1.0 + clampf(horizontal.dot(stride) / (reach * 6.0), -0.35, 0.35)
	_loaded.append(foot)
	return foot.load_weight

func _update_grip(foot: Foot) -> void:
	# A firm heel hands support to the toe as it rolls clear. On yielding ground
	# keep the same patch so rolling the foot cannot reset its available slip.
	var lifted := foot.grip.is_valid() and foot.traction >= GroundTraction.SAND and (foot.body.to_global(foot.sole_anchor) - foot.point).dot(foot.normal) > 0.015
	if foot.grip_surface != foot.surface or lifted:
		_set_grip(foot)
	if not foot.grip.is_valid(): return
	if not is_equal_approx(foot.grip_traction, foot.traction):
		# Firm soles hold their touchdown point. A loose surface can shear under the shoe
		# before it finds purchase. Zero friction leaves both tangents unrestricted.
		var slip := 0.045 * pow(1.0 - foot.traction, 2.0) / maxf(foot.traction, 0.01)
		for axis in [Vector3.AXIS_X, Vector3.AXIS_Z]:
			PhysicsServer3D.generic_6dof_joint_set_flag(foot.grip, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT, foot.traction > 0.0)
			PhysicsServer3D.generic_6dof_joint_set_param(foot.grip, axis, PhysicsServer3D.G6DOF_JOINT_LINEAR_LOWER_LIMIT, -slip)
			PhysicsServer3D.generic_6dof_joint_set_param(foot.grip, axis, PhysicsServer3D.G6DOF_JOINT_LINEAR_UPPER_LIMIT, slip)
			PhysicsServer3D.generic_6dof_joint_set_flag(foot.grip, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_MOTOR, foot.traction > 0.0 and foot.traction < 1.0)
		foot.grip_traction = foot.traction
	if foot.traction <= 0.0 or foot.traction >= 1.0: return
	# A low-friction surface can only arrest so much shear under this foot's share of the weight.
	var max_force := foot.traction * _mass * _gravity * foot.load_weight * maxf(0.0, foot.normal.y)
	if is_equal_approx(max_force, foot.motor_force): return
	foot.motor_force = max_force
	for axis in [Vector3.AXIS_X, Vector3.AXIS_Z]:
		PhysicsServer3D.generic_6dof_joint_set_param(foot.grip, axis, PhysicsServer3D.G6DOF_JOINT_LINEAR_MOTOR_FORCE_LIMIT, max_force)

func _set_grip(foot: Foot) -> void:
	foot.release_grip()
	foot.grip_surface = foot.surface
	var belt := foot.surface as StaticBody3D
	if belt and (not belt.constant_linear_velocity.is_zero_approx() or not belt.constant_angular_velocity.is_zero_approx()):
		# A conveyor's material moves relative to its collision body.
		return
	foot.grip = PhysicsServer3D.joint_create()
	# Hold the material point where this shoe actually struck. The surface
	# supplies the tangent frame, so heel roll and separation remain free.
	var plane := Transform3D(Basis(Quaternion(Vector3.UP, foot.normal)), foot.point)
	var surface_local := foot.surface.global_transform.orthonormalized().affine_inverse() * plane
	var sole_local := foot.body.global_transform.orthonormalized().affine_inverse() * plane
	foot.sole_anchor = sole_local.origin
	PhysicsServer3D.joint_make_generic_6dof(foot.grip, foot.surface.get_rid(), surface_local, foot.body.get_rid(), sole_local)
	PhysicsServer3D.joint_disable_collisions_between_bodies(foot.grip, false)
	for axis in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		PhysicsServer3D.generic_6dof_joint_set_flag(foot.grip, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_ANGULAR_LIMIT, false)
	PhysicsServer3D.generic_6dof_joint_set_flag(foot.grip, Vector3.AXIS_Y, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT, false)

func is_planned_stance(body: RigidBody3D) -> bool:
	var foot: Foot = _feet.get(body)
	return on_ground and foot != null and _stance.has(foot)

func is_stance(body: RigidBody3D) -> bool:
	var foot: Foot = _feet.get(body)
	return on_ground and foot != null and (_stance.has(foot) or _loaded.has(foot))

func push(rig: Node3D, hip_goal: Vector3, gravity: float, dt: float) -> void:
	var hip: RigidBody3D = rig._parts[0].body
	_contacts(hip)
	if _loaded.is_empty(): return
	var surface_velocity := Vector3.ZERO
	var normal := Vector3.ZERO
	var traction := 0.0
	for foot in _loaded:
		surface_velocity += foot.surface_velocity * foot.load_weight
		normal += foot.normal * foot.load_weight
		traction += foot.traction * foot.load_weight
	normal = normal.normalized()
	var relative := hip.linear_velocity - surface_velocity
	var goal := desired
	# When the wider collision capsule has stopped at a wall, brake further
	# travel into it. Backing away and motion along the wall remain available.
	var separation := (hip.global_position - hip_goal).slide(Vector3.UP)
	if separation.length_squared() > 0.16 * 0.16:
		var outward := separation.normalized()
		goal -= outward * maxf(goal.dot(outward), 0.0)
	var along := goal.slide(normal).normalized() * goal.length()
	var tangent := ((along - relative.slide(normal)) * 7.0).limit_length(gravity * 0.95)
	var height_error := (hip_goal.y - hip.global_position.y) * normal.y
	var extension := clampf(gravity * normal.y + 88.0 * height_error - 14.0 * relative.dot(normal), 0.0, gravity * 2.8)
	# On an incline some traction carries the body's weight along the slope.
	tangent += (Vector3.UP * gravity).slide(normal)
	tangent = tangent.limit_length(extension * traction)
	# Distribute the stance impulse along the joint chain by mass. Applying the
	# entire body's impulse to a light ankle in one tick can buckle both knees.
	var velocity_change := tangent * dt
	for part in rig._parts:
		part.body.apply_central_impulse(velocity_change * part.body.mass)
	for foot in _loaded:
		var platform := foot.surface as RigidBody3D
		if platform and not platform.freeze:
			platform.apply_impulse(-velocity_change * _mass * foot.load_weight, foot.point - platform.global_position)

func balance_torque(hip: RigidBody3D, impulse: Vector3) -> void:
	if _loaded.is_empty(): return
	hip.apply_torque_impulse(impulse)
	# The ground takes the reaction. Applying the trunk's full opposing torque
	# to tiny paws twists them out of their joints during a support change.
	for foot in _loaded:
		var platform := foot.surface as RigidBody3D
		if platform and not platform.freeze:
			platform.apply_torque_impulse(-impulse * foot.load_weight)

func supports_step(hip: RigidBody3D, top: Vector3, forward: Vector3) -> bool:
	_contacts(hip)
	for foot in _loaded:
		if absf(foot.point.y - top.y) < 0.075 and (foot.point - top).dot(forward) >= -0.08:
			return true
	return false

func jump(rig: Node3D, up_speed: float) -> bool:
	var hip: RigidBody3D = rig._parts[0].body
	_contacts(hip)
	if _loaded.is_empty(): return false
	var support_y := 0.0
	for foot in _loaded: support_y += foot.surface_velocity.y * foot.load_weight
	var launch := Vector3.UP * maxf(0.0, up_speed + support_y - hip.linear_velocity.y)
	# The short takeoff impulse acts on the whole joint chain; a movable support
	# receives the opposite impulse at the actual point of contact.
	for part in rig._parts: part.body.linear_velocity += launch
	for foot in _loaded:
		var platform := foot.surface as RigidBody3D
		if platform and not platform.freeze:
			platform.apply_impulse(-launch * _mass * foot.load_weight, foot.point - platform.global_position)
	return true
