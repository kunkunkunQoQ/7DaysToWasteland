class_name WastelandCreatureBrain
extends RefCounted

enum Mode { ROAM, INVESTIGATE, SEARCH, CHASE, FLANK, RANGE, FLEE, PURSUE }
enum Action { NONE, MELEE, SMASH, SPIT, SCREAM, CHARGE, RUPTURE, MEND }
enum State { SLEEPING, WAKING, WANDER, INVESTIGATE, CHASE, ATTACK_PLAYER, ATTACK_BLOCK, STAGGER, KNOCKDOWN, RAGE, DEAD }

const SOLIDS := WastelandCreatureRoute.SOLIDS
const FLIGHT_SPEED := 15.0

var actor: WastelandCreature
var route := WastelandCreatureRoute.new()
var profile: Dictionary
var animal := false
var mode := Mode.ROAM
var action := Action.NONE
var seen: WastelandSurvivor
var locked_target: WastelandSurvivor
var locked_wall: StaticBody3D
var patient: WastelandCreature
var patient_serial := 0
var mend_left := 0.0
var attack_point := Vector3.INF
var attack_heading := Vector3.ZERO
var action_left := 0.0
var action_span := 1.0
var charge_left := 0.0
var cooldown := 0.0
var sense_left := 0.0
var vision_arc := 0.0
var hearing := 1.0
var heard_serial := 0
var interest := Vector3.INF
var memory := 0.0
var home := Vector3.ZERO
var herd := 0
var forage_left := 0.0
var hunt_pause := 0.0
var goal := Vector3.INF
var patrol_left := 0.0
var maneuver_left := 0.0
var rally_left := 0.0
var side := 1.0
var desired_facing := Vector3.ZERO
var reach := 1.6
var state := State.WANDER
var state_left := 0.0
var wake_span := 1.0
var light_dwell := 0.0
var rage_left := 0.0
var search_left := -1.0
var retreat_left := 0.0
var slot := -1
var slot_target: WastelandSurvivor
var overflow := false
var pursuing_cue := false

var breach_wall: StaticBody3D:
	get: return route.wall if is_instance_valid(route.wall) else null

func configure(owner: WastelandCreature) -> void:
	actor = owner
	route.actor = owner

func revive(previous: Dictionary) -> void:
	profile = actor.spec.ai
	animal = bool(actor.spec.get("animal", false))
	reach = float(profile.get("reach", 1.6))
	if not animal:
		if actor.biting():
			reach = minf(reach,0.96)
		elif actor.low_crawl():
			reach *= 0.84
	vision_arc = cos(deg_to_rad(float(profile.fov) * 0.5))
	hearing = float(profile.hearing)
	mode = Mode.ROAM
	state = State.WANDER
	state_left = 0.0
	wake_span = clampf(float(previous.get("wake_span", 1.0)), 0.8, 1.2)
	light_dwell = 0.0
	rage_left = maxf(0.0, float(previous.get("rage_left", 0.0)))
	retreat_left = maxf(0.0, float(previous.get("retreat_left", 0.0)))
	search_left = -1.0
	slot = -1
	slot_target = null
	overflow = false
	pursuing_cue = bool(previous.get("pursuing_cue", false))
	seen = null
	locked_target = null
	locked_wall = null
	patient = null
	patient_serial = 0
	attack_point = Vector3.INF
	attack_heading = Vector3.ZERO
	action_span = 1.0
	mend_left = 0.0
	action = Action.NONE
	action_left = 0.0
	charge_left = 0.0
	cooldown = actor.actor_rng.randf_range(0.42, 1.15)
	sense_left = actor.actor_rng.randf_range(0.06, 0.31)
	heard_serial = actor.director.sound_serial
	forage_left = 0.0
	herd = int(previous.get("herd", 0))
	hunt_pause = 0.0
	home = previous.get("home", actor.global_position)
	goal = Vector3.INF
	patrol_left = 0.0
	maneuver_left = 0.0
	rally_left = 0.0
	desired_facing = Vector3.ZERO
	interest = previous.get("interest", Vector3.INF)
	memory = float(previous.get("memory", 0.0))
	if not interest.is_finite() and bool(previous.get("alerted", false)) and not actor.wave:
		interest = home
		memory = 2.8
	if interest.is_finite() and memory > 0.0:
		mode = Mode.FLEE if animal else Mode.INVESTIGATE
	side = -1.0 if actor.actor_rng.randf() < 0.5 else 1.0
	route.reset(side)
	if not animal:
		state = State.CHASE if actor.wave else State.INVESTIGATE if memory > 0.0 else State.WANDER
		if bool(previous.get("sleeping", false)):
			state = State.SLEEPING
		var saved := int(previous.get("fsm", state))
		if saved in [State.SLEEPING, State.WAKING, State.STAGGER, State.KNOCKDOWN, State.DEAD, State.RAGE]:
			state = saved as State
			state_left = maxf(0.0, float(previous.get("state_left", 0.0)))
		if retreat_left > 0.0:
			goal = previous.get("retreat_goal", actor.global_position)
	elif int(previous.get("fsm",state)) in [State.KNOCKDOWN, State.DEAD]:
		state = int(previous.fsm) as State
		state_left = maxf(0.0,float(previous.get("state_left",0.0)))

