class_name WastelandTerrainGen
extends RefCounted

const SIZE := 32
const STEP := 1
const NAV_STRIDE := 2
const GRID := SIZE / STEP + 1
const WATER_LEVEL := 0.0
const CURRENT_REVISION := 5
const Frontier := preload("res://game/world/frontier.gd")
const START := Vector2(9, 44)
const FIXED := {
	Vector2i(-1, 1): "lodge", Vector2i(2, 1): "fuel",
	Vector2i(3, -1): "police", Vector2i(-3, -2): "bunker",
	Vector2i(3, -4): "hospital", Vector2i(-4, -4): "tower",
}
const BIOME_COLOR := ["b18959","77784d","978899","9a6b60","817f8b"]
const RESOURCES := ["oak", "pine", "boulder", "clay_bank", "brush", "ore", "salvage","herb_patch","reed_bed","iron_vein","machine_wreck","cactus"]
var seed_value: int
var revision: int
var site_revision := 0
var wild_start := Vector2.INF

func wilderness_start(roll: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = roll ^ (seed_value * 104729)
	var regions := ["meadow","taiga","desert","mesa","marsh","canyon"]
	var preferred: String = regions[rng.randi_range(0,regions.size()-1)]
	var attempts := 0
	while true:
		attempts += 1
		var cell := Vector2i(rng.randi_range(-158,158),rng.randi_range(-158,158))
		var origin := Vector2(cell*SIZE)
		var point := origin+Vector2(rng.randf_range(7,25),rng.randf_range(7,25))
		if point.length()<440: continue
		var region := region_kind(point.x,point.y)
		if region not in regions or (attempts<500 and region!=preferred): continue
		var cache_roll := RandomNumberGenerator.new()
		cache_roll.seed = seed_at(cell,7819)
		if cache_roll.randf()<=0.14: continue
		var height := ground(point.x,point.y)
		if height<1.6 or height>30 or road_strength(point.x,point.y)>0.35: continue
		var clear := true
		for z in range(-2,3):
			for x in range(-2,3):
				var neighbor := cell+Vector2i(x,z)
				if point.distance_to(Vector2(neighbor*SIZE)+Vector2(16,16))<77 and site_for(neighbor)!="":
					clear=false
					break
			if not clear: break
		if not clear: continue
		for radius: float in [2.0,6.0,11.0]:
			for i in 8:
				var nearby := point+Vector2.from_angle(i*TAU/8.0)*radius
				var level := ground(nearby.x,nearby.y)
				if level<0.8 or absf(level-height)>radius*0.24 or water_basin(nearby.x,nearby.y):
					clear=false
					break
			if not clear: break
		if not clear or water_basin(point.x,point.y): continue
		for fixture: Vector3 in preload("res://game/world/expedition_sites.gd").survey(self).points.values():
			if point.distance_to(Vector2(fixture.x,fixture.z))<60:
				clear=false
				break
		if not clear: continue
		for entry in _dressing(cell,origin,origin+Vector2(16,16),""):
			var prop: Vector3 = entry.point
			if entry.id in RESOURCES and point.distance_to(origin+Vector2(prop.x,prop.z))<3.2:
				clear=false
				break
		if clear: return point
	return Vector2.INF
var relief := FastNoiseLite.new()
var expedition_layout: Dictionary = {}
var river_phase: float
var shape := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ecology := FastNoiseLite.new()
var frontier: Frontier

func _init(value: int, world_revision: int = CURRENT_REVISION) -> void:
	seed_value = value
	revision = world_revision
	if revision >= 3: frontier = Frontier.new(value)
	relief.seed = value ^ 950321
	relief.frequency = 0.0038
	relief.fractal_octaves = 2
	river_phase = posmod(value, 628) * 0.01
	shape.seed = value
	shape.frequency = 0.0105
	shape.fractal_octaves = 3
	detail.seed = value ^ 145321
	detail.frequency = 0.05
	detail.fractal_octaves = 2
	ecology.seed = value ^ 304433
	ecology.frequency = 0.0065

static func chunk_at(xz: Vector2) -> Vector2i:
	return Vector2i(floori(xz.x / SIZE), floori(xz.y / SIZE))

static func grid_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func seed_at(cell: Vector2i, salt: int = 0) -> int:
	return seed_value ^ (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)

func lake_factor(x: float, z: float) -> float:
	var core := Vector2((x - 13.0) / 69.0, (z + 46.0) / 76.0).length()
	return core + shape.get_noise_2d(x + 412.0, z - 59.0) * 0.17 + 0.075 * sin(z * 0.069) * sin(x * 0.052)

func _frontier_weight(x: float, z: float) -> float:
	if revision<3: return 0.0
	return smoothstep(184.0*184.0,280.0*280.0,x*x+z*z)

func region_kind(x: float, z: float) -> String:
	if _frontier_weight(x,z)<0.5: return "basin"
	return Frontier.NAMES[frontier.kind(Vector2(x,z))]

func temperature_offset(x: float, z: float) -> float:
	var blend := _frontier_weight(x,z)
	if blend==0.0: return 0.0
	return Frontier.TEMPERATURE[frontier.kind(Vector2(x,z))]*blend

func starting_outpost(start_id: String) -> Vector2i:
	return frontier.starting_outpost(start_id) if revision>=3 else Vector2i(-1,1)

func nearby_outposts(p: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if revision>=3:
		for cell in frontier.nearby_outposts(p):
			var center := Vector2(cell*SIZE)+Vector2(16,16)
			if _frontier_weight(center.x,center.y)>=0.5:
				result.append(cell)
	return result

func outpost_beacon_cell(outpost: Vector2i) -> Vector2i:
	return frontier.beacon_cell(outpost) if revision>=3 else Vector2i(3,-1)

func road_strength(x: float, z: float) -> float:
	var mix_amount := _frontier_weight(x,z)
	if mix_amount >= 1.0: return frontier.road(Vector2(x,z))
	var cross_x := absf(fposmod(x - 16.0 + 64.0, 128.0) - 64.0)
	var cross_z := absf(fposmod(z - 39.0 + 64.0, 128.0) - 64.0)
	var edge := minf(cross_x, cross_z)
	if absf(x) < 65 and z < 32 and z > -125:
		edge = maxf(edge, 18.0)
	var road := (1.0 - smoothstep(1.4, 3.6, edge)) * smoothstep(0.99, 1.12, lake_factor(x, z))
	return lerpf(road,frontier.road(Vector2(x,z)),mix_amount) if mix_amount>0.0 else road

func biome(x: float, z: float) -> int:
	if _frontier_weight(x,z)>=0.5:
		return Frontier.ZONES[frontier.kind(Vector2(x,z))]
	if lake_factor(x, z) < 1.18 or Vector2(x, z).length() < 68.0:
		return 0
	var height_noise := shape.get_noise_2d(x, z)
	var climate := ecology.get_noise_2d(x, z)
	if x > 76.0 and z < 6.0 and z > -210.0 and x < 220.0:
		return 4
	if height_noise > 0.32 or x < -120.0 and climate > -0.16:
		return 2
	if climate < -0.29 or z < -230.0 and climate < 0.09:
		return 3
	if Vector2(x - 62.0, z + 26.0).length() > 169.0 and climate > 0.36:
		return 4
	return 1

func site_for(cell: Vector2i) -> String:
	if FIXED.has(cell):
		return FIXED[cell]
	if cell.length_squared() < 29:
		return ""
	var center := Vector2(cell * SIZE) + Vector2.ONE * (SIZE * 0.5)
	if _frontier_weight(center.x,center.y)>=0.5:
		return frontier.site_for(cell,revision>=5)
	if lake_factor(center.x, center.y) < 1.17:
		return ""
	var zone := biome(center.x, center.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_at(cell, 19)
	if zone == 4 and rng.randf() < 0.33:
		if revision>=5:
			return ["garage","post","fuel","police","hospital","tower"][rng.randi_range(0,5)]
		return ["fuel", "police", "hospital", "tower"][rng.randi_range(0, 3)]
	if rng.randf() < 0.072:
		if revision>=5 and rng.randf()<0.50:
			return "garage" if zone in [2,3] else "granary"
		return "bunker" if zone in [2, 3] else "cabin"
	return ""

func raw_height(x: float, z: float) -> float:
	var blend := _frontier_weight(x,z)
	if blend>=1.0: return frontier.height(Vector2(x,z))
	var bank := lake_factor(x, z)
	var n := shape.get_noise_2d(x, z)
	var small := detail.get_noise_2d(x, z)
	var outside := 4.2 + n * (12.0 + 21.0 * smoothstep(1.25, 2.35, bank)) + small * 2.2
	var lake := -1.35 - (1.0 - bank) * 13.4 + small * 0.8
	var variable := lerpf(lake, maxf(0.7, outside), smoothstep(0.88, 1.21, bank))
	var islands := maxf(0.0, 1.0 - Vector2((x + 31.0) / 21.0, (z + 78.0) / 19.0).length())
	islands += maxf(0.0, 1.0 - Vector2((x - 39.0) / 19.0, (z + 88.0) / 16.0).length())
	variable += islands * 15.0
	var south_ridge := (1.0 - smoothstep(12.0, 48.0, absf(z - 44.0))) * (1.0 - smoothstep(23.0, 75.0, absf(x - 6.0)))
	variable += south_ridge * 2.8
	var road := road_strength(x, z)
	var height := lerpf(variable, 4.3 + n * 5.8, road * 0.67)
	if revision < 2:
		return height
	# Preserve the launch, landing and starter approach while sculpting the surrounding shores.
	var inland := smoothstep(0.99, 1.27, bank)
	var uplift := 0.0
	if inland > 0.0:
		var fold := relief.get_noise_2d(x, z)
		# The opposing ridges meet at a lower saddle, visible across the reservoir.
		var ridge_line := -151.0 + sin(x * 0.026) * 12.0 + fold * 17.0
		var ridge := 1.0 - smoothstep(3.0, 45.0, absf(z - ridge_line))
		var saddle := 0.54 + 0.46 * smoothstep(5.0, 30.0, absf(x + 21.0))
		uplift += ridge * saddle * (38.0 + 10.0 * n) * (1.0 - smoothstep(82.0, 168.0, absf(x)))
		# Basalt shelves on the west shore leave broad benches between short scarps.
		var flank := -x + sin(z * 0.038) * 9.0 + n * 6.0
		var headland := 1.0 - smoothstep(45.0, 104.0, absf(z + 33.0))
		uplift += headland * (smoothstep(66.0, 78.0, flank) * 9.0 + smoothstep(91.0, 102.0, flank) * 12.0)
		# Beyond the basin the seed drives folded uplands, flat-topped mesas and drainage gullies.
		var hinterland := smoothstep(116.0, 202.0, Vector2(x, z + 38.0).length())
		if hinterland > 0.0:
			var crest := pow(1.0 - clampf(absf(fold) * 2.5, 0.0, 1.0), 3.0)
			var mesa := smoothstep(0.08, 0.27, fold)
			var gully := 1.0 - smoothstep(0.015, 0.15, absf(n + fold * 0.8))
			uplift += hinterland * (crest * 26.0 + mesa * 21.0 - gully * 10.0)
	height += uplift * inland * (1.0 - 0.25 * road)
	if inland > 0.98:
		height = maxf(height, 0.5)
	# A broad walk-in beach grades into a submerged shelf and then the lake bed.
	var beach := (1.0 - smoothstep(8.0, 26.0, absf(x - 28.0))) * smoothstep(4.0, 21.0, z) * (1.0 - smoothstep(30.0, 43.0, z))
	height = lerpf(height, (bank - 1.0) * 12.0 + small * 0.28, beach * 0.9)
	if z > -9.0:
		var cross_stream := absf(x - river_x(z))
		var banks := (1.0 - smoothstep(4.0, 16.0, cross_stream)) * smoothstep(-9.0, 8.0, z)
		if banks > 0.0:
			var ford := 1.0 - smoothstep(3.0, 11.0, absf(fposmod(z - 39.0 + 64.0, 128.0) - 64.0))
			var bed := lerpf(-2.6, -0.38, ford) + smoothstep(2.0, 12.0, cross_stream) * 3.6
			height = lerpf(height, bed + small * 0.18, banks)
	return lerpf(height,frontier.height(Vector2(x,z)),blend) if blend>0.0 else height

func river_x(z: float) -> float:
	return 47.0 + (z - 18.0) * 0.22 + sin((z - 18.0) * 0.031) * 9.5 + sin(z * 0.056 + river_phase) * 2.8

func water_basin(x: float, z: float) -> bool:
	if _frontier_weight(x,z)>0.0 and raw_height(x,z)<0.12: return true
	if _frontier_weight(x,z)>=1.0: return false
	return (revision >= 2 and z > -9.0 and absf(x - river_x(z)) < 16.0) or lake_factor(x, z) < 1.19

func landform(x: float, z: float) -> String:
	if _frontier_weight(x,z)>=0.5:
		return Frontier.TITLES[frontier.kind(Vector2(x,z))]
	if revision >= 2:
		if z > 12.0 and absf(x - river_x(z)) < 15.0:
			return "回湾溪谷"
		if z < -115.0 and z > -196.0 and absf(x) < 115.0:
			return "北岸折脊"
		if x < -60.0 and x > -146.0 and absf(z + 33.0) < 75.0:
			return "西岸岩阶"
		if absf(x - 28.0) < 21.0 and z > 5.0 and z < 37.0:
			return "白沙浅滩"
	return WastelandCatalog.BIOMES[biome(x, z)]

func ground(x: float, z: float, known_site: String = "?", known_center: Vector2 = Vector2.ZERO) -> float:
	var value := raw_height(x, z)
	var cell := chunk_at(Vector2(x, z))
	var site := site_for(cell) if known_site == "?" else known_site
	if site != "":
		var center := Vector2(cell * SIZE) + Vector2.ONE * (SIZE * 0.5) if known_site == "?" else known_center
		var pad_y := maxf(1.35, raw_height(center.x, center.y))
		value = _site_ground(value,pad_y,Vector2(x,z)-center,site)
	return value

func _site_ground(raw:float,pad:float,local:Vector2,site:String)->float:
	# Keep the entrance apron and the east stair landing on the prepared site.
	# The blend still reaches untouched terrain before the chunk boundary.
	var blend_x:=smoothstep(6.6,14.0,absf(local.x))
	var blend_z:=smoothstep(6.6,14.0,absf(local.y))
	if revision>=5 and local.x>0:
		blend_x=smoothstep(9.0,14.0,local.x)
	if revision>=5 and local.y>0:
		blend_z=smoothstep(8.0,14.0,local.y)
	if revision>=5 and site=="bunker" and local.y>0:
		var trench:=1.0-smoothstep(1.5,3.8,absf(local.x))
		blend_z=lerpf(blend_z,smoothstep(12.5,15.5,local.y),trench)
	var height:=lerpf(pad,raw,maxf(blend_x,blend_z))
	return height-_bunker_depth(local) if site=="bunker" else height

func _bunker_depth(local: Vector2) -> float:
	var main := (1.0 - smoothstep(6.3, 7.7, absf(local.x))) * (1.0 - smoothstep(6.4, 8.0, absf(local.y)))
	var ramp := (1.0 - smoothstep(1.30, 2.70, absf(local.x))) * (1.0 - smoothstep(5.0, 13.5, local.y))
	return 4.58 * maxf(main, ramp if local.y > 4.0 else 0.0)

func build(cell: Vector2i, digs: Dictionary, decorations: bool = true) -> Dictionary:
	var start := Vector2(cell * SIZE)
	var center := start + Vector2.ONE * (SIZE * 0.5)
	var site := site_for(cell)
	var points := PackedVector3Array()
	var swatches := PackedColorArray()
	var has_water := false
	var pad_height := maxf(1.35, raw_height(center.x, center.y))
	for row in GRID:
		for col in GRID:
			var x := start.x + col * STEP
			var z := start.y + row * STEP
			var y := raw_height(x, z)
			if site != "":
				y = _site_ground(y,pad_height,Vector2(x,z)-center,site)
			var grid := Vector2i(int(x), int(z))
			var cut := -float(digs.get(grid_key(grid), 0.0))
			y -= cut
			points.append(Vector3(col * STEP, y, row * STEP))
			var surface := ground_color(x, z, y)
			if cut>0:
				var grain := 0.92+0.08*sin(x*1.7+z*2.3)
				var exposed := Color("#967753") if region_kind(x,z)!="desert" else Color("#cbac77")
				exposed = exposed.lerp(Color("#736f70"),smoothstep(1.2,3.0,cut))
				surface = surface.lerp(exposed*grain,smoothstep(0.0,0.45,cut))
			swatches.append(surface)
			has_water = has_water or (y < 0.05 and water_basin(x, z))
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var surface_nav := PackedInt32Array()
	for row in GRID - 1:
		for col in GRID - 1:
			var a := row * GRID + col
			var triangles := [a, a + 1, a + GRID, a + 1, a + GRID + 1, a + GRID]
			for k in [0, 3]:
				var p := points[triangles[k]]
				var q := points[triangles[k + 1]]
				var r := points[triangles[k + 2]]
				var normal := (r - p).cross(q - p).normalized()
				var shade := 0.94 + detail.get_noise_2d(start.x + p.x, start.y + p.z) * 0.16
				var crag := (1.0 - smoothstep(0.53, 0.88, normal.y)) if revision >= 2 else 0.0
				var stratum := Color("#827967").lerp(Color("#b8a68c"), smoothstep(0.6, 2.2, fposmod(p.y, 3.4)))
				for index in range(k, k + 3):
					vertices.append(points[triangles[index]])
					normals.append(normal)
					colors.append(swatches[triangles[index]].lerp(stratum, crag * 0.87) * shade)
	for row in range(0, GRID - 1, NAV_STRIDE):
		for col in range(0, GRID - 1, NAV_STRIDE):
			var a := row * GRID + col
			var b := a + NAV_STRIDE
			var c := a + GRID * NAV_STRIDE
			var d := c + NAV_STRIDE
			for face in [[a,b,c],[b,d,c]]:
				var p := points[face[0]]
				var q := points[face[1]]
				var r := points[face[2]]
				var normal := (r - p).cross(q - p).normalized()
				var above_water := minf(p.y,minf(q.y,r.y)) > -0.55
				if not above_water and not digs.is_empty():
					var centroid := (p+q+r)/3.0
					above_water = not water_basin(start.x+centroid.x,start.y+centroid.z)
				if normal.y > 0.64 and above_water:
					surface_nav.append_array(PackedInt32Array(face))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals
	var dressing := _dressing(cell, start, center, site) if decorations else []
	return {"arrays": arrays, "points": points, "nav": surface_nav, "water": has_water,
		"site": site, "pad": pad_height, "dressing": dressing}

func snow_cover(x: float, z: float, y: float) -> float:
	if revision<3 or region_kind(x,z)!="alpine": return 0.0
	var grain:=detail.get_noise_2d(x-621.0,z+345.0)
	return smoothstep(40.0,64.0,y+grain*14.0)*_frontier_weight(x,z)*(1.0-road_strength(x,z))

func ground_color(x: float, z: float, y: float) -> Color:
	var n := detail.get_noise_2d(x - 621.0, z + 345.0)
	var blend := _frontier_weight(x,z)
	var current := Color.WHITE
	if blend<1.0:
		var local := Color.html(BIOME_COLOR[biome(x,z)])
		var neighbor := Color.html(BIOME_COLOR[biome(x+8.0,z-8.0)])
		current = local.lerp(neighbor,0.26)
	if blend>0.0:
		var region := frontier.kind(Vector2(x,z))
		var base: Color = Frontier.TONES[region]
		match Frontier.NAMES[region]:
			"alpine":
				base = base.lerp(Color("#e6eff2"),smoothstep(40,64,y+n*14))
			"desert":
				base = base.lerp(Color("#e8c782"),0.5+0.5*sin(x*0.069+z*0.033+n))
			"mesa","canyon":
				base = base.lerp(Color("#d9a179"),smoothstep(0.6,2.7,fposmod(y+n,4.3))*0.63)
		current = current.lerp(base,blend)
	var road := road_strength(x, z)
	var pavement := Color("#655f66").lerp(Color("#958783"), clampf(0.5 + n, 0.0, 1.0))
	current = current.lerp(pavement, road * 0.94)
	var shoulder := 4.0 * road * (1.0 - road)
	current = current.lerp(Color("#ae987a"), shoulder * 0.52)
	if y < 1.17:
		current = Color("#c2a986").lerp(current, smoothstep(0.12, 1.17, y))
		var strand := 1.0 - smoothstep(0.05, 0.35, absf(y - 0.44 - n * 0.20))
		current = current.lerp(Color("#907e68"), strand * 0.62)
	if y < -0.25:
		current = current.lerp(Color("#56887d"), smoothstep(0.25, 8.0, -y) * 0.9)
	return current.lerp(Color("#bd8259"), maxf(0.0, n) * 0.3)

func _dressing(cell: Vector2i, start: Vector2, center: Vector2, site: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_at(cell, 3)
	var result: Array = []
	var zone := biome(center.x, center.y)
	var region_id:=region_kind(center.x,center.y)
	var dense := rng.randf_range(0.71, 1.23)
	for index in 87:
		var x := start.x + rng.randf_range(0.4, SIZE - 0.4)
		var z := start.y + rng.randf_range(0.4, SIZE - 0.4)
		var height := ground(x, z, site, center)
		var lot := (Vector2(x, z) - center).abs()
		if height < 0.28 or (site != "" and maxf(lot.x, lot.y) < 7.6):
			continue
		var road := road_strength(x, z)
		var r := rng.randf()
		var kind := "grass" if road < 0.45 else "pebble"
		if index < int(23 * dense):
			if road > 0.48:
				kind = "salvage" if r < 0.32 else "pebble"
			elif r < (0.30 if zone in [2, 3, 4] else 0.57) and height > 1.17:
				kind = "pine" if zone == 1 or (zone != 0 and r < 0.22) else "oak"
			elif r < 0.49:
				kind = "ore" if zone in [2, 3] else "boulder"
			elif r < 0.65:
				kind = "clay_bank" if height < 2.2 else "boulder"
			elif r < 0.78:
				kind = "brush"
		var model:=""
		if region_id!="basin" and road<0.45:
			var cluster:=0.5+0.5*ecology.get_noise_2d(x*1.7,z*1.7)
			var tree_limit:=int(dense*float({"meadow":4,"taiga":30,"alpine":7,"mesa":3,"marsh":10,"canyon":4,"desert":1}.get(region_id,5))*(0.5+cluster))
			if region_id=="alpine": tree_limit=int(tree_limit*(1.0-smoothstep(35.0,59.0,height)))
			if index<tree_limit and height>0.45:
				kind="pine" if region_id in ["taiga","alpine"] else "oak"
				if region_id=="alpine": model="snow_fir"
				elif region_id=="taiga": model="frost_fir" if r<0.70 else "birch"
				elif region_id in ["marsh","mesa","desert","canyon"]: model="snag"
				else: model="birch"
			elif index < tree_limit + (13 if region_id in ["mesa","canyon","alpine"] else 5):
				kind="boulder"
				model="strata" if region_id in ["mesa","canyon","desert"] else "snowstone" if region_id=="alpine" else ""
			elif region_id in ["mesa","canyon","desert","alpine"] and index%5!=0:
				if index%9==0:
					kind="cactus" if region_id=="desert" else "brush"
					model="cactus" if region_id=="desert" else "dry_scrub"
					if revision>=4 and kind=="brush":
						if index%27==0 and (region_id!="alpine" or height<45.0):
							model="brush"
						else:
							kind="grass"
				else: continue
			else:
				kind="grass"
				model="sedge" if region_id=="marsh" else "meadow_grass" if region_id=="meadow" else "dry_scrub" if region_id in ["mesa","desert","canyon","alpine"] else ""
		if region_id!="basin" and region_id in ["alpine","mesa","canyon","desert"]:
			var drop:=absf(ground(x+0.85,z,site,center)-height)+absf(ground(x,z+0.85,site,center)-height)
			if drop>1.55: continue
			if region_id=="desert" and model in ["strata","cactus","dry_scrub"] and rng.randf()>0.47: continue
		var point := Vector3(x - start.x, height - 0.05, z - start.y)
		var entry_lane := (Vector2(x, z) - START).length() < 4.1 or (absf(x - 5.0) < 3.1 and z > 33.0 and z < 44.0)
		if entry_lane and kind in RESOURCES:
			kind = "grass"
		result.append({"index": index, "id": kind, "model":model if kind!="grass" or region_id!="basin" else "", "point": point,
			"scale": rng.randf_range(0.65, 1.31), "angle": rng.randf() * TAU, "variant": rng.randi_range(0, 3)})
	# Extra noninteractive tussocks grow in pockets around the original clumps.
	var meadow: Array = []
	for entry in result:
		if region_id in ["alpine","mesa","desert","canyon"] or entry.id != "grass" or entry.index % 3 != 0:
			continue
		for tuft in range(3):
			var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.52, 2.65)
			var local := Vector2(entry.point.x, entry.point.z) + offset
			var world := start + local
			if not Rect2(0, 0, SIZE, SIZE).has_point(local) or road_strength(world.x, world.y) > 0.45:
				continue
			var lot := (world - center).abs()
			if site != "" and maxf(lot.x, lot.y) < 7.6:
				continue
			var y := ground(world.x, world.y, site, center)
			if y < 0.18:
				continue
			meadow.append({"index": 1000 + int(entry.index) * 3 + tuft, "id": "reeds" if y < 1.1 else "grass",
				"model": "meadow_grass" if region_id=="meadow" else "sedge" if region_id=="marsh" else "",
				"point": Vector3(local.x, y - 0.035, local.y), "scale": rng.randf_range(0.67, 1.16),
				"angle": rng.randf() * TAU, "variant": int(entry.variant)})
	result.append_array(meadow)
	if water_basin(center.x, center.y) or lake_factor(center.x,center.y) < 1.48 or absf(center.x-river_x(center.y)) < SIZE:
		for i in 34:
			var local := Vector2(rng.randf_range(0.5,SIZE-0.5),rng.randf_range(0.5,SIZE-0.5))
			var world := start + local
			var y := ground(world.x,world.y,site,center)
			if y > -0.42 or y < -9.5 or not water_basin(world.x,world.y):
				continue
			var stone := i % 4 == 0
			result.append({"index":2000+i, "id":"bedrock" if stone else "pondweed", "point":Vector3(local.x,y-0.06,local.y),
				"scale":rng.randf_range(0.68,1.4),"angle":rng.randf()*TAU,"variant":i%2})
	var occupied := []
	for entry in result:
		if entry.id in RESOURCES:
			occupied.append(entry.point)
	result.append_array(_harvest_sites(cell,start,center,site,occupied))
	for i in 4:
		var local := Vector2(rng.randf_range(1.0,SIZE-1.0),rng.randf_range(1.0,SIZE-1.0))
		var world := start+local
		var height := ground(world.x,world.y,site,center)
		if height<0.6 or (site!="" and world.distance_to(center)<11.5): continue
		result.append({"index":4800+i,"id":"fallen_stick" if i%2==0 else "pebble","point":Vector3(local.x,height,local.y),"scale":1.0,"angle":rng.randf()*TAU,"variant":i%2,"pickup":true})
	if site!="" and revision>=5:
		# Keep tree trunks, rock outcrops and wrecks away from the doorway and stairs.
		result=result.filter(func(entry:Dictionary)->bool:
			var p:Vector3=entry.point-Vector3(SIZE*0.5,0,SIZE*0.5)
			return not ((absf(p.x)<2.6 and p.z>0 and p.z<(14.5 if site=="bunker" else 9.0)) or (p.x>4.0 and p.x<10.2 and absf(p.z)<7.1)))
	return result
func _harvest_sites(cell: Vector2i, start: Vector2, center: Vector2, site: String, occupied: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_at(cell,41)
	var entries := []
	var counts := {}
	var pocket := seed_at(cell,911)
	for i in 46:
		var local := Vector2(rng.randf_range(1.3,SIZE-1.3),rng.randf_range(1.3,SIZE-1.3))
		var world := start+local
		if world.distance_squared_to(START)<30.0 or (site!="" and absf(world.x-center.x)<10.5 and absf(world.y-center.y)<10.5):
			continue
		var y := ground(world.x,world.y,site,center)
		var road := road_strength(world.x,world.y)
		var zone := biome(world.x,world.y)
		var kind := ""
		var region_id:=region_kind(world.x,world.y)
		if revision>=4 and region_id!="basin" and i%4==2 and road<0.18 and y>=0.1 and y<1.45:
			kind="clay_bank"
		elif revision>=4 and region_id in ["meadow","taiga","marsh"] and posmod(pocket,4)!=0 and i%5==2 and road<0.25 and y>0.45:
			kind="brush"
		elif revision>=4 and region_id in ["alpine","mesa","canyon"] and posmod(pocket,3)!=0 and i%7==3 and road<0.2 and y>3.0:
			kind="ore"
		elif region_id!="basin" and road<0.25 and ((region_id=="marsh" and y>=-0.30 and y<2.8) or (water_basin(world.x,world.y) and y>=-0.38 and y<0.98)):
			kind="reed_bed"
		elif region_id!="basin" and y>0.4 and i%7==1 and (road>0.05 or site!=""):
			kind="machine_wreck"
		elif region_id in ["alpine","mesa","canyon","desert"] and y>0.4 and road<0.2 and i%4==0:
			kind="iron_vein"
		elif region_id in ["meadow","taiga","marsh"] and y>0.3 and road<0.2 and i%3==0:
			kind="herb_patch"
		elif y>=-0.38 and y<0.98 and lake_factor(world.x,world.y)<1.38 and road<0.18:
			kind="reed_bed"
		elif y>1.0 and road>0.035 and road<0.73 and (site in ["fuel","police","bunker"] or zone==4 or i%3==0):
			kind="machine_wreck"
		elif y>1.3 and road<0.09 and (zone in [2,3] or y>7.0 or (site=="bunker" and i%3==0)):
			kind="iron_vein"
		elif y>1.15 and road<0.15 and zone in [0,1]:
			kind="herb_patch"
		if region_id!="basin" and not kind.is_empty() and absf(ground(world.x+0.8,world.y,site,center)-y)+absf(ground(world.x,world.y+0.8,site,center)-y)>1.25: continue
		if kind.is_empty() or int(counts.get(kind,0)) >= (1 if kind in ["machine_wreck","ore","brush","clay_bank"] else 2):
			continue
		var point := Vector3(local.x,y-0.035,local.y)
		if occupied.any(func(p): return point.distance_squared_to(p)<2.65) or entries.any(func(row): return point.distance_squared_to(row.point)<12.0):
			continue
		counts[kind]=int(counts.get(kind,0))+1
		entries.append({"index":3100+i,"id":kind,"point":point,"scale":rng.randf_range(0.88,1.16),"angle":rng.randf()*TAU,"variant":i%3})
	return entries
