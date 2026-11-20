extends RefCounted

class FallingPiece extends RigidBody3D:
	var session: Node3D
	var impact_speed := 0.0
	var last_speed := 0.0
	var struck := {}

	func _physics_process(_delta: float) -> void:
		impact_speed = maxf(last_speed, -linear_velocity.y)
		last_speed = maxf(0.0, -linear_velocity.y)

	func hit_body(victim: Node) -> void:
		if not is_instance_valid(session) or session.replica or impact_speed < 1.3 or struck.has(victim):
			return
		if victim is WastelandSurvivor or victim is WastelandCreature:
			struck[victim] = true
			var damage := clampf(impact_speed * sqrt(mass) * 0.85, 3.0, 85.0)
			if victim is WastelandSurvivor:
				victim.damage(damage, "debris", global_position)
			elif victim.active and victim.hp > 0.0:
				victim.take_hit(damage, global_position, damage >= 22.0)

# Several adjacent blocks can break off as one rigid piece; each has its own collider.
static func release(chunk: Node3D, source: StaticBody3D, key: String, weight := 0.0, join: FallingPiece = null) -> FallingPiece:
	var bounds := AABB()
	var visible_parts: Array[VisualInstance3D] = []
	for child in source.get_children():
		if child is VisualInstance3D and child.visible:
			var local: AABB = child.transform * child.get_aabb()
			bounds = local if visible_parts.is_empty() else bounds.merge(local)
			visible_parts.append(child)
	if visible_parts.is_empty() or bounds.size.length_squared() < 0.01:
		return join
	var piece := join
	var added_mass := weight if weight > 0.0 else clampf(bounds.get_volume() * 65.0, 1.0, 350.0)
	if piece == null:
		piece = FallingPiece.new()
		piece.collision_layer = 0
		piece.collision_mask = 7
		piece.mass = added_mass
		piece.angular_damp = 1.4
		piece.contact_monitor = true
		piece.max_contacts_reported = 6
		piece.continuous_cd = true
		piece.session = chunk.session if chunk is WastelandConstruction else chunk.stream.get_parent()
		chunk.add_child(piece)
		piece.global_transform = source.global_transform
		piece.add_to_group("falling_structure")
		piece.body_entered.connect(piece.hit_body)
		piece.linear_velocity = Vector3.DOWN * 0.6
		piece.angular_velocity = Vector3(0.27, 0.04, -0.43) * (1 if key.hash() % 2 == 0 else -1)
		chunk.get_tree().create_timer(4.0, false, true).timeout.connect(piece.queue_free)
	else:
		piece.mass += added_mass
	var shape := BoxShape3D.new()
	shape.size = (bounds.size * 0.92).max(Vector3.ONE * 0.04)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	piece.add_child(collision)
	collision.global_transform = source.global_transform * Transform3D(Basis.IDENTITY, bounds.get_center())
	for part in visible_parts:
		part.reparent(piece, true)
	return piece
