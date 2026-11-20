extends RefCounted
## Independent geometric witness for the rig's transformed capsules and boxes.
## Depth is the minimum separation along a separating axis, in world metres.

const Rig := preload("../body/physics_rig.gd")
const Config := preload("../config/physics_character_config.gd")
const OVERLAP_M := 0.03

class Segment:
	var id: StringName
	var body: RigidBody3D
	var half: Vector3
	var radius: float
	var shaft: float
	var mount := Transform3D.IDENTITY
	var pose: Transform3D
	var bounds: AABB

	func update() -> void:
		pose = body.global_transform * mount
		var extent := pose.basis.y.abs() * shaft + Vector3.ONE * radius
		if radius == 0.0:
			extent = pose.basis.x.abs() * half.x + pose.basis.y.abs() * half.y + pose.basis.z.abs() * half.z
		bounds = AABB(pose.origin - extent, extent * 2.0)

var _parts: Array[Segment] = []
var _bodies: Array[RigidBody3D] = []
var _pairs: Array[Vector2i] = []
var _floor_peak := 0.0
var _self_peak := 0.0
var _floor_tick := 0
var _self_tick := 0
var _floor_part := ""
var _self_pair := ""
var _floor_tail := 0.0
var _self_tail := 0.0
var _start_self := 0.0
var _start_floor := 0.0
var _span := 0
var _max_span := 0
var trace: FileAccess

func setup(rig: Rig, config: Config) -> void:
	var neighbours := {}
	for joint: Dictionary in config.build_joints():
		neighbours[joint.child] = joint.parent
	for data: Dictionary in config.build_segments():
		var body: RigidBody3D = rig.bodies[data.id]
		_bodies.append(body)
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider == null or collider.disabled:
				continue
			var part := Segment.new()
			part.id = data.id
			part.body = body
			part.mount = collider.transform
			if collider.shape is CapsuleShape3D:
				var capsule := collider.shape as CapsuleShape3D
				part.radius = capsule.radius
				part.shaft = capsule.height * 0.5 - capsule.radius
			else:
				part.half = (collider.shape as BoxShape3D).size * 0.5
			_parts.append(part)
	for i in _parts.size():
		for j in range(i + 1, _parts.size()):
			var a := _parts[i].id
			var b := _parts[j].id
			if a != b and neighbours.get(a) != b and neighbours.get(b) != a:
				_pairs.append(Vector2i(i,j))

func sample(tick: int, in_tail: bool) -> void:
	var floor_now := 0.0
	var self_now := 0.0
	var floor_part := ""
	var self_pair := ""
	for part: Segment in _parts:
		part.update()
		var depth := maxf(0.0, -part.bounds.position.y)
		if depth > floor_now:
			floor_now = depth
			floor_part = String(part.id)
		if depth > _floor_peak:
			_floor_peak = depth
			_floor_part = String(part.id)
			_floor_tick = tick
	for pair: Vector2i in _pairs:
		var a := _parts[pair.x]
		var b := _parts[pair.y]
		if not a.bounds.intersects(b.bounds):
			continue
		var depth := _penetration(a, b)
		if depth > self_now:
			self_now = depth
			self_pair = "%s/%s" % [a.id, b.id]
		if depth > _self_peak:
			_self_peak = depth
			_self_pair = "%s/%s" % [a.id, b.id]
			_self_tick = tick
	if tick == 0:
		_start_self = self_now
		_start_floor = floor_now
	if in_tail:
		_floor_tail = maxf(_floor_tail, floor_now)
		_self_tail = maxf(_self_tail, self_now)
	_span = _span + 1 if maxf(floor_now, self_now) > OVERLAP_M else 0
	_max_span = maxi(_max_span, _span)
	if trace != null:
		_trace_frame(tick, floor_part, floor_now, self_pair, self_now)

func _trace_frame(tick: int, floor_part: String, floor_m: float, self_pair: String, self_m: float) -> void:
	if tick == 0:
		trace.store_csv_line(PackedStringArray(["tick", "geometric_floor_part", "geometric_floor_m", "geometric_self_pair", "geometric_self_m",
			"manifold_floor_part", "manifold_floor_m", "manifold_self_pair", "manifold_self_m", "contact_limit_bodies"]))
	var floor_manifold := 0.0
	var self_manifold := 0.0
	var floor_name := ""
	var pair_name := ""
	var at_limit := 0
	for body in _bodies:
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state == null:
			continue
		at_limit += int(state.get_contact_count() == body.max_contacts_reported)
		for i in state.get_contact_count():
			# GodotPhysics3D exposes the witness pair in world coordinates.
			var d := (state.get_contact_collider_position(i) - state.get_contact_local_position(i)).dot(state.get_contact_local_normal(i))
			var other := state.get_contact_collider_object(i) as Node
			if other == null:
				continue
			if other.name == &"Ground" and d > floor_manifold:
				floor_manifold = d
				floor_name = String(body.name)
			elif other.get_parent() == body.get_parent() and d > self_manifold:
				self_manifold = d
				pair_name = "%s/%s" % [body.name, other.name]
	trace.store_csv_line(PackedStringArray([str(tick), floor_part, str(floor_m), self_pair, str(self_m), floor_name,
		str(floor_manifold), pair_name, str(self_manifold), str(at_limit)]))

