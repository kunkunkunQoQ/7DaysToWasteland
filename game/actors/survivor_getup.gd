extends RefCounted

# Keep the last physical pose through the handoff. The pelvis, legs and torso
# regain their animated targets at different rates as weight returns to the feet.
var joints: Array[Node3D]
var fallen: Array[Transform3D] = []
var targets: Array[Transform3D] = []
var time := 0.0
var duration: float

func _joints(person: WastelandPartyAvatar) -> Array[Node3D]:
	var result: Array[Node3D] = [person.pivot, person.jacket, person.neck]
	for chain in [person.legs, person.knees, person.ankle_joints, person.arms, person.elbows, person.wrist_joints]:
		result.append_array(chain)
	return result

func _init(person: WastelandPartyAvatar, donor: WastelandPartyAvatar) -> void:
	joints = _joints(person)
	var source := _joints(donor)
	duration = lerpf(0.52, 0.81, clampf(donor.jacket.global_basis.z.normalized().dot(Vector3.DOWN), 0.0, 1.0))
	for i in joints.size():
		targets.append(joints[i].transform)
		fallen.append(person.global_transform.affine_inverse() * source[i].global_transform if i == 0 else source[i].transform)
		joints[i].transform = fallen[i]

func restore_targets() -> void:
	for i in joints.size(): joints[i].transform = targets[i]

func blend(dt: float) -> bool:
	time += dt
	if time >= duration: return true
	var progress := time / duration
	for i in joints.size():
		targets[i] = joints[i].transform
		var weight := smoothstep(0.0, 1.0, progress)
		if i == 1 or i == 2: weight = smoothstep(0.0, 0.82, progress)
		elif i >= 3 and i <= 8: weight = smoothstep(0.0, 0.88, progress)
		elif i >= 9: weight = smoothstep(0.12, 1.0, progress)
		joints[i].transform = fallen[i].interpolate_with(targets[i], weight)
	return false
