extends RefCounted

# Source meshes share the same world-space vertex-colour shader as chunk scenery.
# Only the triangles around the cut need clipping after the first hit.
const CUT_Y := 0.80
const MIN_CUT := 0.78
const MAX_CUT := 1.46
const HALF_BAND := 0.13
const SAP := Color("#e8bd80")
const HEART := Color("#be8956")
static var profiles := {}
static var logs := {}

static func parts(source: Mesh, local_face: Vector3, damage: float, severed: bool, cut_height: float = -1.0) -> Dictionary:
	if not profiles.has(source):
		profiles[source] = _profile(source)
	var data: Dictionary = profiles[source]
	var y := clampf(cut_height if is_finite(cut_height) and cut_height >= 0 else CUT_Y, MIN_CUT, data.cut_max)
	var cut_plane := Plane(Vector3.UP, y)
	var section := PackedVector3Array()
	for tri: Array in data.band:
		if tri[3]: _clip(tri[0], cut_plane, 1, section)
	var ring := _outline(section)
	var cross_bounds := AABB(ring[0], Vector3.ZERO)
	for p in ring: cross_bounds = cross_bounds.expand(p)
	var pivot := cross_bounds.get_center()
	var radius := maxf(cross_bounds.size.x, cross_bounds.size.z) * 0.5
	var face := Vector3(local_face.x, 0, local_face.z).normalized()
	if face == Vector3.ZERO: face = Vector3.FORWARD
	var progress := 1.0 if severed else clampf(damage, 0.0, 1.0)
	var front := -INF
	var back := INF
	for p in ring:
		var distance := face.dot(p - pivot)
		front = maxf(front, distance)
		back = minf(back, distance)
	var depth := lerpf(0.12, 0.78, progress) if progress > 0.0 or severed else 0.0
	var hinge := pivot + face * lerpf(front, back, depth)
	var slope := minf(0.57, HALF_BAND * 0.92 / (front - back))
	var lower := _surface()
	var upper := _surface()
	for side: int in [-1, 1]:
		var tool := upper if side > 0 else lower
		# Keep the uncut side on the horizontal fracture plane and carve an
		# inclined axe face into the struck side of both halves.
		var inward := (Vector3.UP * side - face * slope).normalized()
		var bevel := Plane(inward, hinge)
		var lip := PackedVector3Array()
		for tri: Array in data.band:
			var half := _clip(tri[0], cut_plane, side, PackedVector3Array())
			var polygon := _clip(half, bevel, 1, lip if tri[3] else PackedVector3Array())
			_fan(tool, polygon, tri[1], tri[2])
		if lip.size() >= 3:
			_endgrain(tool, _outline(lip), -inward, SAP if side < 0 else SAP.darkened(0.10))
		if severed:
			var held := _clip(ring, Plane(face, hinge), -1, PackedVector3Array())
			_endgrain(tool, held, Vector3.DOWN * side, HEART.lightened(0.14))
			_fibres(tool, held, radius, side)
	var stump_mesh := ArrayMesh.new()
	var top_mesh := ArrayMesh.new()
	if not data.roots.is_empty():
		stump_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.roots)
	top_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.crown)
	lower.commit(stump_mesh)
	upper.commit(top_mesh)
	return {"stump": stump_mesh, "upper": top_mesh, "pivot": pivot, "height": data.top_y - y,
		"trunk_radius": radius, "crown_radius": data.crown_radius}

static func _surface() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool

