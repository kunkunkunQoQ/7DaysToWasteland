extends "physics_character.gd"
## The passive scene and this scene share the same rig, state and fixed-step clock.

const Standing := preload("controllers/standing_controller.gd")
const Muscles := preload("controllers/joint_muscle_controller.gd")
const IntentFrame := preload("controllers/physics_character_intent.gd")

@export var active_standing := true
var _standing := Standing.new()
var _muscles := Muscles.new()

func _ready() -> void:
	super._ready()
	if config == null:
		return
	_standing.setup(config)
	_muscles.setup(config, _rig.bodies)
	_controller.control_step.connect(_actuate)

func _actuate(state: State, intent: IntentFrame, delta: float) -> void:
	if active_standing:
		_standing.plan(state, intent.desired_facing, delta)
		_muscles.step(delta, _standing.relative_targets, _standing.feedforward_world_nm)

func get_muscle_telemetry() -> Dictionary:
	var result := {}
	if active_standing:
		for id: StringName in _muscles.last_torques:
			result[id] = {"torque_world_nm": _muscles.last_torques[id], "limit_nm": _muscles.torque_limits[id]}
	return result
