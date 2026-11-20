extends RefCounted
## Double-support stance using bounded pressure placement, gravity compensation
## and a torso attitude moment. Outputs are relative body orientations and
## internal moments on each child; the actuator applies the opposite to its parent.

const State := preload("../state/physics_character_state.gd")
const Config := preload("../config/physics_character_config.gd")

var relative_targets: Dictionary = {}
var feedforward_world_nm: Dictionary = {}
var pressure_target := Vector3.ZERO
var desired_acceleration := Vector3.ZERO
var _mass := 0.0
var _gravity := 18.0
var _rows: Array[Dictionary] = []
var _segments: Array[Dictionary] = []
var _pivot_from_parent := {}
var _neutral_com_offset := Vector3.ZERO
var _foot_half := Vector3.ZERO
var _masses := {}
var _parent := {}
var _rest := {}

func setup(config: Config) -> void:
	_rows = config.build_joints()
	_segments = config.build_segments()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_mass = 0.0
	_neutral_com_offset = Vector3.ZERO
	for row in _segments:
		_rest[row.id] = row.position
		_masses[row.id] = row.mass
		_mass += float(row.mass)
		_neutral_com_offset += Vector3(row.position) * float(row.mass)
		if row.id == &"foot_l":
			_foot_half = Vector3(row.size) * 0.5
	_neutral_com_offset /= _mass
	_neutral_com_offset -= (Vector3(_rest[&"foot_l"]) + Vector3(_rest[&"foot_r"])) * 0.5 + config.sole_offset
	_neutral_com_offset.y = 0.0
	for joint in _rows:
		_pivot_from_parent[joint.child] = Vector3(joint.position) - Vector3(_rest[joint.parent])
		_parent[joint.child] = joint.parent
		relative_targets[joint.child] = Basis.IDENTITY
		feedforward_world_nm[joint.child] = Vector3.ZERO

func plan(state: State, facing: Vector3, _delta: float) -> void:
	var forward := facing.slide(Vector3.UP).normalized()
	if forward.length_squared() < 0.5:
		forward = -state.body_poses[&"pelvis"].basis.z.slide(Vector3.UP).normalized()
	var lateral := forward.cross(Vector3.UP)
	var heading := Basis(lateral, Vector3.UP, -forward)
	var left := state.left_sole_position
	var right := state.right_sole_position
	var center := (left + right) * 0.5
	var displacement := (state.center_of_mass - center - heading * _neutral_com_offset).slide(Vector3.UP)
	var velocity := state.linear_velocity.slide(Vector3.UP)
	desired_acceleration = (-5.0 * displacement - 4.0 * velocity).limit_length(3.0)
	var height := maxf(0.25, state.center_of_mass.y - center.y)
	pressure_target = state.center_of_mass - desired_acceleration * height / _gravity
	pressure_target -= Vector3.UP.cross(state.angular_momentum) * (1.5 / (_mass * _gravity))
	pressure_target.y = center.y
	var weight_left := 0.0
	if state.support_feet == State.SupportFoot.BOTH:
		var separation := maxf(0.04, (right - left).dot(lateral))
		weight_left = clampf((right - pressure_target).dot(lateral) / separation, 0.0, 1.0)
	elif state.support_feet == State.SupportFoot.LEFT:
		weight_left = 1.0
	var weight_right := 1.0 - weight_left if state.grounded else 0.0
	var load := (Vector3.UP * _gravity + desired_acceleration) * _mass
	var contact_center := left * weight_left + right * weight_right
	var trim := pressure_target - contact_center
	var support_offset := lateral * clampf(trim.dot(lateral), -0.7 * _foot_half.x, 0.7 * _foot_half.x)
	support_offset += forward * clampf(trim.dot(forward), -0.85 * _foot_half.z, 0.85 * _foot_half.z)
	var foot_forces := {&"foot_l": load * weight_left, &"foot_r": load * weight_right}
	var points := {&"foot_l": left + support_offset, &"foot_r": right + support_offset}
	var moments := {}
	var forces := {}
	# Accumulate spatial moments about the COM to avoid cancellation far from
	# the world origin. Traverse the tree leaves-first to build inverse dynamics.
	for row in _segments:
		var position: Vector3 = state.body_poses[row.id].origin
		var force := Vector3.DOWN * (_gravity * float(row.mass))
		var moment := (position - state.center_of_mass).cross(force)
		if foot_forces.has(row.id):
			var contact_force: Vector3 = foot_forces[row.id]
			moment += (Vector3(points[row.id]) - state.center_of_mass).cross(contact_force)
			force += contact_force
		moments[row.id] = moment
		forces[row.id] = force
	for index in range(_rows.size() - 1, -1, -1):
		var joint := _rows[index]
		var pivot: Vector3 = state.body_poses[joint.parent] * Vector3(_pivot_from_parent[joint.child])
		var wrench := Vector3(moments[joint.child]) - (pivot - state.center_of_mass).cross(Vector3(forces[joint.child]))
		feedforward_world_nm[joint.child] = -wrench if state.grounded else Vector3.ZERO
		moments[joint.parent] += moments[joint.child]
		forces[joint.parent] += forces[joint.child]
	var chest: Basis = state.body_poses[&"chest"].basis
	var torso_moment := chest.y.cross(Vector3.UP) * 150.0 - Vector3(state.body_angular_velocities[&"chest"]).slide(Vector3.UP) * 20.0
	feedforward_world_nm[&"thigh_l"] -= torso_moment * weight_left
	feedforward_world_nm[&"thigh_r"] -= torso_moment * weight_right
	# Mild flexion keeps both knees away from their extension stop. Changes in
	# vertical velocity provide compliance during small bumps.
	var flex := clampf(0.045 - state.linear_velocity.y * 0.025, 0.018, 0.11)
	for side in ["_l", "_r"]:
		relative_targets["thigh"+side] = Basis(Vector3.RIGHT, flex)
		relative_targets["calf"+side] = Basis(Vector3.RIGHT, -2.0 * flex)
		relative_targets["foot"+side] = Basis(Vector3.RIGHT, flex)
