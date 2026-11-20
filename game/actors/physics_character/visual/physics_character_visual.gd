extends Node3D
## Display-only skeleton. Each bone follows a world pose published in a snapshot.

const Config := preload("../config/physics_character_config.gd")
const State := preload("../state/physics_character_state.gd")

var _skeleton: Skeleton3D
var _bone_ids: Array[StringName] = []
var _parents: Dictionary[StringName, StringName] = {}

func setup(config: Config) -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton3D"
	add_child(_skeleton)
	for joint: Dictionary in config.build_joints():
		_parents[joint.child] = joint.parent
	var rest_centers: Dictionary[StringName, Vector3] = {}
	var core := _material(Color("#d5e0df"))
	var left := _material(Color("#7ab5bd"))
	var right := _material(Color("#a7b5cd"))
	for segment: Dictionary in config.build_segments():
		var id: StringName = segment.id
		var index := _skeleton.add_bone(String(id))
		_bone_ids.append(id)
		var parent: StringName = _parents.get(id, &"")
		var rest_center: Vector3 = segment.position
		var relative_center := rest_center
		if parent != &"":
			_skeleton.set_bone_parent(index, _skeleton.find_bone(String(parent)))
			relative_center -= rest_centers[parent]
		rest_centers[id] = rest_center
		_skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, relative_center))
		_skeleton.reset_bone_pose(index)
		var attachment := BoneAttachment3D.new()
		attachment.name = id
		_skeleton.add_child(attachment)
		attachment.bone_idx = index
		var material := core
		if String(id).ends_with("_l"):
			material = left
		elif String(id).ends_with("_r"):
			material = right
		for primitive: Dictionary in segment.get("collision_parts", [segment]):
			var geometry := MeshInstance3D.new()
			geometry.mesh = _segment_mesh(primitive.shape, primitive.size)
			geometry.transform = primitive.get("transform", Transform3D.IDENTITY)
			geometry.material_override = material
			attachment.add_child(geometry)

func sync_state(state: State) -> void:
	var poses: Dictionary = state.body_poses
	var skeleton_inverse := _skeleton.global_transform.affine_inverse()
	for index in _bone_ids.size():
		var id := _bone_ids[index]
		var world: Transform3D = poses[id]
		var parent: StringName = _parents.get(id, &"")
		var parent_inverse := skeleton_inverse
		if parent != &"":
			var parent_world: Transform3D = poses[parent]
			parent_inverse = parent_world.affine_inverse()
		_skeleton.set_bone_pose(index, parent_inverse * world)

func _segment_mesh(kind: StringName, size: Vector3) -> PrimitiveMesh:
	if kind == &"capsule":
		var capsule := CapsuleMesh.new()
		capsule.radius = size.x * 0.5
		capsule.height = size.y
		capsule.radial_segments = 16
		capsule.rings = 6
		return capsule
	var box := BoxMesh.new()
	box.size = size
	return box

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
