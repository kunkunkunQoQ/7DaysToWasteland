extends RefCounted
## Read-only measurements for the GodotPhysics3D passive-rig test world.

const ANCHOR_BAND_M := 0.012
const ANGLE_BAND_DEG := 6.0
const HOLD_SECONDS := 0.25
const TAIL_SECONDS := 0.5
const GROSS_ANCHOR_M := 0.18

class Link:
	var a: RigidBody3D
	var b: RigidBody3D
	var local_a: Transform3D
	var local_b: Transform3D
	var hinge: bool
	var low: Vector3
	var high: Vector3
	var peak := -1.0
	var peak_sample := {}
	var sum_sq := 0.0
	var angle_sum_sq := 0.0
	var angle_peak := 0.0
	var limit_peak := 0.0
	var omega_peak := 0.0
	var last_bad := -1
	var tail_anchor := PackedFloat64Array()
	var tail_angle := PackedFloat64Array()
	var tail_limit := PackedFloat64Array()
	var tail_omega := PackedVector3Array()

var _links: Array[Link] = []
var _rig: Node3D
var _owned := {}
var _hz: int
var _samples := 0
var _end_tick := -1
var _first_contact := -1
var _impact_tick := -1
var _tail_size: int
var _invalid := 0
var _trace: FileAccess
var _previous_contacts := {}
var _previous_velocity := {}

func setup(rig: Node3D, config: Resource, hz: int, trace_file: FileAccess = null) -> void:
	_rig = rig
	_hz = hz
	_trace = trace_file
	_tail_size = maxi(1, ceili(hz * TAIL_SECONDS))
	var centers := {}
	for segment: Dictionary in config.build_segments():
		centers[segment.id] = segment.position
		var body: RigidBody3D = rig.bodies[segment.id]
		_owned[body.get_instance_id()] = true
	for row: Dictionary in config.build_joints():
		var link := Link.new()
		link.a = rig.bodies[row.parent]
		link.b = rig.bodies[row.child]
		link.local_a = Transform3D(row.basis, row.position - centers[row.parent])
		link.local_b = Transform3D(row.basis, row.position - centers[row.child])
		# An axial 6DOF variant still uses the backend's XYZ convention even
		# when its anatomical row describes a one-axis knee or elbow.
		var joint: Joint3D = rig.joints[row.child]
		link.hinge = joint is HingeJoint3D
		if link.hinge:
			link.low.z = PhysicsServer3D.hinge_joint_get_param(joint.get_rid(), PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER)
			link.high.z = PhysicsServer3D.hinge_joint_get_param(joint.get_rid(), PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER)
		else:
			for axis in 3:
				link.low[axis] = PhysicsServer3D.generic_6dof_joint_get_param(joint.get_rid(), axis, PhysicsServer3D.G6DOF_JOINT_ANGULAR_LOWER_LIMIT)
				link.high[axis] = PhysicsServer3D.generic_6dof_joint_get_param(joint.get_rid(), axis, PhysicsServer3D.G6DOF_JOINT_ANGULAR_UPPER_LIMIT)
		link.tail_anchor.resize(_tail_size)
		link.tail_angle.resize(_tail_size)
		link.tail_limit.resize(_tail_size)
		link.tail_omega.resize(_tail_size)
		_links.append(link)
	if _trace != null:
		_trace.store_csv_line(PackedStringArray(["tick", "parent", "joint", "anchor_m", "angular_error_deg",
			"limit_violation_deg", "angles_xyz_deg", "hinge_axis_error_deg", "omega_child_minus_parent_joint_frame_rad_s",
			"parent_v_world_m_s", "child_v_world_m_s", "parent_w_world_rad_s", "child_w_world_rad_s",
			"parent_external", "child_external", "whole_external_segments", "parent_impulse_Ns", "child_impulse_Ns"]))

## Returns signed solver-frame coordinates and geometric errors, all in radians.
## Angular error measures a correction into the admissible set. Legal flexion costs zero.
static func measure_angles(a: Basis, b: Basis, hinge: bool, low: Vector3, high: Vector3) -> Dictionary:
	var relative := b.transposed() * a
	var angles: Vector3
	var target: Basis
	var axis_error := 0.0
	if hinge:
		angles = Vector3(0, 0, atan2(b.y.dot(a.x), b.y.dot(a.y)))
		target = Basis(Vector3.BACK, clampf(angles.z, low.z, high.z))
		axis_error = a.z.angle_to(b.z)
	else:
		angles = relative.get_euler(EULER_ORDER_XYZ)
		target = Basis.from_euler(angles.clamp(low, high), EULER_ORDER_XYZ)
	var excess := (angles - angles.clamp(low, high)).abs()
	var q := (target.transposed() * relative).get_rotation_quaternion()
	var correction := 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))
	return {"angles": angles, "correction": correction, "violation": maxf(excess.x, maxf(excess.y, excess.z)),
		"axis_error": axis_error}

