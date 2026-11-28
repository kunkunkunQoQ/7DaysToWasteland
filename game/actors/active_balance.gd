extends RefCounted
## Balance recovery changes the targets of the existing joint motors. Contact impulses
## and the struck bone stay on the same rigid bodies throughout the response.

var stepping_foot := -1
var support_enabled := true:
	set(value):
		support_enabled = value
		if not value:
			stepping_foot = -1
			_step_request = Vector3.ZERO
var strain := 0.0
var lean := Vector3.ZERO
var _velocity := Vector3.ZERO
var _step := Vector3.ZERO
var _step_request := Vector3.ZERO
var _step_time := 0.0
var _remaining := 0.0
var _duration := 0.62
var _reach := 0.20
var _weight := 1.0
var _feet: Array[int] = []
var _leg := PackedInt32Array()
var _leg_weight := PackedFloat32Array()
var _upper := PackedFloat32Array()
var _brace := PackedFloat32Array()
var _yield := PackedFloat32Array()
var _recovery_rate := PackedFloat32Array()
var _sensors: Array[int] = []
var _blocked := PackedByteArray()
var _rig: Node3D

func setup(rig: Node3D, crawling: bool) -> void:
	_rig = rig
	var parts: Array = rig._parts
	_leg.resize(parts.size())
	_leg.fill(-1)
	_leg_weight.resize(parts.size())
	_upper.resize(parts.size())
	_brace.resize(parts.size())
	_yield.resize(parts.size())
	_recovery_rate.resize(parts.size())
	_blocked.resize(parts.size())
	var index: Dictionary = rig._index_by_bone
	var feet: Array = [&"ankle_l",&"ankle_r"]
	if index.has(&"paw0"):
		feet = [&"paw3",&"paw2",&"paw1",&"paw0"]
		_weight = 0.65
		_duration = 0.45
	elif crawling:
		feet = [&"hand_l" if index.has(&"hand_l") else &"elbow_l",&"hand_r" if index.has(&"hand_r") else &"elbow_r"]
		_weight = 0.70
	elif index.has(&"breast"):
		feet = [&"footl",&"footr"]
		_duration = 0.50
	elif index.has(&"carapace"):
		feet = [&"shinl0",&"shinr0",&"shinl1",&"shinr1",&"shinl2",&"shinr2",&"shinl3",&"shinr3"]
		_duration = 0.32
		_weight = 0.65
	elif index.has(&"shell"):
		feet = [&"paddlel0",&"paddler0",&"paddlel1",&"paddler1"]
		_weight = 0.52
	elif not index.has(&"hips"):
		feet = []
		_weight = 0.74
	elif not rig._model is WastelandPartyAvatar:
		feet = [&"ankle_l" if index.has(&"ankle_l") else &"knee_l",&"ankle_r" if index.has(&"ankle_r") else &"knee_r"]
		_weight = 0.82
		_duration = 0.73
	var frame: Transform3D = rig._model.global_transform.orthonormalized().affine_inverse()
	var bounds := AABB(frame*parts[0].body.global_position,Vector3.ZERO)
	for part in parts: bounds = bounds.expand(frame*part.body.global_position)
	_reach = clampf(maxf(bounds.size.y,bounds.size.z*0.48)*0.16,0.035,0.28)
	for side in feet.size():
		var bone: int = index.get(feet[side],-1)
		_feet.append(bone)
		var weight := 1.0
		while bone>0 and weight>=0.18:
			var label := String(parts[bone].body.name)
			if label in ["Body_torso","Body_hips","Body_breast"]: break
			_leg[bone] = side
			_leg_weight[bone] = weight
			weight *= 0.59
			bone = parts[bone].parent
	for label: StringName in index:
		var i: int = index[label]
		_recovery_rate[i] = 2.6 if i==0 or label==&"torso" else 2.05 if _leg[i]>=0 else 1.60
		if _leg[i]<0:
			_upper[i] = 0.40 if i==0 else 1.0
			if label in [&"head",&"skull"]: _upper[i] = 1.22
			if label in [&"tail",&"fan"]: _upper[i] = 0.25
			if label in [&"hand_l",&"elbow_l",&"pectorall",&"paddlel0",&"wingl",&"clawl"]: _brace[i] = -1.0
			if label in [&"hand_r",&"elbow_r",&"pectoralr",&"paddler0",&"wingr",&"clawr"]: _brace[i] = 1.0
		if i==0 or label in [&"head",&"torso",&"skull",&"hand_l",&"hand_r",&"tail",&"fan",&"wingl",&"wingr",&"clawl",&"clawr",&"paddlel0",&"paddler0"] or _feet.has(i):
			_sensors.append(i)
			parts[i].body.max_contacts_reported = 3

