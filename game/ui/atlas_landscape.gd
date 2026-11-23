extends RefCounted

const Stage := preload("res://game/ui/model_study.gd")
const GRID := 37
const WATER_Y := WastelandTerrainGen.WATER_LEVEL
const CACHE_SIZE := 4
static var recent := {}

class Geometry:
	var mesh: ArrayMesh
	var scenery: Array[MultiMesh] = []
	var bounds: AABB

static func build(stage: Stage, terrain: WastelandTerrainGen, at: Vector2, span: float) -> AABB:
	var ground := MeshInstance3D.new()
	ground.name = "TerrainSample"
	ground.material_override = WastelandLook.colored_material()
	var key := [terrain.get_instance_id(), terrain.seed_value, terrain.revision, at, span]
	var geometry: Geometry = recent.get(key)
	if geometry == null:
		geometry = Geometry.new()
		var sample := Sample.new(terrain, at, span)
		geometry.mesh = sample.ground_mesh()
		ground.mesh = geometry.mesh
		geometry.bounds = sample.add_scenery(ground)
		for batch: MultiMeshInstance3D in ground.get_children():
			geometry.scenery.append(batch.multimesh)
		if recent.size() >= CACHE_SIZE: recent.erase(recent.keys()[0])
	else:
		recent.erase(key)
		ground.mesh = geometry.mesh
		for multimesh in geometry.scenery:
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = multimesh
			batch.material_override = ground.material_override
			ground.add_child(batch)
	recent[key] = geometry
	stage.scene.add_child(ground)
	return geometry.bounds

