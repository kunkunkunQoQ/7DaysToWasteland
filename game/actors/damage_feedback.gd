class_name WastelandDamageFeedback
extends RefCounted

const COLORS := {
	"acid": Color("#b8d57e"), "residue": Color("#a3cf66"), "rupture": Color("#f6aa69"), "radiation": Color("#d0cb75"),
	"fall": Color("#edaf81"), "cold": Color("#9cbdf1"), "drown": Color("#8dcfdf"),
}
const LABELS := {
	"claw": "撕咬", "heavy": "重击", "acid": "酸液", "radiation": "辐蚀", "boar": "野猪冲撞", "shield":"盾牌格挡","bark":"树皮擦伤",
	"hard_impact": "拳头挫伤",
	"rupture": "胀囊爆裂", "residue": "腐液灼伤", "fall": "坠落", "bleed": "失血", "infection": "感染", "cold": "失温", "drown": "溺水",
	"hunger": "饥饿", "thirst": "缺水", "debris": "坠物砸伤", "timber":"倒树砸伤", "spikes": "踩中木刺",
}
const DIRECTION_TIME := 1.25
const BASE_TINT := Color("#ef5c78")

var directions: Array[Dictionary] = []
var pulse := 0.0
var tint := BASE_TINT
var trace_health := 0.0
var trace_hold := 0.0
var label_left := 0.0
var last_source := ""
var last_amount := 0.0
var kick_time := 0.0
var kick_strength := 0.0
var kick_side := 1.0
var heart_left := 0.0

func record(before: float, loss: float, source: String, bearing: Vector3, right: Vector3, direct: bool) -> void:
	trace_health = maxf(trace_health, before)
	trace_hold = 0.29 if direct else 0.12
	if label_left > 0.65 and source == last_source:
		last_amount += loss
	else:
		last_amount = loss
	last_source = source
	label_left = 1.65 if direct else 1.45
	if not direct:
		return
	var power := clampf(loss / 27.0, 0.23, 1.0)
	pulse = maxf(pulse, 0.27 + power * 0.57)
	tint = COLORS.get(source, BASE_TINT)
	kick_time = 0.38
	kick_strength = power
	var side := bearing.dot(right)
	kick_side = (1.0 if kick_side <= 0.0 else -1.0) if absf(side) < 0.13 else -signf(side)
	if bearing == Vector3.ZERO:
		return
	for cue in directions:
		if bearing.dot(cue.bearing) > 0.91:
			cue.bearing = bearing
			cue.lifetime = DIRECTION_TIME
			cue.power = maxf(float(cue.power), power)
			cue.color = tint
			return
	if directions.size() == 4:
		directions.pop_front()
	directions.append({"bearing": bearing, "lifetime": DIRECTION_TIME, "power": power, "color": tint})

func advance(delta: float, health: float) -> void:
	pulse = move_toward(pulse, 0.0, 1.9 * delta)
	label_left = maxf(0.0, label_left - delta)
	trace_hold = maxf(0.0, trace_hold - delta)
	if trace_hold == 0.0 or trace_health < health:
		trace_health = move_toward(trace_health, health, delta * 56.0)
	kick_time = maxf(0.0, kick_time - delta)
	for i in range(directions.size() - 1, -1, -1):
		directions[i].lifetime -= delta
		if directions[i].lifetime <= 0.0:
			directions.remove_at(i)

func roll() -> float:
	var t := 0.38 - kick_time
	return kick_side * kick_strength * sin(t * 31.0) * exp(-t * 12.0) * 0.060 if kick_time > 0.0 else 0.0

func reset(health: float) -> void:
	directions.clear()
	pulse = 0.0
	label_left = 0.0
	trace_health = health
	trace_hold = 0.0
	kick_time = 0.0
	heart_left = 0.0
