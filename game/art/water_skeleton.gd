extends Node3D

const Sculpt := WastelandBestiary.Sculpture
const Faces := preload("res://game/art/species_faces.gd")
const April := preload("res://game/art/april_face.gd")

# A morph has a single surface and shared inverse bind matrices. Only the pose is per animal.
static var templates := {}
var bones: Skeleton3D
var bone_ids := {}
var _rests: Array[Vector3] = []
var _parts: Array[Sculpt] = []
var _layout: Array = []
var _head := -1
var _face: MeshInstance3D
var _mask: MeshInstance3D
var _face_bind := Transform3D.IDENTITY
var _mask_bind := Transform3D.IDENTITY
var previewing := false
var preview_time := 0.0

func build_skin(key: String, sculpt: Callable) -> void:
	bones = Skeleton3D.new()
	bones.name = "Skeleton3D"
	add_child(bones)
	if not templates.has(key):
		sculpt.call()
		var mesh := _bake()
		var skin := bones.create_skin_from_rest_transforms()
		templates[key] = {"mesh":mesh, "skin":skin, "layout":_layout}
		_parts.clear()
		_layout = []
	else:
		for row: Array in templates[key].layout:
			_add_bone(row[0], row[1], row[2])
	bones.reset_bone_poses()
	var surface := MeshInstance3D.new()
	surface.name = "Body"
	add_child(surface)
	surface.skeleton = surface.get_path_to(bones)
	surface.skin = templates[key].skin
	surface.mesh = templates[key].mesh
	surface.material_override = WastelandLook.colored_material()
	var bound := surface.mesh.get_aabb()
	surface.custom_aabb = bound.grow(bound.size.length()*0.40)
	set_process(previewing)

func _add_bone(id: String, parent: int, origin: Vector3) -> int:
	var index := bones.get_bone_count()
	bones.add_bone(id)
	bone_ids[id] = index
	if parent >= 0:
		bones.set_bone_parent(index,parent)
	var local := origin if parent < 0 else origin-_rests[parent]
	bones.set_bone_rest(index,Transform3D(Basis.IDENTITY,local))
	_rests.append(origin)
	return index

# Origins are in model space, sculpted geometry is local to its bone.
func joint(id: String, parent: String, origin: Vector3) -> Sculpt:
	var parent_index: int = bone_ids.get(parent,-1)
	_layout.append([id,parent_index,origin])
	_add_bone(id,parent_index,origin)
	var part := Sculpt.new(52+_parts.size())
	_parts.append(part)
	return part

func _bake() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in _parts.size():
		var part := _parts[i]
		if part.triangle_count == 0: continue
		var source := part.commit().surface_get_arrays(0)
		var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var first := vertices.size()
		var end := first+points.size()
		indices.resize(end*4)
		weights.resize(end*4)
		for vertex in range(first,end):
			indices[vertex*4] = i
			weights[vertex*4] = 1.0
		for p in points:
			vertices.append(p+_rests[i])
		normals.append_array(source[Mesh.ARRAY_NORMAL])
		colors.append_array(source[Mesh.ARRAY_COLOR])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = indices
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func attach_head(id: String, species: String, form: String, variant: int, skull: Vector3, radii: Vector3, mask_at: Vector3, mask_size: Vector2) -> void:
	_head = bone_ids[id]
	_face = Faces.attach_aquatic(self,species,form,variant,skull-_rests[_head],radii)
	_mask = April.attach(self,mask_at-_rests[_head],mask_size)
	_face_bind = _face.transform
	_mask_bind = _mask.transform
	sync_head()

func sync_head() -> void:
	var skull := bones.get_bone_global_pose(_head)
	_face.transform = skull*_face_bind
	_mask.transform = skull*_mask_bind

func bend(id: String, x: float, y := 0.0, z := 0.0) -> void:
	bones.set_bone_pose_rotation(bone_ids[id],Quaternion.from_euler(Vector3(x,y,z)))

