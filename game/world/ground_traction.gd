extends RefCounted

const FIRM := 1.0
const WOOD := 0.96
const METAL := 0.90
const SAND := 0.78
const MUD := 0.62
const SNOW := 0.34
const Salvage := preload("res://game/world/structural_salvage.gd")

static func coefficient(surface: PhysicsBody3D, point: Vector3, normal := Vector3.UP) -> float:
	var material: PhysicsMaterial
	if surface is StaticBody3D: material = surface.physics_material_override
	elif surface is RigidBody3D: material = surface.physics_material_override
	if material: return clampf(material.friction, 0.0, FIRM)
	var kind: String = surface.get_meta("kind", "")
	if kind == "terrain":
		var chunk := surface.get_parent() as WastelandChunk
		if chunk and chunk.terrain_body == surface:
			return _terrain(chunk, point, normal)
		return FIRM
	if surface.has_meta("salvage_material"):
		return _material(surface.get_meta("salvage_material"))
	if kind == "block":
		var builder := surface.get_parent() as WastelandConstruction
		if builder: return _material(builder.surface_material(surface.get_meta("block")))
	if kind == "poi_wall":
		var owner := surface.get_parent()
		while owner and not owner is WastelandChunk: owner = owner.get_parent()
		if owner: return _material(Salvage._material(owner.site, surface.get_meta("site_id", "")))
	if kind == "stump": return WOOD
	return FIRM

static func _material(id: String) -> float:
	match id:
		"stick", "wood": return WOOD
		"scrap", "iron", "steel", "metal", "parts", "wire": return METAL
		"packed_snow": return SNOW
		"sand": return SAND
		"clay": return MUD
		_: return FIRM

static func _terrain(chunk: WastelandChunk, point: Vector3, normal: Vector3) -> float:
	var grid := WastelandTerrainGen.GRID
	var local := Vector2(point.x - chunk.position.x, point.z - chunk.position.z) / WastelandTerrainGen.STEP
	local = local.clamp(Vector2.ZERO, Vector2.ONE * (grid - 1))
	var x := mini(floori(local.x), grid - 2)
	var z := mini(floori(local.y), grid - 2)
	var u := local.x - x
	var v := local.y - z
	var a := z * grid + x
	var b := _vertex(chunk, a + 1)
	var c := _vertex(chunk, a + grid)
	var grip: float
	if u + v < 1.0:
		grip = _vertex(chunk, a) * (1.0 - u - v) + b * u + c * v
	else:
		grip = _vertex(chunk, a + grid + 1) * (u + v - 1.0) + b * (1.0 - v) + c * (1.0 - u)
	# Steep faces expose the rock stratum used by the terrain mesh.
	return lerpf(FIRM, grip, smoothstep(0.53, 0.88, normal.y))

static func _vertex(chunk: WastelandChunk, index: int) -> float:
	if chunk.traction_cache.has(index): return chunk.traction_cache[index]
	var vertex: Vector3 = chunk.navigation_data.points[index] + chunk.position
	var gen: WastelandTerrainGen = chunk.stream.generator
	var region := gen.region_kind(vertex.x, vertex.z)
	var cut := -float(chunk.stream.digs.get(WastelandTerrainGen.grid_key(Vector2i(roundi(vertex.x), roundi(vertex.z))), 0.0))
	var grip := FIRM
	match region:
		"alpine":
			var snow := gen.snow_cover(vertex.x, vertex.z, vertex.y) * (1.0 - smoothstep(0.0, 0.45, cut))
			grip = lerpf(FIRM, SNOW, snow)
		"desert", "marsh":
			var loose := SAND if region == "desert" else MUD
			var pavement := gen.road_strength(vertex.x, vertex.z) * (1.0 - smoothstep(0.0, 0.45, cut))
			grip = lerpf(loose, FIRM, maxf(pavement, smoothstep(1.2, 3.0, cut)))
	chunk.traction_cache[index] = grip
	return grip
