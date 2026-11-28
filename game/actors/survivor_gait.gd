extends RefCounted

## Plans sole contacts in world space. The articulated rig consumes the resulting joint targets.
class Foot:
	var sole := Vector3.ZERO
	var origin := Vector3.ZERO
	var ground := Vector3.ZERO
	var normal := Vector3.UP
	var probe_at := Vector3.INF
	var surface := Vector3.ZERO
	var heading := 0.0
	var roll := 0.0
	var planted := true
	var last_phase := 0.0
	var takeoff_phase := 0.59

var feet: Array[Foot] = [Foot.new(), Foot.new()]
var phase := 0.06
var speed := 0.0
var local_velocity := Vector3.ZERO
var lean := Vector3.ZERO
var support_sway := 0.0
var drop := 0.0
var last_root := Vector3.INF
var last_velocity := Vector3.ZERO
var travel_origin := Vector3.ZERO
var travel_elapsed := 0.0
var average_travel := Vector3.ZERO
var input_driven := false
var previous_grounded := false
var landing := 0.0
var swing_strength := 0.0
var released := -1
var hip_compression := 0.0
var airborne_time := 0.0
var apex_y := 0.0
var air_lead := 1
var fall_spread := 0.0
var fall_brace := 0.0
var landing_target := 0.0
var fall_probe_time := 0.0
var fall_surface := Vector3.INF
var desired_travel := Vector3.ZERO
var stair_contact := Vector3.INF
var stair_direction := Vector3.ZERO

func supporting_ankles() -> Array[StringName]:
	var ankles: Array[StringName] = []
	if feet[0].planted: ankles.append(&"ankle_l")
	if feet[1].planted: ankles.append(&"ankle_r")
	return ankles

func reset() -> void:
	last_root = Vector3.INF
	released = -1
	desired_travel = Vector3.ZERO
	input_driven = false
	stair_contact = Vector3.INF

