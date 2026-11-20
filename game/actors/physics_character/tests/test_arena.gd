extends Node3D

const MAX_PUSH_SPEED := 3.8

@onready var _character = $Character
@onready var _block: RigidBody3D = $TestBlock
@onready var _camera: Camera3D = $Camera3D

## The only colliders in this arena are the floor, test block and character.
var block_hit_character := false
var _push_requested := false
var _previous_hz := 0

func _ready() -> void:
	_camera.look_at(to_global(Vector3(-0.22, 0.73, 0)), Vector3.UP)
	_character.state_updated.connect($Telemetry.sync_state)
	_block.body_entered.connect(_on_block_contact)
	_apply_standalone_rate.call_deferred()

func _apply_standalone_rate() -> void:
	if get_tree().current_scene != self:
		return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--physics-hz="):
			continue
		var requested := arg.trim_prefix("--physics-hz=")
		if requested not in ["60", "120"]:
			push_warning("PhysicsCharacter test accepts --physics-hz=60 or --physics-hz=120.")
			return
		_previous_hz = Engine.physics_ticks_per_second
		Engine.physics_ticks_per_second = requested.to_int()
		return

func _exit_tree() -> void:
	if _previous_hz > 0:
		Engine.physics_ticks_per_second = _previous_hz

func _unhandled_key_input(event: InputEvent) -> void:
	if get_tree().current_scene != self or not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			push_block()
		KEY_R:
			get_tree().reload_current_scene.call_deferred()
		_:
			return
	get_viewport().set_input_as_handled()

func push_block() -> void:
	_push_requested = true

func _physics_process(_delta: float) -> void:
	if not _push_requested:
		return
	_push_requested = false
	var state = _character.get_state()
	if state == null:
		return
	var to_target: Vector3 = state.center_of_mass - _block.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	var current := _block.linear_velocity.slide(Vector3.UP)
	var change := to_target.normalized() * MAX_PUSH_SPEED - current
	_block.apply_central_impulse(change.limit_length(MAX_PUSH_SPEED) * _block.mass)

func _on_block_contact(collider: Node) -> void:
	if collider != $Ground:
		block_hit_character = true