func _wake(point: Vector3) -> void:
	if state != State.SLEEPING:
		return
	_remember(point, float(profile.memory))
	pursuing_cue = true
	wake_span = actor.actor_rng.randf_range(0.8, 1.2)
	state_left = wake_span
	state = State.WAKING
	actor.alerted = true
	actor.session.audio.play_at("growl", _eyes(), 0.55)

func interrupt(knockdown: bool, duration: float) -> void:
	if state == State.DEAD or ((animal or state in [State.SLEEPING, State.WAKING]) and not knockdown):
		return
	_cancel_action()
	if state == State.KNOCKDOWN and not knockdown:
		return
	state = State.KNOCKDOWN if knockdown else State.STAGGER
	state_left = maxf(state_left, duration)
	actor.stagger = state_left
	slot = -1

func try_rage() -> void:
	if animal or rage_left > 0.0 or state in [State.DEAD, State.SLEEPING, State.WAKING]:
		return
	if actor.actor_rng.randf() < 0.30:
		rage_left = 5.0
		route.path_delay = 0.0
		if state not in [State.STAGGER, State.KNOCKDOWN]:
			state = State.RAGE

func retreat_from(point: Vector3) -> void:
	actor.wave = false
	if state == State.DEAD:
		return
	_cancel_action()
	route.clear_plan()
	rage_left = 0.0
	if state != State.KNOCKDOWN:
		state_left = 0.0
		actor.stagger = 0.0
		state = State.WANDER
	actor.alerted = false
	seen = null
	slot = -1
	memory = 0.0
	interest = Vector3.INF
	mode = Mode.ROAM
	retreat_left = 8.0
	pursuing_cue = false
	var away := WastelandCreatureRoute.planar(actor.global_position - point).normalized()
	goal = actor.global_position + (away if away != Vector3.ZERO else actor.global_basis.z) * 19.0

func _beam_reaches(player: WastelandSurvivor) -> bool:
	if not _alive(player) or not player.headlamp.visible:
		return false
	var lamp := player.headlamp
	var delta := _eyes() - lamp.global_position
	return delta.length_squared() < lamp.spot_range * lamp.spot_range and (-lamp.global_basis.z).dot(delta.normalized()) >= cos(deg_to_rad(lamp.spot_angle)) and _clear_to(player, lamp.global_position, _eyes())

func provoke(origin: Vector3, interrupt_action := true) -> void:
	_wake(origin)
	if origin.is_finite():
		_remember(origin, float(profile.memory))
	sense_left = 0.0
	if interrupt_action: _cancel_action()

