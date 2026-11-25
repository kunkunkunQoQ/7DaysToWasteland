extends Node3D

signal struck(id, damage: float, point: Vector3)
signal crown_contact(point: Vector3)
signal crown_swing
signal impacted(point: Vector3)
signal settled(wood_point: Vector3)

const WARNING := 0.54
const LEAN := 0.048
const SETTLE_TIME := 0.52
const CONTACT_STEP := PI / 36.0
const MAX_TILT := PI * 0.89
const SOFT_RESOURCES := ["fallen_stick", "pebble", "grass", "reeds", "pondweed", "silt",
	"driftwood", "brush", "herb_patch", "reed_bed", "cactus"]

var elapsed := 0.0
var _pivot := Vector3.ZERO
var _axis := Vector3.RIGHT
var _forward := Vector3.FORWARD
var _height := 1.0
var _radius := 0.15
var _spread := 1.0
var _ground: Callable
var _targets: Callable
var _plan: Dictionary
var _previous_feet := {}
var _struck := {}
var _branches := PackedVector3Array()
var _limbs: Array[Dictionary] = []
var _fall_time := 1.4
var _impact_time := 0.0
var _crown_time := INF
var _end_angle := 0.0
var _configured := false
var _finished := false

# Mesh children use the original standing orientation with their cut face at local zero.
# The host sends get_plan() with the spawn. Replicas need neither terrain nor targets.
func setup(pivot_world: Vector3, direction: Vector3, height: float, trunk_radius: float,
		crown_radius: float, ground_at: Callable, targets: Callable = Callable(),
		plan: Dictionary = {}, start_elapsed: float = 0.0, exclude: Array[RID] = []) -> void:
	_finished = false
	_previous_feet.clear()
	_struck.clear()
	_crown_time = INF
	_pivot = pivot_world
	_forward = direction.slide(Vector3.UP).normalized()
	if _forward.is_zero_approx():
		_forward = Vector3.FORWARD
	_axis = Vector3.UP.cross(_forward)
	_height = maxf(height, 0.5)
	_radius = clampf(trunk_radius, 0.045, _height * 0.18)
	_spread = maxf(crown_radius, _radius)
	_ground = ground_at
	_targets = targets
	_fall_time = clampf(0.53 * sqrt(_height), 1.10, 2.20)
	global_transform = Transform3D(Basis.IDENTITY, _pivot)
	if plan.is_empty():
		_build_branches()
		_plan = _trace_fall(exclude)
	else:
		_plan = plan.duplicate()
		if _targets.is_valid():
			_build_branches()
	if _targets.is_valid():
		_build_limbs()
	_end_angle = float(_plan.angle)
	_impact_time = _time_at(_end_angle)
	if float(_plan.crown_angle) >= 0.0:
		_crown_time = _time_at(float(_plan.crown_angle))
	elapsed = maxf(0.0, start_elapsed)
	global_basis = Basis(_axis, _angle_at(elapsed))
	_configured = true

func point_along(fraction: float) -> Vector3:
	return _pivot + global_basis.y * (_height * clampf(fraction, 0.0, 1.0))

func get_plan() -> Dictionary:
	return _plan.duplicate()

func _time_at(angle: float) -> float:
	return WARNING + _fall_time * pow(maxf(0.0, (angle - LEAN) / (PI * 0.5 - LEAN)), 1.0 / 2.15)

func _angle_at(time: float) -> float:
	if time < WARNING:
		var u := time / WARNING
		# Tension first pulls against the hinge. The trunk then leans into its cut.
		return LEAN * smoothstep(0.0, 1.0, u) - 0.035 * sin(PI * u)
	if time < _impact_time:
		return LEAN + (PI * 0.5 - LEAN) * pow((time - WARNING) / _fall_time, 2.15)
	var recovery := clampf((time - _impact_time) / SETTLE_TIME, 0.0, 1.0)
	var lift := minf(0.078, _end_angle * 0.065)
	return _end_angle - lift * absf(sin(recovery * TAU)) * pow(1.0 - recovery, 2.3)

