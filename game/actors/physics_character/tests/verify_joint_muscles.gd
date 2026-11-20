extends SceneTree
## Native two-body fixture, with a rotated joint basis and zero external loads.
const Controller := preload("../controllers/joint_muscle_controller.gd")
var failures := 0

class Fixture extends Resource:
	func build_joints() -> Array[Dictionary]:
		return [{"parent": &"thigh_l", "child": &"calf_l", "kind": &"hinge",
			"basis": Basis(Vector3.UP, PI / 2.0)}]

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	failures += int(not ok)

func _body(id: String, offset: Vector3, frame: Basis) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = id
	body.mass = 1.0
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.collision_layer = 0
	body.collision_mask = 0
	body.can_sleep = false
	body.transform = Transform3D(frame, offset)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 0.25
	body.add_child(shape)
	root.add_child(body)
	return body

func _run() -> void:
	var identity_error := Controller.rotation_error(Basis.IDENTITY, Basis.IDENTITY)
	var wrap_error := Controller.rotation_error(Basis(Vector3.UP, deg_to_rad(-179.0)), Basis(Vector3.UP, deg_to_rad(179.0)))
	_check(identity_error.length() < 0.000001, "identity has zero orientation error")
	_check(wrap_error.distance_to(Vector3.UP * deg_to_rad(2.0)) < 0.00001, "wrapped orientation follows the two degree arc")
	var rotated := Basis(Vector3.UP, 0.8) * Basis(Vector3.BACK, 0.3)
	var parent := _body("parent", Vector3.LEFT, rotated)
	var child := _body("child", Vector3.RIGHT, rotated)
	var muscle := Controller.new()
	muscle.setup(Fixture.new(), {&"thigh_l":parent, &"calf_l":child})
	for i in 3:
		await physics_frame
	var dt := 1.0 / Engine.physics_ticks_per_second
	var hinge_axis := rotated.x
	muscle.step(dt, {}, {&"calf_l":rotated.y * 5000.0})
	_check(muscle.last_torques[&"calf_l"].length() < 0.001, "off-axis feed-forward cannot drive a hinge")
	var target := Basis(Vector3.RIGHT, 0.3)
	var relative_targets := {&"calf_l":target}
	muscle.step(dt, relative_targets)
	var applied := muscle.last_torques[&"calf_l"]
	_check(applied.dot(hinge_axis) > 0.0 and applied.cross(hinge_axis).length() < 0.001, "relative target generates the rotated hinge-axis torque")
	await physics_frame
	await physics_frame
	_check(child.angular_velocity.dot(hinge_axis) > 0.0 and parent.angular_velocity.dot(hinge_axis) < 0.0,
		"native bodies receive opposing angular impulses")
	_check((child.angular_velocity + parent.angular_velocity).length() < 0.0001,
		"equally inertial free bodies conserve angular momentum")
	var error_before := Controller.rotation_error(target, parent.global_basis.transposed() * child.global_basis).length()
	for i in 90:
		muscle.step(dt, relative_targets)
		await physics_frame
	var error_after := Controller.rotation_error(target, parent.global_basis.transposed() * child.global_basis).length()
	_check(error_after < 0.005 and error_after < error_before, "closed-loop motion converges from measured relative rotation and velocity")
	muscle.step(dt, relative_targets, {&"calf_l":hinge_axis * 1e6}, 0.45)
	_check(is_equal_approx(muscle.last_torques[&"calf_l"].length(), 0.45 * muscle.torque_limits[&"calf_l"]), "strength scales the physical torque ceiling")
	muscle.step(dt, relative_targets, {&"calf_l":hinge_axis * 1e6}, 0.0)
	_check(muscle.last_torques[&"calf_l"].is_zero_approx(), "disabled muscles request zero torque")
	print("MUSCLE errors=", failures, " final_relative_error_rad=", error_after)
	parent.free()
	child.free()
	quit(1 if failures else 0)
