extends "../tests/test_arena.gd"
## Dedicated standalone test scene. A nested instance never configures its host.

const Experiment := preload("experiment_config.gd")
var _test_space := RID()
var _saved_iterations := 0

func _enter_tree() -> void:
	if get_parent() != get_tree().root:
		return
	_previous_hz = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 120
	_test_space = get_world_3d().space
	_saved_iterations = roundi(PhysicsServer3D.space_get_param(_test_space, PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS))
	Experiment.configure_space("rounded_feet120", _test_space)

func _apply_standalone_rate() -> void:
	# This scene reproduces the 120 Hz / 48 iteration experiment.
	pass

func _exit_tree() -> void:
	if _test_space.is_valid():
		PhysicsServer3D.space_set_param(_test_space, PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS, _saved_iterations)
	super._exit_tree()
