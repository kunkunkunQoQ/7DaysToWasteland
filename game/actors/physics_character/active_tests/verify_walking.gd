extends SceneTree
## Independent trial. Only the intent port can command the walking character.

const SCENE := "res://game/actors/physics_character/walking_character.tscn"
const Probe := preload("standing_contact_probe.gd")
const HZ := 60
const SETTLE := 120
const DRIVE := 600
const STOP := 180
const TURN_AT := 240
const CASES := ["forward", "backward", "left", "right", "turn_left", "turn_right", "slow", "uneven"]
const HEIGHTS := [0.0,0.022,0.009,0.034,0.015,0.0]
const LEG_PARTS := [&"thigh_l",&"calf_l",&"foot_l",&"thigh_r",&"calf_r",&"foot_r"]

var _case := "forward"
var _directory := ""
var _trace_requested := false
var _actor: Node3D
var _ground: StaticBody3D
var _trace: FileAccess
var _events: FileAccess
var _contacts := Probe.new()
var _previous_poses: Dictionary
var _joint_locations := {}
var _sample_bodies: Dictionary
var _anchor_peak := 0.0
var _anchor_tick := -1
var _anchor_joint := ""
var _first_gross_tick := -1
var _gross_anchor_frames := 0
var _release_tick := -1
var _release_reason := ""
var _release_torque_peak := 0.0
var _previous_vy := 0.0
var _weight := 0.0
var _command := Vector3.ZERO
var _facing := Vector3.FORWARD
var _last_tick := 0
var _prev_com := Vector3.ZERO
var _segment_start := Vector3.ZERO
var _tail_start := Vector3.ZERO
var _segments: Array[Dictionary] = []
var _feet: Array[Dictionary] = []
var _reported_switches := 0
var _previous_support := -1
var _real_switches := 0
var _last_landing := -1
var _alternations := 0
var _worst_tilt := 0.0
var _min_height := INF
var _min_pelvis := INF
var _fallen := 0
var _fall_events := 0
var _was_fallen := false
var _nonfoot := 0
var _air_run := 0
var _max_air := 0
var _sum_load := 0.0
var _end_travel := 0.0
var _tail_speed_sq := 0.0
var _tail_facing_max := 0.0
var _min_floor := INF
var _max_floor := -INF
var _max_probe_slope := 0.0
var _probe_errors := 0
var _phases := {}
var _failures := {}
var _first_tick := -1
var _first_reason := ""

func _initialize() -> void:
	Engine.physics_ticks_per_second = HZ
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
		elif arg.begins_with("--out="):
			_directory = arg.trim_prefix("--out=")
		elif arg == "--trace":
			_trace_requested = true
		else:
			_abort("Unknown option " + arg)
			return
	if _case not in CASES or not _directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_abort("A known --case and writable absolute --out are required.")
		return
	_start.call_deferred()

func _abort(message: String) -> void:
	printerr("WALK ERROR ", message)
	quit(2)

func _path(suffix: String) -> String:
	return _directory.path_join("walk_%s_%s" % [_case,suffix])

func _fail(tick: int, reason: String) -> void:
	if not _failures.has(reason):
		_failures[reason] = tick
	if _first_tick < 0:
		_first_tick = tick
		_first_reason = reason

func _floor_box(z_back: float, z_front: float, h_back: float, h_front: float) -> void:
	var length := z_back - z_front
	var rotation_x := atan2(h_front - h_back, length)
	var axes := Basis(Vector3.RIGHT, rotation_x)
	var middle := Vector3(0, (h_back + h_front) * 0.5, (z_back + z_front) * 0.5)
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, length / cos(rotation_x))
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.transform = Transform3D(axes, middle - axes.y * 0.1)
	_ground.add_child(collider)

func _floor_height(p: Vector3) -> float:
	if _case != "uneven" or p.z >= -0.75:
		return 0.0
	var tile := (-0.75 - p.z) / 0.50
	var i := floori(tile)
	return lerpf(HEIGHTS[i % HEIGHTS.size()], HEIGHTS[(i + 1) % HEIGHTS.size()], tile - floorf(tile))

func _floor_normal(p: Vector3) -> Vector3:
	if _case != "uneven" or p.z >= -0.75:
		return Vector3.UP
	var i := floori((-0.75-p.z)/0.5)
	return Vector3(0,0.5,float(HEIGHTS[(i+1)%HEIGHTS.size()])-float(HEIGHTS[i%HEIGHTS.size()])).normalized()

