extends RigidBody3D
## Contact feedback and optional finite rolling resistance during native integration.

const Config = preload("../config/physics_character_config.gd")

var config: Config
var is_foot: bool
var has_ground_contact: bool = false
var sole_contacts := PackedVector3Array()
var sole_load_n := 0.0
var _static_load_n := 0.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	has_ground_contact = false
	sole_load_n = 0.0
	var static_normal_impulse := 0.0
	var on_static_surface := false
	var rolling_enabled := config.rolling_resistance_m > 0.0 or config.low_speed_extra_lever_m > 0.0
	# A sampled frame can retain the previous packed array after this callback.
	if is_foot:
		sole_contacts = PackedVector3Array()
	for index in state.get_contact_count():
		var other := state.get_contact_collider_object(index) as Node
		if other != null and other.get_parent() == get_parent():
			continue
		# In GodotPhysics3D both the reported point and normal use world axes.
		var normal := state.get_contact_local_normal(index)
		if rolling_enabled and other is StaticBody3D and not other is AnimatableBody3D:
			if other.constant_linear_velocity.is_zero_approx() and other.constant_angular_velocity.is_zero_approx():
				on_static_surface = true
				static_normal_impulse += maxf(0.0, state.get_contact_impulse(index).dot(normal))
		if normal.dot(Vector3.UP) < config.min_ground_up_dot:
			continue
		has_ground_contact = true
		if not is_foot or normal.dot(state.transform.basis.y) < config.min_ground_up_dot:
			continue
		var impulse_n := state.get_contact_impulse(index).dot(normal)
		if impulse_n <= 0.0:
			continue
		var point := state.get_contact_local_position(index)
		var foot_point := state.transform.affine_inverse() * point
		if absf(foot_point.y - config.sole_offset.y) <= config.sole_contact_band:
			sole_contacts.append(point)
			sole_load_n += impulse_n * normal.y / state.step
	if config.contact_load_time_s > 0.0:
		if on_static_surface:
			var fraction := 1.0 - exp(-state.step / config.contact_load_time_s)
			_static_load_n = lerpf(_static_load_n, static_normal_impulse / state.step, fraction)
		else:
			_static_load_n = 0.0
		static_normal_impulse = _static_load_n * state.step
	if static_normal_impulse > 0 and state.inverse_inertia_tensor.determinant() > 0:
		# A static contact patch can resist spin/rolling with a finite moment.
		# The impulse never exceeds the measured normal load times the lever
		# arm or the angular momentum needed to stop the current rotation.
		var angular_momentum := state.inverse_inertia_tensor.inverse() * state.angular_velocity
		var lever := config.rolling_resistance_m
		if config.low_speed_extra_lever_m > 0.0:
			var transition := config.rolling_transition_rad_s
			lever += config.low_speed_extra_lever_m * exp(-state.angular_velocity.length_squared() / (transition * transition))
		state.apply_torque_impulse(-angular_momentum.limit_length(static_normal_impulse * lever))
