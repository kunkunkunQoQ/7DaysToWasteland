extends "../tests/test_arena.gd"

var _stand_space := RID()
var _old_iterations := 0

func _enter_tree() -> void:
	if get_parent() != get_tree().root:
		return
	_previous_hz = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60
	_stand_space = get_world_3d().space
	var iterations := PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS
	_old_iterations = roundi(PhysicsServer3D.space_get_param(_stand_space, iterations))
	PhysicsServer3D.space_set_param(_stand_space, iterations, 128)

func _apply_standalone_rate() -> void:
	pass

func _exit_tree() -> void:
	if _stand_space.is_valid():
		PhysicsServer3D.space_set_param(_stand_space, PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS, _old_iterations)
	super._exit_tree()
