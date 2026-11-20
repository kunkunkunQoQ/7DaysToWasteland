extends RefCounted
## Independent readback of the floor manifold. Does not submit forces.

var _bodies: Array[RigidBody3D] = []
var _floor: StaticBody3D
var _config: Resource
var _mass: float
var _start_com_vy := 0.0
var _last_com_vy := 0.0
var _frames := 0
var _all_impulse_y := 0.0
var _nonfoot_impulse_y := 0.0
var _sole_impulse := Vector2.ZERO
var _speed_sq_weighted := Vector2.ZERO
var _cached_speed_sq := Vector2.ZERO
var _sampled_speed_sq := Vector2.ZERO
var _slip_path := Vector2.ZERO
var _contact_count := 0
var _max_contacts_at_cap := 0

func setup(rig: Node, floor_body: StaticBody3D, config: Resource, mass: float) -> void:
	_floor = floor_body
	_config = config
	_mass = mass
	for body: RigidBody3D in rig.bodies.values():
		_bodies.append(body)

func sample(state, previous_poses: Dictionary, previous_com_vy: float) -> Vector2:
	if _frames == 0:
		_start_com_vy = previous_com_vy
	_last_com_vy = state.linear_velocity.y
	_frames += 1
	var impulse := Vector2.ZERO
	var slip_weighted := Vector2.ZERO
	var at_cap := 0
	for body in _bodies:
		var native := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if native == null:
			continue
		var count := native.get_contact_count()
		at_cap += int(count == body.max_contacts_reported)
		for i in count:
			if native.get_contact_collider_object(i) != _floor:
				continue
			var applied := native.get_contact_impulse(i)
			_all_impulse_y += applied.y
			var foot_index := 0 if body.name == &"foot_l" else 1
			if body.name not in [&"foot_l", &"foot_r"]:
				_nonfoot_impulse_y += applied.y
				continue
			var n := native.get_contact_local_normal(i)
			var vertical := applied.dot(n) * n.y
			if vertical <= 0.0 or n.y < _config.min_ground_up_dot or n.dot(native.transform.basis.y) < _config.min_ground_up_dot:
				continue
			var p := native.transform.affine_inverse() * native.get_contact_local_position(i)
			if absf(p.y - _config.sole_offset.y) > _config.sole_contact_band:
				continue
			# Native GodotPhysics reports the point at the previous pose and
			# caches contact velocities before solving that physical step.
			var old_pose: Transform3D = previous_poses[body.name]
			var new_pose: Transform3D = state.body_poses[body.name]
			var witness := native.get_contact_local_position(i)
			var new_witness := new_pose * (old_pose.affine_inverse() * witness)
			var speed := ((new_witness - witness) / float(state.step_seconds)).slide(n).length()
			var cached := native.get_contact_local_velocity_at_position(i) - native.get_contact_collider_velocity_at_position(i)
			var omega: Vector3 = state.body_angular_velocities[body.name]
			var sampled: Vector3 = state.body_linear_velocities[body.name] + omega.cross(new_witness - new_pose * body.center_of_mass)
			impulse[foot_index] += vertical
			slip_weighted[foot_index] += vertical * speed
			_speed_sq_weighted[foot_index] += vertical * speed * speed
			_cached_speed_sq[foot_index] += vertical * cached.slide(n).length_squared()
			_sampled_speed_sq[foot_index] += vertical * sampled.slide(n).length_squared()
			_contact_count += 1
	_max_contacts_at_cap = maxi(_max_contacts_at_cap, at_cap)
	_sole_impulse += impulse
	var speeds := Vector2.ZERO
	for index in 2:
		if impulse[index] > 0.0:
			speeds[index] = slip_weighted[index] / impulse[index]
	_slip_path += speeds * float(state.step_seconds)
	return speeds

func summary(weight_impulse: float) -> Dictionary:
	return {"native_sole_impulse_over_weight_impulse":(_sole_impulse.x + _sole_impulse.y)/weight_impulse,
		"native_all_floor_impulse_over_weight_impulse":_all_impulse_y/weight_impulse,
		"native_nonfoot_floor_impulse_over_weight_impulse":_nonfoot_impulse_y/weight_impulse,
		"vertical_momentum_residual_over_weight_impulse":(_all_impulse_y - weight_impulse - _mass * (_last_com_vy - _start_com_vy))/weight_impulse,
		"left_loaded_contact_speed_rms_m_s":sqrt(_speed_sq_weighted.x / _sole_impulse.x) if _sole_impulse.x > 0 else -1.0,
		"right_loaded_contact_speed_rms_m_s":sqrt(_speed_sq_weighted.y / _sole_impulse.y) if _sole_impulse.y > 0 else -1.0,
		"left_cached_pre_solve_contact_speed_rms_m_s":sqrt(_cached_speed_sq.x / _sole_impulse.x) if _sole_impulse.x > 0 else -1.0,
		"right_cached_pre_solve_contact_speed_rms_m_s":sqrt(_cached_speed_sq.y / _sole_impulse.y) if _sole_impulse.y > 0 else -1.0,
		"left_sampled_contact_speed_rms_m_s":sqrt(_sampled_speed_sq.x / _sole_impulse.x) if _sole_impulse.x > 0 else -1.0,
		"right_sampled_contact_speed_rms_m_s":sqrt(_sampled_speed_sq.y / _sole_impulse.y) if _sole_impulse.y > 0 else -1.0,
		"left_loaded_contact_travel_m":_slip_path.x, "right_loaded_contact_travel_m":_slip_path.y,
		"loaded_contact_samples":_contact_count, "max_bodies_at_contact_report_limit":_max_contacts_at_cap}