func _start() -> void:
	if root.world_3d.direct_space_state.get_class() != &"GodotPhysicsDirectSpaceState3D":
		_abort("Expected GodotPhysics3D.")
		return
	var param := PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS
	PhysicsServer3D.space_set_param(root.world_3d.space, param, 128)
	if roundi(PhysicsServer3D.space_get_param(root.world_3d.space, param)) != 128:
		_abort("Could not apply private-space solver iterations.")
		return
	_ground = StaticBody3D.new()
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	_ground.name = "Ground"
	if _case == "uneven":
		_floor_box(10.0,-0.75,0.0,0.0)
		for i in 27:
			_floor_box(-0.75 - i * 0.5, -1.25 - i * 0.5, HEIGHTS[i % HEIGHTS.size()], HEIGHTS[(i+1) % HEIGHTS.size()])
	else:
		_floor_box(10.0,-10.0,0.0,0.0)
	root.add_child(_ground)
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_abort("Walking scene did not load.")
		return
	_actor = packed.instantiate()
	if not _actor.has_method("get_gait_telemetry") or not _actor.has_method("submit_intent"):
		_abort("Walking telemetry and intent port are required.")
		return
	root.add_child(_actor)
	var state = _actor.call("get_state")
	var rig = _actor.get_node("PhysicsRig")
	if state == null or not "left_sole_touching" in state or not "right_sole_touching" in state or rig.bodies.size() != 16 or rig.joints.size() != 15:
		_abort("Missing sole geometry feedback or rig.")
		return
	for body: RigidBody3D in rig.bodies.values():
		if body.freeze or body.axis_lock_linear_x or body.axis_lock_linear_y or body.axis_lock_linear_z or body.axis_lock_angular_x or body.axis_lock_angular_y or body.axis_lock_angular_z:
			_abort("Found a frozen or axis-locked body.")
			return
	var mass: float = state.total_mass
	_weight = mass * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_contacts.setup(rig, _ground, _actor.get("config"), mass)
	_previous_poses = state.body_poses
	_previous_vy = state.linear_velocity.y
	_prev_com = state.center_of_mass
	_segment_start = _prev_com
	for i in 2:
		_segments.append({"n":0,"projected_sum":0.0,"sq_error":0.0,"progress":0.0,"cross":0.0,"facing_sq":0.0})
		_feet.append({"was_loaded":false,"air":0,"clear_of_ground":false,"origin":Vector3.ZERO,"peak":0.0,"landings":0})
	_events = FileAccess.open(_path("events.csv"), FileAccess.WRITE)
	if _events == null:
		_abort("Cannot create events CSV.")
		return
	_events.store_csv_line(["tick","kind","foot","load_n","air_frames","clearance_m","step_m","floor_y","upright"])
	_sample_bodies = rig.bodies
	var centers := {}
	for segment: Dictionary in _actor.get("config").build_segments():
		centers[segment.id] = segment.position
	for joint: Dictionary in _actor.get("config").build_joints():
		_joint_locations[joint.child] = {"parent":joint.parent,"axis":joint.basis.z,
			"a":joint.position-centers[joint.parent],"b":joint.position-centers[joint.child]}
	if _trace_requested:
		_trace = FileAccess.open(_path("frames.csv"), FileAccess.WRITE)
		if _trace == null:
			_abort("Cannot create frame CSV.")
			return
		var header := PackedStringArray(["tick","goal_vx","goal_vz","com_x","com_y","com_z","vx","vz","pelvis_y","tilt_deg","facing_err_deg","load_l_n","load_r_n","sole_l_y","sole_r_y","contact_slip_l_m_s","contact_slip_r_m_s","phase","support","switches","fallen","nonfoot","planned_vx","planned_vz","probe_y","probe_slope_deg","sole_l_x","sole_l_z","sole_r_x","sole_r_z","goal_l_x","goal_l_y","goal_l_z","goal_r_x","goal_r_y","goal_r_z","goal_com_x","goal_com_z","capture_x","capture_z"])
		for id: StringName in LEG_PARTS:
			for key in ["pitch_deg","roll_deg","wx_rad_s","wz_rad_s","torque_x_nm","torque_z_nm","limit_fraction","anchor_error_m","joint_z_axis_separation_deg"]:
				header.append("%s_%s"%[id,key])
		header.append_array(PackedStringArray(["strongest_self_pair","self_impulse_ns","self_pairs","com_horizontal_speed_m_s","com_vertical_speed_m_s","release_reason","release_tick","worst_anchor_joint","worst_anchor_m"]))
		_trace.store_csv_line(header)
	_actor.call("submit_intent",Vector3.ZERO,_facing,false,false)
	_actor.connect("state_updated",_observe)