func finish(hz: int) -> Dictionary:
	var duration := float(_max_span) / hz
	return {"floor_peak_m":_floor_peak, "floor_tick":_floor_tick, "floor_part":_floor_part,
		"self_peak_m":_self_peak, "self_tick":_self_tick, "self_pair":_self_pair,
		"floor_tail_m":_floor_tail, "self_tail_m":_self_tail, "floor_spawn_m":_start_floor, "self_spawn_m":_start_self,
		"penetration_duration_over_3cm_s":duration,
		"penetration_pass":maxf(_floor_tail, _self_tail) <= 0.02 and duration <= 0.12 and maxf(_floor_peak, _self_peak) <= 0.12}

static func _penetration(a: Segment, b: Segment) -> float:
	if a.radius == 0.0 and b.radius == 0.0:
		return _box_box(a, b)
	if a.radius > 0.0 and b.radius > 0.0:
		var ad := a.pose.basis.y * a.shaft
		var bd := b.pose.basis.y * b.shaft
		var points := Geometry3D.get_closest_points_between_segments(a.pose.origin-ad, a.pose.origin+ad,
			b.pose.origin-bd, b.pose.origin+bd)
		return maxf(0.0, a.radius + b.radius - points[0].distance_to(points[1]))
	return _capsule_box(a, b) if a.radius > 0.0 else _capsule_box(b, a)

static func _radius_on_axis(box: Segment, axis: Vector3) -> float:
	return absf(axis.dot(box.pose.basis.x)) * box.half.x + absf(axis.dot(box.pose.basis.y)) * box.half.y + absf(axis.dot(box.pose.basis.z)) * box.half.z

static func _box_box(a: Segment, b: Segment) -> float:
	var axes: Array[Vector3] = [a.pose.basis.x, a.pose.basis.y, a.pose.basis.z, b.pose.basis.x, b.pose.basis.y, b.pose.basis.z]
	for i in 3:
		for j in 3:
			axes.append(a.pose.basis[i].cross(b.pose.basis[j]))
	var nearest := INF
	var separation := b.pose.origin - a.pose.origin
	for raw in axes:
		if raw.length_squared() < 1e-12:
			continue
		var axis := raw.normalized()
		var margin := _radius_on_axis(a, axis) + _radius_on_axis(b, axis) - absf(axis.dot(separation))
		if margin <= 0.0:
			return 0.0
		nearest = minf(nearest, margin)
	return nearest

static func _capsule_box(cap: Segment, box: Segment) -> float:
	var inverse := box.pose.affine_inverse()
	var center := inverse * cap.pose.origin
	var half_axis := inverse.basis * cap.pose.basis.y * cap.shaft
	var start := center - half_axis
	var delta := 2.0 * half_axis
	var h := box.half
	# Squared point-to-box distance is quadratic between slab crossings.
	var cuts: Array[float] = [0.0, 1.0]
	for i in 3:
		if absf(delta[i]) < 1e-10:
			continue
		for face: float in [-h[i], h[i]]:
			var t := (face - start[i]) / delta[i]
			if t > 0.0 and t < 1.0:
				cuts.append(t)
	cuts.sort()
	var closest_sq := INF
	for i in cuts.size() - 1:
		var mid := start + delta * (0.5 * (cuts[i] + cuts[i+1]))
		var derivative := 0.0
		var norm_sq := 0.0
		for k in 3:
			if absf(mid[k]) > h[k]:
				derivative += (start[k] - signf(mid[k]) * h[k]) * delta[k]
				norm_sq += delta[k] * delta[k]
		var t := cuts[i] if norm_sq == 0.0 else clampf(-derivative / norm_sq, cuts[i], cuts[i+1])
		var point := start + t * delta
		closest_sq = minf(closest_sq, point.distance_squared_to(point.clamp(-h, h)))
	if closest_sq > 1e-12:
		return maxf(0.0, cap.radius - sqrt(closest_sq))
	# Inside the Minkowski box+segment, its faces have three box axes and
	# three shaft/edge cross axes. The swept sphere expands every face by r.
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for k in 3:
		axes.append(half_axis.cross(axes[k]))
	var inside := INF
	for raw in axes:
		if raw.length_squared() < 1e-12:
			continue
		var axis := raw.normalized()
		inside = minf(inside, axis.abs().dot(h) + absf(axis.dot(half_axis)) - absf(axis.dot(center)))
	return cap.radius + maxf(inside, 0.0)