func advance(dt: float, frame: Transform3D, velocity: Vector3, grounded: bool, floor_normal: Vector3,
		duck: float, half_width: float, leg_length: float, probe: Callable, recovery_foot: int, fall_probe := Callable()) -> void:
	var pos := frame.origin
	var basis := frame.basis.orthonormalized()
	var flat := Vector3(velocity.x, 0, velocity.z).limit_length(8.5)
	var restart := not last_root.is_finite() or pos.distance_squared_to(last_root) > 1.3 * 1.3 or dt > 0.20
	var h := clampf(dt, 0.0, 0.10)
	if restart:
		speed = flat.length()
		last_velocity = flat
		travel_origin = pos
		travel_elapsed = 0.0
		average_travel = flat
		lean = Vector3.ZERO
		landing = 0.0
		hip_compression = 0.0
		phase = 0.06
	travel_elapsed += h
	if travel_elapsed >= 0.15:
		average_travel = ((pos-travel_origin)/travel_elapsed).slide(Vector3.UP)
		travel_origin = pos
		travel_elapsed = 0.0
	# The follower capsule can alternate rapidly about a stationary pelvis. Use
	# net displacement once the movement input is released, including braking.
	if not desired_travel.is_zero_approx(): input_driven = true
	elif grounded and (input_driven or probe.is_valid()):
		flat = average_travel if average_travel.length_squared() > 0.22*0.22 else Vector3.ZERO
	speed = lerpf(speed, flat.length(), 1.0 - exp(-h * 15.0))
	var acceleration := ((flat - Vector3(last_velocity.x, 0, last_velocity.z)) / maxf(0.001, h)).limit_length(14)
	lean = lean.lerp(basis.transposed() * acceleration, 1.0 - exp(-h * 7.0))
	local_velocity = basis.transposed() * flat
	var yaw := atan2(basis.z.x, basis.z.z)
	var width := half_width + 0.022 + 0.036 * duck + 0.050 * smoothstep(0.2, 3.0, absf(local_velocity.x))
	var forward_share := absf(local_velocity.z) / maxf(0.1, flat.length())
	var run := smoothstep(2.2, 6.5, speed)
	var period := (1.04 - 0.39 * smoothstep(0, 3.5, speed) - 0.11 * run) * lerpf(1.0, 0.85, duck)
	var contact_length := lerpf(0.49, 0.79, forward_share) * leg_length * lerpf(1.0, 0.72, duck)
	# Strike with room ahead of the heel to retract before contact. The trailing
	# sole then stays behind the hip for the rest of its support interval.
	var strike_share := lerpf(0.5,0.37,smoothstep(1.8,4.0,speed))
	var stance := minf(0.59, contact_length / maxf(0.1, speed * period))
	var moving := flat.length_squared() > 0.016
	# At rest the first swing must be possible before the supporting leg has accelerated the hips.
	# The short lead changes only where the foot lands and never translates the character.
	var first_step := grounded and desired_travel.length_squared() > 0.04 and flat.length_squared() < 0.10
	var balance_step := flat
	if grounded and not desired_travel.is_zero_approx():
		# As actual speed builds, transition from the starting reach to measured travel.
		var lead := 1.0 - smoothstep(0.24, 0.75, flat.length())
		balance_step = flat.lerp(desired_travel.limit_length(0.74), lead)
	var start_side := 0 if basis.x.dot(desired_travel) < -0.15 else 1
	var home: Array[Vector3] = [pos - basis.x * width, pos + basis.x * width]
	var reposition := false
	var turning := false
	for i in 2:
		var foot := feet[i]
		if restart or grounded != previous_grounded or (i == released and i != recovery_foot):
			foot.probe_at = Vector3.INF
			_sample(foot, home[i], pos, floor_normal, probe)
			foot.sole = foot.ground
			foot.heading = yaw
			foot.planted = true
			foot.roll = 0.0
		var gap := (home[i] - foot.sole).slide(Vector3.UP)
		var staged := first_step and i == start_side and -gap.dot(balance_step.normalized()) > 0.08
		turning = turning or absf(angle_difference(foot.heading, yaw)) > 0.24
		reposition = reposition or not foot.planted or (not staged and gap.length_squared() > 0.0144) or turning
	var start_needed := first_step and (feet[start_side].sole - home[start_side]).dot(balance_step.normalized()) < 0.08
	# After braking, set down the last lifted foot under the hip. Waiting for
	# another complete stride here makes the body mark time while standing.
	var settling := grounded and input_driven and desired_travel.is_zero_approx() and not moving and not turning
	if settling: reposition = false
	if not restart and grounded and (moving or reposition or start_needed):
		phase = fposmod(phase + h / period, 1.0)
	swing_strength = move_toward(swing_strength, smoothstep(0.05, 1.8, speed) if grounded else 0.0, h * 6.0)
	_update_fall(h, pos, velocity, grounded, restart, fall_probe)
	for i in 2:
		var foot := feet[i]
		var t := fposmod(phase + 0.5 * i, 1.0)
		var touched_down := t < foot.last_phase
		foot.last_phase = t
		if not grounded:
			foot.planted = false
			var leading := i == air_lead
			var tuck := smoothstep(-5.2, 2.3, velocity.y)
			var lift := 0.036 + (0.115 if leading else 0.053) * tuck
			lift = lerpf(lift, 0.135 if leading else 0.095, fall_spread)
			lift = lerpf(lift, 0.060 if leading else 0.042, fall_brace)
			var fore_aft := (-0.09 if leading else 0.085) * (0.68 + 0.32 * tuck)
			foot.sole = home[i] + Vector3.UP * lift + basis.z * fore_aft
			foot.sole += basis.x * (-1.0 if i == 0 else 1.0) * (0.046 * fall_spread + 0.032 * fall_brace)
			foot.normal = Vector3.UP
			foot.heading = yaw
			foot.roll = lerpf(-0.16 * tuck, 0.025, fall_brace)
			continue
		if i == recovery_foot:
			foot.planted = false
			foot.sole = home[i] + basis.z * (0.096 if i == 1 else -0.048)
			foot.sole.y += (0.14 if i == 1 else 0.06) + 0.035 * clampf(velocity.y, -1, 1)
			foot.normal = Vector3.UP
			foot.heading = yaw
			foot.roll = -0.15
			continue
		if settling:
			if not foot.planted:
				_sample(foot,home[i],pos,floor_normal,probe)
				foot.sole = foot.sole.move_toward(foot.ground,h*1.75)
				foot.planted = foot.sole.is_equal_approx(foot.ground)
			foot.roll = move_toward(foot.roll,0.0,h*2.0)
			foot.heading = yaw
			continue
		if (foot.planted and t < stance) or (not foot.planted and touched_down):
			if not foot.planted:
				var heel := home[i] + balance_step * (period * (strike_share * stance - t))
				heel = _step_reach(heel)
				_sample(foot, heel, pos, floor_normal, probe, true)
				foot.sole = foot.ground
				foot.planted = true
				foot.heading = yaw
			foot.roll = lerpf(0.085, -0.12, smoothstep(0, stance, t)) * swing_strength * forward_share
			foot.roll *= -signf(local_velocity.z)
			continue
		var gap := (home[i] - foot.sole).slide(Vector3.UP)
		if foot.planted and first_step and i == start_side and -gap.dot(balance_step.normalized()) > 0.08 and absf(angle_difference(foot.heading, yaw)) < 0.24:
			foot.roll = 0.0
			continue
		if foot.planted and not moving and not (first_step and i == start_side) and gap.length_squared() <= 0.0144 and absf(angle_difference(foot.heading, yaw)) <= 0.24:
			foot.roll = 0.0
			continue
		if foot.planted and t > 0.88: continue
		if foot.planted:
			foot.origin = foot.sole
			foot.planted = false
			foot.probe_at = Vector3.INF
			foot.takeoff_phase = t
		var swing := clampf((t - foot.takeoff_phase) / maxf(0.001, 1.0 - foot.takeoff_phase), 0.0, 1.0)
		var touchdown := home[i] + balance_step * (period * (1.0 - t + strike_share * stance))
		touchdown = _step_reach(touchdown)
		_sample(foot, touchdown, pos, floor_normal, probe)
		# Retract the foot under the hip and finish its forward reach before heel
		# strike, leaving the foot motor time to decelerate on the approach.
		var transfer := smoothstep(0.0,0.88,swing)
		foot.sole = foot.origin.lerp(foot.ground, transfer)
		if not stair_contact.is_finite():
			var offset := (foot.sole-home[i]).slide(Vector3.UP)
			var reachable := offset.limit_length(contact_length*0.62)
			foot.sole += reachable-offset
		var lift := lerpf(0.078, 0.23, run) * lerpf(1.0, 0.68, duck)
		var lift_phase := lerpf(swing,1.0-(1.0-swing)*(1.0-swing),0.38-0.62*run)
		foot.sole.y += sin(PI * lift_phase) * (lift + maxf(0, foot.ground.y - foot.origin.y) * 0.36)
		foot.roll = (-0.17 + 0.27 * swing) * swing_strength * -signf(local_velocity.z)
		foot.heading = lerp_angle(foot.heading, yaw, 1.0 - exp(-h * 14.0))
	var support := sin(TAU * (phase + 0.11))
	support_sway = lerpf(support_sway, -support * swing_strength * 0.018, 1.0 - exp(-h * 11.0))
	drop = landing + swing_strength * (0.057 + 0.05 * run + 0.018 * cos(phase * TAU * 2.0))
	released = recovery_foot
	previous_grounded = grounded
	last_velocity = Vector3(flat.x, velocity.y, flat.z)
	last_root = pos