func _is_turn() -> bool:
	return _case in ["turn_left","turn_right"]

func _set_next_intent(tick: int) -> void:
	var step := tick - SETTLE
	_command = Vector3.ZERO
	if step >= 1 and step <= DRIVE:
		var direction := Vector3.FORWARD
		match _case:
			"backward": direction = Vector3.BACK
			"left": direction = Vector3.LEFT
			"right": direction = Vector3.RIGHT
			"turn_left","turn_right":
				if step > TURN_AT:
					direction = Vector3.LEFT if _case == "turn_left" else Vector3.RIGHT
				_facing = direction
		_command = direction * (0.35 if _case == "slow" else 0.8)
	_actor.call("submit_intent",_command,_facing,false,false)

func _foot_step(i: int, pos: Vector3, load_n: float, valid_contact: bool, touching: bool, tick: int, upright: bool) -> void:
	var foot := _feet[i]
	var height := _floor_height(pos)
	if load_n < 0.05*_weight or not valid_contact:
		if foot.was_loaded:
			foot.air += 1
			foot.peak = maxf(foot.peak, pos.y-height)
			foot.clear_of_ground = foot.clear_of_ground or not touching
		return
	if load_n < 0.15*_weight:
		return
	if foot.was_loaded and foot.air >= 2:
		var reach := (pos - Vector3(foot.origin)).slide(Vector3.UP).length()
		var valid: bool = upright and foot.clear_of_ground and foot.peak >= 0.015 and reach >= (0.04 if _case == "slow" else 0.07)
		_events.store_csv_line([tick,"physical_step" if valid else "reload",i,load_n,foot.air,foot.peak,reach,height,upright])
		if valid:
			foot.landings += 1
			_min_floor = minf(_min_floor,height)
			_max_floor = maxf(_max_floor,height)
			if _last_landing >= 0 and _last_landing != i:
				_alternations += 1
			_last_landing = i
	foot.was_loaded = true
	foot.origin = pos
	foot.air = 0
	foot.clear_of_ground = false
	foot.peak = 0.0

func _check_switch(gait: Dictionary, state, tick: int) -> void:
	var count: int = gait.switches
	var side := str(gait.support)
	var i := 0 if side in ["left","foot_l"] else 1 if side in ["right","foot_r"] else -1
	if count != _reported_switches:
		var load_n: float = state.left_support_load_n if i==0 else state.right_support_load_n
		var valid: bool = i >= 0 and count == _reported_switches+1 and i != _previous_support and (state.support_feet & (1<<i)) != 0 and load_n >= 0.15*_weight
		if not valid:
			_fail(tick,"unverified_support_switch")
		elif tick > SETTLE and tick <= SETTLE+DRIVE:
			_real_switches += 1
		_events.store_csv_line([tick,"declared_switch",i,load_n,0,0,0,0,not state.fallen])
		_reported_switches = count
	_previous_support = i

func _self_contacts() -> Array:
	var peak := 0.0
	var pair := ""
	var pairs := {}
	for body: RigidBody3D in _sample_bodies.values():
		var native := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if native == null:
			continue
		for index in native.get_contact_count():
			var other := native.get_contact_collider_object(index) as RigidBody3D
			if other == null or not _sample_bodies.has(other.name) or other != _sample_bodies[other.name] or body.name >= other.name:
				continue
			var impulse := native.get_contact_impulse(index).length()
			if impulse <= 0.0:
				continue
			var key := "%s/%s"%[body.name,other.name]
			pairs[key] = true
			if impulse > peak:
				peak = impulse
				pair = key
	return [pair,peak,pairs.size()]

