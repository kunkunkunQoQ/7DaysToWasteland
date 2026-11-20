extends RefCounted

const WOOD := Color.WHITE
const FITTING := Color("#404040")

static func mesh(tier: int, shape: int, opened: bool) -> Mesh:
	var parts: Array = []
	match shape:
		0, 2:
			var height := 0.5 if shape == 2 else 1.0
			if tier == 0:
				_frame(parts, height)
			else:
				parts.append([Vector3(0, -0.5 + height*0.5, 0), Vector3(1,height,1), WOOD])
		1:
			if tier > 0:
				return _ramp()
			# Flat deck boards follow the same incline as the solid ramp collision.
			var lean := Basis(Vector3.RIGHT, PI/4)
			for i in 6:
				var z := -0.405 + i*0.160
				parts.append([Vector3(0,-z-0.018,z),Vector3(0.99,0.030,0.207),WOOD,lean])
			for x in [-0.39,0.39]:
				parts.append([Vector3(x,-0.037,-0.025),Vector3(0.084,0.060,1.238),WOOD,lean])
				parts.append([Vector3(x,-0.03,-0.442),Vector3(0.08,0.93,0.08),WOOD])
		3:
			_railing(parts,tier)
		4:
			_hatch(parts,tier,opened)
	return WastelandLook.mesh_parts(parts)

static func _frame(parts: Array, height: float) -> void:
	var bottom := -0.454
	var top := height - 0.546
	for x in [-0.453,0.453]:
		for z in [-0.453,0.453]:
			parts.append([Vector3(x,-0.5+height*0.5,z),Vector3(0.094,height,0.094),WOOD])
	for y in [bottom,top]:
		for edge in [-0.453,0.453]:
			parts.append([Vector3(edge,y,0),Vector3(0.091,0.091,0.816),WOOD])
			parts.append([Vector3(0,y,edge),Vector3(0.816,0.091,0.091),WOOD])
	for z in [-0.452,0.452]:
		var span := Vector3(0.838,top-bottom,0)
		parts.append([Vector3(0,(top+bottom)*0.5,z),Vector3(0.054,span.length(),0.052),WOOD,Basis(Quaternion(Vector3.UP,span.normalized()))])

static func _railing(parts: Array, tier: int) -> void:
	var pier := 0.17 if tier in [2,3] else 0.105
	for x in [-0.399,0.399]:
		parts.append([Vector3(x,-0.02,0),Vector3(pier,0.92,0.18),WOOD])
		parts.append([Vector3(x,0.44,0),Vector3(pier+0.032,0.065,0.225),FITTING if tier>=3 else WOOD])
	for y in [-0.26,0.25]:
		parts.append([Vector3(0,y,0.066),Vector3(0.98,0.09,0.074),FITTING if tier>=2 else WOOD])
	if tier==0:
		parts.append([Vector3(0,0,0),Vector3(0.060,1.01,0.08),WOOD,Basis(Vector3.FORWARD,0.96)])
	else:
		for x in [-0.20,0,0.20]:
			parts.append([Vector3(x,-0.055,0),Vector3(0.057 if tier>=2 else 0.095,0.66,0.073),FITTING if tier>=2 else WOOD])

static func _hatch(parts: Array, tier: int, opened: bool) -> void:
	# Build the leaf in its closed pose so the hardware turns with the hinge.
	for i in 4:
		parts.append([Vector3((i-1.5)*0.245,-0.434,0),Vector3(0.238,0.10,0.98),WOOD])
	for z in [-0.31,0.31]:
		parts.append([Vector3(0,-0.374,z),Vector3(0.87,0.032,0.066),FITTING if tier>=1 else WOOD])
	for x in [-0.32,0.32]:
		parts.append([Vector3(x,-0.386,-0.424),Vector3(0.18,0.072,0.095),FITTING])
	parts.append([Vector3(0,-0.371,0.28),Vector3(0.225,0.066,0.086),FITTING])
	if opened:
		for part: Array in parts:
			var point: Vector3 = part[0]
			var size: Vector3 = part[1]
			part[0] = Vector3(point.x,-0.06+point.z*0.88,-0.422-(point.y+0.43)*0.84)
			part[1] = Vector3(size.x,size.z*0.88,size.y*0.84)

static func _ramp() -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var points := [Vector3(-0.5,-0.5,-0.5),Vector3(0.5,-0.5,-0.5),Vector3(0.5,-0.5,0.5),Vector3(-0.5,-0.5,0.5),Vector3(-0.5,0.5,-0.5),Vector3(0.5,0.5,-0.5)]
	for face in [[0,3,2,0,2,1],[4,5,2,4,2,3],[0,4,3],[1,2,5],[0,1,5,0,5,4]]:
		for index in face:
			surface.set_color(WOOD)
			surface.add_vertex(points[index])
	surface.generate_normals()
	return surface.commit()
