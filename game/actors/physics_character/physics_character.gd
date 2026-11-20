class_name PhysicsCharacter
extends Node3D

const State := preload("state/physics_character_state.gd")
const Config := preload("res://game/actors/physics_character/config/physics_character_config.gd")
const Sampler := preload("res://game/actors/physics_character/state/state_sampler.gd")
const Rig := preload("res://game/actors/physics_character/body/physics_rig.gd")
const InputController := preload("res://game/actors/physics_character/controllers/intent_controller.gd")

## Gameplay reads get_state() or listens to state_updated. World-space samples
## contain values only. The physics rig belongs to this scene.
signal state_updated(state: State)
signal configured(parameters: Config)

@export var config: Config
@onready var _rig: Rig = $PhysicsRig
@onready var _controller: InputController = $Controller
var _sampler := Sampler.new()
var _state: State
var _tick := 0

func _ready() -> void:
	if config == null:
		push_error("PhysicsCharacter requires a body configuration.")
		set_physics_process(false)
		return
	_rig.build(config, _initial_segment_poses())
	configured.emit(config)
	_state = _sampler.sample(_rig, config, 0, 0.0)
	state_updated.emit(_state)

func _initial_segment_poses() -> Dictionary:
	return {}

func _physics_process(delta: float) -> void:
	_tick += 1
	_state = _sampler.sample(_rig, config, _tick, delta)
	_controller.advance(_state, delta)
	state_updated.emit(_state)

func get_state() -> State:
	return _state

## Facing is independent of travel direction. Jump is latched until the next
## physics tick. This interface accepts intent even while the rig is passive.
func submit_intent(velocity: Vector3, facing: Vector3, jump_pressed := false, grab_held := false, run_held := false) -> void:
	_controller.submit(velocity, facing, jump_pressed, grab_held, run_held)