func _observe(state) -> void:
	var tick: int = state.tick_index
	if tick != _last_tick+1 or not is_equal_approx(state.step_seconds,1.0/HZ):
		_fail(tick,"physics_clock")
	_last_tick = tick
	var gait: Dictionary = _actor.call("get_gait_telemetry")
	if not gait.has_all(["phase","support","switches","target_velocity","ground_probe"]):
		_abort("Incomplete gait telemetry.")
		return
	_release_tick = gait.get("release_tick",-1)
	_release_reason = str(gait.get("release_reason",""))
	if _release_tick >= 0:
		_fail(tick,"walking_actuation_released")
		var muscles: Dictionary = _actor.call("get_muscle_telemetry")
		for id: StringName in muscles:
			_release_torque_peak = maxf(_release_torque_peak,Vector3(muscles[id].torque_world_nm).length())
	var worst_anchor := 0.0
	var worst_joint := ""
	for id: StringName in _joint_locations:
		var mount: Dictionary = _joint_locations[id]
		var a: Vector3 = state.body_poses[mount.parent]*Vector3(mount.a)
		var b: Vector3 = state.body_poses[id]*Vector3(mount.b)
		var gap := a.distance_to(b)
		if gap>worst_anchor:
			worst_anchor = gap
			worst_joint = id
	if worst_anchor>_anchor_peak:
		_anchor_peak = worst_anchor
		_anchor_joint = worst_joint
		_anchor_tick = tick
	if worst_anchor>0.20:
		if _first_gross_tick<0:
			_first_gross_tick = tick
		_gross_anchor_frames += 1
		_fail(tick,"anchor_separation_over_20cm")
	var com: Vector3 = state.center_of_mass
	var vel: Vector3 = state.linear_velocity
	var chest: Transform3D = state.body_poses[&"chest"]
	var tilt := rad_to_deg(chest.basis.y.angle_to(Vector3.UP))
	var forward := (-chest.basis.z).slide(Vector3.UP).normalized()
	var face_error := rad_to_deg(forward.angle_to(_facing))
	var ground_y := _floor_height(com)
	var pelvis_y: float = state.pelvis_position.y-ground_y
	var height := com.y-ground_y
	var upright: bool = not state.fallen and not state.nonfoot_ground_contact and height >= 0.65 and pelvis_y >= 0.65 and tilt <= 35
	if not com.is_finite() or not vel.is_finite() or not chest.is_finite() or not is_finite(state.left_support_load_n) or not is_finite(state.right_support_load_n):
		_fail(tick,"invalid_state")
	if not upright:
		_fail(tick,"posture_or_nonfoot_support")
	_fallen += int(state.fallen)
	_fall_events += int(state.fallen and not _was_fallen)
	_was_fallen = state.fallen
	_nonfoot += int(state.nonfoot_ground_contact)
	_min_height = minf(_min_height,height)
	_min_pelvis = minf(_min_pelvis,pelvis_y)
	_worst_tilt = maxf(_worst_tilt,tilt)
	_check_switch(gait,state,tick)
	var slips := Vector2.ZERO
	var step := tick-SETTLE
	var probe_y := 0.0
	var probe_slope := 0.0
	if step >= 1 and step <= DRIVE:
		_phases[gait.phase] = int(_phases.get(gait.phase,0))+1
		var probe: Dictionary = gait.ground_probe
		if not probe.is_empty():
			if typeof(probe.get("position")) != TYPE_VECTOR3 or typeof(probe.get("normal")) != TYPE_VECTOR3:
				_probe_errors += 1
			else:
				var p: Vector3 = probe.position
				var n: Vector3 = probe.normal
				probe_y = p.y
				probe_slope = rad_to_deg(n.angle_to(Vector3.UP))
				# Either adjoining top plane may own a witness exactly at a seam.
				var normal_error := minf(n.angle_to(_floor_normal(p+Vector3.BACK*0.005)),n.angle_to(_floor_normal(p+Vector3.FORWARD*0.005)))
				if not p.is_finite() or not n.is_finite() or absf(p.y-_floor_height(p))>0.015 or absf(n.length()-1.0)>0.03 or rad_to_deg(normal_error)>1:
					_probe_errors += 1
				_max_probe_slope = maxf(_max_probe_slope,probe_slope)
		_foot_step(0,state.left_sole_position,state.left_support_load_n,(state.support_feet & 1)!=0,state.left_sole_touching,tick,upright)
		_foot_step(1,state.right_sole_position,state.right_support_load_n,(state.support_feet & 2)!=0,state.right_sole_touching,tick,upright)
		slips = _contacts.sample(state,_previous_poses,_previous_vy)
		_sum_load += state.left_support_load_n+state.right_support_load_n
		_air_run = 0 if state.grounded and state.left_support_load_n+state.right_support_load_n>=0.02*_weight else _air_run+1
		_max_air = maxi(_max_air,_air_run)
		if _air_run > 6:
			_fail(tick,"lost_foot_support")
		var second := _is_turn() and step > TURN_AT
		var seg: Dictionary = _segments[int(second)]
		var age := step - (TURN_AT if second else 0)
		if age == 1:
			_segment_start = _prev_com
		var dir := _command.normalized()
		var displacement := (com-_segment_start).slide(Vector3.UP)
		seg.progress = displacement.dot(dir)
		seg.cross = maxf(seg.cross,displacement.slide(dir).length())
		if age > HZ:
			seg.n += 1
			seg.projected_sum += vel.dot(dir)
			seg.sq_error += (vel.slide(Vector3.UP)-_command).length_squared()
			seg.facing_sq += face_error*face_error
	if tick == SETTLE+DRIVE+STOP-HZ:
		_tail_start = com
	if tick > SETTLE+DRIVE+STOP-HZ:
		_end_travel = maxf(_end_travel,(com-_tail_start).slide(Vector3.UP).length())
		_tail_speed_sq += vel.slide(Vector3.UP).length_squared()
		_tail_facing_max = maxf(_tail_facing_max,face_error)
	if _trace:
		var planned: Vector3 = gait.target_velocity
		var target_l: Vector3 = gait.get("left_target",Vector3(INF,INF,INF))
		var target_r: Vector3 = gait.get("right_target",Vector3(INF,INF,INF))
		var target_com: Vector3 = gait.get("com_target",Vector3(INF,INF,INF))
		var capture: Vector3 = gait.get("capture_point",Vector3(INF,INF,INF))
		var trace_row := PackedStringArray([tick,_command.x,_command.z,com.x,com.y,com.z,vel.x,vel.z,pelvis_y,tilt,face_error,state.left_support_load_n,state.right_support_load_n,state.left_sole_position.y,state.right_sole_position.y,slips.x,slips.y,gait.phase,gait.support,gait.switches,state.fallen,state.nonfoot_ground_contact,planned.x,planned.z,probe_y,probe_slope,state.left_sole_position.x,state.left_sole_position.z,state.right_sole_position.x,state.right_sole_position.z,target_l.x,target_l.y,target_l.z,target_r.x,target_r.y,target_r.z,target_com.x,target_com.z,capture.x,capture.z])
		var muscle: Dictionary = _actor.call("get_muscle_telemetry")
		for id: StringName in LEG_PARTS:
			var up: Vector3 = state.body_poses[id].basis.y
			var w: Vector3 = state.body_angular_velocities[id]
			var torque: Vector3 = muscle[id].torque_world_nm
			var geom: Dictionary = _joint_locations[id]
			var parent: Transform3D = state.body_poses[geom.parent]
			var child: Transform3D = state.body_poses[id]
			var anchor_error := (parent*Vector3(geom.a)).distance_to(child*Vector3(geom.b))
			var axis_separation := (parent.basis*Vector3(geom.axis)).angle_to(child.basis*Vector3(geom.axis))
			trace_row.append_array(PackedStringArray([rad_to_deg(atan2(up.z,up.y)),rad_to_deg(atan2(-up.x,up.y)),w.x,w.z,torque.x,torque.z,torque.length()/maxf(0.001,muscle[id].limit_nm),anchor_error,rad_to_deg(axis_separation)]))
		trace_row.append_array(PackedStringArray(_self_contacts()))
		trace_row.append_array(PackedStringArray([vel.slide(Vector3.UP).length(),vel.y]))
		trace_row.append_array(PackedStringArray([_release_reason,_release_tick,worst_joint,worst_anchor]))
		_trace.store_csv_line(trace_row)
	_previous_poses = state.body_poses
	_previous_vy = vel.y
	_prev_com = com
	if tick >= SETTLE+DRIVE+STOP:
		_finish()
	else:
		_set_next_intent(tick+1)