func reset() -> void:
	stepping_foot = -1
	_step_time = 0.0
	_step_request = Vector3.ZERO
	_remaining = 0.0
	lean = Vector3.ZERO
	_velocity = Vector3.ZERO
	strain = 0.0
	_yield.fill(0.0)
	_blocked.fill(0)

func stop() -> void:
	reset()
	for i in _sensors: _rig._parts[i].body.max_contacts_reported = 0

func resume() -> void:
	reset()
	for i in _sensors: _rig._parts[i].body.max_contacts_reported = 3

func hit(push: Vector3, at: Vector3, bone: StringName) -> void:
	var i: int = _rig._index_by_bone.get(StringName(String(bone).to_lower()),-1)
	if i<0:
		i = 0
		if at.is_finite():
			var best := INF
			for j in _rig._parts.size():
				var part = _rig._parts[j]
				var local: Vector3 = part.body.to_local(at)
				var gap := local.distance_squared_to(local.clamp(-part.extents,part.extents))
				if gap<best:
					best = gap
					i = j
	_react(i,push)

func _react(i: int, push: Vector3) -> void:
	if not push.is_finite() or push.length_squared()<0.09: return
	var ease := minf(1.0,push.length()/5.0)
	_remaining = maxf(_remaining,0.54+0.60*ease)
	_yield[i] = maxf(_yield[i],ease)
	var parent: int = _rig._parts[i].parent
	if parent>=0: _yield[parent] = maxf(_yield[parent],ease*0.42)
	# A hit on a light hand transfers less momentum to the trunk than a hip or leg strike.
	var transfer := 1.0 if i==0 or _rig._parts[i].body.name==&"Body_torso" else 0.60 if _leg[i]>=0 else 0.38
	var planar := push.slide(Vector3.UP)
	_velocity = (_velocity + planar.limit_length(8.0)*_reach*transfer*_weight*1.9).limit_length(_reach*8.5)
	strain = maxf(strain,ease*transfer)
	var request := planar*transfer
	if support_enabled and stepping_foot<0 and not _feet.is_empty() and request.length_squared()>_step_request.length_squared():
		_step_request = request

func _choose_step(request: Vector3) -> void:
	var strength := smoothstep(0.95,4.9,request.length())
	if strength<0.10: return
	var best := -INF
	var hips: RigidBody3D = _rig._parts[0].body
	var pivot := hips.global_position
	var nominal: Vector3 = _rig._model.global_transform * _rig._targets[0].origin
	# Land toward the displaced pelvis as well as the incoming blow. This changes the
	# catching side when a second impact reaches a body already falling the other way.
	var direction := ((pivot-nominal).slide(Vector3.UP) + request*0.12).normalized()
	var travel := direction*_reach*strength
	for side in _feet.size():
		var foot := _feet[side]
		if foot<0: continue
		var point: Vector3 = _rig._parts[foot].body.global_position
		var score := direction.dot(point-pivot)
		if score<=best: continue
		var cast := PhysicsRayQueryParameters3D.create(point+Vector3.UP*_reach*0.45,point-Vector3.UP*(_reach*1.7+0.04),1|2|8,_rig._own_rids)
		var floor_hit := _rig.get_world_3d().direct_space_state.intersect_ray(cast)
		if floor_hit.is_empty() or floor_hit.normal.y<0.45: continue
		cast.from += travel
		cast.to += travel
		var landing := _rig.get_world_3d().direct_space_state.intersect_ray(cast)
		if landing.is_empty() or landing.normal.y<0.45: continue
		var rise := float(landing.position.y-floor_hit.position.y)
		if absf(rise)>_reach*0.70: continue
		stepping_foot = side
		_step = travel+Vector3.UP*rise
		best = score
	if stepping_foot>=0:
		_step_time = 0.0

