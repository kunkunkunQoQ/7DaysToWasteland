class_name WastelandCreatureRoute
extends RefCounted

const SOLIDS := 1 | 2 | 8
const WALL_RAYS := [0.0, -23.0, 23.0, -47.0, 47.0, -73.0, 73.0]
const SIDE_STEPS := [0.62, -0.62, 1.16, -1.16, 1.82, -1.82]

var actor: WastelandCreature
var ray_query := PhysicsRayQueryParameters3D.new()
var motion_hit := KinematicCollision3D.new()
var path_query := NavigationPathQueryParameters3D.new()
var path_result := NavigationPathQueryResult3D.new()
var path := PackedVector3Array()
var waypoint := 0
var path_delay := 0.0
var planned_goal := Vector3.INF
var steer_delay := 0.0
var steer_toward := Vector3.ZERO
var steered := Vector3.ZERO
var turn_side := 1.0
var stuck := 0.0
var wants_motion := false
var progress_heading := Vector3.ZERO
var wall: StaticBody3D
var wall_point := Vector3.INF
var wall_probe_height := 0.0
var holding_point := Vector3.INF
var progress_origin := Vector3.ZERO
var progress_time := 0.0

func reset(side: float) -> void:
	clear_plan()
	steered = Vector3.ZERO
	steer_toward = Vector3.ZERO
	steer_delay = 0.0
	turn_side = side
	stuck = 0.0
	progress_time = 0.0
	progress_origin = actor.global_position
	progress_heading = Vector3.ZERO
	wall_probe_height = 0.0
	wants_motion = false
	path_query.metadata_flags = 0
	path_query.path_search_max_polygons = 850
	path_query.path_search_max_distance = 60.0

func clear_plan() -> void:
	path.clear()
	waypoint = 0
	path_delay = 0.0
	planned_goal = Vector3.INF
	wall = null
	wall_point = Vector3.INF
	holding_point = Vector3.INF

static func planar(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0.0, offset.z)

func ray(from: Vector3, to: Vector3, mask: int = SOLIDS, ignored: Array[RID] = []) -> Dictionary:
	ray_query.from = from
	ray_query.to = to
	ray_query.collision_mask = mask
	ray_query.exclude = ignored
	return actor.get_world_3d().direct_space_state.intersect_ray(ray_query)

func ground_near(at: Vector3, dry: bool) -> Vector3:
	if not actor.session.stream.at_surface(at):
		return Vector3.INF
	var down := ray(at + Vector3.UP * 1.30, at - Vector3.UP * 2.10, 3)
	if down.is_empty() or (down.normal as Vector3).y < 0.62:
		return Vector3.INF
	if dry and down.position.y < 0.12 and actor.session.stream.water_at(down.position):
		return Vector3.INF
	return down.position

func heading(delta: float, goal: Vector3, dry: bool, breach: bool, reach: float, stop: float) -> Vector3:
	wants_motion = false
	if not goal.is_finite():
		return Vector3.ZERO
	path_delay -= delta
	steer_delay -= delta
	if wall_point.is_finite() and (not is_instance_valid(wall) or actor.session.wall_health(wall) <= 0.0):
		clear_plan()
	if path_delay <= 0.0 or (path_delay < 0.32 and planned_goal.distance_squared_to(goal) > 5.4):
		_plan(goal, dry, breach, reach)
	var at := actor.global_position
	var destination := goal
	if is_instance_valid(wall):
		destination = wall_point
		stop = reach * 0.79
	elif holding_point.is_finite():
		destination = holding_point
		stop = 0.34
	elif waypoint < path.size():
		while waypoint < path.size() - 1 and planar(at - path[waypoint]).length_squared() < 0.32 and absf(at.y - path[waypoint].y) < 0.95:
			waypoint += 1
		destination = path[waypoint]
		stop = 0.42
	var offset := planar(destination - at)
	if offset.length_squared() <= stop * stop:
		return Vector3.ZERO
	wants_motion = true
	var ideal := offset.normalized()
	progress_heading = ideal
	if steer_delay <= 0.0 or ideal.dot(steer_toward) < 0.42:
		steer_delay = 0.14 if breach else 0.19
		steer_toward = ideal
		var probe := minf(1.03, maxf(0.35, offset.length() - stop * 0.46))
		steered = _steer(ideal, probe, dry)
	return steered

