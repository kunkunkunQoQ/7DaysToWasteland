extends RefCounted

# A weapon ray may nudge a corpse without putting solid obstacles in the
# player's movement mask or allowing a second damage / loot settlement.
const LAYER := 1 << 16

static func enable(rig: Node3D, enabled: bool, category: String, id: Variant) -> void:
	if rig.get_meta("corpse_layer",false) == enabled: return
	rig.set_meta("corpse_layer",enabled)
	rig.set_meta("corpse_kind",category)
	rig.set_meta("corpse_id",id)
	for part in rig.get_children():
		if part is RigidBody3D:
			part.set_collision_layer_value(17,enabled)

static func strike(hit: Dictionary, origin: Vector3, amount: float) -> Dictionary:
	var part := hit.get("collider") as RigidBody3D
	if not part or (part.collision_layer & LAYER) == 0: return {}
	var rig := part.get_parent()
	var at: Vector3 = hit.position
	var direction := (at-origin).normalized() if origin.is_finite() else Vector3.ZERO
	if direction.is_zero_approx(): direction = -Vector3(hit.get("normal",Vector3.UP))
	var impulse := direction * clampf(0.65 + amount * 0.075,0.8,7.0)
	var bone := StringName(String(part.name).trim_prefix("Body_"))
	rig.kick_at(impulse,at,bone)
	return {"kind":rig.get_meta("corpse_kind"),"id":rig.get_meta("corpse_id"),"bone":bone,"at":at,"impulse":impulse}