func tick(delta: float, player: WastelandSurvivor, teammates: Array[WastelandSurvivor], observer_range: float) -> Vector3:
	if not is_instance_valid(seen):
		seen = null
	if not is_instance_valid(locked_target):
		locked_target = null
	cooldown = maxf(0.0, cooldown - delta)
	mend_left = maxf(0.0,mend_left-delta)
	forage_left=maxf(0.0,forage_left-delta)
	hunt_pause = maxf(0.0, hunt_pause - delta)
	if animal or state != State.INVESTIGATE:
		memory = maxf(0.0, memory - delta)
	maneuver_left -= delta
	rally_left -= delta
	patrol_left -= delta
	sense_left -= delta
	route.wants_motion = false
	desired_facing = Vector3.ZERO
	if not animal:
		rage_left = maxf(0.0, rage_left - delta)
		if retreat_left > 0.0:
			retreat_left = maxf(0.0, retreat_left - delta)
			if retreat_left <= 0.0:
				actor.director.release(actor)
				return Vector3.ZERO
			return route.heading(delta, goal, false, false, reach, 0.4)
		if state == State.SLEEPING:
			var lamp_owner:=_closest_player(player,teammates,_beam_reaches)
			light_dwell = light_dwell + delta if lamp_owner != null else 0.0
			if light_dwell >= 0.6:
				seen = lamp_owner
				_wake(lamp_owner.global_position)
			elif sense_left <= 0.0 or heard_serial != actor.director.sound_serial:
				sense_left = 0.20
				seen=_closest_player(player,teammates,_can_see)
				if seen != null:
					_wake(seen.global_position)
				else:
					_listen()
					if memory > 0.0:
						_wake(interest)
			return Vector3.ZERO
		if state in [State.WAKING, State.STAGGER, State.KNOCKDOWN]:
			state_left = maxf(0.0, state_left - delta)
			if state_left <= 0.0:
				state = State.RAGE if rage_left > 0.0 else State.CHASE
				mode = Mode.CHASE
				goal = interest
				sense_left = 0.0
			return Vector3.ZERO
		if state == State.DEAD:
			return Vector3.ZERO
		if search_left >= 0.0:
			search_left -= delta
			if search_left < 0.0:
				memory = 0.0
				interest = Vector3.INF
				sense_left = 0.0
	if actor.stagger > 0.0:
		_cancel_action()
		return Vector3.ZERO
	if charge_left > 0.0:
		return _charge(delta)
	if action != Action.NONE:
		_update_attack(delta)
		return Vector3.ZERO
	if sense_left <= 0.0:
		sense_left = actor.actor_rng.randf_range(0.19, 0.29) if observer_range < 26.0 else 0.59 if observer_range < 55.0 else 1.25
		_survey(player,teammates)
	actor.alerted = actor.wave or memory > 0.0 or _alive(seen) or mode == Mode.PURSUE
	if not animal:
		state = State.ATTACK_BLOCK if is_instance_valid(route.wall) else State.RAGE if rage_left > 0.0 else State.CHASE if mode in [Mode.CHASE, Mode.RANGE, Mode.FLANK] else State.INVESTIGATE if mode in [Mode.INVESTIGATE, Mode.SEARCH] else State.WANDER
	if cooldown <= 0.0 and _prepare_attack():
		desired_facing = attack_heading
		return Vector3.ZERO
	var aware := _alive(seen)
	if aware and mode in [Mode.CHASE, Mode.RANGE]:
		desired_facing = WastelandCreatureRoute.planar(seen.global_position - actor.global_position).normalized()
	if not animal and actor.attack > 0.48:
		return Vector3.ZERO
	var stop := 0.17 if mode == Mode.CHASE and (slot >= 0 or overflow) else reach * 0.78 if mode == Mode.CHASE else 0.60
	var can_breach := not animal and (mode in [Mode.CHASE, Mode.INVESTIGATE] or rage_left > 0.0) and float(actor.spec.wall)*actor.wall_factor() > 0.0
	if rage_left > 0.0 and not goal.is_finite():
		goal = actor.global_position
	if not can_breach and is_instance_valid(route.wall):
		route.clear_plan()
	if animal and mode==Mode.ROAM and forage_left>0.0: return Vector3.ZERO
	var heading := route.heading(delta, goal, animal and actor.type!="otter", can_breach, reach, stop)
	if is_instance_valid(route.wall):
		if not animal: state = State.ATTACK_BLOCK
		desired_facing = WastelandCreatureRoute.planar(route.wall_point - actor.global_position).normalized()
	return heading

func speed_factor() -> float:
	if charge_left > 0.0:
		return 2.10 if profile.has("rush_range") else 1.56
	match mode:
		Mode.ROAM: return 0.34
		Mode.SEARCH: return 0.54
		Mode.INVESTIGATE: return 0.83
		Mode.RANGE: return 0.73
	return 1.0

func windup_progress() -> float:
	return clampf(1.0 - action_left / action_span, 0.0, 1.0) if action != Action.NONE else 0.0

func _alive(player: WastelandSurvivor) -> bool:
	return is_instance_valid(player) and not player.is_queued_for_deletion() and player.health > 0.0

func _closest_player(player:WastelandSurvivor,teammates:Array[WastelandSurvivor],condition:Callable)->WastelandSurvivor:
	var best:WastelandSurvivor
	var distance:=INF
	if _alive(player) and condition.call(player):
		best=player
		distance=actor.global_position.distance_squared_to(player.global_position)
	for person:WastelandSurvivor in teammates:
		if not _alive(person): continue
		var next:=actor.global_position.distance_squared_to(person.global_position)
		if next<distance and condition.call(person):
			best=person
			distance=next
	return best

