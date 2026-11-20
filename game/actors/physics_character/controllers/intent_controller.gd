extends Node

const State := preload("../state/physics_character_state.gd")
const Intent := preload("physics_character_intent.gd")

## Future balance, gait and muscle controllers subscribe to this fixed-step port.
## The passive rig has no actuator subscriber in phase 1.
signal control_step(state: State, intent: Intent, delta: float)

var _velocity := Vector3.ZERO
var _facing := Vector3.FORWARD
var _jump_pending := false
var _grab_held := false

func submit(velocity: Vector3, facing: Vector3, jump: bool, grab: bool) -> void:
	if velocity.is_finite():
		_velocity = velocity
	var horizontal := Vector3(facing.x, 0.0, facing.z)
	if horizontal.is_finite() and not horizontal.is_zero_approx():
		_facing = horizontal.normalized()
	_jump_pending = _jump_pending or jump
	_grab_held = grab

func advance(state: State, delta: float) -> void:
	var intent := Intent.new(_velocity, _facing, _jump_pending, _grab_held)
	_jump_pending = false
	control_step.emit(state, intent, delta)