func advance(dt: float) -> void:
	for i in _sensors:
		var body: RigidBody3D = _rig._parts[i].body
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var strongest := Vector3.ZERO
		if state:
			for c in state.get_contact_count():
				var normal := state.get_contact_local_normal(c)
				if absf(normal.y)>0.78: continue
				var speed := state.get_contact_impulse(c).dot(normal)/body.mass
				if speed>strongest.length(): strongest = normal*speed
		# One response at impact, without retriggering it while a body leans against a wall.
		if strongest.length_squared()>0.64 and _blocked[i]==0:
			_react(i,strongest)
			_blocked[i] = 1
		elif strongest.length_squared()<0.04:
			_blocked[i] = 0
	# Inputs and network hits may arrive on a render frame; query the ground only in physics.
	if not _step_request.is_zero_approx():
		_choose_step(_step_request)
		_step_request = Vector3.ZERO
	if _remaining<=0.0 and stepping_foot<0: return
	_remaining = maxf(0.0,_remaining-dt)
	strain = move_toward(strain,0.0,dt*1.35)
	var decay := exp(-7.4*dt)
	var impulse := _velocity + lean*7.4
	lean = ((lean + impulse*dt)*decay).limit_length(_reach*0.8)
	_velocity = (_velocity-impulse*7.4*dt)*decay
	for i in _yield.size(): _yield[i]=move_toward(_yield[i],0.0,dt*_recovery_rate[i])
	if stepping_foot>=0:
		_step_time += dt
		if _step_time>=_duration: stepping_foot = -1
	if _remaining<=0.0 and stepping_foot<0:
		_yield.fill(0.0)
		lean = Vector3.ZERO
		_velocity = Vector3.ZERO

func step_offset(side: int) -> Vector3:
	if stepping_foot<0 or side!=stepping_foot: return Vector3.ZERO
	var t := _step_time/_duration
	var out := smoothstep(0.0,0.43,t)
	var back := smoothstep(0.57,1.0,t)
	var lift := sin(PI*out) + 0.65*sin(PI*back)
	return _step*(out-back)+Vector3.UP*(_step.length()*0.38*lift)

func frequency_scale(i: int) -> float:
	return 1.0-0.62*_yield[i]

func impact_weight(i: int) -> float:
	var parent: int = _rig._parts[i].parent
	return maxf(_yield[i], _yield[parent] if parent >= 0 else 0.0)

func target(i: int, goal: Transform3D) -> Transform3D:
	if _remaining<=0.0 and stepping_foot<0: return goal
	var weight := _upper[i]
	if weight>0.0:
		goal.origin += lean*weight
		if _brace[i]!=0:
			var right: Vector3 = _rig._model.global_basis.x.normalized()
			goal.origin += (right*_brace[i]+Vector3.UP)*lean.length()*0.76
		var axis := Vector3.UP.cross(lean)
		if axis.length_squared()>0.0000001:
			goal.basis = Basis(axis.normalized(),minf(0.32,axis.length()*0.6/_reach)*weight)*goal.basis
	elif _leg[i]==stepping_foot:
		goal.origin += step_offset(_leg[i])*_leg_weight[i]
	return goal
