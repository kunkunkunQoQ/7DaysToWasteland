extends "physics_character_config.gd"
## Hand collider variant. Keep the baseline mass and principal inertia when
## rounding the palm contact surface so shape and mass can be tested separately.

func build_segments() -> Array[Dictionary]:
	var rows := super.build_segments()
	for row: Dictionary in rows:
		if row.id not in [&"hand_l", &"hand_r"]:
			continue
		var size: Vector3 = row.size
		var square := size * size
		row.inertia = Vector3(square.y + square.z, square.x + square.z, square.x + square.y) * (float(row.mass) / 12.0)
		row.shape = &"capsule"
		row.size = Vector3(size.x, size.y, size.x)
	return rows
