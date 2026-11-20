extends RefCounted

# Center of the opening between the thumb and curled fingers in the original
# handle/trigger meshes. The support arm is a mirrored copy of the same hand.
const PALM := Vector3(0.100,-0.012,-0.290)

static func fit(id: String, asset: MeshInstance3D, support: MeshInstance3D) -> void:
	var main_socket := Vector3(0,-0.072,0.028)
	var support_socket := Vector3.ZERO
	var support_contact := PALM
	var support_rotation := Vector3(0.68,-0.69,-0.46)
	match id:
		"bow":
			# Right hand grips the wrapped bow, left fingers catch the nock.
			# Canting the bow clears the returning string from the right wrist.
			main_socket = Vector3(0,-0.003,-0.215)
			asset.rotation = Vector3(0.024,-0.38,-0.18)
			support_socket = Vector3(0,0.071,0.126)
			# A cord is much narrower than a stock; rest it against the bent
			# index pad instead of suspending it in the center of the fist.
			support_contact = Vector3(0.086,0.020,-0.278)
			support_rotation = Vector3(0.29,-0.79,-0.22)
		"field_crossbow":
			main_socket = Vector3(0,-0.061,0.03)
			support_socket = Vector3(0,0.022,-0.231)
		"rifle":
			support_socket = Vector3(0,0.037,-0.38)
		"pistol":
			pass
		_:
			return
	asset.position = PALM - asset.basis * main_socket
	if is_instance_valid(support):
		# Assign the mirrored basis directly. Euler setters on a negatively
		# scaled Node3D may absorb the reflection into all three scale axes.
		support.basis = Basis.from_euler(support_rotation) * Basis.from_scale(Vector3(-0.89,0.89,0.95))
		support.position = asset.transform * support_socket - support.basis * support_contact

static func flash_center(id: String) -> Vector3:
	# The flash volume straddles the open end of each barrel.
	return Vector3(0,0.104,-0.737) if id == "rifle" else Vector3(0,0.104,-0.357)
