extends RefCounted
## Analytic, value-only leg targets. The muscle controller supplies all actuation.
const State := preload("../state/physics_character_state.gd")
const Config := preload("../config/physics_character_config.gd")

class Leg:
	var thigh: StringName
	var calf: StringName
	var foot: StringName
	var hip_offset: Vector3
	var upper: Vector3
	var lower: Vector3
	var ankle_to_sole: Vector3
	var knee_axis: Vector3
	var knee_min: float
	var knee_max: float
	var hip: Dictionary
	var ankle: Dictionary

var _legs := {}

func setup(config: Config) -> void:
	_legs.clear()
	var centers := {}
	var joints := {}
	for segment in config.build_segments():
		centers[segment.id] = segment.position
	for joint in config.build_joints():
		joints[joint.child] = joint
	for side: StringName in [&"left", &"right"]:
		var suffix := "_l" if side == &"left" else "_r"
		var leg := Leg.new()
		leg.thigh = StringName("thigh" + suffix)
		leg.calf = StringName("calf" + suffix)
		leg.foot = StringName("foot" + suffix)
		leg.hip = joints[leg.thigh]
		var knee: Dictionary = joints[leg.calf]
		leg.ankle = joints[leg.foot]
		leg.hip_offset = Vector3(leg.hip.position) - Vector3(centers[&"pelvis"])
		leg.upper = Vector3(knee.position) - Vector3(leg.hip.position)
		leg.lower = Vector3(leg.ankle.position) - Vector3(knee.position)
		leg.ankle_to_sole = Vector3(centers[leg.foot]) + config.sole_offset - Vector3(leg.ankle.position)
		leg.knee_axis = Basis(knee.basis).z.normalized()
		# GodotPhysics reports parent relative to child; the muscles target child
		# relative to parent. Physical knee flexion therefore has negative sign.
		leg.knee_min = -float(knee.upper)
		leg.knee_max = -float(knee.lower)
		_legs[side] = leg

static func _plane_frame(direction: Vector3, preferred_axis: Vector3) -> Basis:
	var x := preferred_axis.slide(direction)
	if x.length_squared() < 0.000001:
		var fallback := Vector3.BACK if absf(direction.z) < 0.9 else Vector3.UP
		x = fallback.slide(direction)
	x = x.normalized()
	var y := -direction
	return Basis(x, y, x.cross(y).normalized())

static func _limit(relative: Basis, joint: Dictionary) -> Basis:
	var frame: Basis = joint.basis
	var native := frame.transposed() * relative.transposed() * frame
	var angles := native.get_euler(EULER_ORDER_XYZ)
	var bound := Vector3(joint.twist, joint.swing, joint.swing)
	var clamped := angles.clamp(joint.get("lower_angles", -bound), joint.get("upper_angles", bound))
	if angles.is_equal_approx(clamped):
		return relative
	return frame * Basis.from_euler(clamped, EULER_ORDER_XYZ).transposed() * frame.transposed()

## Find the flexed branch including the rest knee and ankle offsets. The cosine
## law is applied in the actual hinge plane; axial offsets are preserved.
static func _knee_angle(leg: Leg, distance: float) -> float:
	var upper := leg.upper.slide(leg.knee_axis)
	var lower := leg.lower.slide(leg.knee_axis)
	var a := upper.dot(lower)
	var b := upper.dot(leg.knee_axis.cross(lower))
	var axial := leg.upper.dot(leg.knee_axis) * leg.lower.dot(leg.knee_axis)
	var required := (distance * distance - leg.upper.length_squared() - leg.lower.length_squared()) * 0.5 - axial
	var cosine := clampf(required / maxf(0.000001, Vector2(a, b).length()), -1.0, 1.0)
	return clampf(atan2(b, a) - acos(cosine), leg.knee_min, leg.knee_max)

func solve(state: State, side: StringName, target_sole: Vector3, normal: Vector3, heading: Basis) -> Dictionary:
	var leg: Leg = _legs.get(side)
	if leg == null or not target_sole.is_finite() or not normal.is_finite() or not heading.is_finite():
		return {}
	var pelvis: Transform3D = state.body_poses[&"pelvis"]
	var root_basis := pelvis.basis.orthonormalized()
	var hip_position := pelvis * leg.hip_offset
	var up := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	var foot_target := _plane_frame(-up, heading.x)
	# Project the heading's forward onto the surface for oblique cross-slopes.
	var forward := (-heading.z).slide(up)
	if forward.length_squared() > 0.000001:
		var right := forward.normalized().cross(up)
		foot_target = Basis(right, up, right.cross(up))
	var foot_world := foot_target
	var result := {}
	for iteration in 5:
		var offset := target_sole - foot_world * leg.ankle_to_sole - hip_position
		var world_direction := offset.normalized() if offset.length_squared() > 0.000001 else -root_basis.y
		var knee := Basis(leg.knee_axis, _knee_angle(leg, offset.length()))
		var local_direction := (leg.upper + knee * leg.lower).normalized()
		var desired_thigh := _plane_frame(world_direction, heading.x) * _plane_frame(local_direction, leg.knee_axis).transposed()
		var hip := _limit(root_basis.transposed() * desired_thigh, leg.hip)
		var calf_world := root_basis * hip * knee
		var ankle := _limit(calf_world.transposed() * foot_target, leg.ankle)
		result = {leg.thigh: hip, leg.calf: knee, leg.foot: ankle}
		var achieved := calf_world * ankle
		# An ankle stop can tilt the foot, moving its sole relative to the ankle.
		# Update the ankle request using that achievable orientation.
		if (achieved * leg.ankle_to_sole - foot_world * leg.ankle_to_sole).length_squared() < 0.00000001:
			break
		foot_world = achieved
	return result