func _survey(player: WastelandSurvivor, teammates: Array[WastelandSurvivor]) -> void:
	# Keep a visible target until it escapes. A closer player behind cover cannot steal aggro.
	if not _can_see(seen):
		seen=_closest_player(player,teammates,_can_see)
	if _alive(seen):
		pursuing_cue = false
		heard_serial = actor.director.sound_serial
		_remember(seen.global_position, float(profile.memory))
		if animal:
			_escape()
		else:
			_chase(seen)
		return
	_listen()
	if animal and memory <= 0.0:
		var danger: Vector3 = actor.director.wildlife_danger(actor)
		if danger.is_finite():
			_remember(danger, float(profile.memory))
	if actor.wave and actor.session.clock.horde_active():
		var anchor:=_closest_player(player,teammates,_alive)
		if _alive(anchor):
			_remember(anchor.global_position, 5.5)
			pursuing_cue = true
	if pursuing_cue and interest.is_finite():
		if WastelandCreatureRoute.planar(actor.global_position - interest).length_squared() > 1.55:
			mode = Mode.CHASE
			goal = interest
			memory = maxf(memory, 2.0)
			return
		pursuing_cue = false
	if memory > 0.0 and interest.is_finite():
		if animal:
			_escape()
		else:
			_investigate()
		return
	if animal and hunt_pause <= 0.0:
		var prey: Array = actor.spec.ecology.get("prey", [])
		if not prey.is_empty() and actor.director.wildlife_activity(actor.type) != actor.spec.ecology.rest:
			var target: WastelandCreature = actor.director.hunt_target(actor, prey)
			if is_instance_valid(target):
				_pursue(target)
				return
	if mode != Mode.ROAM:
		if herd == 0 or actor.global_position.distance_squared_to(home) > 20.0 * 20.0:
			home = actor.global_position
		patrol_left = 0.0
		route.clear_plan()
		goal = Vector3.INF
		mode = Mode.ROAM
	if mode==Mode.ROAM and goal.is_finite() and actor.global_position.distance_squared_to(goal)<1.75 and animal and forage_left<=0 and actor.director.wildlife_activity(actor.type)!=actor.spec.ecology.rest:
		forage_left=actor.actor_rng.randf_range(1.1,2.9)
		patrol_left=forage_left
		goal=Vector3.INF
		actor.forage_sign()
	if patrol_left <= 0.0:
		if herd != 0 and actor.director.wildlife_activity(actor.type) == actor.spec.ecology.rest and actor.global_position.distance_squared_to(home) < 20.0:
			goal = Vector3.INF
			patrol_left = actor.actor_rng.randf_range(5.0, 9.0)
			return
		var out := Vector3.FORWARD.rotated(Vector3.UP, actor.actor_rng.randf() * TAU)
		goal = route.ground_near(home + out * actor.actor_rng.randf_range(2.7,8.0), animal)
		if actor.type in ["argali","otter","jerboa"]:
			# Sheep browse higher shoulders, otters search downshore, jerboas stay close to cover.
			for attempt in 3:
				var dir:=out.rotated(Vector3.UP,attempt*2.1)
				var probe:=route.ground_near(home+dir*(3.1 if actor.type=="jerboa" else 6.0),actor.type!="otter")
				if probe.is_finite() and (not goal.is_finite() or (probe.y>goal.y if actor.type=="argali" else probe.y<goal.y)):
					goal=probe if actor.type!="otter" or probe.y> -0.7 else goal
		patrol_left = actor.actor_rng.randf_range(4.1, 7.5)
		if not goal.is_finite():
			patrol_left = 1.3

func _pursue(target: WastelandCreature) -> void:
	mode = Mode.PURSUE
	goal = target.physical_position()
	if actor.global_position.distance_squared_to(goal) > 1.6 or cooldown > 0.0:
		return
	actor.attack = 1.0
	cooldown = 2.2
	target.brain.provoke(actor.global_position)
	target.hurt = 0.56
	target.hp -= 18.0 if actor.type == "wolf" else 9.0
	var mouth := actor.melee_origin()
	var contact: Dictionary = target.hurtboxes.closest_contact(mouth)
	var touch: Vector3 = contact.get("at",target.physical_position())
	var bone: StringName = contact.get("bone",&"")
	var push := mouth.direction_to(touch) * 2.2
	target.record_limb_hit(push,touch,bone)
	if target.hp <= 0.0:
		target.begin_death(push,touch,bone)
		actor.director.retain_corpse(target)
		hunt_pause = 24.0
		goal = Vector3.INF
		mode = Mode.ROAM
	elif target.ragdoll != null:
		target.ragdoll.kick_at(push,touch,bone)
	elif target.active_motion != null:
		target.active_motion.kick_at(push,touch,bone)

