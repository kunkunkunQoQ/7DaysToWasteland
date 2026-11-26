extends RefCounted

# Near, grounded characters keep stance points in world space as their body
# moves or turns. Swing still belongs to each species' original gait solver.
var enabled := false
var recovery_foot := -1
var planted := PackedVector3Array([Vector3.INF,Vector3.INF,Vector3.INF,Vector3.INF])
var release_offset := PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])

func clear() -> void:
	planted.fill(Vector3.INF)
	release_offset.fill(Vector3.ZERO)
	enabled = false
	recovery_foot = -1

func target(index: int, frame: Transform3D, local_point: Vector3, in_stance: bool, swing: float, reach: float) -> Vector3:
	if not enabled:
		return local_point
	if index == recovery_foot:
		planted[index] = Vector3.INF
		release_offset[index] = Vector3.ZERO
		return local_point
	var world := frame * local_point
	var offset := Vector3.ZERO
	if in_stance:
		if not planted[index].is_finite():
			planted[index] = world
		offset = planted[index] - world
		offset.y = 0.0
		# A shove or a replicated snap can carry the hip past its reach.
		if offset.length_squared() > reach * reach:
			offset = offset.limit_length(reach)
			planted[index] = world + offset
		release_offset[index] = offset
	else:
		planted[index] = Vector3.INF
		offset = release_offset[index] * (1.0 - smoothstep(0.0, 0.65, swing))
	return local_point + frame.basis.inverse() * offset