func _update_fall(dt: float, at: Vector3, velocity: Vector3, grounded: bool, restart: bool, probe: Callable) -> void:
	if restart or (previous_grounded and not grounded):
		apex_y = at.y
		airborne_time = 0.0
		air_lead = 1 if phase < 0.5 else 0
		fall_surface = Vector3.INF
		fall_probe_time = 0.0
		if restart:
			fall_spread = 0.0
			fall_brace = 0.0
			landing_target = 0.0
	if grounded:
		if not previous_grounded and not restart:
			var impact_speed := -last_velocity.y
			landing_target = maxf(landing_target, clampf((impact_speed - 2.1) * 0.017, 0, 0.17))
		landing = move_toward(landing, landing_target, dt * 2.6)
		landing_target = move_toward(landing_target, 0, dt * 0.44)
		fall_spread = move_toward(fall_spread, 0, dt * 4.2)
		fall_brace = move_toward(fall_brace, 0, dt * 3.4)
		airborne_time = 0.0
		return
	airborne_time += dt
	apex_y = maxf(apex_y, at.y)
	var down := maxf(-velocity.y, 0)
	var severity := smoothstep(0.98, 2.75, apex_y - at.y) * smoothstep(4.6, 8.1, down) * smoothstep(0.15, 0.42, airborne_time)
	fall_spread = move_toward(fall_spread, severity, dt * 4.8)
	var brace := severity * 0.16
	if severity > 0.02 and probe.is_valid():
		fall_probe_time -= dt
		if fall_probe_time <= 0.0:
			fall_probe_time = 0.075
			# Aim along the horizontal trajectory as well as down, including constructed floors.
			var prediction := at + Vector3(velocity.x, 0, velocity.z) * 0.38
			prediction.y -= down * 0.46 + 1.9
			var hit: Dictionary = probe.call(at + Vector3.UP * 0.12, prediction)
			fall_surface = hit.position if not hit.is_empty() and hit.normal.y > 0.45 else Vector3.INF
		if fall_surface.is_finite():
			var gap := maxf(0.0, at.y - fall_surface.y)
			var seconds := 2 * gap / maxf(0.001, down + sqrt(down * down + 36.0 * gap))
			brace = severity * (1.0 - smoothstep(0.13, 0.46, seconds))
	fall_brace = move_toward(fall_brace, brace, dt * 7.5)
	landing = move_toward(landing, 0, dt * 1.5)
	landing_target = 0.0

