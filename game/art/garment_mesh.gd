extends RefCounted

# All three sets of indices address the same garment vertices, including their
# fabric colors and skin weights. Godot chooses a set using projected size.
const MEDIUM_ERROR := 0.022
const DISTANT_ERROR := 0.065

static func rings(sides: int, rows: PackedInt32Array, step := 1, reverse := false, offset := 0) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for row in rows.size() - 1:
		for i in range(0, sides, step):
			var j := (i + step) % sides
			var a := offset + rows[row] * sides + i
			var b := offset + rows[row] * sides + j
			var c := offset + rows[row+1] * sides + i
			var d := offset + rows[row+1] * sides + j
			if reverse: indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
			else: indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	return indices

static func finish(surface: SurfaceTool, near: PackedInt32Array, middle: PackedInt32Array, far: PackedInt32Array) -> ArrayMesh:
	var arrays := surface.commit_to_arrays()
	arrays[Mesh.ARRAY_INDEX] = near
	if arrays[Mesh.ARRAY_NORMAL] == null:
		# Keep original vertex numbers for the coarser index sets. SurfaceTool's
		# generate_normals() reindexes a surface and can reorder skinned seams.
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		normals.resize(vertices.size())
		for i in range(0, near.size(), 3):
			var a := near[i]
			var b := near[i+1]
			var c := near[i+2]
			var n := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
			normals[a] += n
			normals[b] += n
			normals[c] += n
		for i in normals.size(): normals[i] = normals[i].normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {MEDIUM_ERROR: middle, DISTANT_ERROR: far})
	return mesh

# Caps, straps and sleeves are sculpted as separate triangles. Their coarse
# shape has its own normals and UVs, packed into the same renderer surface.
static func sculpted(detail: ArrayMesh, coarse: ArrayMesh) -> ArrayMesh:
	var arrays := detail.surface_get_arrays(0)
	var lower := coarse.surface_get_arrays(0)
	var vertex_count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var indices := PackedInt32Array(range(vertex_count)) if arrays[Mesh.ARRAY_INDEX] == null else PackedInt32Array(arrays[Mesh.ARRAY_INDEX])
	var lod := PackedInt32Array(range(lower[Mesh.ARRAY_VERTEX].size())) if lower[Mesh.ARRAY_INDEX] == null else PackedInt32Array(lower[Mesh.ARRAY_INDEX])
	for i in lod.size(): lod[i] += vertex_count
	for attribute in Mesh.ARRAY_INDEX:
		if arrays[attribute] != null: arrays[attribute].append_array(lower[attribute])
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {MEDIUM_ERROR: lod})
	return mesh