func _can_see(player: WastelandSurvivor) -> bool:
	if not _alive(player):
		return false
	var offset := player.global_position - actor.global_position
	var range_m := float(profile.vision) * lerpf(1.0, 0.51, player.crouch)
	if not player.headlamp.visible:
		range_m *= lerpf(0.71, 1.0, clampf(float(actor.session.atmosphere.sun_strength), 0.0, 1.0))
	if offset.length_squared() > range_m * range_m:
		return false
	var relaxed_arc := vision_arc - (0.48 if player == seen else 0.0)
	if (state == State.SLEEPING or WastelandCreatureRoute.planar(offset).length_squared() > 6.25) and (-actor.global_basis.z).dot(WastelandCreatureRoute.planar(offset).normalized()) < relaxed_arc:
		return false
	return _clear_to(player, _eyes(), _target_point(player, 0.79))

func _target_point(player: WastelandSurvivor, height_ratio: float) -> Vector3:
	return player.global_position + Vector3.UP * player.stand_shape.height * height_ratio

func _clear_to(player: WastelandSurvivor, from: Vector3, to: Vector3) -> bool:
	var ignored: Array[RID] = []
	if is_instance_valid(player.mount_vehicle):
		ignored.append(player.mount_vehicle.get_rid())
	return route.ray(from, to, SOLIDS, ignored).is_empty()

func _eyes() -> Vector3:
	if state in [State.SLEEPING, State.WAKING]:
		return actor.global_position + Vector3.UP * minf(actor.body_height() * 0.4, 0.56)
	return actor.global_position + Vector3.UP * actor.body_height() * 0.77

func _listen() -> void:
	if heard_serial == actor.director.sound_serial:
		return
	var score := 0.0
	var at := actor.global_position
	var time: float = actor.session.clock.elapsed
	var best := Vector3.INF
	for cue in actor.director.sounds:
		if state == State.SLEEPING and not cue.get("from_player",true):
			continue
		if int(cue.id) <= heard_serial or float(cue.until) < time:
			continue
		var distance := at.distance_to(cue.point)
		var radius := float(cue.radius) * hearing
		if distance >= radius:
			continue
		var rank := (1.0 - distance / radius) * clampf(radius / 12.0, 0.3, 1.6)
		if rank <= score:
			continue
		if not route.ray(_eyes(), cue.point).is_empty():
			radius *= 0.46
			rank = (1.0 - distance / radius) * clampf(radius / 12.0, 0.3, 1.6)
		if rank > score:
			best = cue.point
			score = rank
	heard_serial = actor.director.sound_serial
	if best.is_finite():
		_remember(best, float(profile.memory) * 0.78)

func _remember(point: Vector3, seconds: float) -> void:
	search_left = -1.0
	if not interest.is_finite() or interest.distance_squared_to(point) > 2.25:
		patrol_left = 0.0
	interest = point
	memory = seconds

func _chase(player: WastelandSurvivor) -> void:
	var at := actor.global_position
	var offset := WastelandCreatureRoute.planar(player.global_position - at)
	var distance := offset.length()
	var across := offset.normalized().cross(Vector3.UP) * side
	var lower := float(profile.get("range_min", 0.0))
	var upper := float(profile.get("range_max", 0.0))
	if upper > 0.0 and distance < upper + 0.3 and distance > reach * 1.30 and absf(player.global_position.y - at.y) < 3.0:
		if mode != Mode.RANGE or patrol_left <= 0.0:
			var direction := across
			if distance < lower + 0.7:
				direction = (across * 0.46 - offset.normalized()).normalized()
			goal = route.ground_near(at + direction * 2.7, false)
			if not goal.is_finite() or not route.step_toward(direction, false):
				side = -side
				goal = route.ground_near(at - across * 2.5, false)
			patrol_left = actor.actor_rng.randf_range(0.78, 1.20)
		mode = Mode.RANGE
		return
	if mode == Mode.FLANK and maneuver_left > 0.0 and distance > 3.6 and goal.is_finite() and at.distance_squared_to(goal) > 1.06:
		return
	var flank := float(profile.get("flank", 0.0))
	if maneuver_left <= 0.0 and flank > 0.0 and distance > 6.6 and distance < 20.0:
		var point := route.ground_near(player.global_position + across * flank - offset.normalized() * 2.3, false)
		if point.is_finite() and route.step_toward(WastelandCreatureRoute.planar(point - at).normalized(), false):
			mode = Mode.FLANK
			goal = point
			maneuver_left = actor.actor_rng.randf_range(1.45, 2.17)
			return
		maneuver_left = 3.1
	if mode == Mode.FLANK:
		maneuver_left = actor.actor_rng.randf_range(4.3, 6.9)
	mode = Mode.CHASE
	goal = player.global_position + WastelandCreatureRoute.planar(player.velocity).limit_length(5.3) * float(profile.get("lead", 0.0))
	if distance <= 6.0:
		_assign_slot(player)
	else:
		slot = -1
		overflow = false