static func _profile(source: Mesh) -> Dictionary:
	var arrays := source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else points.size()
	var upper_ids := PackedInt32Array()
	var roots := _surface()
	var root_count := 0
	var band := []
	var trunk := true
	var cut_max := MAX_CUT
	for i in range(0, count, 3):
		var a := indices[i] if not indices.is_empty() else i
		var b := indices[i+1] if not indices.is_empty() else i+1
		var c := indices[i+2] if not indices.is_empty() else i+2
		var lo := minf(points[a].y, minf(points[b].y, points[c].y))
		var hi := maxf(points[a].y, maxf(points[b].y, points[c].y))
		# Every harvestable tree starts with its stem tube. Its lower cap
		# follows the last side face, before roots, markings and branches.
		if trunk and hi < 0 and normals[a].y < -0.9: trunk = false
		var foliage := false
		if not trunk and hi > 1.0 and lo < MAX_CUT + HALF_BAND:
			for id in [a,b,c]:
				if Vector2(points[id].x, points[id].z).length_squared() > 0.64:
					foliage = true
					break
		if foliage: cut_max = minf(cut_max, lo + 0.10)
		if lo >= MAX_CUT + HALF_BAND or foliage:
			upper_ids.append(a)
			upper_ids.append(b)
			upper_ids.append(c)
			continue
		var triangle := PackedVector3Array([points[a], points[b], points[c]])
		if hi <= MIN_CUT - HALF_BAND:
			_fan(roots, triangle, normals[a], colours[a])
			root_count += 1
		else:
			band.append([triangle, normals[a], colours[a], trunk])
	var crown_bounds := source.get_aabb()
	arrays[Mesh.ARRAY_INDEX] = upper_ids
	return {"crown": arrays, "roots": roots.commit_to_arrays() if root_count else [],
		"band": band, "cut_max": cut_max, "top_y": crown_bounds.end.y,
		"crown_radius": maxf(crown_bounds.size.x, crown_bounds.size.z) * 0.5}

static func _clip(poly: PackedVector3Array, plane: Plane, side: int, intersections: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	if poly.is_empty(): return result
	var previous := poly[-1]
	var before := plane.distance_to(previous) * side
	for point in poly:
		var after := plane.distance_to(point) * side
		if (after >= 0.0) != (before >= 0.0):
			var crossing := previous.lerp(point, before / (before - after))
			result.append(crossing)
			intersections.append(crossing)
		if after >= 0.0: result.append(point)
		previous = point
		before = after
	return result

# All clipped faces are single convex trunk sections. A 2D hull removes repeated
# triangle edges and bark decoration inside the solid.
static func _outline(points: PackedVector3Array) -> PackedVector3Array:
	var flat := PackedVector2Array()
	var lookup := {}
	for point in points:
		var key := Vector2(point.x, point.z).snapped(Vector2.ONE * 0.00001)
		if not lookup.has(key):
			flat.append(key)
			lookup[key] = point
	var result := PackedVector3Array()
	if flat.size() < 3: return result
	var hull := Geometry2D.convex_hull(flat)
	for i in range(hull.size()-1):
		result.append(lookup[hull[i]])
	return result

static func _fan(tool: SurfaceTool, poly: PackedVector3Array, normal: Vector3, tint: Color) -> void:
	for i in range(1, poly.size()-1):
		_triangle(tool, poly[0], poly[i], poly[i+1], normal, tint)

static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, tint: Color) -> void:
	var facing := (c-a).cross(b-a).dot(normal)
	if absf(facing) < 0.00000001: return
	tool.set_color(tint)
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.add_vertex(b if facing > 0 else c)
	tool.add_vertex(c if facing > 0 else b)

static func _endgrain(tool: SurfaceTool, rim: PackedVector3Array, normal: Vector3, sapwood: Color) -> void:
	if rim.size() < 3: return
	var center := Vector3.ZERO
	for p in rim: center += p
	center /= rim.size()
	# Alternating thin growth lines are baked into the end face, with no
	# coplanar decals and no additional material or texture.
	var scales := [1.0, 0.88, 0.66, 0.60, 0.34, 0.29, 0.0]
	var tones := [sapwood.darkened(0.10), sapwood, HEART, sapwood.lerp(HEART, 0.32), HEART, sapwood.lerp(HEART, 0.50)]
	for i in rim.size():
		var p := rim[i] - center
		var q := rim[(i+1)%rim.size()] - center
		for layer in tones.size():
			var a: Vector3 = center+p*scales[layer]
			var b: Vector3 = center+q*scales[layer]
			var c: Vector3 = center+p*scales[layer+1]
			var d: Vector3 = center+q*scales[layer+1]
			_triangle(tool, a,b,c,normal,tones[layer])
			_triangle(tool, c,b,d,normal,tones[layer])

