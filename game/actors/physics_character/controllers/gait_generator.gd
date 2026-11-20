extends RefCounted
## Targets are world-space sole landmarks. Only measured contact and load may
## finish a step. A terrain probe supplies geometry, never a contact event.

const State := preload("../state/physics_character_state.gd")
var phase: StringName = &"stop"
var support: StringName = &"left"
var switches := 0
var target_velocity := Vector3.ZERO
var ground_probe := {}
var capture_point := Vector3.ZERO
var phase_time := 0.0
var commanded_center := Vector3.ZERO
var commanded_left := Vector3.ZERO
var commanded_right := Vector3.ZERO
var _initialized := false
var _heading := Basis.IDENTITY
var _gravity: float
var _ground: Callable
var _swing_origin := Vector3.ZERO
var _landing := Vector3.ZERO
var _landing_normal := Vector3.UP
var _anchors := {}
var _normals := {}
var _load_steps := 0
var _left_ground := false
var _swing_time := 0.0
var _since_start := 0.0
var _width := 0.102
var _com_offset := Vector3.ZERO
var _turning := false
var _stance_samples := 0

func setup(gravity: float, terrain: Callable) -> void:
	_gravity = gravity
	_ground = terrain

func _sole(state: State, side: StringName) -> Vector3:
	return state.left_sole_position if side == &"left" else state.right_sole_position

func _bearing(state: State, side: StringName) -> float:
	if side == &"left" and state.support_feet & State.SupportFoot.LEFT:
		return state.left_support_load_n
	if side == &"right" and state.support_feet & State.SupportFoot.RIGHT:
		return state.right_support_load_n
	return 0.0

func _other() -> StringName:
	return &"right" if support == &"left" else &"left"

## In double support, brake if the velocity would carry the capture point
## beyond the currently loaded ground. A delayed landing must not accumulate
## another stride's worth of forward momentum while both feet are planted.
func _supported_velocity(state: State, requested: Vector3, height: float) -> Vector3:
	var samples := state.left_support_points
	samples.append_array(state.right_support_points)
	if samples.is_empty():
		return Vector3.ZERO
	var omega := sqrt(_gravity / height)
	var result := Vector3.ZERO
	for axis: Vector3 in [_heading.x,-_heading.z]:
		var lo := INF
		var hi := -INF
		for point in samples:
			var coordinate := (point - state.center_of_mass).dot(axis)
			lo = minf(lo,coordinate)
			hi = maxf(hi,coordinate)
		result += axis * clampf(requested.dot(axis),lo * omega,hi * omega)
	return result.limit_length(1.2)

func _begin_swing(state: State) -> void:
	var swing := _other()
	var stance := _sole(state, support)
	_swing_origin = _sole(state, swing)
	_swing_time = clampf(0.36 - target_velocity.length() * 0.16, 0.22, 0.36)
	var foot_offset := _heading.x * (_width if swing == &"right" else -_width)
	var ahead := capture_point - _heading * _com_offset + foot_offset
	var lead := minf(0.5,0.25 + 0.08 * switches)
	ahead += target_velocity * (lead * _swing_time)
	var relative := ahead - stance
	var side := 1.0 if swing == &"right" else -1.0
	var spread := clampf(relative.dot(_heading.x) * side, 0.13, 0.34)
	var fore := clampf(relative.dot(-_heading.z), -0.34, 0.34)
	var placement := stance + _heading.x * side * spread - _heading.z * fore
	ground_probe = _ground.call(placement)
	if ground_probe.is_empty():
		return
	_landing = ground_probe.position
	_landing_normal = ground_probe.normal
	_left_ground = false
	_load_steps = 0
	phase = &"swing"
	phase_time = 0.0

