extends Resource
## Rest dimensions are in metres, masses in kilograms. The rig faces local -Z.

@export_group("Body")
@export_range(0.1, 3.0, 0.05) var mass_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var surface_friction: float = 0.85
@export_range(0.0, 4.0, 0.05) var linear_damping: float = 0.1
@export_range(0.0, 4.0, 0.05) var angular_damping: float = 0.35
@export var continuous_collision_detection: bool = true
@export_flags_3d_physics var body_layer: int = 4
@export_flags_3d_physics var body_mask: int = 1 | 2 | 4 | 8

@export_group("Passive constraint solver")
@export_range(1, 8) var joint_solver_priority: int = 1
@export_range(0.1, 2.0, 0.05) var multi_axis_limit_damping: float = 1.0
## Zero inherits the world's contact bias. This applies only to this rig's shapes.
@export_range(0.0, 1.0, 0.01) var shape_contact_bias: float = 0.0
## Decay rate of relative angular velocity (1/s). Zero reproduces phase 1.
@export_range(0.0, 30.0, 0.1) var passive_joint_drag: float = 0.0
@export_range(1.0, 120.0, 1.0) var passive_drag_torque_limit_nm: float = 24.0
## Finite dry bearing friction, dissipating relative rotation about each joint.
@export_range(0.0, 3.0, 0.05) var dry_joint_friction_nm: float = 0.0
## Reduce the dry torque ceiling on joints narrower than this bearing radius.
## Zero applies the same finite torque ceiling at every joint.
@export_range(0.0, 0.12, 0.001) var bearing_reference_radius_m: float = 0.0
@export var use_multi_axis_hinges: bool = false
@export_range(0.05, 0.8, 0.05) var angular_limit_erp: float = 0.5
## Zero retains the backend's original passive angular limit force.
@export_range(0.0, 300.0, 1.0) var multi_axis_limit_torque_nm: float = 0.0
## Effective contact-patch lever arm for rolling resistance on a static surface.
@export_range(0.0, 0.03, 0.001) var rolling_resistance_m: float = 0.0
## Extra static-contact rolling lever at low angular speed; decays with speed.
@export_range(0.0, 0.03, 0.001) var low_speed_extra_lever_m: float = 0.0
@export_range(0.2, 12.0, 0.1) var rolling_transition_rad_s: float = 2.0
## Time constant of a loaded contact patch (seconds); a lost contact clears the load.
@export_range(0.0, 0.15, 0.005) var contact_load_time_s: float = 0.0
@export var predict_contacts: bool = false
@export var articulated_contact_response: bool = false

@export_group("Contact feedback")
@export_range(4, 32) var contacts_per_body: int = 12
@export_range(0.05, 1.0, 0.01) var min_ground_up_dot: float = 0.64
@export_range(0.001, 0.05, 0.001) var sole_contact_band: float = 0.022
@export var sole_offset: Vector3 = Vector3(0.0, -0.055, 0.0)
@export var eye_offset: Vector3 = Vector3(0.0, 0.045, -0.075)
@export_range(1.0, 89.0) var fallen_enter_angle_degrees: float = 60.0
@export_range(1.0, 89.0) var fallen_exit_angle_degrees: float = 45.0

func build_segments() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		_segment(&"pelvis", &"box", Vector3(0, 0.955, 0), Vector3(0.302, 0.194, 0.185), 10.5),
		_segment(&"spine", &"box", Vector3(0, 1.148, 0), Vector3(0.216, 0.199, 0.164), 5.0),
		_segment(&"chest", &"box", Vector3(0, 1.355, 0), Vector3(0.350, 0.224, 0.199), 13.0),
		_segment(&"head", &"capsule", Vector3(0, 1.608, 0), Vector3(0.19, 0.258, 0.19), 4.5)
	]
	for side in [-1, 1]:
		var suffix := "_l" if side == -1 else "_r"
		rows.append(_segment("upper_arm" + suffix, &"capsule", Vector3(side * 0.226, 1.313, 0), Vector3(0.092, 0.263, 0.092), 2.1))
		rows.append(_segment("lower_arm" + suffix, &"capsule", Vector3(side * 0.226, 1.057, 0), Vector3(0.078, 0.238, 0.078), 1.45))
		rows.append(_segment("hand" + suffix, &"box", Vector3(side * 0.226, 0.868, 0), Vector3(0.069, 0.133, 0.083), 0.65))
		rows.append(_segment("thigh" + suffix, &"capsule", Vector3(side * 0.102, 0.670, 0), Vector3(0.148, 0.380, 0.148), 7.5))
		rows.append(_segment("calf" + suffix, &"capsule", Vector3(side * 0.102, 0.291, 0.008), Vector3(0.114, 0.374, 0.114), 3.6))
		rows.append(_segment("foot" + suffix, &"box", Vector3(side * 0.102, 0.055, -0.052), Vector3(0.137, 0.110, 0.249), 1.25))
	return rows

func _segment(id: StringName, shape: StringName, position: Vector3, size: Vector3, mass_kg: float) -> Dictionary:
	return {"id": id, "shape": shape, "position": position, "size": size, "mass": mass_kg * mass_scale}

func build_joints() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		_multi_axis(&"pelvis", &"spine", Vector3(0, 1.049, 0), 19.0, 14.0),
		_multi_axis(&"spine", &"chest", Vector3(0, 1.246, 0), 23.0, 16.0),
		_multi_axis(&"chest", &"head", Vector3(0, 1.473, 0), 38.0, 50.0)
	]
	for side in [-1, 1]:
		var suffix := "_l" if side == -1 else "_r"
		rows.append(_multi_axis(&"chest", "upper_arm" + suffix, Vector3(side * 0.205, 1.447, 0), 65.0, 60.0))
		rows.append(_hinge("upper_arm" + suffix, "lower_arm" + suffix, Vector3(side * 0.226, 1.178, 0), -136.0, 3.0))
		rows.append(_multi_axis("lower_arm" + suffix, "hand" + suffix, Vector3(side * 0.226, 0.936, 0), 38.0, 30.0))
		rows.append(_multi_axis(&"pelvis", "thigh" + suffix, Vector3(side * 0.102, 0.86, 0), 65.0, 32.0))
		rows.append(_hinge("thigh" + suffix, "calf" + suffix, Vector3(side * 0.102, 0.478, 0.008), -3.0, 132.0))
		rows.append(_multi_axis("calf" + suffix, "foot" + suffix, Vector3(side * 0.102, 0.104, 0.008), 32.0, 18.0))
	return rows

func _multi_axis(parent: StringName, child: StringName, position: Vector3, swing: float, twist: float) -> Dictionary:
	# Use local X for twist, along the limb, and independent Y/Z swing limits.
	return {"kind": &"multi_axis", "parent": parent, "child": child, "position": position,
		"basis": Basis(Vector3.BACK, PI / 2.0), "swing": deg_to_rad(swing), "twist": deg_to_rad(twist)}

func _hinge(parent: StringName, child: StringName, position: Vector3, lower: float, upper: float) -> Dictionary:
	# Hinge's local Z is its free axis. A positive GodotPhysics hinge angle bends the knee back.
	return {"kind": &"hinge", "parent": parent, "child": child, "position": position,
		"basis": Basis(Vector3.UP, PI / 2.0), "lower": deg_to_rad(lower), "upper": deg_to_rad(upper)}
