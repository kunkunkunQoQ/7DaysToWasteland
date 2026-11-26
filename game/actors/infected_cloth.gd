extends RefCounted

# Both meshes stay on the animated torso. Only vertices below their seam move.
const REACH := 32.0
const TRAVEL := 0.072
const SPRING := 9.5
var skeleton: Skeleton3D
var torso: int
var shirt: MeshInstance3D
var accessory: MeshInstance3D
var anchor := Vector3.INF
var last_velocity := Vector3.ZERO
var offset := Vector2.ZERO
var speed := Vector2.ZERO
var rest_clock := 0.0

static func flexible_mesh(base: ArrayMesh, seam: float, loose_end: float) -> ArrayMesh:
	var arrays := base.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var shaped := ArrayMesh.new()
	shaped.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var targets: Array[Array] = []
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		shaped.add_blend_shape("Across" if axis == Vector3.RIGHT else "Back")
		var target_points := points.duplicate()
		var target_normals := normals.duplicate()
		for i in points.size():
			var u := clampf((seam-points[i].y)/(seam-loose_end),0.0,1.0)
			target_points[i] += axis * (TRAVEL*u*u)
			if u > 0 and u < 1:
				var slope := -2.0*TRAVEL*u/(seam-loose_end)
				target_normals[i] = (normals[i] - Vector3.UP*normals[i].dot(axis)*slope).normalized()
		var channels := []
		channels.resize(Mesh.ARRAY_MAX)
		channels[Mesh.ARRAY_VERTEX] = target_points
		channels[Mesh.ARRAY_NORMAL] = target_normals
		targets.append(channels)
	shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,targets)
	shaped.custom_aabb = base.get_aabb().grow(TRAVEL)
	return shaped

func reset() -> void:
	rest_clock = 0.0
	if not anchor.is_finite(): return
	anchor = Vector3.INF
	last_velocity = Vector3.ZERO
	offset = Vector2.ZERO
	speed = Vector2.ZERO
	_apply()

func tick_resting(span: float) -> void:
	rest_clock += span
	if rest_clock < 0.10: return
	var elapsed := rest_clock
	rest_clock = 0.0
	tick(minf(elapsed,0.15))

func tick(span: float, distance := 0.0) -> void:
	if distance > REACH or not shirt.is_visible_in_tree():
		reset()
		return
	var camera := shirt.get_viewport().get_camera_3d()
	# BoneAttachment3D is updated later by Godot. Read the torso that the solver just wrote.
	var garment := skeleton.global_transform * skeleton.get_bone_global_pose(torso) * shirt.transform
	var point := garment * Vector3(0,0.20,0.04)
	if not camera or not camera.is_position_in_frustum(point) or camera.global_position.distance_squared_to(point) > REACH*REACH:
		reset()
		return
	if not anchor.is_finite() or anchor.distance_squared_to(point) > 1.0 or span > 0.15:
		reset()
		anchor = point
		return
	var velocity := (point-anchor)/span
	var acceleration := ((velocity-last_velocity)/span).limit_length(19.0)
	anchor = point
	last_velocity = velocity
	var local_force := garment.basis.orthonormalized().transposed() * (Vector3.DOWN*3.5 - acceleration*0.70 - velocity*0.65)
	var goal := (Vector2(local_force.x,local_force.z)/(SPRING*SPRING)).limit_length(TRAVEL)
	if offset.distance_squared_to(goal) < 0.00000001 and speed.length_squared() < 0.000001: return
	# Exact critically damped spring, stable at both near and distant pose rates.
	var displacement := offset-goal
	var impulse := speed+displacement*SPRING
	var decay := exp(-SPRING*span)
	offset = goal+(displacement+impulse*span)*decay
	speed = (speed-impulse*SPRING*span)*decay
	_apply()

func _apply() -> void:
	shirt.set_blend_shape_value(0,offset.x/TRAVEL)
	shirt.set_blend_shape_value(1,offset.y/TRAVEL)
	if accessory:
		accessory.set_blend_shape_value(0,offset.x*0.7/TRAVEL)
		accessory.set_blend_shape_value(1,offset.y*0.7/TRAVEL)
