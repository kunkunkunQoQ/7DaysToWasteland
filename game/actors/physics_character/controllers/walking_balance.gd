extends "standing_controller.gd"
## The pressure target and reaction forces are inverse dynamics requests.
## The muscle layer applies only equal-and-opposite internal joint torques.

const LegIK := preload("leg_ik.gd")
const SIDES: Array[StringName] = [&"left", &"right"]

const KNEE_MOMENT_BUDGET_NM := 175.0
const LOADED_KNEE_ANGLE := -0.6981317007977318 # 40 degrees of knee flexion

var _legs := LegIK.new()
var _previous_goal := {}
var _contact_time := {&"left": 1.0, &"right": 1.0}
var _last_support: StringName = &""
var _swing_blend := 0.0

func setup(config: Config) -> void:
	super.setup(config)
	_legs.setup(config)
	_previous_goal.clear()
	_contact_time = {&"left": 1.0, &"right": 1.0}
	_last_support = &""
	_swing_blend = 0.0

## Bound a requested pressure point to the box containing the actual contact
## samples. A thin patch allows a little rolling around a newly touching pad.
func _contact_offset(sole: Vector3, points: PackedVector3Array, offset: Vector3, heading: Basis) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for point in points:
		var displacement := point - sole
		var planar := Vector2(displacement.dot(heading.x), displacement.dot(heading.z))
		lo = lo.min(planar)
		hi = hi.max(planar)
	var pad := Vector2.ONE * 0.006
	var projection := Vector2(offset.dot(heading.x), offset.dot(heading.z)).clamp(lo - pad, hi + pad)
	return heading.x * projection.x + heading.z * projection.y

func _foot_offset(trim: Vector3, heading: Basis) -> Vector3:
	return heading.x * clampf(trim.dot(heading.x), -0.7 * _foot_half.x, 0.7 * _foot_half.x) + heading.z * clampf(trim.dot(heading.z), -0.85 * _foot_half.z, 0.85 * _foot_half.z)

## A loaded ankle can move pressure gradually between pads. With only a
## lightly touching toe the same requested moment can rotate the free foot.
func _ankle_request(request: Vector3, state: State, side: StringName, foot: StringName, pivot: Vector3, points: PackedVector3Array, reaction: Vector3, share: float) -> Vector3:
	var loads := state.left_support_point_loads_n if side == &"left" else state.right_support_point_loads_n
	var total := state.left_support_load_n if side == &"left" else state.right_support_load_n
	if points.is_empty() or loads.size() != points.size() or share <= 0.0 or total <= 0.1:
		return request
	var measured_lever := Vector3.ZERO
	for index in points.size():
		measured_lever += (points[index] - pivot) * loads[index]
	measured_lever /= total
	var gravity_moment := (state.body_poses[foot].origin - pivot).cross(Vector3.UP * _gravity * float(_masses[foot]))
	var neutral := gravity_moment - measured_lever.cross(reaction * share)
	var budget := 0.8 + 0.008 * maxf(0.0, reaction.y * share)
	var bounded := neutral + (request - neutral).limit_length(budget)
	return request.lerp(bounded, 0.45 * smoothstep(0.38, 0.78, share))

