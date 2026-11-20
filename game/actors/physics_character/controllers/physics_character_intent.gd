class_name PhysicsCharacterIntent
extends RefCounted

## World-space intent sampled once per physics tick. It contains no body handles.
var desired_velocity: Vector3:
	get: return _velocity
var move_direction: Vector3:
	get: return Vector3(_velocity.x, 0.0, _velocity.z).normalized()
var desired_facing: Vector3:
	get: return _facing
var jump_pressed: bool:
	get: return _jump
var grab_held: bool:
	get: return _grab
var run_held: bool:
	get: return _run

var _velocity: Vector3
var _facing: Vector3
var _jump: bool
var _grab: bool
var _run: bool

func _init(velocity: Vector3, facing: Vector3, jump: bool, grab: bool, run := false) -> void:
	_velocity = velocity
	_facing = facing
	_jump = jump
	_grab = grab
	_run = run