func _step_reach(target: Vector3) -> Vector3:
	if stair_contact.is_finite():
		var advance := (stair_contact - target).dot(stair_direction)
		if advance > 0: target += stair_direction * advance
	return target

func _sample(foot: Foot, at: Vector3, root: Vector3, normal: Vector3, probe: Callable, force := false) -> void:
	var n := normal if normal.is_finite() and normal.y > 0.48 else Vector3.UP
	var y := root.y - ((at.x - root.x) * n.x + (at.z - root.z) * n.z) / n.y
	if stair_contact.is_finite() and (at - stair_contact).dot(stair_direction) >= -0.02:
		y = stair_contact.y
	var query := Vector3(at.x, y, at.z)
	if force or not foot.probe_at.is_finite() or foot.probe_at.distance_squared_to(query) > 0.012:
		foot.probe_at = query
		foot.surface = query
		foot.normal = n
		if probe.is_valid():
			var result: Dictionary = probe.call(query)
			if not result.is_empty() and result.normal.y > 0.48:
				foot.surface = result.position
				foot.normal = result.normal
	var offset := query - foot.surface
	foot.ground = Vector3(at.x, foot.surface.y - (offset.x * foot.normal.x + offset.z * foot.normal.z) / foot.normal.y, at.z)

func load_supporting_legs(pivot: Node3D, hips: Array[Node3D], dt: float) -> void:
	# Lower the pelvis enough for the heel to remain reachable at each end of stance.
	var needed := 0.0
	for i in 2:
		var foot := feet[i]
		if not foot.planted: continue
		var hip := hips[i]
		var target := pivot.to_local(_ankle_target(foot, pivot, hip)) - hip.position
		var reach := 0.739 * hip.scale.y
		var vertical := sqrt(maxf(0.10, reach * reach - Vector2(target.x, target.z).length_squared()))
		needed = maxf(needed, (-target.y - vertical) * pivot.scale.y)
	hip_compression = clampf(maxf(needed, hip_compression - 0.38 * dt), 0.0, 0.15)
	pivot.position.y -= hip_compression

func _ankle_target(foot: Foot, pivot: Node3D, hip: Node3D) -> Vector3:
	var height := 0.104 * hip.scale.y * pivot.scale.y + maxf(0, -foot.roll) * 0.12
	return foot.sole + foot.normal * height

func solve(side: int, pivot: Node3D, hip: Node3D, knee: Node3D, ankle: Node3D) -> void:
	var foot := feet[side]
	var heading := Basis(Vector3.UP, foot.heading)
	var sole_basis := Basis.looking_at((-heading.z).slide(foot.normal).normalized(), foot.normal) * Basis(Vector3.RIGHT, foot.roll)
	var target := pivot.to_local(_ankle_target(foot, pivot, hip)) - hip.position
	var length := target.length()
	# Solve the knee hinge first. Account for the unique non-uniform thigh scale of each survivor.
	var a := (knee.position * hip.scale).length()
	var b := (ankle.position * hip.scale).length()
	var bend := -acos(clampf((length * length - a * a - b * b) / (2.0 * a * b), -0.90, 0.9995))
	for iteration in 2:
		var shin := Basis(Vector3.RIGHT, bend) * ankle.position
		var chain := (knee.position + shin) * hip.scale
		var derivative := chain.normalized().dot(Vector3.RIGHT.cross(shin) * hip.scale)
		if absf(derivative) > 0.018:
			bend = clampf(bend + (length - chain.length()) / derivative, -2.55, -0.025)
	knee.rotation = Vector3(bend, 0, 0)
	var line := (knee.position + knee.basis * ankle.position) * hip.scale
	hip.quaternion = Quaternion(line.normalized(), target.normalized())
	var parent_basis := (pivot.global_basis.orthonormalized() * Basis(hip.quaternion) * knee.basis).orthonormalized()
	ankle.quaternion = (parent_basis.transposed() * sole_basis).get_rotation_quaternion()