func advance(state: State, velocity: Vector3, facing: Vector3, dt: float) -> Dictionary:
	_since_start += dt
	var left := state.left_sole_position
	var right := state.right_sole_position
	if not _initialized:
		_heading = Basis.looking_at(-state.body_poses[&"pelvis"].basis.z.slide(Vector3.UP).normalized(), Vector3.UP)
		_width = maxf(0.065, absf((right - left).dot(_heading.x)) * 0.5)
		_com_offset = _heading.inverse() * (state.center_of_mass - (left + right) * 0.5).slide(Vector3.UP)
		_anchors = {&"left":left, &"right":right}
		_normals = {&"left":Vector3.UP, &"right":Vector3.UP}
		_initialized = true
	var desired_facing := facing.slide(Vector3.UP).normalized()
	if desired_facing.length_squared() > 0.5:
		var angle := (-_heading.z).signed_angle_to(desired_facing, Vector3.UP)
		var chest_forward := -state.body_poses[&"chest"].basis.z.slide(Vector3.UP).normalized()
		_turning = absf(chest_forward.signed_angle_to(desired_facing, Vector3.UP)) > deg_to_rad(12.0)
		_heading = Basis(Vector3.UP, clampf(angle, -1.2 * dt, 1.2 * dt)) * _heading
	target_velocity = target_velocity.move_toward(velocity.slide(Vector3.UP), 1.75 * dt)
	var moving := velocity.slide(Vector3.UP).length() > 0.035 or _turning
	var stance := _sole(state, support)
	var height := maxf(0.25, state.center_of_mass.y - stance.y)
	capture_point = state.center_of_mass + state.linear_velocity.slide(Vector3.UP) * sqrt(height / _gravity)
	var body_weight := maxf(1.0, state.total_mass * _gravity)
	phase_time += dt
	if phase == &"stop" and moving and state.grounded and _since_start > 0.25:
		# For lateral travel, first free the foot on the side of travel.
		support = &"right" if target_velocity.dot(_heading.x) < -0.01 else &"left"
		if _bearing(state,support) > body_weight * 0.12:
			_anchors[&"left"] = left
			_anchors[&"right"] = right
			_com_offset = _heading.inverse() * (state.center_of_mass - (left + right) * 0.5).slide(Vector3.UP)
			_stance_samples = 0
			phase = &"transfer"
			phase_time = 0.0
	var swing := _other()
	var blend := smoothstep(0.0, 0.36, phase_time)
	var middle: Vector3 = (Vector3(_anchors[&"left"]) + Vector3(_anchors[&"right"])) * 0.5
	var support_center := Vector3(_anchors[support]) + _heading * _com_offset
	commanded_center = middle + _heading * _com_offset
	if phase == &"transfer":
		commanded_center = commanded_center.lerp(support_center, blend)
		if not moving:
			phase = &"stop"
		else:
			var total_load := state.left_support_load_n + state.right_support_load_n
			var on_stance := _bearing(state,support) > 0.74 * total_load and total_load > 0.65 * body_weight
			var centered := absf((capture_point - support_center).dot(_heading.x)) < 0.055
			_stance_samples = _stance_samples + 1 if on_stance and centered else 0
			if phase_time > 0.22 and _stance_samples >= 3:
				_begin_swing(state)
	elif phase == &"swing" or phase == &"load":
		commanded_center = support_center
	if phase == &"swing" or phase == &"load":
		var t := clampf(phase_time / _swing_time, 0.0, 1.0)
		var middle_at_landing := (Vector3(_anchors[support]) + _landing) * 0.5 + _heading * _com_offset
		# Reverse lateral COM travel before touchdown. After contact, let the
		# incoming foot take load while the previous stance remains declared.
		var incoming_touch := state.left_sole_touching if swing == &"left" else state.right_sole_touching
		var return_fraction := 0.42 * smoothstep(0.45,1.0,t)
		if incoming_touch and _left_ground:
			return_fraction += 0.58 * smoothstep(0.0,0.25,maxf(0.0,phase_time - 0.80*_swing_time))
		commanded_center = support_center.lerp(middle_at_landing,return_fraction)
		var path := _swing_origin.lerp(_landing,smoothstep(0.0,1.0,t))
		var clearance := 0.030 + 0.016 * minf(1.0,target_velocity.length()) + absf(_landing.y - _swing_origin.y)
		# Both landing and lift-off have zero vertical target velocity.
		path.y += 16.0 * clearance * t * t * (1.0 - t) * (1.0 - t)
		if phase_time > _swing_time:
			phase = &"load"
			path.y -= minf(0.035, (phase_time - _swing_time) * 0.12)
		_anchors[swing] = path
		_normals[swing] = _landing_normal
		var touching := state.left_sole_touching if swing == &"left" else state.right_sole_touching
		if not touching and _sole(state,swing).y > minf(_landing.y,_swing_origin.y) + 0.017:
			_left_ground = true
		var miss := _sole(state,swing) - _landing
		var near_landing := miss.slide(Vector3.UP).length() < 0.095 and absf(miss.y) < 0.04
		var accepting := _left_ground and t > 0.72 and near_landing and touching and _bearing(state,swing) > 0.15 * body_weight
		_load_steps = _load_steps + 1 if accepting else 0
		if _load_steps >= 2:
			_anchors[swing] = _sole(state,swing)
			_anchors[support] = _sole(state,support)
			support = swing
			switches += 1
			_stance_samples = 0
			phase = &"transfer" if moving else &"stop"
			phase_time = 0.0
	commanded_left = _anchors[&"left"]
	commanded_right = _anchors[&"right"]
	var walk_gain := minf(1.0,0.15 + 0.24 * switches)
	var planned_velocity := target_velocity * walk_gain
	if phase == &"transfer":
		planned_velocity = _supported_velocity(state, planned_velocity * (0.25 if switches > 0 else 0.12), height)
	elif phase == &"load":
		planned_velocity = _supported_velocity(state, planned_velocity * 0.35, height)
	return {"phase":phase,"support":support,"blend":blend,"moving":moving,"heading":_heading,
		"velocity":planned_velocity,"com_target":commanded_center,"left_sole":commanded_left,
		"right_sole":commanded_right,"left_normal":_normals[&"left"],"right_normal":_normals[&"right"]}
