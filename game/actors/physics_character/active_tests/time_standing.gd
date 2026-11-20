extends "../stability/time_steps.gd"
## Reuse the phase 2 real-time step timer. Each active ragdoll stands on the
## same floor in a separate contact island, with visual nodes removed.

const Active := preload("../active_character.tscn")
var actor_count := 1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--actors="):
			actor_count = arg.trim_prefix("--actors=").to_int()
	if actor_count not in [1,2,6]:
		printerr("Expected --actors=1, 2 or 6.")
		quit(2)
		return
	super._initialize()

func _setup() -> void:
	if hz != 60 or root.world_3d.direct_space_state.get_class() != &"GodotPhysicsDirectSpaceState3D":
		printerr("The standing benchmark requires GodotPhysics3D at 60 Hz.")
		quit(2)
		return
	profile = "standing_%d" % actor_count
	PhysicsServer3D.space_set_param(root.world_3d.space,PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS,128)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position.y = -0.10
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30,0.20,30)
	collider.shape = box
	floor_body.add_child(collider)
	root.add_child(floor_body)
	for i in actor_count:
		var body := Active.instantiate() as Node3D
		body.get_node("Visual").free()
		body.position = Vector3(i * 1.6,0,0)
		root.add_child(body)
	wall_start_us = Time.get_ticks_usec()
	physics_frame.connect(_begin)
	process_frame.connect(_end)

func _begin() -> void:
	tick += 1
	if start_us >= 0:
		multi_step = true
	start_us = Time.get_ticks_usec()
