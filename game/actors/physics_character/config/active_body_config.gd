extends "physics_character_config.gd"
## Four finite sole contact patches with a solid upper shoe. The lowest
## points, envelope, mass, joint pivots and inertial properties keep the
## original dimensions. Pads are child shapes of the same foot rigid body.

@export_range(0.014, 0.050, 0.001) var sole_pad_radius_m := 0.032

func build_segments() -> Array[Dictionary]:
	var rows := super.build_segments()
	for row in rows:
		if row.id not in [&"foot_l", &"foot_r"]:
			continue
		var size: Vector3 = row.size
		var radius := minf(sole_pad_radius_m, 0.5 * minf(size.x, size.y))
		var parts: Array[Dictionary] = []
		for side in [-1, 1]:
			for end in [-1, 1]:
				var center := Vector3(side * (0.5 * size.x - radius), -0.5 * size.y + radius,
					end * (0.5 * size.z - radius))
				parts.append({"name": "Sole_%s_%s" % [side, end], "shape": &"capsule",
					"size": Vector3.ONE * (2.0 * radius), "transform": Transform3D(Basis.IDENTITY, center)})
		parts.append({"name": &"Collider", "shape": &"box", "size": size * Vector3(0.96, 0.55, 0.94),
			"transform": Transform3D(Basis.IDENTITY, Vector3.UP * (0.225 * size.y))})
		row.collision_parts = parts
		row.mass_center = Vector3.ZERO
		var squared := size * size
		row.inertia = Vector3(squared.y + squared.z, squared.x + squared.z, squared.x + squared.y) * (float(row.mass) / 12.0)
	return rows