func _assign_slot(player: WastelandSurvivor) -> void:
	var occupied := 0
	for other: WastelandCreature in actor.director.alive:
		if other == actor or other.hp <= 0.0 or other.brain.slot_target != player or other.brain.slot < 0 or other.brain.seen != player:
			continue
		if other.global_position.distance_squared_to(player.global_position) <= 42.25:
			occupied |= 1 << other.brain.slot
	var from := WastelandCreatureRoute.planar(actor.global_position - player.global_position)
	var nearest := posmod(roundi(atan2(from.z, from.x) * 8.0 / TAU), 8)
	if slot_target != player or slot < 0 or occupied & (1 << slot):
		slot = -1
		for offset: int in [0,1,-1,2,-2,3,-3,4]:
			var candidate := posmod(nearest + offset, 8)
			if not occupied & (1 << candidate):
				slot = candidate
				break
	slot_target = player
	overflow = slot < 0
	var angle := (nearest + side * 1.25 if overflow else float(slot)) * TAU / 8.0
	goal += Vector3(cos(angle), 0, sin(angle)) * (3.1 if overflow else reach * 0.76)

func _investigate() -> void:
	slot = -1
	overflow = false
	var at := actor.global_position
	var offset := interest - at
	if WastelandCreatureRoute.planar(offset).length_squared() > 1.55 or absf(offset.y) > 1.65:
		mode = Mode.INVESTIGATE
		goal = interest
		return
	if mode != Mode.SEARCH:
		mode = Mode.SEARCH
		goal = Vector3.INF
		search_left = 3.0
		route.clear_plan()
	desired_facing = (-actor.global_basis.z).rotated(Vector3.UP, side * (0.85 if search_left > 1.5 else -0.85))

func _escape() -> void:
	var at := actor.global_position
	var offset := WastelandCreatureRoute.planar(at - interest)
	var away := offset.normalized() if offset.length_squared() > 0.01 else actor.global_basis.z
	if actor.type=="jerboa": away=away.rotated(Vector3.UP,side*0.52)
	if actor.type in ["argali","otter"]:
		var best:= -INF
		for turn:float in [-0.79,0.0,0.79]:
			var dir:=away.rotated(Vector3.UP,turn)
			var at_probe:=at+dir*6.0
			var altitude:float=actor.session.stream.ground_at(at_probe)
			var rank:=altitude if actor.type=="argali" else -absf(altitude-0.2)
			if rank>best:
				best=rank
				offset=dir
		away=offset.normalized()
	if _alive(seen) and _wants_charge(seen):
		mode = Mode.CHASE
		goal = seen.global_position
		return
	if mode == Mode.FLEE and patrol_left > 0.0 and goal.is_finite() and route.stuck < 0.40:
		return
	mode = Mode.FLEE
	forage_left=0.0
	patrol_left = 0.76
	goal = Vector3.INF
	for turn: float in [0.0, 0.55, -0.55, 1.12, -1.12, 1.63, -1.63]:
		var direction := away.rotated(Vector3.UP, turn * side)
		var point := route.ground_near(at + direction * float(profile.flee), true)
		if point.is_finite() and route.step_toward(direction, true):
			goal = point
			return
	# A short escape along the shore or around a boulder can open a longer route on the next survey.
	for turn: float in [0.0, 0.81, -0.81, 1.57, -1.57]:
		var direction := away.rotated(Vector3.UP, turn * side)
		var point := route.ground_near(at + direction * 3.0, true)
		if point.is_finite() and route.step_toward(direction, true):
			goal = point
			return

