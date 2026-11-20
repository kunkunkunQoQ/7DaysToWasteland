extends SceneTree

const Meter := preload("joint_telemetry.gd")
const Rig := preload("../body/physics_rig.gd")
const Config := preload("../config/physics_character_config.gd")
var _errors := 0

func _initialize() -> void:
	_verify.call_deferred()

func _check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	_errors += int(not condition)

func _verify() -> void:
	var a := Basis.from_euler(Vector3(0.42, -0.15, 0.71))
	var knee_low := Vector3(0, 0, deg_to_rad(-3.0))
	var knee_high := Vector3(0, 0, deg_to_rad(132.0))
	var bend := Meter.measure_angles(a, a * Basis(Vector3.BACK, deg_to_rad(-100.0)), true, knee_low, knee_high)
	_check(absf(rad_to_deg(bend.angles.z) - 100.0) < 0.001 and bend.correction < 0.0001, "100 degree knee flexion is legal")
	var reversed := Meter.measure_angles(a, a * Basis(Vector3.BACK, deg_to_rad(18.0)), true, knee_low, knee_high)
	_check(absf(rad_to_deg(reversed.violation) - 15.0) < 0.001 and absf(rad_to_deg(reversed.correction) - 15.0) < 0.001,
		"18 degree extension exceeds the knee interval by 15 degrees")
	var tilt := Meter.measure_angles(a, a * Basis(Vector3.RIGHT, deg_to_rad(12.0)), true, knee_low, knee_high)
	_check(absf(rad_to_deg(tilt.axis_error) - 12.0) < 0.001 and absf(rad_to_deg(tilt.correction) - 12.0) < 0.001,
		"off-axis bend is visible with unchanged hinge coordinate")
	var high := Vector3(0.5, 0.4, 0.3)
	for coords: Vector3 in [Vector3(0.3, -0.2, 0.1), Vector3(-0.7, 0.46, -0.34)]:
		var b := a * Basis.from_euler(coords, EULER_ORDER_XYZ).transposed()
		var measured := Meter.measure_angles(a, b, false, -high, high)
		_check(measured.angles.distance_to(coords) < 0.0001, "signed compound XYZ recovered: " + str(coords))
		var excess := coords - coords.clamp(-high, high)
		_check(absf(measured.violation - excess.abs()[excess.abs().max_axis_index()]) < 0.0001 and
			((measured.correction < 0.0001) == excess.is_zero_approx()), "compound admissible orientation and violation")

	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, 0.2, 12)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = -0.1
	floor_body.name = "Ground"
	root.add_child(floor_body)
	var rig := Rig.new()
	rig.position = Vector3(0.2, 0.5, -0.1)
	root.add_child(rig)
	var config := Config.new()
	rig.build(config)
	_verify_asymmetric_hip(rig, config)
	_verify_statistics(rig, config)
	var meter := Meter.new()
	var trace_path := OS.get_temp_dir().path_join("pc-joint-trace-%s.csv" % OS.get_process_id())
	var csv := FileAccess.open(trace_path, FileAccess.WRITE)
	meter.setup(rig, config, Engine.physics_ticks_per_second, csv)
	for i in Engine.physics_ticks_per_second * 2:
		await physics_frame
		meter.sample(i + 1)
	var report := meter.finish()
	csv.close()
	var input := FileAccess.open(trace_path, FileAccess.READ)
	var columns := input.get_csv_line().size()
	var rows := 0
	while input.get_position() < input.get_length():
		var fields := input.get_csv_line()
		if fields.size() == columns:
			rows += 1
	input.close()
	DirAccess.remove_absolute(trace_path)
	_check(report.joints.size() == 15 and report.body.samples == Engine.physics_ticks_per_second * 2, "all joint summaries cover every physics step")
	_check(report.body.finite and report.body.first_external_tick > 0 and report.body.max_anchor_m > 0.0001, "fall records finite constraint error and real external contact")
	_check(rows == int(report.body.samples) * 15, "CSV roundtrip preserves each multi-component sample")
	rig.free()
	floor_body.free()
	print("TELEMETRY selftest errors=", _errors)
	quit(1 if _errors else 0)

func _verify_asymmetric_hip(rig: Node3D, config: Resource) -> void:
	var hip: Generic6DOFJoint3D = rig.joints[&"thigh_l"]
	var thigh: RigidBody3D = rig.bodies[&"thigh_l"]
	var rest := thigh.basis
	var lower := hip.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
	var upper := hip.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
	hip.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-5.0))
	hip.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(25.0))
	var axis := hip.basis.y
	for angle in [20.0, -10.0]:
		var meter := Meter.new()
		meter.setup(rig, config, 60)
		thigh.basis = Basis(axis, -deg_to_rad(angle)) * rest
		meter.sample(1, 1)
		for row: Dictionary in meter.finish().joints:
			if row.joint == &"thigh_l":
				var expected := 0.0 if angle == 20.0 else 5.0
				_check(absf(row.peak_limit_deg - expected) < 0.001,
					"effective asymmetric hip bounds use the correct side at %s degrees" % angle)
	thigh.basis = rest
	hip.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
	hip.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)

func _verify_statistics(rig: Node3D, config: Resource) -> void:
	# Manufactured observations validate aggregation independently of engine trajectories.
	var meter := Meter.new()
	meter.setup(rig, config, 60)
	var hand: RigidBody3D = rig.bodies[&"hand_l"]
	var rest := hand.position
	for tick in range(1, 61):
		hand.position = rest + Vector3.RIGHT * 0.03 if tick in [5, 45] else rest
		meter.sample(tick, 1)
		if tick == 55:
			_check(meter.finish().body.max_recovery_s == -1.0, "short in-band suffix cannot certify recovery")
	var report := meter.finish()
	for row: Dictionary in report.joints:
		if row.joint != &"hand_l":
			continue
		_check(absf(row.peak_anchor_m - 0.03) < 0.00001 and row.peak_tick == 5 and
			absf(row.rms_anchor_m - 0.03 * sqrt(2.0 / 60.0)) < 0.00001, "two known excursions give the expected peak and full-window RMS")
		_check(absf(row.residual_m - 0.03 / sqrt(30.0)) < 0.00001 and absf(row.recovery_s - 0.75) < 0.00001,
			"residual uses the tail window and recovery restarts after the last excursion")
