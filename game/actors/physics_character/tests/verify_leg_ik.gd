extends SceneTree
const IK := preload("../controllers/leg_ik.gd")
const State := preload("../state/physics_character_state.gd")
const Config := preload("../config/active_standing.tres")

var failures := 0
var centers := {}
var joints := {}
var solver := IK.new()

func _initialize() -> void:
	solver.setup(Config)
	for row in Config.build_segments():
		centers[row.id] = row.position
	for row in Config.build_joints():
		joints[row.child] = row
	for side: StringName in [&"left", &"right"]:
		_run(side)
	print("LEG_IK failures=", failures)
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	failures += int(not ok)

func _fk(pelvis: Transform3D, ids: Array, angles: Dictionary) -> Transform3D:
	var pose := pelvis
	for id: StringName in ids:
		var joint: Dictionary = joints[id]
		var pivot := pose * (Vector3(joint.position) - Vector3(centers[joint.parent]))
		var orientation: Basis = pose.basis * Basis(angles[id])
		pose = Transform3D(orientation, pivot + orientation * (Vector3(centers[id]) - Vector3(joint.position)))
	return Transform3D(pose.basis, pose * Config.sole_offset)

func _legal(ids: Array, angles: Dictionary) -> bool:
	for id: StringName in ids:
		var pose: Basis = angles[id]
		if not pose.is_finite() or absf(pose.determinant() - 1.0) > 0.0001:
			return false
		var j: Dictionary = joints[id]
		var mount: Basis = j.basis
		var xyz := (mount.transposed() * pose.transposed() * mount).get_euler(EULER_ORDER_XYZ)
		if j.kind == &"hinge":
			if absf(xyz.x) + absf(xyz.y) > 0.0001 or xyz.z < j.lower - 0.0001 or xyz.z > j.upper + 0.0001:
				return false
		else:
			var bound := Vector3(j.twist, j.swing, j.swing)
			if xyz.distance_to(xyz.clamp(-bound, bound)) > 0.0001:
				return false
	return true

func _run(side: StringName) -> void:
	var suffix := "_l" if side == &"left" else "_r"
	var ids := [StringName("thigh" + suffix), StringName("calf" + suffix), StringName("foot" + suffix)]
	var heading := Basis(Vector3.UP, 0.74)
	var pelvis := Transform3D(heading, Vector3(2.1, 0.90, -1.7))
	var frame := State.Measurements.new()
	frame.body_poses[&"pelvis"] = pelvis
	var state := State.new(frame)
	for bend: float in [0.25, 0.43, 0.52]:
		var nominal := {ids[0]:Basis(Vector3.RIGHT,bend), ids[1]:Basis(Vector3.RIGHT,-bend*2), ids[2]:Basis(Vector3.RIGHT,bend)}
		var original := _fk(pelvis, ids, nominal)
		var result := solver.solve(state, side, original.origin, original.basis.y, heading)
		var achieved := _fk(pelvis, ids, result)
		_check(achieved.origin.distance_to(original.origin) < 0.0001 and achieved.basis.is_equal_approx(original.basis) and _legal(ids, result),
			"%s squat %.2f rad FK recovers the transformed sole" % [side, bend])
	var neutral := _fk(pelvis, ids, {ids[0]:Basis(Vector3.RIGHT,.42), ids[1]:Basis(Vector3.RIGHT,-.84), ids[2]:Basis(Vector3.RIGHT,.42)})
	var slope := heading * Vector3(0.06, 1, -0.12).normalized()
	for step: Vector3 in [Vector3(0.035, .01, -.075), Vector3(-.04, .005, .07)]:
		var requested := neutral.origin + heading * step
		var result := solver.solve(state, side, requested, slope, heading)
		var achieved := _fk(pelvis, ids, result)
		_check(achieved.origin.distance_to(requested) < 0.001 and achieved.basis.y.dot(slope) > 0.999 and _legal(ids, result),
			"%s reaches a staggered oblique-slope sole" % side)
	var tilted := Transform3D(heading * Basis(Vector3.FORWARD, 0.12), pelvis.origin)
	var leaning := State.Measurements.new()
	leaning.body_poses[&"pelvis"] = tilted
	var steered := Basis(Vector3.UP, 0.11) * heading
	var compensation := solver.solve(State.new(leaning), side, neutral.origin, Vector3.UP, steered)
	var planted := _fk(tilted, ids, compensation)
	_check(planted.origin.distance_to(neutral.origin) < 0.001 and planted.basis.is_equal_approx(steered) and _legal(ids, compensation),
		"%s keeps its sole level and turns the toes under a tilted pelvis" % side)
	for target: Vector3 in [pelvis.origin + Vector3(15,-10,8), pelvis * (Vector3(joints[ids[0]].position) - Vector3(centers[&"pelvis"]))]:
		var result := solver.solve(state, side, target, Vector3.UP, heading)
		_check(result.size() == 3 and _legal(ids, result), "%s unreachable sole produces bounded finite joints" % side)
