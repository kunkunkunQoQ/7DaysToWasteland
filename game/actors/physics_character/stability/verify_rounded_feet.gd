extends SceneTree
## Native collision shapes, local mass properties, displayed feet and state.

const ARENA := preload("rounded_feet_test.tscn")
const Character := preload("../physics_character.gd")
const Rig := preload("../body/physics_rig.gd")
const GeometryProbe := preload("penetration_probe.gd")
const Baseline := preload("../config/default.tres")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if change_scene_to_packed(ARENA) != OK:
		quit(2)
		return
	await scene_changed
	await physics_frame
	var actor: Character = current_scene.get_node("Character")
	var rig: Rig = actor.get_node("PhysicsRig")
	var skeleton: Skeleton3D = actor.get_node("Visual/Skeleton3D")
	var config_rows := Baseline.build_segments()
	var shapes_valid := true
	var inertia_valid := true
	var visual_valid := true
	for row: Dictionary in config_rows:
		if row.id not in [&"foot_l", &"foot_r"]:
			continue
		var body: RigidBody3D = rig.bodies[row.id]
		var direct := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var attachment := skeleton.get_node(NodePath(String(row.id)))
		var size: Vector3 = row.size
		var squared := size * size
		var nominal := Vector3(squared.y + squared.z, squared.x + squared.z, squared.x + squared.y) * (float(row.mass) / 12.0)
		var union := AABB()
		shapes_valid = shapes_valid and body.get_child_count() == 2
		visual_valid = visual_valid and attachment.get_child_count() == body.get_child_count()
		for i in body.get_child_count():
			var collider := body.get_child(i) as CollisionShape3D
			if collider == null or not collider.shape is CapsuleShape3D:
				shapes_valid = false
				continue
			var capsule := collider.shape as CapsuleShape3D
			var half_extent := Vector3.ONE * capsule.radius + collider.basis.y.abs() * (capsule.height * 0.5 - capsule.radius)
			var bounds := AABB(collider.position - half_extent, 2.0 * half_extent)
			union = bounds if i == 0 else union.merge(bounds)
			if i >= attachment.get_child_count():
				visual_valid = false
				continue
			var mesh_instance := attachment.get_child(i) as MeshInstance3D
			if mesh_instance == null:
				visual_valid = false
				continue
			var mesh := mesh_instance.mesh as CapsuleMesh
			visual_valid = visual_valid and mesh != null and is_equal_approx(mesh.radius, capsule.radius) and is_equal_approx(mesh.height, capsule.height) and mesh_instance.transform.is_equal_approx(collider.transform)
		shapes_valid = shapes_valid and union.position.is_equal_approx(-0.5 * size) and union.size.is_equal_approx(size)
		shapes_valid = shapes_valid and is_equal_approx(union.position.y, actor.config.sole_offset.y)
		inertia_valid = inertia_valid and is_equal_approx(body.mass, float(row.mass)) and direct.center_of_mass_local.is_zero_approx()
		inertia_valid = inertia_valid and direct.inverse_inertia.inverse().distance_to(nominal) < 1e-7 and direct.principal_inertia_axes.is_equal_approx(Basis.IDENTITY)
	var seen_left := false
	var seen_right := false
	var sole_state_valid := true
	var probe := GeometryProbe.new()
	probe.setup(rig, actor.config)
	for tick in range(1, 121):
		await physics_frame
		var state := actor.get_state()
		seen_left = seen_left or not state.left_support_points.is_empty()
		seen_right = seen_right or not state.right_support_points.is_empty()
		sole_state_valid = sole_state_valid and state.left_sole_position.is_equal_approx(state.body_poses[&"foot_l"] * actor.config.sole_offset)
		sole_state_valid = sole_state_valid and state.right_sole_position.is_equal_approx(state.body_poses[&"foot_r"] * actor.config.sole_offset)
		probe.sample(tick, tick > 90)
	var geometry := probe.finish(60)
	print("ROUNDED_FEET_VERIFY shapes=", shapes_valid, " inertia=", inertia_valid, " visual=", visual_valid,
		" public_sole=", sole_state_valid, " left_contact=", seen_left, " right_contact=", seen_right,
		" floor_peak_m=", geometry.floor_peak_m, " self_peak_m=", geometry.self_peak_m)
	quit(0 if shapes_valid and inertia_valid and visual_valid and sole_state_valid and seen_left and seen_right and skeleton.get_bone_count() == 16 else 1)
