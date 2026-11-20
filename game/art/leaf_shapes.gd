extends RefCounted

# Each blade is folded along its midrib so its colour changes as it tumbles.
# Meshes are coloured by the canopy sample on the MultiMesh instance.
static func build(form: String) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if form == "needles":
		_strip(tool, Vector3(0, 0, -0.095), Vector3(0, 0.006, 0.095), 0.006, 0.69)
		for pair in 5:
			var z := -0.068 + pair * 0.031
			var span := 0.064 - pair * 0.005
			for side: float in [-1.0, 1.0]:
				var foot := Vector3(0.0, 0.003, z)
				var tip := foot + Vector3(side * span, 0.013, 0.055)
				_strip(tool, foot, tip, 0.008, 0.84 + pair * 0.035)
	else:
		var widths := PackedFloat32Array([0.012,0.028,0.022,0.045,0.031,0.050,0.031,0.037,0.012,0.0])
		if form == "birch":
			widths = PackedFloat32Array([0.009,0.038,0.048,0.037,0.040,0.028,0.030,0.018,0.011,0.0])
		var previous := PackedVector3Array()
		for row in widths.size():
			var t := float(row) / (widths.size() - 1)
			var z := lerpf(-0.073, 0.104, t)
			var y := sin(t * PI) * 0.008
			var rib := Vector3(sin(t * PI) * 0.004, y + 0.016 * sin(t * PI), z)
			var section := PackedVector3Array([Vector3(-widths[row], y, z-0.003), rib, Vector3(widths[row]*0.93,y,z+0.003)])
			if row > 0:
				for facet in 2:
					var tone := 0.80 if facet == 0 else 1.0
					_triangle(tool,previous[facet],section[facet],previous[facet+1],tone)
					_triangle(tool,previous[facet+1],section[facet],section[facet+1],tone)
			previous = section
		_strip(tool,Vector3(-0.005,0.0,-0.105),Vector3(0,0.003,-0.064),0.0035,0.63)
	return tool.commit()

static func _strip(tool: SurfaceTool, foot: Vector3, tip: Vector3, width: float, tone: float) -> void:
	var crosswise := Vector3.UP.cross(tip - foot).normalized() * width
	var middle := foot.lerp(tip, 0.48)
	_triangle(tool, foot, middle - crosswise, tip, tone)
	_triangle(tool, foot, tip, middle + crosswise, tone * 0.87)

static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tone: float) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.is_zero_approx(): return
	if normal.y < 0.0:
		var swap := c
		c = b
		b = swap
		normal = -normal
	for point in [a, b, c]:
		tool.set_normal(normal)
		tool.set_color(Color(tone, tone, tone))
		tool.add_vertex(point)
