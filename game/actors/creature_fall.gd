extends RefCounted
## Track continuous travel of the authority's capsule and then the released pelvis.
## Network corrections, pooled actors and a newly streamed region start a fresh trace.

var last := Vector3.INF
var peak := 0.0
var pending := false
var from_fall := false
var launch_velocity := Vector3.ZERO

func reset(point := Vector3.INF) -> void:
	last = point
	peak = point.y if point.is_finite() else 0.0
	pending = false
	from_fall = false
	launch_velocity = Vector3.ZERO

func capsule(before: Vector3, after: Vector3, grounded: bool, down_speed: float, height: float) -> bool:
	if not last.is_finite() or last.distance_squared_to(before)>0.36:
		reset(before)
	if grounded:
		reset(after)
		return false
	peak = maxf(peak,maxf(before.y,after.y))
	last = after
	return dangerous(peak-after.y,down_speed,height)

func passive(point: Vector3, drop: float) -> void:
	last = point
	peak = point.y+drop
	pending = true

static func dangerous(drop: float, down_speed: float, height: float) -> bool:
	return drop > maxf(1.75,height*1.08) and down_speed>6.2

static func damage_fraction(drop: float, closing_speed: float) -> float:
	# A glancing contact converts little of the descent into a normal impulse.
	var effective_drop := minf(drop,closing_speed*closing_speed/30.0)
	return clampf((effective_drop-1.85)*0.115,0.0,1.40)