func _finish() -> void:
	var speed := 0.35 if _case == "slow" else 0.8
	var rows := {}
	for i in (2 if _is_turn() else 1):
		var s := _segments[i]
		var mean: float = s.projected_sum / maxi(1,s.n)
		var rms := sqrt(float(s.sq_error) / maxi(1,s.n))
		var facing := sqrt(float(s.facing_sq) / maxi(1,s.n))
		var length := (TURN_AT if i==0 else DRIVE-TURN_AT) if _is_turn() else DRIVE
		var prefix := "segment%d_"%(i+1)
		rows[prefix+"progress_m"] = s.progress
		rows[prefix+"mean_m_s"] = mean
		rows[prefix+"rms_velocity_error_m_s"] = rms
		rows[prefix+"max_crosstrack_m"] = s.cross
		rows[prefix+"rms_facing_error_deg"] = facing
		if mean < .6*speed or mean > 1.4*speed or s.progress < .6*speed*length/HZ or rms > (.25 if _case=="slow" else .45) or s.cross > .30:
			_fail(_last_tick,prefix+"travel")
		if facing > 30:
			_fail(_last_tick,prefix+"facing")
	if _real_switches < 4 or _feet[0].landings < 2 or _feet[1].landings < 2 or _alternations < 3:
		_fail(_last_tick,"insufficient_alternating_loaded_steps")
	var stop_speed := sqrt(_tail_speed_sq/HZ)
	if _end_travel > .12 or stop_speed > .15 or _tail_facing_max > 30:
		_fail(_last_tick,"stop")
	var contacts: Dictionary = _contacts.summary(_weight*DRIVE/HZ)
	var load_ratio := _sum_load/(_weight*DRIVE)
	if load_ratio < .85 or load_ratio > 1.15:
		_fail(_last_tick,"ground_reaction")
	for side in ["left","right"]:
		var slip: float = contacts[side+"_loaded_contact_speed_rms_m_s"]
		if slip < 0 or slip > .12:
			_fail(_last_tick,side+"_foot_slip")
	var relief := _max_floor-_min_floor if _min_floor != INF else 0.0
	if _probe_errors>0 or (_case=="uneven" and (_max_probe_slope<1 or relief<.012)):
		_fail(_last_tick,"terrain_traversal")
	var summary := {"case":_case,"engine":Engine.get_version_info().string,"hz":HZ,"solver_iterations":128,
		"samples":_last_tick,"test_pass":_failures.is_empty(),"first_failure_tick":_first_tick,"first_failure":_first_reason,
		"all_failures":JSON.stringify(_failures),"min_com_height_m":_min_height,"min_pelvis_height_m":_min_pelvis,
		"max_tilt_deg":_worst_tilt,"fall_events":_fall_events,"fallen_frames":_fallen,"nonfoot_frames":_nonfoot,"max_low_load_frames":_max_air,
		"release_reason":_release_reason,"release_tick":_release_tick,"post_release_peak_torque_nm":_release_torque_peak,
		"peak_anchor_m":_anchor_peak,"peak_anchor_tick":_anchor_tick,"peak_anchor_joint":_anchor_joint,"first_anchor_over_20cm_tick":_first_gross_tick,
		"anchor_over_20cm_frames":_gross_anchor_frames,
		"drive_sole_load_ratio":load_ratio,"support_switches":_reported_switches,"verified_drive_switches":_real_switches,
		"physical_steps_left":_feet[0].landings,"physical_steps_right":_feet[1].landings,"alternating_landings":_alternations,
		"stop_last_s_drift_m":_end_travel,"stop_last_s_rms_m_s":stop_speed,"stop_last_s_max_facing_deg":_tail_facing_max,
		"observed_landing_relief_m":relief,"max_probe_slope_deg":_max_probe_slope,"invalid_ground_probe_frames":_probe_errors,
		"drive_phase_frames":JSON.stringify(_phases)}
	summary.merge(rows)
	summary.merge(contacts)
	var output := JSON.stringify(summary)
	var json := FileAccess.open(_path("summary.json"),FileAccess.WRITE)
	if json == null:
		_abort("Cannot create summary.")
		return
	json.store_line(output)
	json.close()
	_events.close()
	if _trace:
		_trace.close()
	print("WALK ",output)
	quit(0 if _failures.is_empty() else 1)
