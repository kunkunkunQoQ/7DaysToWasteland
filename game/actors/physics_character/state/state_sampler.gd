extends RefCounted
## Internal adapter. Other game systems consume PhysicsCharacterState through the character.

const State := preload("physics_character_state.gd")
const Rig := preload("../body/physics_rig.gd")
const Config := preload("../config/physics_character_config.gd")

var _fallen := false

func sample(rig: Rig, config: Config, tick_index: int, delta: float) -> State:
	var frame := State.Measurements.new()
	frame.tick_index = tick_index
	frame.step_seconds = delta

	var total_mass := 0.0
	var weighted_position := Vector3.ZERO
	var weighted_velocity := Vector3.ZERO
	var other_segment_supported := false
	for id: StringName in rig.bodies:
		var segment: RigidBody3D = rig.bodies[id]
		var pose := segment.global_transform
		frame.body_poses[id] = pose
		frame.body_angular_velocities[id] = segment.angular_velocity
		frame.body_linear_velocities[id] = segment.linear_velocity
		# The rig defines each segment's mass center in its own local coordinates.
		weighted_position += (pose * segment.center_of_mass) * segment.mass
		weighted_velocity += segment.linear_velocity * segment.mass
		total_mass += segment.mass
		if rig.has_ground_contact(id):
			frame.body_grounded = true
			if id != &"foot_l" and id != &"foot_r":
				other_segment_supported = true
	frame.center_of_mass = weighted_position / total_mass
	frame.linear_velocity = weighted_velocity / total_mass
	frame.total_mass = total_mass
	frame.nonfoot_ground_contact = other_segment_supported
	for id: StringName in rig.bodies:
		var segment: RigidBody3D = rig.bodies[id]
		var arm := frame.body_poses[id] * segment.center_of_mass - frame.center_of_mass
		frame.angular_momentum += arm.cross((frame.body_linear_velocities[id] - frame.linear_velocity) * segment.mass)
		var inverse_inertia := segment.get_inverse_inertia_tensor()
		if inverse_inertia.determinant() > 0.0:
			frame.angular_momentum += inverse_inertia.inverse() * frame.body_angular_velocities[id]
	frame.left_support_load_n = rig.bodies[&"foot_l"].sole_load_n
	frame.right_support_load_n = rig.bodies[&"foot_r"].sole_load_n
	frame.left_sole_touching = rig.bodies[&"foot_l"].sole_touching
	frame.right_sole_touching = rig.bodies[&"foot_r"].sole_touching
	var pelvis: RigidBody3D = rig.bodies[&"pelvis"]
	frame.angular_velocity = pelvis.angular_velocity
	frame.left_sole_position = frame.body_poses[&"foot_l"] * config.sole_offset
	frame.right_sole_position = frame.body_poses[&"foot_r"] * config.sole_offset
	frame.eye_position = frame.body_poses[&"head"] * config.eye_offset

	frame.left_support_points = rig.get_support_contacts(&"foot_l")
	frame.right_support_points = rig.get_support_contacts(&"foot_r")
	frame.left_support_point_loads_n = rig.bodies[&"foot_l"].sole_point_loads_n
	frame.right_support_point_loads_n = rig.bodies[&"foot_r"].sole_point_loads_n
	if not frame.left_support_points.is_empty():
		frame.support_feet |= State.SupportFoot.LEFT
	if not frame.right_support_points.is_empty():
		frame.support_feet |= State.SupportFoot.RIGHT

	var chest_up := frame.body_poses[&"chest"].basis.y.normalized()
	var uprightness := chest_up.dot(Vector3.UP)
	if _fallen:
		if frame.support_feet != State.SupportFoot.NONE and uprightness >= cos(deg_to_rad(config.fallen_exit_angle_degrees)):
			_fallen = false
	elif other_segment_supported and uprightness <= cos(deg_to_rad(config.fallen_enter_angle_degrees)):
		_fallen = true
	frame.fallen = _fallen
	return State.new(frame)
