extends "standing_arena.gd"
## Standalone diagnostic controls. Gameplay scenes use their own input routing.

var _view_yaw := 0.0
var _body_yaw := 0.0
var _jump := false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_view_yaw -= event.relative.x * 0.006
		if not Input.is_key_pressed(KEY_ALT):
			_body_yaw = _view_yaw
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE:
			_jump = true
		KEY_P:
			push_block()
		KEY_R:
			get_tree().reload_current_scene.call_deferred()
		_:
			return
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var state = _character.get_state()
	if state == null:
		return
	var x := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
	var z := int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
	var view := Basis(Vector3.UP,_view_yaw)
	var speed := 0.35 if Input.is_physical_key_pressed(KEY_Z) else 0.8
	var velocity := view * Vector3(x,0,z).normalized() * speed
	_character.submit_intent(velocity, Basis(Vector3.UP,_body_yaw)*Vector3.FORWARD,
		_jump, false, Input.is_key_pressed(KEY_SHIFT))
	_jump = false
	var center: Vector3 = state.center_of_mass
	_camera.global_position = center + view.z * 3.1 + Vector3.UP * 0.95
	_camera.look_at(center,Vector3.UP)
