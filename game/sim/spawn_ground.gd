extends RefCounted

const Terrain := preload("res://game/world/terrain_gen.gd")
var clearance := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	var hull := CapsuleShape3D.new()
	hull.radius = 0.48
	hull.height = 2.45
	clearance.shape = hull
	clearance.collision_mask = 2 | 8

func standing_clear(session: Node3D, feet: Vector3) -> bool:
	clearance.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 1.27)
	return session.get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty()

func surface(session: Node3D, candidate: Vector3) -> Vector3:
	var stream: WastelandStream = session.stream
	var cell := Terrain.chunk_at(Vector2(candidate.x, candidate.z))
	var chunk: WastelandChunk = stream.active.get(cell)
	if chunk == null or chunk.region == null:
		return Vector3.INF
	var local := candidate - chunk.position
	var stride := Terrain.NAV_STRIDE
	var x := floori(local.x / stride) * stride
	var z := floori(local.z / stride) * stride
	var a := z * Terrain.GRID + x
	var b := a + stride
	var c := a + stride * Terrain.GRID
	var d := c + stride
	var points: PackedVector3Array = chunk.navigation_data.points
	# Use the same triangle, slope and water limits as the terrain navigation mesh.
	var second := local.x - x + local.z - z >= stride
	var p := points[b if second else a]
	var q := points[d if second else b]
	var r := points[c]
	if (r - p).cross(q - p).normalized().y <= 0.64:
		return Vector3.INF
	if minf(p.y, minf(q.y, r.y)) <= -0.55 and (stream.digs.is_empty() or stream.generator.water_basin(candidate.x, candidate.z)):
		return Vector3.INF
	candidate.y = stream.ground_at(candidate) + 0.12
	if stream.water_at(candidate) or in_enclosure(session.construction, candidate):
		return Vector3.INF
	var sky := PhysicsRayQueryParameters3D.create(candidate, candidate + Vector3.UP * 2048.0, 3)
	sky.hit_back_faces = true
	sky.hit_from_inside = true
	if not session.get_world_3d().direct_space_state.intersect_ray(sky).is_empty() or not standing_clear(session, candidate):
		return Vector3.INF
	for actor: WastelandCreature in session.hordes.alive:
		if actor.active and actor.global_position.distance_squared_to(candidate) < 2.25:
			return Vector3.INF
	return candidate

func in_enclosure(build: WastelandConstruction, point: Vector3) -> bool:
	var origin := WastelandConstruction.cell_at(point)
	var region := Terrain.chunk_at(Vector2(point.x, point.z))
	var sides := 0
	# A roofless courtyard can have clear sky. Any enclosing grid perimeter
	# must cross the four axial half-lines; inspect only those indexed chunks.
	for key: Vector2i in build.chunk_index:
		if key.x != region.x and key.y != region.y:
			continue
		for block: Vector3i in build.get_blockers(key):
			if block.x != origin.x and block.z != origin.z:
				continue
			var data: Dictionary = build.blocks[block]
			if not str(data.get("device", "")).is_empty() or bool(data.get("open", false)):
				continue
			var floor_y: float = build.session.stream.ground_at(Vector3(block))
			if block.y + 1.0 <= floor_y + 0.2 or block.y > floor_y + 2.2:
				continue
			if block.x == origin.x:
				sides |= 1 if block.z < origin.z else 2
			if block.z == origin.z:
				sides |= 4 if block.x < origin.x else 8
			if sides == 15:
				return true
	return false