# Retain the leading branch in each height/width band of the actual cut mesh. Low
# fir skirts can brush the ground long before the upper branches carry any weight.
func _build_branches() -> void:
	var leading := {}
	for child in get_children():
		if not child is MeshInstance3D or child.mesh == null:
			continue
		for surface in child.mesh.get_surface_count():
			var vertices: PackedVector3Array = child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var p: Vector3 = child.transform * vertex
				var along := p.dot(_forward)
				if p.y < _height * 0.055 or along < _radius * 1.15:
					continue
				var band := Vector2i(clampi(int(p.y / _height * 5.0), 0, 4),
					clampi(int((p.dot(_axis) / _spread + 1.0) * 1.5), 0, 2))
				if not leading.has(band) or along > _forward.dot(leading[band]):
					leading[band] = p
	_branches = PackedVector3Array(leading.values())
	if _branches.is_empty():
		_branches.append(Vector3.UP * _height * 0.58 + _forward * _spread)
		_branches.append(Vector3.UP * _height * 0.8 + _forward * _spread * 0.62)

func _trace_fall(exclude: Array[RID]) -> Dictionary:
	var wood := PackedVector3Array()
	for i in range(1, 13):
		var u := i / 12.0
		wood.append(Vector3.UP * (_height * u) + _forward * _radius * lerpf(1.0, 0.21, u))
	for tip in _branches:
		if tip.y >= _height * 0.46:
			wood.append(Vector3.UP * tip.y + tip.slide(Vector3.UP) * 0.33)
	var space := get_world_3d().direct_space_state
	var ignored: Array[RID] = exclude.duplicate()
	var has_obstacles := _collect_obstacles(space, ignored)
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 2  # Scenery, bedrock and built structures.
	ray.exclude = ignored
	var capsule := CapsuleShape3D.new()
	capsule.radius = _radius * 0.69
	capsule.height = maxf(_height * 0.88, capsule.radius * 2.0)
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = capsule
	shape.exclude = ignored
	shape.collision_mask = 2
	var angle := 0.0
	var crown_angle := -1.0
	var crown_point := Vector3.ZERO
	var impact_point := _pivot
	var support := {}
	while angle < MAX_TILT:
		var next := minf(angle + CONTACT_STEP, MAX_TILT)
		var hard := _first_touch(wood, angle, next, space, ray, has_obstacles)
		# The full shaft also catches narrow posts between its height samples.
		shape.transform = _shaft_pose(next)
		var rest := space.get_rest_info(shape) if has_obstacles else {}
		if not rest.is_empty():
			var low := angle
			var high := next
			for i in 6:
				var mid := (low + high) * 0.5
				shape.transform = _shaft_pose(mid)
				var sample := space.get_rest_info(shape)
				if sample.is_empty():
					low = mid
				else:
					rest = sample
					high = mid
			if hard.is_empty() or high < float(hard.angle):
				hard = {"angle":high, "point":rest.point, "body":instance_from_id(rest.collider_id)}
		if not hard.is_empty():
			next = maxf(LEAN, float(hard.angle))
			impact_point = hard.point
			var body: Object = hard.get("body")
			if is_instance_valid(body):
				match str(body.get_meta("kind","")):
					"block": support = {"block":body.get_meta("block")}
					"poi_wall": support = {"cell":body.get_meta("cell"),"id":body.get_meta("site_id")}
		if crown_angle < 0.0:
			var soft := _first_touch(_branches, angle, next, space, ray, has_obstacles)
			if not soft.is_empty():
				crown_angle = maxf(LEAN, float(soft.angle))
				crown_point = soft.point
		angle = next
		if not hard.is_empty():
			break
		impact_point = _pivot + Basis(_axis, angle) * (Vector3.UP * _height)
	var wood_point := _pivot + Basis(_axis, angle) * (Vector3.UP * (_height * 0.47))
	if _ground.is_valid():
		wood_point.y = float(_ground.call(wood_point))
	return {"angle":angle, "impact":impact_point, "crown_angle":crown_angle,
		"crown":crown_point, "wood":wood_point, "support":support}

