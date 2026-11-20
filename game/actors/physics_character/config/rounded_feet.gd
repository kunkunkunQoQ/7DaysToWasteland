extends "rounded_palms.gd"
## Two parallel fore-aft capsules preserve the foot envelope and sole height.
## Preserve the original box mass properties independently of the contact shape.

func build_segments() -> Array[Dictionary]:
	var rows := super.build_segments()
	for row: Dictionary in rows:
		if row.id != &"foot_l" and row.id != &"foot_r":
			continue
		var size: Vector3 = row.size
		var half_spacing := (size.x - size.y) * 0.5
		var capsule_size := Vector3(size.y, size.z, size.y)
		var basis := Basis(Vector3.RIGHT, PI / 2.0)
		row.collision_parts = [
			{"name": &"SecondSole", "shape": &"capsule", "size": capsule_size,
				"transform": Transform3D(basis, Vector3.RIGHT * half_spacing)},
			{"name": &"Collider", "shape": &"capsule", "size": capsule_size,
				"transform": Transform3D(basis, Vector3.LEFT * half_spacing)}
		]
		var squared := size * size
		row.mass_center = Vector3.ZERO
		row.inertia = Vector3(squared.y + squared.z, squared.x + squared.z, squared.x + squared.y) * (float(row.mass)/12.0)
	return rows