class Sample:
	var terrain: WastelandTerrainGen
	var center: Vector2
	var span: float
	var step: float
	var floor_y := INF
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var depths := PackedFloat32Array()
	var surface := SurfaceTool.new()
	var sites := {}

	func _init(generator: WastelandTerrainGen, at: Vector2, width: float) -> void:
		terrain = generator
		center = at
		span = width
		step = span / (GRID - 1)
		for z in GRID:
			for x in GRID:
				var local := Vector2(x,z) * step - Vector2.ONE * span * 0.5
				var world := center + local
				var cell := WastelandTerrainGen.chunk_at(world)
				var middle := Vector2(cell * WastelandTerrainGen.SIZE) + Vector2.ONE * (WastelandTerrainGen.SIZE * 0.5)
				var h := terrain.ground(world.x, world.y, _site(cell), middle)
				points.append(Vector3(local.x, h, local.y))
				colors.append(terrain.ground_color(world.x, world.y, h))
				var depth := WATER_Y - h
				if depth > 0.0 and not terrain.water_basin(world.x, world.y):
					depth = -depth
				depths.append(depth)
				floor_y = minf(floor_y, h)
		floor_y -= span * 0.045

	func _site(cell: Vector2i) -> String:
		if not sites.has(cell): sites[cell] = terrain.site_for(cell)
		return sites[cell]

	func ground_mesh() -> ArrayMesh:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for z in GRID - 1:
			for x in GRID - 1:
				var a := z * GRID + x
				_ground_face(a, a + 1, a + GRID)
				_ground_face(a + 1, a + GRID + 1, a + GRID)
		for i in GRID - 1:
			_edge(i, i + 1)
			_edge((i + 1) * GRID - 1, (i + 2) * GRID - 1)
			_edge(GRID * GRID - 1 - i, GRID * GRID - 2 - i)
			_edge((i + 1) * GRID, i * GRID)
		for i: int in [0, GRID * GRID - GRID, GRID - 1, GRID - 1, GRID * GRID - GRID, GRID * GRID - 1]:
			_vertex(Vector3(points[i].x, floor_y, points[i].z), Vector3.DOWN, Color("#534d4c"))
		return surface.commit()

	func _vertex(p: Vector3, n: Vector3, c: Color) -> void:
		surface.set_normal(n)
		surface.set_color(c)
		surface.add_vertex(p)

	func _ground_face(i: int, j: int, k: int) -> void:
		var n := (points[k] - points[i]).cross(points[j] - points[i]).normalized()
		_vertex(points[i], n, colors[i])
		_vertex(points[j], n, colors[j])
		_vertex(points[k], n, colors[k])
		if maxf(depths[i], maxf(depths[j], depths[k])) <= 0.0:
			return
		# Clip this exact terrain triangle to the shoreline. Keep depth until coloring the flat water.
		var polygon := PackedVector3Array()
		var previous := k
		for current: int in [i, j, k]:
			var a := points[previous]
			var b := points[current]
			a.y = depths[previous]
			b.y = depths[current]
			if (a.y > 0.0) != (b.y > 0.0):
				polygon.append(a.lerp(b, a.y / (a.y - b.y)))
			if b.y > 0.0:
				polygon.append(b)
			previous = current
		for t in range(1, polygon.size() - 1):
			_water_vertex(polygon[0])
			_water_vertex(polygon[t])
			_water_vertex(polygon[t + 1])

	func _water_vertex(p: Vector3) -> void:
		var tint := Color("#99c5ac").lerp(Color("#448e91"), smoothstep(0.0, 2.8, p.y))
		tint = tint.lerp(Color("#325c75"), smoothstep(2.8, 11.0, p.y))
		_vertex(Vector3(p.x, WATER_Y + 0.015, p.z), Vector3.UP, tint)

	func _edge(i: int, j: int) -> void:
		var a := points[i]
		var b := points[j]
		var n := (b - a).cross(Vector3.DOWN).normalized()
		var skin := span * 0.012
		var under_a := a + Vector3.DOWN * skin
		var under_b := b + Vector3.DOWN * skin
		var earth := colors[i].lerp(colors[j], 0.5).lerp(Color("#876e55"), 0.68)
		_band(a, b, under_a, under_b, n, earth, earth.darkened(0.12))
		var base_a := Vector3(a.x, floor_y, a.z)
		var base_b := Vector3(b.x, floor_y, b.z)
		var layer_a := base_a + Vector3.UP * span * (0.022 + 0.004 * sin(a.x * 0.08 + a.z * 0.04))
		var layer_b := base_b + Vector3.UP * span * (0.022 + 0.004 * sin(b.x * 0.08 + b.z * 0.04))
		_band(under_a, under_b, layer_a, layer_b, n, Color("#826e60"), Color("#6f625b"))
		_band(layer_a, layer_b, base_a, base_b, n, Color("#685b53"), Color("#534d4c"))
		if maxf(depths[i], depths[j]) <= 0.0:
			return
		if minf(depths[i], depths[j]) <= 0.0:
			var bank := a.lerp(b, depths[i] / (depths[i] - depths[j]))
			if depths[i] <= 0.0: a = bank
			else: b = bank
		_band(Vector3(a.x, WATER_Y + 0.015, a.z), Vector3(b.x, WATER_Y + 0.015, b.z),
			a, b, n, Color("#659f9f"), Color("#325c75"))

	func _band(a: Vector3, b: Vector3, low_a: Vector3, low_b: Vector3, normal: Vector3, top: Color, bottom: Color) -> void:
		_vertex(a, normal, top)
		_vertex(low_a, normal, bottom)
		_vertex(b, normal, top)
		_vertex(b, normal, top)
		_vertex(low_a, normal, bottom)
		_vertex(low_b, normal, bottom)

	func _surface_height(p: Vector3) -> float:
		var cell := (Vector2(p.x, p.z) + Vector2.ONE * span * 0.5) / step
		var x := clampi(floori(cell.x), 0, GRID - 2)
		var z := clampi(floori(cell.y), 0, GRID - 2)
		var uv := cell - Vector2(x, z)
		var i := z * GRID + x
		var b := points[i + 1].y
		var c := points[i + GRID].y
		if uv.x + uv.y <= 1.0:
			return points[i].y * (1.0 - uv.x - uv.y) + b * uv.x + c * uv.y
		return points[i + GRID + 1].y * (uv.x + uv.y - 1.0) + b * (1.0 - uv.y) + c * (1.0 - uv.x)

	func add_scenery(ground: MeshInstance3D) -> AABB:
		var bounds := ground.mesh.get_aabb()
		var groups := {}
		var first := WastelandTerrainGen.chunk_at(center - Vector2.ONE * span * 0.5)
		var last := WastelandTerrainGen.chunk_at(center + Vector2.ONE * span * 0.5)
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var cell := Vector2i(x, z)
				var origin := Vector2(cell * WastelandTerrainGen.SIZE)
				var middle := origin + Vector2.ONE * (WastelandTerrainGen.SIZE * 0.5)
				for entry: Dictionary in terrain._dressing(cell, origin, middle, _site(cell)):
					var id: String = entry.id
					if id in ["pondweed", "bedrock", "fallen_stick", "pebble"]:
						continue
					if id in ["grass", "reeds", "herb_patch"] and (span > 160.0 or int(entry.index) % 6 != 0):
						continue
					var p: Vector3 = entry.point + Vector3(origin.x - center.x, 0.0, origin.y - center.y)
					if maxf(absf(p.x), absf(p.z)) >= span * 0.5:
						continue
					p.y = _surface_height(p) - 0.04
					var model := str(entry.get("model", ""))
					if model.is_empty(): model = id
					var asset := WastelandChunk._nature_mesh(model, int(entry.variant), false)
					if not groups.has(asset):
						var transforms: Array[Transform3D] = []
						groups[asset] = transforms
					var basis := Basis(Vector3.UP, float(entry.angle)).scaled(Vector3.ONE * float(entry.scale))
					var pose := Transform3D(basis, p)
					groups[asset].append(pose)
					bounds = bounds.merge(pose * asset.get_aabb())
		for asset: Mesh in groups:
			WastelandLook.instanced(ground, asset, groups[asset])
		return bounds
