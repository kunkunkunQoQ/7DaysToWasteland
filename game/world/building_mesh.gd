extends RefCounted

# Each face owns its four corners for flat normals and square UVs. The index
# stream retains the original triangle winding and the 36 collision points per box.
const CORNERS := [
	Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,-1,1), Vector3(-1,-1,1),
	Vector3(-1,1,-1), Vector3(1,1,-1), Vector3(1,1,1), Vector3(-1,1,1)
]
const FACES := [[0,1,2,3], [7,6,5,4], [4,5,1,0], [1,5,6,2], [2,6,7,3], [3,7,4,0]]
const UV := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
const WINDING := [0,2,1,0,3,2]
static var uvs := PackedVector2Array()
static var indices := PackedInt32Array()

static func boxes(parts: Array) -> ArrayMesh:
	var count := parts.size()
	var vertex_count := count * 24
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	var points := PackedVector3Array()
	points.resize(8)
	var dst := 0
	for part: Array in parts:
		var center: Vector3 = part[0]
		var size: Vector3 = part[1]
		var tint: Color = part[2]
		var basis: Basis = part[3] if part.size() > 3 else Basis.IDENTITY
		var taper: float = part[4] if part.size() > 4 else 1.0
		# A collapsed or inverted cap can give the two triangles different
		# normals. Such a face needs the original independent corners.
		if taper <= 0.0 or size.x == 0.0 or size.y == 0.0 or size.z == 0.0 or basis.determinant() == 0.0:
			return WastelandLook.mesh_parts(parts)
		for i in 8:
			var p: Vector3 = CORNERS[i] * size * 0.5
			if p.y > 0.0:
				p *= Vector3(taper, 1, taper)
			points[i] = center + basis * p
		for face: Array in FACES:
			var a := points[face[0]]
			var b := points[face[1]]
			var c := points[face[2]]
			var normal := (b-a).cross(c-a).normalized()
			for corner: int in face:
				vertices[dst] = points[corner]
				normals[dst] = normal
				colors[dst] = tint
				dst += 1
	_extend_topology(count)
	var attributes := []
	attributes.resize(Mesh.ARRAY_MAX)
	attributes[Mesh.ARRAY_VERTEX] = vertices
	attributes[Mesh.ARRAY_NORMAL] = normals
	attributes[Mesh.ARRAY_COLOR] = colors
	attributes[Mesh.ARRAY_TEX_UV] = uvs.slice(0, vertex_count)
	attributes[Mesh.ARRAY_INDEX] = indices.slice(0, count * 36)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, attributes)
	return mesh

static func _extend_topology(count: int) -> void:
	var faces := count * 6
	var existing := uvs.size() / 4
	if faces <= existing: return
	uvs.resize(faces * 4)
	indices.resize(faces * 6)
	for face in range(existing, faces):
		for i in 4:
			uvs[face*4+i] = UV[i]
		for i in 6:
			indices[face*6+i] = face*4 + int(WINDING[i])
