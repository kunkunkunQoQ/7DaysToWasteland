extends "joint_muscle_controller.gd"
## A moving leg tracks relative target velocity as well as relative orientation.
## The support leg and upper body retain the standing actuator's response.

const MAX_TARGET_SPEED := 7.0 # rad/s
const RATE_FILTER := 28.0 # 1/s
const LEFT_LEG := [&"thigh_l", &"calf_l", &"foot_l"]
const RIGHT_LEG := [&"thigh_r", &"calf_r", &"foot_r"]

var _last_support := &""
var _previous_targets: Dictionary[StringName, Basis] = {}
var _filtered_rates: Dictionary[StringName, Vector3] = {}

func setup(config: Resource, bodies: Dictionary) -> void:
	super.setup(config, bodies)
	_reset_rates()
	_last_support = &""

func _reset_rates() -> void:
	_previous_targets.clear()
	_filtered_rates.clear()

func step_walk(delta: float, targets: Dictionary, feedforward: Dictionary, phase: StringName, support: StringName) -> void:
	if support != _last_support:
		_reset_rates()
		_last_support = support
	if delta <= 0.0 or phase not in [&"swing", &"load"] or support not in [&"left", &"right"]:
		_reset_rates()
		step(delta, targets, feedforward)
		return
	var commanded := feedforward.duplicate()
	var swing_leg := RIGHT_LEG if support == &"left" else LEFT_LEG
	var blend := 1.0 - exp(-RATE_FILTER * delta)
	for muscle: Muscle in _muscles:
		if muscle.id not in swing_leg:
			continue
		var mount := muscle.rest_frame
		var target := mount.transposed() * Basis(targets.get(muscle.id, Basis.IDENTITY)) * mount
		if _previous_targets.has(muscle.id):
			var rate := (rotation_error(target, _previous_targets[muscle.id]) / delta).limit_length(MAX_TARGET_SPEED)
			var smooth := Vector3(_filtered_rates.get(muscle.id, Vector3.ZERO)).lerp(rate, blend)
			_filtered_rates[muscle.id] = smooth
			commanded[muscle.id] = Vector3(commanded.get(muscle.id, Vector3.ZERO)) + _rate_torque(muscle, smooth, delta)
		_previous_targets[muscle.id] = target
	step(delta, targets, commanded)

## By linearity, solving S*tau = kp*error - c*(omega - desired_rate)
## adds S^-1*c*desired_rate to the static-target torque. The inherited
## actuator limits the sum and applies equal and opposite impulses.
func _rate_torque(muscle: Muscle, rate: Vector3, delta: float) -> Vector3:
	var frame := muscle.parent.global_basis.orthonormalized() * muscle.rest_frame
	var ia := muscle.parent.get_inverse_inertia_tensor()
	var ib := muscle.child.get_inverse_inertia_tensor()
	var mobility := frame.transposed() * Basis(ia.x + ib.x, ia.y + ib.y, ia.z + ib.z) * frame
	var c := muscle.kd * damping_scale + muscle.kp * gain_scale * delta
	var rhs := c * rate
	if muscle.hinge:
		return frame.z * (rhs.z / (1.0 + c * delta * mobility.z.z))
	var system := Basis(Vector3.RIGHT + mobility.x * (c * delta),
		Vector3.UP + mobility.y * (c * delta), Vector3.BACK + mobility.z * (c * delta))
	return frame * (system.inverse() * rhs)