func moved(delta: float, displacement: Vector3, speed: float) -> void:
	if not wants_motion or actor.brain.animal:
		progress_origin = actor.global_position
		progress_time = 0.0
	else:
		progress_time += delta
		if planar(actor.global_position - progress_origin).length_squared() >= 0.09:
			progress_origin = actor.global_position
			progress_time = 0.0
		elif progress_time >= 2.0:
			progress_time = 0.0
			path_delay = 0.0
			var chest := actor.global_position + Vector3.UP * _body_height()
			var axis := planar(actor.brain.goal - actor.global_position).normalized()
			var probe := axis * minf(3.0, actor.brain.reach + 1.2)
			var obstruction := ray(chest, chest + probe)
			if obstruction.is_empty():
				var ankle := actor.global_position + Vector3.UP * 0.24
				obstruction = ray(ankle, ankle + probe)
			var solid := obstruction.get("collider") as StaticBody3D
			if actor.session.wall_health(solid) > 0 and Vector3(obstruction.normal).y < 0.64:
				_find_breach(chest, actor.brain.goal, actor.brain.reach)
			if is_instance_valid(wall):
				actor.brain.state = WastelandCreatureBrain.State.ATTACK_BLOCK
				path_delay = 0.50
			else:
				turn_side *= -1.0
				steered = _steer(progress_heading.rotated(Vector3.UP, turn_side * 0.85), 0.68, false)
				steer_delay = 0.34
				var head := actor.global_position + Vector3.UP * actor.capsule.height
				if actor.grounded() and ray(head, head + Vector3.UP * 0.85).is_empty():
					actor.velocity.y = 4.4
	if wants_motion and displacement.dot(progress_heading) < speed * delta * 0.23:
		stuck = minf(2.0, stuck + delta)
	else:
		stuck = maxf(0.0, stuck - delta * 2.0)

func strike_wall(reach: float) -> Dictionary:
	if not is_instance_valid(wall) or actor.wall_factor() <= 0.0 or actor.session.wall_health(wall) <= 0.0:
		return {}
	var at := actor.global_position + Vector3.UP * wall_probe_height
	if actor.biting() or actor.low_crawl():
		at = actor.melee_origin()
	if at.distance_squared_to(wall_point) > pow(reach + 0.16, 2):
		return {}
	var hit := ray(at, wall_point + (wall_point - at).normalized() * 0.24)
	if hit.get("collider") == wall and at.distance_squared_to(hit.position) <= reach * reach:
		return hit
	return {}

func _body_height() -> float:
	return clampf(actor.body_height() * 0.49, 0.23, 0.84)