func _wants_charge(player: WastelandSurvivor) -> bool:
	if not profile.has("charge_threshold"):
		return false
	var vulnerable := actor.hp < actor.max_health() * float(profile.charge_threshold)
	var distance := actor.global_position.distance_squared_to(player.global_position)
	return distance < (35.0 if vulnerable else 10.24) and (vulnerable or route.stuck > 0.62)

func _prepare_attack() -> bool:
	if _alive(seen):
		var gap := seen.global_position - actor.global_position
		var distance := WastelandCreatureRoute.planar(gap).length()
		var heading := WastelandCreatureRoute.planar(gap).normalized()
		if profile.has("mend_range") and mend_left <= 0.0 and distance > reach:
			mend_left = 0.65
			patient = actor.director.wounded_ally(actor,float(profile.mend_range))
			if is_instance_valid(patient):
				patient_serial = patient.spawn_serial
				var face := WastelandCreatureRoute.planar(patient.global_position-actor.global_position).normalized()
				_begin(Action.MEND,float(profile.mend_windup),null,patient.global_position,face,"scream_tell")
				return true
		if heading != Vector3.ZERO and (-actor.global_basis.z).dot(heading) > 0.42:
			if animal:
				if distance < 3.9 and absf(gap.y) < 0.91 and _wants_charge(seen) and _clear_to(seen, _eyes(), _target_point(seen, 0.38)):
					_begin(Action.CHARGE, float(profile.windup), seen, Vector3.INF, heading, "attack_tell")
					return true
			elif profile.has("call_range") and not actor.screamed and distance < float(profile.call_range) and _clear_to(seen, _eyes(), _target_point(seen, 0.68)):
				_begin(Action.SCREAM, float(profile.call_windup), seen, seen.global_position, heading, "scream_tell")
				return true
			elif not overflow and not is_instance_valid(route.wall) and _within_melee(seen, heading, reach):
				_begin(Action.MELEE, clampf(float(profile.windup), 0.35, 0.55), seen, Vector3.INF, heading, "attack_tell")
				return true
			elif profile.has("rush_range") and actor.can_rush() and distance < float(profile.rush_range) and absf(gap.y) < 0.85 and _clear_to(seen,_eyes(),_target_point(seen,0.50)):
				_begin(Action.CHARGE,float(profile.rush_windup),seen,seen.global_position,heading,"attack_tell")
				return true
			elif profile.has("range_max") and distance > float(profile.range_min) and distance < float(profile.range_max):
				var aim := _target_point(seen, 0.66) + WastelandCreatureRoute.planar(seen.velocity).limit_length(5.0) * 0.19
				var ignored: Array[RID] = [actor.get_rid()]
				var lane := route.ray(actor.gland.global_position, aim, SOLIDS | 4, ignored)
				if lane.is_empty() or lane.get("collider") == seen or (is_instance_valid(seen.mount_vehicle) and lane.get("collider") == seen.mount_vehicle):
					_begin(Action.SPIT, float(profile.spit_windup), seen, aim, heading, "spit_tell")
					return true
				cooldown = 0.18
	var wall_contact := route.strike_wall(reach)
	if not wall_contact.is_empty():
		var heading := WastelandCreatureRoute.planar(wall_contact.position - actor.global_position).normalized()
		locked_wall = wall_contact.collider
		_begin(Action.SMASH, float(profile.windup) * 1.05, null, wall_contact.position, heading, "attack_tell")
		return true
	return false

func _begin(next: Action, duration: float, victim: WastelandSurvivor, point: Vector3, heading: Vector3, sample: String) -> void:
	if not animal:
		state = State.ATTACK_BLOCK if next == Action.SMASH else State.ATTACK_PLAYER
	action = next
	action_left = duration
	action_span = duration
	attack_point = point
	attack_heading = heading
	locked_target = victim
	actor.session.audio.play_at(sample, _eyes(), 0.88 if next in [Action.SPIT, Action.SCREAM] else 0.67)

func _cancel_action() -> void:
	if action == Action.MEND:
		mend_left = 3.5
	patient = null
	if action != Action.NONE or charge_left > 0.0:
		cooldown = maxf(cooldown, 0.42)
	action = Action.NONE
	action_left = 0.0
	charge_left = 0.0
	locked_target = null
	locked_wall = null

