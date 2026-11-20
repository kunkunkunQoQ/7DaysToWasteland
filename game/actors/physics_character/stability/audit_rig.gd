extends SceneTree
## Read actual initialized body tensors and joint properties; no active drives.
const CHARACTER := preload("../physics_character.tscn")
const Actor := preload("../physics_character.gd")
const Experiment := preload("experiment_config.gd")

var _out := "user://rig_stability"
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			_out = arg.trim_prefix("--out-dir=")
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		quit(2)
		return
	var actor: Actor = CHARACTER.instantiate()
	actor.config = Experiment.create("baseline")
	actor.get_node("Visual").free()
	root.add_child(actor)
	var neutral := actor.get_state().body_poses
	var rig := actor.get_node("PhysicsRig")
	var segments := {}
	for row: Dictionary in actor.config.build_segments():
		segments[row.id] = row
	# Capture rest frames before gravity advances. Inertia updates after the
	# first actual backend step, which is why the body table is sampled later.
	_joints(actor, rig, segments, neutral)
	_clearances(segments, actor.config.build_joints())
	await physics_frame
	await physics_frame
	_bodies(rig, segments)
	actor.free()
	await process_frame
	print("RIG_AUDIT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)

func _open(stem: String, header: Array) -> FileAccess:
	var f := FileAccess.open(_out.path_join(stem + ".csv"), FileAccess.WRITE)
	if f == null:
		_failures += 1
		printerr("Cannot create ", stem)
		return null
	f.store_csv_line(PackedStringArray(header))
	return f

func _num(x: float) -> String:
	return "%.8f" % x

func _vec(v: Vector3) -> String:
	return "%s %s %s" % [_num(v.x), _num(v.y), _num(v.z)]

func _basis(b: Basis) -> String:
	return "%s | %s | %s" % [_vec(b.x), _vec(b.y), _vec(b.z)]

func _bodies(rig: Node, segments: Dictionary) -> void:
	var f := _open("rig_inertia", ["segment","shape","size_xyz_m","mass_kg","volume_m3","mean_density_kg_m3",
		"principal_I_kg_m2","principal_axes_local_columns","com_local_m","body_local_I_tensor_columns_kg_m2",
		"backend_expected_diag","uniform_solid_expected_diag","max_backend_error_kg_m2","collider_matches_geometry","ccd","linear_damp_body","angular_damp_body"])
	if f == null:
		return
	var total := 0.0
	for id: StringName in rig.bodies:
		var body: RigidBody3D = rig.bodies[id]
		var collider := body.get_node("Collider") as CollisionShape3D
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var row: Dictionary = segments[id]
		var size: Vector3 = row.size
		var m := body.mass
		var expected := Vector3(size.y**2 + size.z**2, size.x**2 + size.z**2, size.x**2 + size.y**2) * (m / 12.0)
		var solid := expected
		var collider_matches := false
		var volume := size.x * size.y * size.z
		if row.shape == &"capsule":
			var radius := size.x * 0.5
			var capsule := collider.shape as CapsuleShape3D
			collider_matches = capsule != null and is_equal_approx(capsule.radius, radius) and is_equal_approx(capsule.height, size.y)
			var length := size.y - 2.0 * radius
			var cylinder := PI * radius**2 * length
			volume = cylinder + 4.0 * PI * radius**3 / 3.0
			var mc := m * cylinder / volume
			var ms := m - mc
			var ix := mc * (3.0 * radius**2 + length**2) / 12.0 + ms * (0.4 * radius**2 + length**2 / 4.0 + 3.0 * length * radius / 8.0)
			solid = Vector3(ix, (0.5 * mc + 0.4 * ms) * radius**2, ix)
		else:
			var box := collider.shape as BoxShape3D
			collider_matches = box != null and box.size.is_equal_approx(size)
		collider_matches = collider_matches and collider.transform.is_equal_approx(Transform3D.IDENTITY)
		var principal := state.inverse_inertia.inverse()
		var axes := state.transform.basis.orthonormalized()
		var local_tensor := axes.transposed() * state.inverse_inertia_tensor.inverse() * axes
		var principal_local := axes.transposed() * state.principal_inertia_axes
		var err := maxf(
			(local_tensor.x - Vector3(expected.x, 0, 0)).length(),
			maxf((local_tensor.y - Vector3(0, expected.y, 0)).length(), (local_tensor.z - Vector3(0, 0, expected.z)).length()))
		total += m
		if not collider_matches or not principal.is_finite() or err > 0.00001 or state.center_of_mass_local.length() > 0.00001:
			_failures += 1
		f.store_csv_line(PackedStringArray([id,row.shape,_vec(size),_num(m),_num(volume),_num(m/volume),
			_vec(principal),_basis(principal_local),_vec(state.center_of_mass_local),_basis(local_tensor),
			_vec(expected),_vec(solid),_num(err),str(collider_matches),str(body.continuous_cd),_num(body.linear_damp),_num(body.angular_damp)]))
	if absf(total - 66.1) > 0.0001:
		_failures += 1

func _joints(actor: Actor, rig: Node, segments: Dictionary, neutral: Dictionary) -> void:
	var f := _open("rig_joints", ["parent","child","type","mass_ratio","anchor_character_m","anchor_parent_local_m",
		"anchor_child_local_m","rest_mismatch_m","joint_basis_character_xyz_columns","axes_orthonormal_error",
		"anchor_to_parent_surface_m","anchor_to_child_surface_m","adjacent_shape_surface_gap_m",
		"actual_collision_exception_both","actual_endpoint_ids_match","angular_lower_deg","angular_upper_deg",
		"linear_xyz_locked","angular_limit_enabled","angular_motors_off","angular_damping_xyz","hinge_bias_limit_bias_relax",
		"joint_solver_priority","node_angular_force_limit_xyz","server_angular_force_limit_xyz",
		"node_motor_force_limit_xyz","server_motor_force_limit_xyz"])
	if f == null:
		return
	for row: Dictionary in actor.config.build_joints():
		var j: Joint3D = rig.joints[row.child]
		var a: RigidBody3D = rig.bodies[row.parent]
		var b: RigidBody3D = rig.bodies[row.child]
		var xform_a: Transform3D = neutral[row.parent]
		var xform_b: Transform3D = neutral[row.child]
		var anchor := j.global_position
		var la: Vector3 = row.position - segments[row.parent].position
		var lb: Vector3 = row.position - segments[row.child].position
		var pa := xform_a * la
		var pb := xform_b * lb
		var mismatch := maxf(pa.distance_to(pb), maxf(pa.distance_to(anchor), pb.distance_to(anchor)))
		var basis := j.transform.basis
		var ortho := maxf(absf(basis.determinant() - 1.0), maxf(absf(basis.x.dot(basis.y)), maxf(absf(basis.y.dot(basis.z)), absf(basis.x.dot(basis.z)))))
		var excluded := j.exclude_nodes_from_collision and a.get_collision_exceptions().has(b) and b.get_collision_exceptions().has(a)
		var endpoints := j.get_node(j.node_a) == a and j.get_node(j.node_b) == b
		var lower: String
		var upper: String
		var damping := ""
		var bias_relax := ""
		var limited := true
		var locked := true
		var passive := true
		var limits_match := true
		var node_limit := ""
		var server_limit := ""
		var node_motor := ""
		var server_motor := ""
		if j is HingeJoint3D:
			var hinge := j as HingeJoint3D
			lower = _num(rad_to_deg(hinge.get_param(HingeJoint3D.PARAM_LIMIT_LOWER)))
			upper = _num(rad_to_deg(hinge.get_param(HingeJoint3D.PARAM_LIMIT_UPPER)))
			bias_relax = _vec(Vector3(hinge.get_param(HingeJoint3D.PARAM_BIAS), hinge.get_param(HingeJoint3D.PARAM_LIMIT_BIAS), hinge.get_param(HingeJoint3D.PARAM_LIMIT_RELAXATION)))
			limited = hinge.get_flag(HingeJoint3D.FLAG_USE_LIMIT)
			passive = not hinge.get_flag(HingeJoint3D.FLAG_ENABLE_MOTOR)
			limits_match = basis.z.is_equal_approx(Vector3.RIGHT) and is_equal_approx(hinge.get_param(HingeJoint3D.PARAM_LIMIT_LOWER),row.lower) and is_equal_approx(hinge.get_param(HingeJoint3D.PARAM_LIMIT_UPPER),row.upper)
		else:
			var lo := Vector3.ZERO
			var hi := Vector3.ZERO
			var damp := Vector3.ZERO
			var node_force := Vector3.ZERO
			var server_force := Vector3.ZERO
			var node_drive := Vector3.ZERO
			var server_drive := Vector3.ZERO
			for i in 3:
				var axis: String = ["x","y","z"][i]
				var param := Callable(j, "get_param_" + axis)
				var flag := Callable(j, "get_flag_" + axis)
				lo[i] = rad_to_deg(param.call(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT))
				hi[i] = rad_to_deg(param.call(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
				damp[i] = param.call(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING)
				node_force[i] = param.call(Generic6DOFJoint3D.PARAM_ANGULAR_FORCE_LIMIT)
				node_drive[i] = param.call(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT)
				server_force[i] = PhysicsServer3D.generic_6dof_joint_get_param(j.get_rid(),i,PhysicsServer3D.G6DOF_JOINT_ANGULAR_FORCE_LIMIT)
				server_drive[i] = PhysicsServer3D.generic_6dof_joint_get_param(j.get_rid(),i,PhysicsServer3D.G6DOF_JOINT_ANGULAR_MOTOR_FORCE_LIMIT)
				locked = locked and flag.call(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT) and is_zero_approx(param.call(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)) and is_zero_approx(param.call(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT))
				limited = limited and flag.call(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)
				passive = passive and not flag.call(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR) and not flag.call(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR)
			lower = _vec(lo)
			upper = _vec(hi)
			damping = _vec(damp)
			var expected := Vector3(row.twist,row.swing,row.swing) * rad_to_deg(1.0)
			limits_match = basis.x.is_equal_approx(Vector3.UP) and lo.is_equal_approx(-expected) and hi.is_equal_approx(expected)
			node_limit = _vec(node_force)
			server_limit = _vec(server_force)
			node_motor = _vec(node_drive)
			server_motor = _vec(server_drive)
		if mismatch > 0.00001 or ortho > 0.00001 or not limits_match or not excluded or not endpoints or not limited or not passive or not locked:
			_failures += 1
		var sa: Dictionary = segments[row.parent]
		var sb: Dictionary = segments[row.child]
		f.store_csv_line(PackedStringArray([row.parent,row.child,j.get_class(),_num(maxf(a.mass,b.mass)/minf(a.mass,b.mass)),
			_vec(j.position),_vec(la),_vec(lb),_num(mismatch),_basis(basis),_num(ortho),
			_num(_surface(sa,la)),_num(_surface(sb,lb)),_num(_gap(sa,sb)),str(excluded),str(endpoints),
			lower,upper,str(locked),str(limited),str(passive),damping,bias_relax,str(j.solver_priority),
			node_limit,server_limit,node_motor,server_motor]))

func _box_sdf(p: Vector3, half_size: Vector3) -> float:
	var q := p.abs() - half_size
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x,maxf(q.y,q.z)),0.0)

func _clearances(segments: Dictionary, joints: Array[Dictionary]) -> void:
	var f := _open("rig_rest_clearances", ["segment_a","segment_b","adjacent","rest_surface_gap_m"])
	if f == null:
		return
	var neighbors := {}
	for joint: Dictionary in joints:
		neighbors[joint.child] = joint.parent
	var ids := segments.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: StringName = ids[i]
			var b: StringName = ids[j]
			var adjacent: bool = neighbors.get(b, &"") == a or neighbors.get(a, &"") == b
			var gap := _gap(segments[a], segments[b])
			if not adjacent and gap < -0.00001:
				_failures += 1
			f.store_csv_line(PackedStringArray([a,b,str(adjacent),_num(gap)]))

func _surface(segment: Dictionary, local: Vector3) -> float:
	var size: Vector3 = segment.size
	if segment.shape == &"box":
		return _box_sdf(local, size * 0.5)
	var radius := size.x * 0.5
	var half_line := size.y * 0.5 - radius
	local.y -= clampf(local.y, -half_line, half_line)
	return local.length() - radius

# Baseline rest poses have parallel local axes. A capsule is the Minkowski sum
# of its central Y segment and a sphere; apply the signed box distance once.
func _gap(a: Dictionary, b: Dictionary) -> float:
	var sizes: Array[Vector3] = []
	var radii := 0.0
	for segment: Dictionary in [a,b]:
		var half: Vector3 = segment.size * 0.5
		if segment.shape == &"capsule":
			radii += half.x
			half = Vector3(0.0, half.y - half.x, 0.0)
		sizes.append(half)
	return _box_sdf(a.position - b.position, sizes[0]+sizes[1]) - radii