func _plan(goal: Vector3, dry: bool, breach: bool, reach: float) -> void:
	path_delay = 0.5 if planned_goal.is_finite() else 0.21 + 0.025 * posmod(actor.spawn_serial,12)
	holding_point = Vector3.INF
	var at := actor.global_position
	var gap := at.distance_to(goal)
	var probe_height := _body_height()
	var height := Vector3.UP * probe_height
	if breach and actor.brain.rage_left > 0.0 and _nearby_support(at + height):
		planned_goal = goal
		return
	if breach and actor.brain.overflow:
		wall = null
		wall_point = Vector3.INF
		_find_breach(at + height, goal, reach)
		if is_instance_valid(wall):
			planned_goal = goal
			return
	var near_goal := at.move_toward(goal, 25.0)
	var blocker := ray(at + height, near_goal + height) if gap > 0.25 else {}
	if blocker.is_empty() and breach and gap > 0.60 and probe_height > 0.40:
		var low := Vector3.UP * 0.30
		var knee_wall := ray(at + low, at.move_toward(goal, 4.4) + low)
		var body := knee_wall.get("collider") as StaticBody3D
		if actor.session.wall_health(body) > 0.0:
			blocker = knee_wall
			probe_height = 0.30
	var direct := blocker.is_empty() and absf(near_goal.y - at.y) < maxf(0.65, gap * 0.43)
	if direct and stuck < 0.44:
		planned_goal = goal
		path.clear()
		waypoint = 0
		wall = null
		wall_point = Vector3.INF
		return
	var map := actor.get_world_3d().navigation_map
	var option := PackedVector3Array()
	if gap < 57.0 and NavigationServer3D.map_get_iteration_id(map) > 0:
		if not actor.director.spend_path_query():
			path_delay = actor.actor_rng.randf_range(0.11, 0.24)
			return
		path_query.map = map
		path_query.start_position = at
		path_query.target_position = goal
		NavigationServer3D.query_path(path_query, path_result)
		option = path_result.get_path()
		# A partial path ending on this side of an obstacle is still useful until the creature reaches it.
		if option.size() > 1 and at.distance_squared_to(option[0]) > 4.75:
			option.clear()
	var complete := option.size() > 1 and goal.distance_squared_to(option[-1]) < 1.85
	if complete and _path_crosses_blocker(option, blocker, probe_height):
		complete = false
		option.clear()
	if dry and option.size() > 1 and option[1].y < 0.14 and actor.session.stream.water_at(option[1]):
		complete = false
		option.clear()
	planned_goal = goal
	path = option
	waypoint = 1 if path.size() > 1 else path.size()
	wall = null
	wall_point = Vector3.INF
	var length := 0.0
	if complete:
		length = at.distance_to(option[0]) + goal.distance_to(option[-1])
		for i in range(1, option.size()):
			length += option[i - 1].distance_to(option[i])
	if breach and (not complete or (length > 20.0 and length > gap * 2.2)):
		_find_breach(at + height, goal, reach)

func _nearby_support(from: Vector3) -> bool:
	var building: WastelandConstruction = actor.session.construction
	var center := WastelandConstruction.cell_at(actor.global_position)
	var nearest := 12.25
	var selected: StaticBody3D
	var point := Vector3.ZERO
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for dy in range(-1, 2):
				var cell := center + Vector3i(dx, dy, dz)
				var body: StaticBody3D = building.nodes.get(cell)
				if not is_instance_valid(body):
					continue
				var distance := from.distance_squared_to(body.global_position)
				if distance >= nearest or not building.is_support_column(cell):
					continue
				var contact := ray(from, body.global_position)
				if contact.get("collider") == body:
					nearest = distance
					selected = body
					point = contact.position
	if selected == null:
		return false
	wall = selected
	wall_point = point
	wall_probe_height = _body_height()
	return true

func _path_crosses_blocker(option: PackedVector3Array, blocker: Dictionary, probe_height: float) -> bool:
	if blocker.is_empty() or not is_instance_valid(blocker.get("collider")):
		return false
	var height := Vector3.UP * probe_height
	var distance := 0.0
	var inspect := minf(10.0, actor.global_position.distance_to(blocker.position) + 2.8)
	# While a chunk's new navmesh is baking, local solids still define whether a route is open.
	for i in range(1, mini(8, option.size())):
		var from := option[i - 1]
		var to := from.move_toward(option[i], inspect - distance)
		var cross := ray(from + height, to + height)
		if is_instance_valid(cross.get("collider")) and cross.collider == blocker.collider:
			return true
		distance += from.distance_to(to)
		if distance >= inspect - 0.01:
			break
	return false