func _contacts() -> Dictionary:
	var out := {}
	for id: StringName in _rig.bodies:
		var body: RigidBody3D = _rig.bodies[id]
		var direct := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if direct == null:
			continue
		var objects := PackedStringArray()
		var impulse := 0.0
		for i in direct.get_contact_count():
			if _owned.has(direct.get_contact_collider_id(i)):
				continue
			var other := direct.get_contact_collider_object(i) as Node
			var label := String(other.name) if other != null else "external"
			if not objects.has(label):
				objects.append(label)
			impulse += direct.get_contact_impulse(i).length()
		if not objects.is_empty():
			out[id] = {"objects": "|".join(objects), "impulse": impulse}
	return out

func sample(tick: int, last_impact_tick: int = -1) -> void:
	var contacts := _contacts()
	if _first_contact < 0 and not contacts.is_empty():
		_first_contact = tick
	_impact_tick = maxi(_impact_tick, last_impact_tick)
	_end_tick = tick
	var slot := _samples % _tail_size
	_samples += 1
	var velocities := {}
	for id: StringName in _rig.bodies:
		var body: RigidBody3D = _rig.bodies[id]
		velocities[id] = [body.linear_velocity, body.angular_velocity]
	for link in _links:
		var left := link.a.global_transform * link.local_a
		var right := link.b.global_transform * link.local_b
		if not (left.is_finite() and right.is_finite() and link.a.linear_velocity.is_finite()
				and link.b.linear_velocity.is_finite() and link.a.angular_velocity.is_finite() and link.b.angular_velocity.is_finite()):
			_invalid += 1
			continue
		var a := left.basis.orthonormalized()
		var b := right.basis.orthonormalized()
		var measurement := measure_angles(a, b, link.hinge, link.low, link.high)
		var anchor := left.origin.distance_to(right.origin)
		var angle := rad_to_deg(measurement.correction)
		var limit := rad_to_deg(measurement.violation)
		var omega := a.transposed() * (link.b.angular_velocity - link.a.angular_velocity)
		link.sum_sq += anchor * anchor
		link.angle_sum_sq += angle * angle
		link.angle_peak = maxf(link.angle_peak, angle)
		link.limit_peak = maxf(link.limit_peak, limit)
		link.omega_peak = maxf(link.omega_peak, omega.length())
		link.tail_anchor[slot] = anchor
		link.tail_angle[slot] = angle
		link.tail_limit[slot] = limit
		link.tail_omega[slot] = omega
		if anchor > ANCHOR_BAND_M or angle > ANGLE_BAND_DEG:
			link.last_bad = tick
		var ca: Dictionary = contacts.get(link.a.name, {})
		var cb: Dictionary = contacts.get(link.b.name, {})
		if anchor > link.peak:
			link.peak = anchor
			var pa: Array = _previous_velocity.get(link.a.name, velocities[link.a.name])
			var pb: Array = _previous_velocity.get(link.b.name, velocities[link.b.name])
			link.peak_sample = {"peak_tick": tick, "peak_parent_v_world_m_s": link.a.linear_velocity,
				"peak_child_v_world_m_s": link.b.linear_velocity, "peak_parent_w_world_rad_s": link.a.angular_velocity,
				"peak_child_w_world_rad_s": link.b.angular_velocity, "peak_relative_w_joint_rad_s": omega,
				"previous_parent_v_world_m_s": pa[0], "previous_child_v_world_m_s": pb[0],
				"previous_parent_w_world_rad_s": pa[1], "previous_child_w_world_rad_s": pb[1],
				"peak_parent_external": ca.get("objects", ""), "peak_child_external": cb.get("objects", ""),
				"peak_parent_impulse_Ns": ca.get("impulse", 0.0), "peak_child_impulse_Ns": cb.get("impulse", 0.0),
				"peak_external_segments": "|".join(contacts.keys()),
				"previous_external_segments": "|".join(_previous_contacts.keys())}
		if _trace != null:
			_trace.store_csv_line(_strings([tick, link.a.name, link.b.name, anchor, angle, limit,
				measurement.angles * (180.0 / PI), rad_to_deg(measurement.axis_error), omega,
				link.a.linear_velocity, link.b.linear_velocity, link.a.angular_velocity, link.b.angular_velocity,
				ca.get("objects", ""), cb.get("objects", ""), contacts.size(), ca.get("impulse", 0.0), cb.get("impulse", 0.0)]))
	_previous_contacts = contacts
	_previous_velocity = velocities