func impact_speed() -> float:
	var u := maxf(0.0,(_impact_time-WARNING)/_fall_time)
	var omega := 2.15 * (PI*0.5-LEAN) / _fall_time * pow(u,1.15)
	return omega * (Vector3(_plan.impact)-_pivot).slide(_axis).length()

# Query the fall corridor once. Crops, dropped items and soft harvest nodes share
# the scenery layer with walls, so omit their RIDs from the subsequent arc queries.
func _collect_obstacles(space: PhysicsDirectSpaceState3D, ignored: Array[RID]) -> bool:
	var box := BoxShape3D.new()
	var reach := _height + _spread
	box.size = Vector3(_spread * 2.3, reach * 2.0, reach + _spread * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 2
	query.transform = Transform3D(Basis.looking_at(_forward), _pivot + _forward * reach * 0.5)
	var seen: Array[RID] = ignored.duplicate()
	var has_solid := false
	while true:
		query.exclude = seen
		var nearby := space.intersect_shape(query, 64)
		for hit in nearby:
			var body: Object = hit.collider
			var kind: String = str(body.get_meta("kind", ""))
			if not body is StaticBody3D or kind in ["crop", "drop", "buoy"] or (
					kind == "resource" and body.get_meta("resource", "") in SOFT_RESOURCES):
				ignored.append(hit.rid)
			else:
				has_solid = true
			seen.append(hit.rid)
		if nearby.size() < 64:
			break
	return has_solid

func _shaft_pose(angle: float) -> Transform3D:
	var rotation_basis := Basis(_axis, angle)
	return Transform3D(rotation_basis, _pivot + rotation_basis.y * _height * 0.49)

# Each tip describes a short circular arc. Trace its chord against obstacles,
# then bisect the arc against the same deformed heightfield the actors walk on.
func _first_touch(points: PackedVector3Array, angle: float, next: float,
		space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, has_obstacles: bool) -> Dictionary:
	var first := INF
	var contact := Vector3.ZERO
	var body: Object
	var old_basis := Basis(_axis, angle)
	var new_basis := Basis(_axis, next)
	for local in points:
		var start := _pivot + old_basis * local
		var end := _pivot + new_basis * local
		ray.from = start
		ray.to = end
		var hit := space.intersect_ray(ray) if has_obstacles else {}
		if not hit.is_empty():
			var fraction := start.distance_to(hit.position) / maxf(start.distance_to(end), 0.0001)
			var hit_angle := lerpf(angle, next, clampf(fraction, 0.0, 1.0))
			if hit_angle < first:
				first = hit_angle
				contact = hit.position
				body = hit.collider
		if _ground.is_valid() and end.y <= float(_ground.call(end)):
			var low := angle
			var high := next
			for i in 7:
				var mid := (low + high) * 0.5
				var probe := _pivot + Basis(_axis, mid) * local
				if probe.y > float(_ground.call(probe)):
					low = mid
				else:
					high = mid
			if high < first:
				first = high
				contact = _pivot + Basis(_axis, high) * local
				contact.y = float(_ground.call(contact))
				body = null
	return {} if is_inf(first) else {"angle":first, "point":contact,"body":body}

func advance(delta: float) -> void:
	if not _configured or _finished or delta <= 0.0:
		return
	var before := elapsed
	elapsed += delta
	global_basis = Basis(_axis, _angle_at(elapsed))
	if _targets.is_valid() and before < _impact_time:
		_check_targets(before, elapsed)
	var shaking := _time_at(0.58)
	if _end_angle >= 0.58 and before < shaking and elapsed >= shaking: crown_swing.emit()
	if before < _crown_time and elapsed >= _crown_time:
		crown_contact.emit(_plan.crown)
	if before < _impact_time and elapsed >= _impact_time:
		impacted.emit(_plan.impact)
	if elapsed >= _impact_time + SETTLE_TIME:
		_finished = true
		settled.emit(_plan.wood)

func _check_targets(before: float, now: float) -> void:
	var last_feet := {}
	var span := maxf(0.00001, now - before)
	var start := maxf(before, WARNING)
	var end := minf(now, _impact_time)
	for actor: Dictionary in _targets.call():
		var id = actor.id
		var feet: Vector3 = actor.feet
		last_feet[id] = feet
		if _struck.has(id) or start >= end:
			continue
		var old: Vector3 = _previous_feet.get(id, feet)
		# A respawn/teleport does not sweep a body across the entire forest.
		if old.distance_to(feet) > 1.5 + span * 30.0:
			old = feet
		var radius := maxf(0.04, float(actor.radius))
		var height := maxf(radius * 2.0, float(actor.height))
		var nearest := feet if old.is_equal_approx(feet) else Geometry3D.get_closest_point_to_segment(_pivot, old, feet)
		if nearest.distance_squared_to(_pivot) > pow(_height + _spread + height, 2.0):
			continue
		var start_feet := old.lerp(feet, (start - before) / span)
		var end_feet := old.lerp(feet, (end - before) / span)
		_sweep_actor(id, start_feet, end_feet, height, radius, start, end)
	_previous_feet = last_feet

func _build_limbs() -> void:
	_limbs.clear()
	for segment in 3:
		var t0 := 0.025 if segment == 0 else segment / 3.0
		var t1 := (segment + 1) / 3.0
		_limbs.append({"a":Vector3.UP * (_height * t0), "b":Vector3.UP * (_height * t1),
			"radius":_radius * lerpf(1.0, 0.23, t0), "strength":1.0})
	for tip in _branches:
		var root := Vector3.UP * (tip.y * 0.85)
		_limbs.append({"a":root, "b":root.lerp(tip, 0.67), "radius":_radius * 0.32, "strength":0.6})

# Advance by the measured gap divided by the maximum relative closing speed.
# This catches actors crossing between ticks without widening a limb's hit area.
func _sweep_actor(id, old: Vector3, feet: Vector3, height: float, radius: float,
		start: float, end: float) -> void:
	var peak_rate := (PI * 0.5 - LEAN) * 2.15 / _fall_time
	var max_omega := peak_rate * pow((end - WARNING) / _fall_time, 1.15)
	var span := end - start
	var body_speed := old.distance_to(feet) / span
	var earliest := end
	var damage := 0.0
	var point := Vector3.ZERO
	for limb in _limbs:
		var a: Vector3 = limb.a
		var b: Vector3 = limb.b
		var reach := maxf(a.slide(_axis).length(), b.slide(_axis).length())
		if max_omega * reach < 1.45:
			continue
		var max_speed := max_omega * reach + body_speed
		var combined_radius := radius + float(limb.radius)
		var time := start
		while time <= earliest:
			var spin := Basis(_axis, _angle_at(time))
			var sole := old.lerp(feet, (time - start) / span)
			var pair := Geometry3D.get_closest_points_between_segments(
				_pivot + spin * a, _pivot + spin * b, sole + Vector3.UP * radius,
				sole + Vector3.UP * (height - radius))
			var gap := pair[0].distance_to(pair[1]) - combined_radius
			if gap <= 0.001:
				var omega := peak_rate * pow((time - WARNING) / _fall_time, 1.15)
				var speed := omega * (pair[0] - _pivot).slide(_axis).length()
				if speed >= 1.45:
					earliest = time
					point = pair[1] + pair[1].direction_to(pair[0]) * radius
					damage = clampf(speed * (2.5 + _radius * 4.0) * float(limb.strength), 3.0, 76.0)
					break
				time += 0.003
			else:
				time += maxf(0.00005, gap / max_speed)
	if damage > 0.0:
		_struck[id] = true
		struck.emit(id, damage, point)