func _find_breach(from: Vector3, goal: Vector3, reach: float) -> void:
	var axis := planar(goal - from).normalized()
	if axis == Vector3.ZERO:
		return
	var best := INF
	var local_range := clampf(planar(goal - from).length() + 1.0, 3.8, 18.0)
	var best_hp := INF
	var crowded := Vector3.INF
	var crowded_distance := INF
	var power := float(actor.spec.wall)*actor.wall_factor()
	if power<=0.0:
		return
	var chest := _body_height()
	var low_from := actor.global_position + Vector3.UP * 0.30
	for angle: float in WALL_RAYS:
		var offset := axis.rotated(Vector3.UP, deg_to_rad(angle)) * local_range
		var probe_height := chest
		var hit := ray(from, from + offset)
		if hit.is_empty() and chest > 0.40:
			hit = ray(low_from, low_from + offset)
			probe_height = 0.30
		var body := hit.get("collider") as StaticBody3D
		var hp: float = actor.session.wall_health(body)
		if hp <= 0.0:
			continue
		var point: Vector3 = hit.position
		if point.distance_to(goal) > from.distance_to(goal) + 0.45:
			continue
		var pressure: int = actor.director.breach_pressure(body, actor)
		if pressure >= 3:
			var distance := from.distance_squared_to(point)
			if distance < crowded_distance:
				crowded = point
				crowded_distance = distance
			continue
		var travel := maxf(0.0, from.distance_to(point) - reach)
		var rank := travel + point.distance_to(goal) * 0.32 + pressure * (2.0 if actor.brain.overflow else 0.05)
		if hp < best_hp or (is_equal_approx(hp, best_hp) and rank < best):
			best_hp = hp
			best = rank
			wall = body
			wall_point = point
			wall_probe_height = probe_height
	if not is_instance_valid(wall) and crowded.is_finite():
		var lateral := axis.cross(Vector3.UP) * turn_side
		var offset := lateral * (1.4 + posmod(actor.spawn_serial, 4) * 0.68) - axis * 1.25
		holding_point = ground_near(crowded + offset, false)

func _steer(ideal: Vector3, lookahead: float, dry: bool) -> Vector3:
	if _step_clear(ideal, lookahead, dry):
		return ideal
	for angle: float in SIDE_STEPS:
		var nudge := ideal.rotated(Vector3.UP, angle * turn_side)
		if _step_clear(nudge, lookahead * 0.88, dry):
			if angle < 0.0:
				turn_side = -turn_side
			return nudge
	# Move up to a close obstruction before attempting a melee strike or another route.
	if lookahead > 0.48 and _step_clear(ideal, 0.36, dry):
		return ideal
	return Vector3.ZERO

func step_toward(heading: Vector3, dry: bool) -> bool:
	return _step_clear(heading, 1.0, dry)

func _step_clear(heading: Vector3, lookahead: float, dry: bool) -> bool:
	var motion := heading * lookahead
	var lift := Vector3.UP * (0.065 if actor.low_crawl() else 0.15)
	if actor.test_move(actor.global_transform.translated(lift), motion, motion_hit, 0.015) and motion_hit.get_normal().y < 0.62:
		# The raised toe probe can strike a lintel above the walking capsule.
		var head := actor.global_position.y + actor.capsule.height - actor.capsule.radius
		if motion_hit.get_position().y < head or actor.test_move(actor.global_transform, motion, motion_hit, 0.015):
			return false
	var end := actor.global_position + heading * lookahead
	if not actor.session.stream.at_surface(end):
		return false
	if not actor.grounded() and not dry:
		return true
	var floor_ahead := ray(end + Vector3.UP * 0.69, end - Vector3.UP * 1.42, 3)
	if floor_ahead.is_empty() or (floor_ahead.normal as Vector3).y < 0.59:
		return false
	return not dry or floor_ahead.position.y >= 0.13 or not actor.session.stream.water_at(end)