func _tail(link: Link) -> Dictionary:
	var count := mini(_samples, _tail_size)
	var first := (_samples - count) % _tail_size
	var anchor_sq := 0.0
	var angle_sq := 0.0
	var omega_sq := 0.0
	var peak_limit := 0.0
	var amin := INF
	var amax := 0.0
	var previous_sign := Vector3i.ZERO
	var reversals := Vector3i.ZERO
	var extremum := link.tail_anchor[first]
	var rising := true
	var anchor_reversals := 0
	for i in count:
		var slot := (first + i) % _tail_size
		var value := link.tail_anchor[slot]
		var angle := link.tail_angle[slot]
		var omega := link.tail_omega[slot]
		amin = minf(amin, value)
		amax = maxf(amax, value)
		anchor_sq += value * value
		angle_sq += angle * angle
		omega_sq += omega.length_squared()
		peak_limit = maxf(peak_limit, link.tail_limit[slot])
		for axis in 3:
			if absf(omega[axis]) < 0.5:
				continue
			var sign_now := int(signf(omega[axis]))
			if previous_sign[axis] != 0 and previous_sign[axis] != sign_now:
				reversals[axis] += 1
			previous_sign[axis] = sign_now
		if (rising and value < extremum - 0.002) or (not rising and value > extremum + 0.002):
			anchor_reversals += 1
			rising = not rising
			extremum = value
		else:
			extremum = maxf(extremum, value) if rising else minf(extremum, value)
	var speed := sqrt(omega_sq / count)
	var angular_reversals := maxi(reversals.x, maxi(reversals.y, reversals.z))
	return {"residual_m": sqrt(anchor_sq / count), "residual_angular_deg": sqrt(angle_sq / count),
		"tail_peak_limit_deg": peak_limit, "tail_anchor_span_m": amax - amin, "tail_anchor_reversals": anchor_reversals,
		"tail_rel_omega_rad_s": speed, "tail_omega_reversals": angular_reversals,
		"sustained_oscillation": (anchor_reversals >= 4 and amax - amin > 0.01) or (angular_reversals >= 4 and speed > 1.0)}

func finish() -> Dictionary:
	var rows: Array[Dictionary] = []
	var body := {"samples": _samples, "finite": _invalid == 0 and _samples > 0, "invalid_joint_samples": _invalid,
		"first_external_tick": _first_contact, "impact_tick": maxi(_impact_tick, _first_contact), "peak_joint": "",
		"peak_tick": -1, "max_anchor_m": -1.0, "rms_anchor_m": 0.0, "max_angular_error_deg": 0.0,
		"max_limit_deg": 0.0, "max_residual_m": 0.0, "max_residual_angular_deg": 0.0,
		"max_tail_anchor_span_m": 0.0, "max_tail_rel_omega_rad_s": 0.0, "max_recovery_s": -1.0,
		"unrecovered_joints": 0, "oscillating_joints": 0, "pass": false}
	if _samples == 0:
		return {"joints": rows, "body": body}
	var sum_sq := 0.0
	for link in _links:
		var row := {"joint": link.b.name, "parent": link.a.name, "peak_anchor_m": link.peak,
			"rms_anchor_m": sqrt(link.sum_sq / _samples), "peak_angular_error_deg": link.angle_peak,
			"rms_angular_error_deg": sqrt(link.angle_sum_sq / _samples), "peak_limit_deg": link.limit_peak,
			"peak_relative_omega_rad_s": link.omega_peak}
		row.merge(link.peak_sample)
		row.merge(_tail(link))
		var stable_start := maxi(body.impact_tick, link.last_bad + 1)
		var can_measure: bool = body.impact_tick >= 0 and _end_tick - stable_start + 1 >= ceili(_hz * HOLD_SECONDS)
		row["recovery_s"] = float(stable_start - int(body.impact_tick)) / _hz if can_measure else -1.0
		rows.append(row)
		if link.peak > float(body.max_anchor_m):
			body.max_anchor_m = link.peak
			body.peak_joint = link.b.name
			body.peak_tick = link.peak_sample.get("peak_tick", -1)
		sum_sq += link.sum_sq
		body.max_angular_error_deg = maxf(body.max_angular_error_deg, link.angle_peak)
		body.max_limit_deg = maxf(body.max_limit_deg, link.limit_peak)
		body.max_residual_m = maxf(body.max_residual_m, row.residual_m)
		body.max_residual_angular_deg = maxf(body.max_residual_angular_deg, row.residual_angular_deg)
		body.max_tail_anchor_span_m = maxf(body.max_tail_anchor_span_m, row.tail_anchor_span_m)
		body.max_tail_rel_omega_rad_s = maxf(body.max_tail_rel_omega_rad_s, row.tail_rel_omega_rad_s)
		body.max_recovery_s = maxf(body.max_recovery_s, row.recovery_s)
		body.unrecovered_joints += int(not can_measure)
		body.oscillating_joints += int(row.sustained_oscillation)
	body.rms_anchor_m = sqrt(sum_sq / (_links.size() * _samples))
	if body.unrecovered_joints > 0:
		body.max_recovery_s = -1.0
	body["pass"] = body.finite and body.max_anchor_m < GROSS_ANCHOR_M and body.unrecovered_joints == 0 and body.oscillating_joints == 0
	return {"joints": rows, "body": body}

static func _strings(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(str(value))
	return result

static func write_table(file: FileAccess, rows: Array) -> void:
	if rows.is_empty():
		return
	var keys: Array = rows[0].keys()
	file.store_csv_line(_strings(keys))
	for row: Dictionary in rows:
		var values := []
		for key in keys:
			values.append(row.get(key, ""))
		file.store_csv_line(_strings(values))