func _update_attack(delta: float) -> void:
	desired_facing = attack_heading
	action_left -= delta
	if action_left > 0.0:
		return
	var difficulty: float = actor.session.world_settings.difficulty
	cooldown = float(actor.spec.rate)
	actor.attack = 1.0
	match action:
		Action.MELEE:
			if _within_melee(locked_target, attack_heading, reach + 0.12):
				var source := "heavy" if actor.type == "brute" and not actor.biting() else "radiation" if actor.type == "radiant" else "claw"
				var hand := actor.melee_origin()
				var ratio := 0.22 if actor.low_crawl() or actor.type == "crawler" else 0.55
				locked_target.damage(float(actor.spec.hit) * actor.melee_factor() * difficulty,source,hand,locked_target.surface_toward(hand,ratio))
		Action.SMASH:
			var contact := route.strike_wall(reach + 0.12)
			if not contact.is_empty() and contact.collider == locked_wall:
				actor.session.hit_wall(locked_wall, float(actor.spec.wall) * actor.wall_factor() * difficulty)
				if not is_instance_valid(locked_wall) or actor.session.wall_health(locked_wall) <= 0.0:
					route.clear_plan()
					sense_left = 0.0
					state = State.CHASE
					actor.attack = 0.46
				actor.session.audio.play_at("stone" if actor.type == "brute" and not actor.biting() else "hit", contact.position, 0.74)
				actor.session.fx.burst(contact.position + contact.normal * 0.05, Color("#ae928c"), 0.53)
		Action.SPIT:
			_spit(difficulty)
		Action.SCREAM:
			actor.screamed = true
			actor.session.audio.play_at("scream", _eyes(), 1.19)
			actor.director.call_pack(actor.global_position, attack_point)
		Action.CHARGE:
			charge_left = 0.80 if profile.has("rush_range") else 0.58
		Action.MEND:
			mend_left = 7.5
			if is_instance_valid(patient) and patient.spawn_serial == patient_serial and actor.director.can_mend(actor,patient,float(profile.mend_range)):
				patient.hp = minf(patient.max_health(),patient.hp+24.0)
				actor.director.infected_effect("mend",patient.global_position + Vector3.UP * patient.body_height()*0.55)
			patient = null
	action = Action.NONE
	if charge_left <= 0.0:
		locked_target = null
	locked_wall = null

func _within_melee(player: WastelandSurvivor, direction: Vector3, reach_m: float) -> bool:
	if not _alive(player):
		return false
	var offset := player.global_position - actor.global_position
	var flat := WastelandCreatureRoute.planar(offset)
	if flat.length_squared() > reach_m * reach_m or absf(offset.y) > clampf(actor.body_height() * 0.66, 0.49, 1.25):
		return false
	if flat.length_squared() > 0.13 and direction.dot(flat.normalized()) < 0.56:
		return false
	var chest := actor.global_position + Vector3.UP * minf(actor.body_height()*0.57,1.08)
	var origin := chest if animal else actor.melee_origin()
	if chest.distance_squared_to(origin)>0.0025 and not _clear_to(player,chest,origin):
		return false
	return _clear_to(player,origin,_target_point(player,0.22 if actor.type == "crawler" or actor.low_crawl() else 0.55))

func _spit(difficulty: float) -> void:
	var jaw := actor.gland.global_position
	var at := jaw + attack_heading * 0.10
	if not route.ray(_eyes(), at).is_empty():
		return
	var departure := attack_point - at
	var flight := clampf(departure.length() / FLIGHT_SPEED, 0.23, 1.30)
	var launch := departure / flight + Vector3.UP * (0.5 * WastelandEffects.ACID_GRAVITY * flight)
	actor.session.fx.projectile(at, launch, actor, "acid", float(actor.spec.hit) * difficulty)
	actor.session.fx.burst(at, Color("#a8ba75"), 0.46)
	actor.session.audio.play_at("splash", at, 0.68)

func _charge(delta: float) -> Vector3:
	charge_left = maxf(0.0, charge_left - delta)
	desired_facing = attack_heading
	if _within_melee(locked_target, attack_heading, reach):
		var front := actor.melee_origin()
		var contact: Vector3 = locked_target.surface_toward(front,0.28 if actor.type == "boar" else 0.5)
		locked_target.damage(float(actor.spec.hit) * actor.melee_factor() * float(actor.session.world_settings.difficulty) * 1.30, "boar" if actor.type == "boar" else "claw",front,contact)
		locked_target = null
	if actor.is_on_wall() or charge_left == 0.0:
		charge_left = 0.0
		locked_target = null
		sense_left = 0.0
		return Vector3.ZERO
	return attack_heading