static func _fibres(tool: SurfaceTool, rim: PackedVector3Array, radius: float, side: int) -> void:
	if rim.size() < 3: return
	var center := Vector3.ZERO
	for p in rim: center += p
	center /= rim.size()
	for i in 6:
		var p := center.lerp(rim[(i*3)%rim.size()], 0.40 + 0.23*sin(i*5.2))
		var span := radius * (0.035 + 0.016*cos(i*3.3))
		var tip := p + Vector3(0.05*sin(i), -side*(0.19+0.24*absf(sin(i*2.3))), 0.04*cos(i))*radius
		var feet := PackedVector3Array([p + Vector3.RIGHT*span, p + Vector3.BACK*span, p - Vector3(1,0,1)*span])
		for j in 3:
			var a := feet[j]
			var b := feet[(j+1)%3]
			var normal := (b-a).cross(tip-a).normalized()
			if normal.dot((a+b)*0.5-p) < 0: normal = -normal
			_triangle(tool,a,b,tip,normal,SAP.darkened(0.08*j))

# Unit log centred on the Z axis. Callers set the two radial scales and length.
static func log_mesh(model: String, variant: int) -> ArrayMesh:
	var key := "%s/%d" % [model, variant]
	if logs.has(key): return logs[key]
	var bark: Color = {"birch": Color("#c3bba5"), "snag": Color("#726650"), "pine": Color("#68534b"),
		"frost_fir": Color("#62594b"), "snow_fir": Color("#62594b")}.get(model,
		Color.html(["664635","6d4b3c","755340","684b42"][posmod(variant,4)]))
	var tool := _surface()
	var ends: Array[PackedVector3Array] = []
	for end in 2:
		var rim := PackedVector3Array()
		for i in 9:
			var angle := i*TAU/9 + variant*0.31 + end*0.035
			var width := (0.95 + 0.05*sin(3.2*i+variant)) * (1.0-end*0.07)
			rim.append(Vector3(cos(angle)*width, sin(angle)*width, float(end)-0.5))
		ends.append(rim)
		_endgrain(tool,rim,Vector3.BACK if end else Vector3.FORWARD,SAP)
	for i in 9:
		var j := (i+1)%9
		var normal := Vector3(ends[0][i].x+ends[0][j].x, ends[0][i].y+ends[0][j].y,0).normalized()
		var shade := bark.darkened(0.08*(i%3))
		_triangle(tool,ends[0][i],ends[0][j],ends[1][i],normal,shade)
		_triangle(tool,ends[0][j],ends[1][j],ends[1][i],normal,shade.darkened(0.06))
		# Tapered fissures follow the fibres. Birch has shorter horizontal
		# lenticels, matching the dark dashes on its original standing stem.
		var low := ends[0][i].lerp(ends[0][j],0.33)
		var high := ends[1][i].lerp(ends[1][j],0.33)
		var crosswise := ends[0][j]-ends[0][i]
		var middle := low.lerp(high,0.46+0.14*sin(i*2.3+variant))+normal*0.008
		if model == "birch":
			for dash in 2:
				var base := middle+Vector3.BACK*(dash*0.28-0.14)
				_triangle(tool,base-crosswise*0.16,base+crosswise*0.39,
					base+crosswise*0.18+Vector3.BACK*0.031,normal,Color("#5e594b"))
		else:
			var run := (high-low)*(0.13+0.07*cos(i*1.8))
			_triangle(tool,middle-run,middle+crosswise*0.09,middle+run,normal,shade.darkened(0.22))
			_triangle(tool,middle-run,middle+run,middle-crosswise*0.04,normal,shade.lightened(0.12))
	logs[key] = tool.commit()
	return logs[key]
