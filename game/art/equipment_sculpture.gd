extends WastelandBestiary.Sculpture

# Small buttons and padded panels need few latitude rings. Keep the original
# oval's height and cardinal extents when substituting a lower-sided ellipse.
func bead(center: Vector3, size: Vector3, pigment: Color, tilt := 0.0) -> void:
	var sides := 8 if size[size.max_axis_index()] >= 0.035 else 6
	var width := size.x * cos(PI / 10.0) / cos(PI / sides)
	var depth := size.z / (cos(PI / sides) if sides == 8 else 1.0)
	loft([
		Vector4(-0.96 * size.y, 0, 0, 0),
		Vector4(-0.65 * size.y, 0.78 * width, 0.77 * depth, 0),
		Vector4(0, width, depth, 0),
		Vector4(0.68 * size.y, 0.74 * width, 0.74 * depth, 0),
		Vector4(size.y, 0, 0, 0)
	], pigment, center, Basis(Vector3.BACK, tilt), sides)