func plan_step(state: State, facing: Vector3, delta: float, command: Dictionary) -> void:
	var heading: Basis = command.heading
	var target: Vector3 = command.com_target
	var velocity: Vector3 = command.velocity
	_stance_center = target - heading * _neutral_com_offset + 0.8 * velocity
	super.plan(state, facing, delta)
	var support := StringName(command.support)
	var swinging := StringName(command.phase) in [&"swing", &"load"]
	var support_left := support == &"left"
	var left_contact := bool(state.support_feet & State.SupportFoot.LEFT)
	var right_contact := bool(state.support_feet & State.SupportFoot.RIGHT)
	var supported := left_contact if support_left else right_contact
	if _last_support != support:
		_swing_blend = 0.0
		_last_support = support
	var landing_touch := state.right_sole_touching if support_left else state.left_sole_touching
	var loading := StringName(command.phase) == &"load" and landing_touch
	var single_support := swinging and supported and not loading
	_swing_blend = move_toward(_swing_blend, 1.0 if single_support else 0.0, delta * (3.0 if loading else 8.0))
	var left := state.left_sole_position
	var right := state.right_sole_position
	var width := maxf(0.04, (right - left).dot(heading.x))
	var left_fraction := clampf((right - pressure_target).dot(heading.x) / width, 0.0, 1.0)
	if state.support_feet != State.SupportFoot.BOTH:
		left_fraction = 1.0 if left_contact else 0.0
	var right_fraction := 1.0 - left_fraction if state.grounded else 0.0
	var center := 0.5 * (left + right)
	var height := maxf(0.25, state.center_of_mass.y - center.y)
	var vertical := clampf((_stance_height - height) * 100.0 - state.linear_velocity.y * 16.0, -8.0, 18.0)
	var reaction := (Vector3.UP * (_gravity + vertical) + desired_acceleration) * _mass
	var old_offset := _foot_offset(pressure_target - left * left_fraction - right * right_fraction, heading)
	var left_share := lerpf(left_fraction, 1.0 if support_left else 0.0, _swing_blend) if left_contact else 0.0
	var right_share := 1.0 - left_share if right_contact else 0.0
	var fractions := {&"left":left_share, &"right":right_share}
	var loads := {&"left":state.left_support_load_n, &"right":state.right_support_load_n}
	var contacts := {&"left":left_contact, &"right":right_contact}
	var transition := {}
	for side in SIDES:
		_contact_time[side] = float(_contact_time[side]) + delta if contacts[side] else 0.0
		var settling := 1.0 - smoothstep(0.0, 0.12, float(_contact_time[side]))
		transition[side] = settling
		# A new toe contact can initially carry only a fraction of body weight.
		# Limit its share using measured load before requesting ankle moment.
		var budget := (1.25 * float(loads[side]) + 0.015 * _mass * _gravity) / maxf(1.0, reaction.y)
		fractions[side] = lerpf(float(fractions[side]), minf(float(fractions[side]), budget), settling)
	var missing := 1.0 - float(fractions[&"left"]) - float(fractions[&"right"])
	if supported and float(loads[support]) > 0.4 * _mass * _gravity:
		fractions[support] += maxf(0.0, missing)
	var force_center := left * float(fractions[&"left"]) + right * float(fractions[&"right"])
	var offset := _foot_offset(pressure_target - force_center / maxf(0.01, float(fractions[&"left"]) + float(fractions[&"right"])), heading)
	var standing_torso := state.body_poses[&"chest"].basis.y.cross(Vector3.UP) * 150.0 - Vector3(state.body_angular_velocities[&"chest"]).slide(Vector3.UP) * 20.0
	# The two endpoints describe the trunk as a whole, including motion across
	# the spinal joints. Their relative speed gives the derivative of its axis.
	var trunk_line := state.body_poses[&"head"].origin - state.body_poses[&"pelvis"].origin
	var trunk_axis := trunk_line.normalized()
	var relative_speed := state.body_linear_velocities[&"head"] - state.body_linear_velocities[&"pelvis"]
	var trunk_rate := trunk_axis.cross(relative_speed) / maxf(0.25, trunk_line.length())
	var trunk_moment := trunk_axis.cross(Vector3.UP) * 300.0 - trunk_rate * 14.0
	for side in SIDES:
		var suffix := "_l" if side == &"left" else "_r"
		var goal: Vector3 = command[String(side) + "_sole"]
		var normal: Vector3 = command[String(side) + "_normal"]
		var sole := left if side == &"left" else right
		var foot := StringName("foot" + suffix)
		var targets := _legs.solve(state, side, goal, normal, heading)
		var is_swing := side != support and swinging
		var mix := 1.0 if is_swing else 0.22
		for id: StringName in targets:
			relative_targets[id] = Basis(relative_targets[id]).slerp(targets[id], mix)
		var target_vel := (goal - Vector3(_previous_goal.get(side, goal))) / maxf(0.001, delta)
		_previous_goal[side] = goal
		var tip_velocity := Vector3(state.body_linear_velocities[foot]) + Vector3(state.body_angular_velocities[foot]).cross(sole - state.body_poses[foot].origin)
		var swing_drive := Vector3.ZERO
		if is_swing:
			swing_drive = ((goal - sole) * 850.0 + (target_vel.limit_length(2.0) - tip_velocity) * 25.0).limit_length(140.0)
			if contacts[side] and StringName(command.phase) == &"load":
				swing_drive -= normal * minf(0.0, swing_drive.dot(normal))
		var points := state.left_support_points if side == &"left" else state.right_support_points
		var new_offset := offset.lerp(_contact_offset(sole, points, offset, heading), float(transition[side]))
		var old_share := left_fraction if side == &"left" else right_fraction
		var share := float(fractions[side])
		# Project the pressure point along the knee's moment gradient when the
		# requested extension would consume its available torque reserve.
		var thigh_id := StringName("thigh" + suffix)
		var knee_id := StringName("calf" + suffix)
		var thigh_pose: Transform3D = state.body_poses[thigh_id]
		var knee_pose: Transform3D = state.body_poses[knee_id]
		var knee_pivot := thigh_pose * Vector3(_pivot_from_parent[knee_id])
		var axis := thigh_pose.basis.x
		var unconstrained := Vector3(feedforward_world_nm[knee_id]) + (sole+old_offset-knee_pivot).cross(reaction*old_share) - (sole+new_offset-knee_pivot).cross(reaction*share)
		var expected := unconstrained.dot(axis)
		var gradient := axis.cross(reaction*share).slide(normal)
		if absf(expected)>KNEE_MOMENT_BUDGET_NM and gradient.length_squared()>1500.0:
			var correction := gradient*((clampf(expected,-KNEE_MOMENT_BUDGET_NM,KNEE_MOMENT_BUDGET_NM)-expected)/gradient.length_squared())
			new_offset = _foot_offset(new_offset+correction, heading)
		var weight_mix := smoothstep(0.55,0.94,share)
		var knee_relative := thigh_pose.basis.transposed()*knee_pose.basis
		var knee_angle := atan2(knee_relative.y.z,knee_relative.y.y)
		var knee_omega := Vector3(state.body_angular_velocities[knee_id]-state.body_angular_velocities[thigh_id]).dot(axis)
		var posture := clampf(110.0 * (LOADED_KNEE_ANGLE-knee_angle)-5.0 * knee_omega,-55.0,55.0)
		if not is_swing:
			feedforward_world_nm[knee_id] += axis * weight_mix * posture
			relative_targets[knee_id] = Basis(relative_targets[knee_id]).slerp(Basis(Vector3.RIGHT,LOADED_KNEE_ANGLE),weight_mix)
		for prefix in ["thigh", "calf", "foot"]:
			var joint := StringName(prefix + suffix)
			var pivot: Vector3 = state.body_poses[_parent[joint]] * Vector3(_pivot_from_parent[joint])
			var lever := sole - pivot
			# Replace the standing reaction with the phase- and contact-specific
			# wrench. Gravity compensation for the distal segments is preserved.
			var difference := (lever + old_offset).cross(reaction * old_share) - (lever + new_offset).cross(reaction * share)
			var endpoint_moment := lever.cross(swing_drive)
			if prefix == "foot":
				endpoint_moment = endpoint_moment.limit_length(3.0)
			if prefix == "thigh":
				difference += standing_torso * old_share - trunk_moment * share
			feedforward_world_nm[joint] += difference + endpoint_moment
			if prefix == "foot":
				feedforward_world_nm[foot] = _ankle_request(feedforward_world_nm[foot], state, side, foot, pivot, points, reaction, share)
	var forward := (-state.body_poses[&"pelvis"].basis.z).slide(Vector3.UP)
	var yaw := forward.signed_angle_to(-heading.z.slide(Vector3.UP), Vector3.UP)
	var yaw_moment := Vector3.UP * clampf(75.0 * yaw - 2.0 * state.angular_momentum.y, -50.0, 50.0)
	if state.grounded:
		feedforward_world_nm[&"thigh_l"] -= yaw_moment * float(fractions[&"left"])
		feedforward_world_nm[&"thigh_r"] -= yaw_moment * float(fractions[&"right"])

