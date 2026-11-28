extends RefCounted

# x is the fraction of balance spent, y is the world time of the last hit.
static func after_hit(previous: Vector2, now: float, strength: float, threshold: float, rig: WastelandActiveRagdoll) -> Vector2:
	var remaining := maxf(0.0,previous.x-maxf(0.0,now-previous.y)*0.26)
	var instability := 1.0
	if rig != null and rig.balance != null:
		instability += rig.balance.strain*0.20
		if rig.balance.stepping_foot>=0: instability += 0.14
	return Vector2(remaining+strength*instability/maxf(1.0,threshold),now)
