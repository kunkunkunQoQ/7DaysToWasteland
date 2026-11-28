class_name WastelandSurvivor
extends CharacterBody3D

const Profiles := preload("res://game/core/survivor_profiles.gd")
const SurvivorBody := preload("res://game/actors/survivor_ragdoll.gd")
const ImpactResistance := preload("res://game/actors/impact_resistance.gd")
enum RagdollMode { UPRIGHT, KNOCKED_DOWN, DEAD }
signal ragdoll_changed(mode: int, impact: Vector3)
signal ragdoll_struck(impact: Vector3, at: Vector3, bone: StringName)

var ragdoll_mode := RagdollMode.UPRIGHT
var ragdoll_impact := Vector3.ZERO
var ragdoll_body: SurvivorBody
var live_avatar: WastelandPartyAvatar
var live_swing := 0
var live_shot := 0
var live_last_position := Vector3.INF
var knockdown_left := 0.0
var impact_load := Vector2.ZERO
var fall_uncontrolled := false
var fall_apex := -INF
var fall_last := Vector3.INF
var air_momentum := Vector3.INF
var sole_normal := Vector3.ZERO
var step_point := Vector3.INF
var step_direction := Vector3.ZERO
var step_wait := 0.0
var owns_view := false
var carried_bag: WastelandBag
var camera_focus := Vector3.ZERO
var camera_outward := Vector3.BACK
const SHOULDER_OFFSET := Vector3(0.62, -0.12, 3.15)
const CAMERA_CLEARANCE := 0.19
var third_person := false
var shoulder_fraction := 0.0
var camera_probe := PhysicsShapeQueryParameters3D.new()
var profile := "ranger"
var session: Node3D
var guarding:=false
var guard_exhausted:=false
var offhand_cooldown:=0.0
var camera := Camera3D.new()
var eyes := Node3D.new()
var hand := WastelandHands.new()
var headlamp := SpotLight3D.new()
var stand_shape := CapsuleShape3D.new()
var clearance_shape := CapsuleShape3D.new()
var capsule: CollisionShape3D
var health := 100.0
var stamina := 100.0
var hunger := 91.0
var hydration := 89.0
var body_temp := 36.7
var ambient := 16.0
var bleed := 0.0
var infection := 0.0
var fracture := 0.0
var sprain := 0.0
var wound_rng := RandomNumberGenerator.new()
var warm_drink_left := 0.0
var ration_left := 0.0
var wet := 0.0
var wet_feet := false
const MAX_BREATH := 18.0
var breath := MAX_BREATH
var submerged := false
var swimming := false
var flashlight := false
var torch_in_hand := false
var pitch := -0.071
var crouch := 0.0
var sprinting := false
var sprint_exhausted := false
var jump_buffer := 0.0
var ledge_grace := 0.0
var invulnerable := 0.0
var hit_stop := 0.0
var confirmed_hit:=0
var confirmed_head:=false
var confirmed_melee:=false
var recent_noise:=0.0
var noise_until:=0.0
var impact_kick:=0.0
var confirmation_left:=0.0
var injury := WastelandDamageFeedback.new()
var pending_drain := 0.0
var drain_time := 0.0
var foot_distance := 0.0
var survival_tick := 0.0
var mount_vehicle: Node3D
var moving := Vector2.ZERO
var challenge_interval := 0.0
var challenge_position := Vector3.INF
var challenge_streaks := {}
var shawl_last_action := ""
var shawl_last_spoken := ""
var shawl_pending := false
var shawl_voice_after_ms := 0
var shawl_sprint_distance := 0.0

func configure(owner_session: Node3D, save: Dictionary, initial: Vector3, local_camera: bool = true, remote_profile: String = "ranger", initial_bag: WastelandBag = null) -> void:
	# Moving platforms already contribute their actual surface motion through the supporting feet.
	platform_floor_layers = 0
	session = owner_session
	owns_view = local_camera
	third_person = local_camera and bool(session.options.display.get("third_person", false))
	var camera_sphere := SphereShape3D.new()
	camera_sphere.radius = CAMERA_CLEARANCE
	camera_probe.shape = camera_sphere
	camera_probe.collision_mask = 1 | 2 | 8
	carried_bag = initial_bag if initial_bag != null else session.bag
	var chosen: String = owner_session.options.appearance if local_camera else remote_profile
	profile = chosen if Profiles.STATS.has(chosen) else "ranger"
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	floor_max_angle = deg_to_rad(51)
	floor_snap_length = 0.32
	stand_shape.radius = 0.31
	clearance_shape.radius = 0.295
	crouch = clampf(float(save.get("crouch", 0.0)), 0.0, 1.0)
	stand_shape.height = minf(float(save.get("body_height", 1.78 if not save.is_empty() else 2.0)), lerpf(1.78,1.21,crouch) * stature())
	capsule = CollisionShape3D.new()
	capsule.shape = stand_shape
	capsule.position.y = stand_shape.height * 0.5
	add_child(capsule)
	add_child(eyes)
	eyes.position.y = minf(lerpf(1.62,1.02,crouch) * stature(), stand_shape.height - 0.09)
	camera.fov = 76.0
	camera.near = 0.065
	camera.far = 380.0 if owner_session.stream.generator.revision>=3 else 227.0
	eyes.add_child(camera)
	if local_camera:
		camera.make_current()
	camera.add_child(hand)
	hand.visible=local_camera
	eyes.add_child(headlamp)
	headlamp.light_color = Color("#ffdfae")
	headlamp.light_energy = 1.36
	headlamp.spot_range = 25.0
	headlamp.spot_angle = 37.0
	headlamp.visible = false
	headlamp.shadow_enabled = false
	global_position = save.get("point", initial)
	rotation.y = float(save.get("yaw", 0.14))
	pitch = float(save.get("pitch", -0.071))
	wound_rng.seed = hash([owner_session.world_settings.seed, initial, local_camera])
	if save.has("wound_rng"):
		wound_rng.state = int(save.wound_rng)
	restore_vitals(save)
	impact_load = save.get("impact_load",Vector2.ZERO)
	body_temp = float(save.get("temp", body_temp))
	bleed = float(save.get("bleed", 0.0))
	infection = float(save.get("infection", 0.0))
	fracture = float(save.get("fracture", 0.0))
	sprain = float(save.get("sprain", 0.0))
	wet = clampf(float(save.get("wet", 0.0)), 0.0, 1.0)
	flashlight = bool(save.get("lamp", false)) and carried_bag.count("torch") > 0
	torch_in_hand = bool(save.get("torch_in_hand", false))
	eyes.rotation.x = pitch
	injury.reset(health)

func snapshot() -> Dictionary:
	return {"point": global_position, "yaw": rotation.y, "pitch": pitch, "health": health,
		"profile":profile, "limits":Vector3(max_health(),max_stamina(),max_breath()),
		"crouch":crouch, "body_height":stand_shape.height, "eye_height":eyes.position.y, "torch_in_hand":torch_in_hand,
		"provisions":Vector2(warm_drink_left,ration_left), "stamina": stamina, "hunger": hunger, "hydration": hydration, "temp": body_temp,
		"bleed": bleed, "infection": infection, "fracture": fracture, "sprain": sprain, "wet": wet, "wound_rng": wound_rng.state,
		"lamp": flashlight, "breath": breath, "impact_load":impact_load}

func reset_water_state() -> void:
	_stop_ground_drive()
	air_momentum = Vector3.INF
	sole_normal = Vector3.ZERO
	swimming = false
	wet_feet = false
	submerged = false
	breath = max_breath()
	floor_snap_length = 0.32
	jump_buffer = 0.0
	ledge_grace = 0.0
	hand.landing = 0.0
	hand.swimming = false
	hand.swim_blend = 0.0

func max_health() -> float:
	return float(Profiles.STATS[profile].health)

func max_stamina() -> float:
	var trained := float(Profiles.STATS[profile].stamina) + float(session.progress.rank("fitness")) * 12.0
	return trained * lerpf(0.4, 1.0, clampf(hunger / 30.0, 0.0, 1.0))

func recovery_rate() -> float:
	var trained := 10.8 + float(session.progress.rank("fitness")) * 1.6 + (4.0 if ration_left > 0.0 else 0.0)
	return trained * lerpf(0.25, 1.0, clampf(hydration / 30.0, 0.0, 1.0))

func max_breath() -> float:
	return float(Profiles.STATS[profile].breath)

func stature() -> float:
	return float(WastelandPartyAvatar.STATURE.get(profile, 1.0))

func restore_vitals(saved: Dictionary) -> void:
	hunger = clampf(float(saved.get("hunger", hunger)), 0.0, 100.0)
	hydration = clampf(float(saved.get("hydration", hydration)), 0.0, 100.0)
	var provisions: Vector2=saved.get("provisions",Vector2.ZERO)
	warm_drink_left=maxf(0.0,provisions.x)
	ration_left=maxf(0.0,provisions.y)
	# Saves predating character selection used 100 health, 100 base stamina and 18 seconds of air.
	var previous: Vector3 = saved.get("limits", Vector3(100, 100 + session.progress.rank("fitness") * 12, 18))
	health = clampf(float(saved.get("health", previous.x)) / maxf(previous.x, 1.0), 0.0, 1.0) * max_health()
	stamina = clampf(float(saved.get("stamina", previous.y)) / maxf(previous.y, 1.0), 0.0, 1.0) * max_stamina()
	breath = clampf(float(saved.get("breath", previous.z)) / maxf(previous.z, 1.0), 0.0, 1.0) * max_breath()

func set_profile(id: String) -> void:
	if id == profile or not Profiles.STATS.has(id):
		return
	var old := Vector3(max_health(), max_stamina(), max_breath())
	profile = id
	health = clampf(health / old.x, 0.0, 1.0) * max_health()
	stamina = clampf(stamina / old.y, 0.0, 1.0) * max_stamina()
	breath = clampf(breath / old.z, 0.0, 1.0) * max_breath()
	injury.trace_health = clampf(injury.trace_health / old.x, 0.0, 1.0) * max_health()
	if is_knocked_down(): return
	if not is_instance_valid(mount_vehicle) and not _can_grow_to(lerpf(1.78,1.21,crouch) * stature()):
		crouch = 1.0
	_apply_posture(is_instance_valid(mount_vehicle))

func _can_grow_to(height: float) -> bool:
	if height <= stand_shape.height + 0.001:
		return true
	var extra := height - stand_shape.height
	clearance_shape.height = 2.0 * clearance_shape.radius + extra
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = clearance_shape
	probe.transform.origin = global_position + Vector3.UP * (height - clearance_shape.height * 0.5)
	probe.collision_mask = 1 | 2 | 4 | 8
	probe.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty()

func _apply_posture(seated: bool) -> void:
	var scale_y := stature()
	var height := lerpf(1.78, 1.21, crouch) * scale_y
	if seated or _can_grow_to(height):
		stand_shape.height = height
		capsule.position.y = height * 0.5
	eyes.position.y = minf((1.45 if seated else lerpf(1.62,1.02,crouch)) * scale_y, stand_shape.height - 0.09)

func toggle_lamp() -> void:
	torch_in_hand = session.bag.current() == "torch" or session.bag.gear.get("offhand","")=="torch"
	if session.bag.available_count("torch") == 0:
		flashlight = false
		session.notify("先在随身制作中做一盏提灯")
	else:
		flashlight = not flashlight
	headlamp.visible = flashlight and session.bag.gear.get("offhand","")!="torch"

func sync_lamp(holding: String) -> void:
	if session.bag.available_count("torch") == 0:
		flashlight = false
	elif (holding == "torch" or session.bag.gear.get("offhand","")=="torch") and not torch_in_hand:
		flashlight = true
	torch_in_hand = holding == "torch" or session.bag.gear.get("offhand","")=="torch"
	headlamp.visible = flashlight and session.bag.gear.get("offhand","")!="torch"

func look(relative: Vector2) -> void:
	if is_knocked_down(): return
	if camera.fov<74.0:
		relative *= tan(deg_to_rad(camera.fov*0.5))/tan(deg_to_rad(38.0))
	rotation.y = wrapf(rotation.y - relative.x, -PI, PI)
	pitch = clampf(pitch - relative.y, -1.49, 1.49)
	eyes.rotation.x = pitch

func update_optics(delta: float, aiming: bool) -> void:
	if not is_knocked_down():
		if third_person and not aiming:
			var extension := lerpf(shoulder_fraction, 1.0, 1.0 - exp(-delta * 12.0))
			shoulder_fraction = minf(_clear_shoulder_fraction(), extension)
			camera.position = SHOULDER_OFFSET * shoulder_fraction
		elif shoulder_fraction > 0.0:
			shoulder_fraction = 0.0
			camera.position = Vector3.ZERO
		if owns_view and is_instance_valid(live_avatar):
			live_avatar.set_shadows_only(not _shows_body())
	if camera.current:
		camera.fov = move_toward(camera.fov,29.2 if aiming and not is_knocked_down() else 76.0,delta*220.0)
		hand.visible = not _shows_body() and not aiming and not is_knocked_down()

func _clear_shoulder_fraction() -> float:
	var exclusions: Array[RID] = [get_rid()]
	if is_instance_valid(mount_vehicle): exclusions.append(mount_vehicle.get_rid())
	camera_probe.exclude = exclusions
	camera_probe.transform = Transform3D(Basis.IDENTITY, eyes.global_position)
	camera_probe.motion = eyes.global_basis * SHOULDER_OFFSET
	var space := get_world_3d().direct_space_state
	var limit := space.cast_motion(camera_probe)[0]
	if limit < 1.0: return limit
	# A cast ignores a shape it already overlaps, e.g. a low ceiling grazing the probe at eye level.
	var ray := PhysicsRayQueryParameters3D.create(eyes.global_position, eyes.global_position + camera_probe.motion, camera_probe.collision_mask, exclusions)
	ray.hit_from_inside = true
	var hit := space.intersect_ray(ray)
	if hit.is_empty(): return 1.0
	return maxf(0.0, (eyes.global_position.distance_to(hit.position) - CAMERA_CLEARANCE) / SHOULDER_OFFSET.length())

func _shows_body() -> bool:
	return shoulder_fraction >= 0.20

func read_view_input() -> void:
	if owns_view and InputMap.has_action("toggle_view") and Input.is_action_just_pressed("toggle_view"):
		third_person = not third_person
		session.options.display.third_person = third_person
		session.options.save_options()

func action_origin() -> Vector3:
	return eyes.global_position if third_person else camera.global_position

func sync_view_lantern(secondary: String) -> void:
	var lit := flashlight and not submerged and not is_knocked_down() and not _shows_body()
	preload("res://game/art/offhand_art.gd").sync_world_light(eyes, secondary, lit, true)

func is_knocked_down() -> bool:
	return ragdoll_mode != RagdollMode.UPRIGHT

func set_live_avatar(avatar: WastelandPartyAvatar) -> void:
	live_avatar = avatar
	live_avatar.configure_live_motion(session, owns_view)
	if owns_view: live_avatar.set_shadows_only(not _shows_body())

func update_live_avatar(delta: float) -> void:
	if not owns_view or is_knocked_down(): return
	if not is_instance_valid(live_avatar):
		var avatar := WastelandPartyAvatar.new()
		avatar.show_tag = false
		avatar.apply_outfit(profile)
		set_live_avatar(avatar)
		add_child(avatar)
	var seated := is_instance_valid(mount_vehicle)
	live_avatar.visible = not seated or _shows_body()
	live_avatar.set_seat_vehicle(mount_vehicle)
	if not live_avatar.visible:
		live_avatar.pose(delta,0.0,0.0,false,Vector3.INF,false,Vector3.UP,true)
		return
	live_avatar.apply_outfit(profile)
	live_avatar.wear_loadout(carried_bag.gear)
	var held := carried_bag.current()
	live_avatar.aim_pitch = pitch
	live_avatar.set_mainhand(held, int(carried_bag.magazine.get(held, 0)) > 0)
	live_avatar.set_offhand(carried_bag.offhand, guarding, flashlight and not submerged and _shows_body())
	if hand.swing_serial != live_swing:
		live_avatar.act("punch" if held.is_empty() else "tool")
	if hand.shot_serial != live_shot: live_avatar.act("fire")
	live_swing = hand.swing_serial
	live_shot = hand.shot_serial
	if seated:
		live_avatar.pose(delta,0.0,0.0,false,Vector3.INF,false,Vector3.UP,true)
	elif session.replica:
		var motion := Vector3.ZERO
		if live_last_position.is_finite() and delta > 0.0:
			var travel := global_position - live_last_position
			if travel.length_squared() < 2.25: motion = (travel / delta).limit_length(12.0)
		live_avatar.pose_replica(delta, motion, crouch, swimming)
	else:
		pose_ground_motion(delta)
	live_last_position = global_position

func pose_ground_motion(delta: float) -> void:
	var motion := get_real_velocity()
	var normal := get_floor_normal() if is_on_floor() else sole_normal
	var supported := normal.y > 0.0 or (step_point.is_finite() and step_wait > 0.0)
	live_avatar.pose(delta, Vector2(motion.x, motion.z).length(), crouch, swimming, motion,
		supported, normal if normal.y > 0.0 else Vector3.UP)

func animate_hands(delta: float, light: float, pace: float) -> void:
	var phase := -1.0
	if is_instance_valid(live_avatar) and live_avatar.visible and not swimming and live_avatar.gait.last_root.is_finite():
		var gait := live_avatar.gait
		phase = gait.phase
		pace = minf(3.0, gait.speed * 0.44) * gait.swing_strength
	hand.animate(delta, pace, crouch, light, hit_stop, phase)
	if not owns_view: return
	var right := Vector3.ZERO
	var left := Vector3.ZERO
	if hand.visible and is_instance_valid(live_avatar) and live_avatar.visible and is_instance_valid(live_avatar.active_motion):
		var rig := live_avatar.active_motion
		var to_view := camera.global_basis.orthonormalized().transposed()
		right = to_view * rig.hand_contact_offset(&"hand_r")
		left = to_view * rig.hand_contact_offset(&"hand_l")
	hand.apply_hand_contacts(right, left, delta)

func sync_part_hit(impact: Vector3, at: Vector3, bone: StringName = &"") -> void:
	if is_instance_valid(ragdoll_body):
		ragdoll_body.push(impact, at, bone)
	elif is_instance_valid(live_avatar):
		live_avatar.push_part(impact, at, bone)

func _push_part(impact: Vector3, at: Vector3, bone: StringName = &"") -> void:
	sync_part_hit(impact, at, bone)
	ragdoll_struck.emit(impact, at, bone)

func surface_toward(origin: Vector3, height_ratio: float) -> Vector3:
	var target := global_position + Vector3.UP * (stand_shape.height * clampf(height_ratio, 0.0, 1.0))
	if not origin.is_finite() or origin.distance_squared_to(target) < 0.0001: return target
	var ray := PhysicsRayQueryParameters3D.create(origin, target, 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider == self: return hit.position
	return target + target.direction_to(origin) * minf(stand_shape.radius, target.distance_to(origin))

func begin_death_ragdoll(impact := Vector3.ZERO, at := Vector3.INF, bone: StringName = &"") -> void:
	if ragdoll_mode == RagdollMode.DEAD: return
	_set_ragdoll(RagdollMode.DEAD, impact, {"impact_at":at, "impact_bone":bone})
	ragdoll_changed.emit(ragdoll_mode, impact)

func reset_ragdoll() -> void:
	if not is_knocked_down(): return
	_set_ragdoll(RagdollMode.UPRIGHT, Vector3.ZERO)
	ragdoll_changed.emit(ragdoll_mode, Vector3.ZERO)

func sync_ragdoll(mode: int, impact: Vector3, appearance: Dictionary = {}) -> void:
	if mode >= RagdollMode.UPRIGHT and mode <= RagdollMode.DEAD and mode != ragdoll_mode:
		_set_ragdoll(mode, impact, appearance)
		if mode == RagdollMode.KNOCKED_DOWN and owns_view: session.notify("被击倒了，正在起身", 1.5)

func _set_ragdoll(mode: int, impact: Vector3, appearance: Dictionary = {}) -> void:
	impact_load = Vector2.ZERO
	_stop_ground_drive()
	live_last_position = Vector3.INF
	fall_last = Vector3.INF
	air_momentum = Vector3.INF
	sole_normal = Vector3.ZERO
	if mode != RagdollMode.KNOCKED_DOWN:
		fall_uncontrolled = false
		if is_instance_valid(ragdoll_body): ragdoll_body.physics.watch_landing(false)
	if mode == RagdollMode.UPRIGHT:
		if is_instance_valid(ragdoll_body) and ragdoll_mode == RagdollMode.KNOCKED_DOWN:
			if is_instance_valid(live_avatar):
				ragdoll_body.recover_into(live_avatar)
			else: ragdoll_body.dismiss()
		ragdoll_body = null
		collision_layer = 4
		collision_mask = 1 | 2 | 8
		stand_shape.height = lerpf(1.78, 1.21, crouch) * stature()
		_apply_posture(false)
		if owns_view:
			camera.top_level = false
			camera.transform = Transform3D.IDENTITY
			shoulder_fraction = 0.0
			hand.visible = not third_person
		knockdown_left = 0.0
	else:
		var contact: Vector3 = appearance.get("impact_at", Vector3.INF)
		var bone: StringName = appearance.get("impact_bone", &"")
		if is_instance_valid(mount_vehicle): dismount(true)
		if not is_instance_valid(ragdoll_body):
			var held: String = appearance.get("held", carried_bag.current())
			ragdoll_body = SurvivorBody.spawn(session, global_transform, appearance.get("profile", profile),
				appearance.get("gear", carried_bag.gear), held, appearance.get("offhand", carried_bag.offhand),
				appearance.get("loaded", int(carried_bag.magazine.get(held, 0)) > 0),
				appearance.get("crouch", crouch), appearance.get("swim", swimming), appearance.get("velocity", velocity),
				impact, contact, bone, live_avatar)
			if is_instance_valid(ragdoll_body) and appearance.get("falling",false):
				ragdoll_body.appearance.falling = true
				ragdoll_body.physics.set_motion(appearance.get("velocity",velocity))
		elif impact.length_squared() > 0.0:
			ragdoll_body.push(impact, contact, bone)
		if ragdoll_mode == RagdollMode.UPRIGHT and owns_view:
			camera_focus = global_position + Vector3.UP * stature()
			camera_outward = (global_basis.z + global_basis.x * 0.96).normalized()
			camera.top_level = true
		if mode == RagdollMode.DEAD and is_instance_valid(ragdoll_body):
			ragdoll_body.become_corpse()
		# The small target follows the fallen torso. World contacts belong to the articulated rig.
		collision_layer = 4 if mode == RagdollMode.KNOCKED_DOWN else 0
		collision_mask = 0
		stand_shape.height = stand_shape.radius * 2.0
		capsule.position.y = stand_shape.radius
		velocity = Vector3.ZERO
		moving = Vector2.ZERO
		sprinting = false
		guarding = false
		jump_buffer = 0.0
		ledge_grace = 0.0
		foot_distance = 0.0
		hand.hide()
		headlamp.hide()
	ragdoll_mode = mode as RagdollMode
	if is_instance_valid(live_avatar): live_avatar.visible = mode == RagdollMode.UPRIGHT and not is_instance_valid(mount_vehicle)
	ragdoll_impact = impact
	if mode != RagdollMode.UPRIGHT: update_ragdoll_camera(0.0)

func _simulate_knockdown(delta: float) -> void:
	invulnerable = maxf(0.0, invulnerable - delta)
	if is_instance_valid(ragdoll_body):
		global_position = ragdoll_body.center() - Vector3.UP * stand_shape.radius
	wet_feet = session.stream.water_at(global_position) and global_position.y < 0.12
	submerged = wet_feet and global_position.y + stand_shape.height * 0.85 < -0.065
	breath = move_toward(breath, 0.0 if submerged else max_breath(), delta * (1.0 if submerged else 3.0))
	_survival(delta)
	if owns_view: update_damage_feedback(delta)
	if ragdoll_mode != RagdollMode.KNOCKED_DOWN: return
	if fall_uncontrolled:
		if wet_feet and global_position.y < -0.68 and session.stream.ground_at(global_position) < -1.12:
			swimming = true
			reset_ragdoll()
		elif global_position.y < -42.0 and session.stream.below_terrain(global_position):
			damage(200.0, "fall")
		return
	knockdown_left -= delta
	if knockdown_left > 0.0: return
	# If the body slid under a low structure, wait for space to get up.
	knockdown_left = 0.18
	var space := get_world_3d().direct_space_state
	var center := global_position + Vector3.UP * stand_shape.radius
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = clearance_shape
	probe.collision_mask = 1 | 2 | 4 | 8
	probe.exclude = [get_rid()]
	for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT * 0.45, Vector3.LEFT * 0.45, Vector3.BACK * 0.45, Vector3.FORWARD * 0.45]:
		var point := center + offset
		if offset != Vector3.ZERO and not space.intersect_ray(PhysicsRayQueryParameters3D.create(center, point, 1 | 2 | 8)).is_empty(): continue
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.12, point + Vector3.DOWN * 1.1, 1 | 2 | 8))
		var floor_point: Vector3
		if floor_hit.is_empty():
			if not session.stream.water_at(point) or point.y > 0.4: continue
			floor_point = Vector3(point.x, maxf(-1.25 * stature(), session.stream.ground_at(point) + 0.06), point.z)
		else:
			if floor_hit.normal.y < 0.48: continue
			var lift := stand_shape.radius * (1.0 / float(floor_hit.normal.y) - 1.0)
			floor_point = floor_hit.position + Vector3.UP * (0.06 + lift)
		for duck: float in [0.0, 1.0]:
			var height := lerpf(1.78, 1.21, duck) * stature()
			clearance_shape.height = height
			probe.transform.origin = floor_point + Vector3.UP * (height * 0.5)
			if not space.intersect_shape(probe, 1).is_empty(): continue
			global_position = floor_point
			crouch = duck
			reset_ragdoll()
			return

func update_ragdoll_camera(delta: float) -> void:
	if not is_knocked_down() or not owns_view: return
	if is_instance_valid(ragdoll_body):
		var target := ragdoll_body.center() + Vector3.UP * 0.16
		camera_focus = camera_focus.lerp(target, 1.0 - exp(-delta * 12.0)) if delta > 0.0 else target
	var eye := camera_focus + camera_outward * 2.55 + Vector3.UP * 1.12
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera_focus, eye, 1 | 2 | 8))
	if not wall.is_empty(): eye = wall.position + wall.normal * 0.10
	if eye.distance_squared_to(camera_focus) > 0.0025:
		camera.global_position = eye
		camera.look_at(camera_focus)
	camera.fov = 76.0
	hand.hide()
	headlamp.hide()
	sync_view_lantern("")

func _exit_tree() -> void:
	if ragdoll_mode == RagdollMode.KNOCKED_DOWN and is_instance_valid(ragdoll_body):
		ragdoll_body.dismiss()

func simulate(delta: float, controls: bool) -> void:
	if shawl_pending: session.tick_shawl(self)
	if is_knocked_down():
		if ragdoll_mode == RagdollMode.KNOCKED_DOWN: _simulate_knockdown(delta)
		update_ragdoll_camera(delta)
		return
	offhand_cooldown=maxf(0.0,offhand_cooldown-delta)
	var raised:bool=controls and session.bag.is_shield(session.bag.offhand) and ((InputMap.has_action("offhand_use") and session.action_held("offhand_use")) or (session.action_held("alternate") and session.alternate_uses_offhand()))
	if not raised: guard_exhausted=false
	guarding=raised and not guard_exhausted and stamina>=3.0 and health>0.0
	if guarding:
		stamina=maxf(0.0,stamina-delta*3.5)
		if stamina<3.0:
			guarding=false
			guard_exhausted=true
	elif raised: guard_exhausted=true
	var invert := -1.0 if session.options.display.invert_y else 1.0
	if controls and not session.remote_actor:
		read_view_input()
		var stick := _stick_look()
		look(stick * Vector2(2.7, 2.16 * invert) * delta)
	var holding: String = session.bag.current()
	hand.set_gloves(session.bag.gear.hands=="work_gloves",session.bag.gear.hands=="meme_claws")
	hand.hold(holding, session.catalog.items.get(holding, {}))
	hand.set_loaded_arrow(int(session.bag.magazine.get(holding,0))>0)
	sync_lamp(holding)
	warm_drink_left=maxf(0.0,warm_drink_left-delta)
	ration_left=maxf(0.0,ration_left-delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	confirmation_left=maxf(0.0,confirmation_left-delta)
	var drive: Vector2 = session.movement_axis() if controls else Vector2.ZERO
	moving = drive
	if mount_vehicle != null:
		_drive(delta, drive, controls)
	else:
		_walk(delta, drive, controls)
	if is_knocked_down(): return
	update_optics(delta,controls and session.optics_active())
	submerged = wet_feet and eyes.global_position.y < (0.035 if submerged else -0.065)
	breath = move_toward(breath, 0.0 if submerged else max_breath(), delta * (1.0 if submerged else 3.0))
	_survival(delta)
	if is_knocked_down(): return
	session.achievements.sample(self,delta,controls,drive)
	if session.audio.listener == camera:
		update_damage_feedback(delta)
	var secondary:String=session.bag.gear.get("offhand","")
	if not session.remote_actor:
		hand.set_offhand(secondary,bool(get("guarding")),flashlight and not submerged)
		sync_view_lantern(secondary)
	hand.swimming = swimming
	hand.search_ratio = session.loot_ratio if controls else 0.0
	animate_hands(delta, session.atmosphere.sun_strength + (0.35 if headlamp.visible else 0.0),
		minf(3.0, Vector2(velocity.x, velocity.z).length() * 0.44))
	update_live_avatar(delta)
	hit_stop=maxf(0.0,hit_stop-delta)

func _walk(delta: float, drive: Vector2, controls: bool) -> void:
	var ground_rig: WastelandActiveRagdoll = live_avatar.active_motion if is_instance_valid(live_avatar) else null
	var has_rig := is_instance_valid(ground_rig) and ground_rig.driving
	var relocated := fall_last.is_finite() and global_position.distance_squared_to(fall_last) > 2.25
	if relocated:
		air_momentum = Vector3.INF
		if has_rig:
			ground_rig.follow_relocation()
			live_avatar.gait.reset()
	sole_normal = Vector3.ZERO
	var sole_velocity := Vector3.ZERO
	if not is_on_floor() and has_rig and not relocated:
		sole_normal = ground_rig.landing_normal()
		if sole_normal.y > 0.0: sole_velocity = ground_rig.landing_surface_velocity()
	var grounded := is_on_floor() or sole_normal.y > 0.0
	if grounded or swimming or not fall_last.is_finite() or relocated:
		fall_apex = global_position.y
	else:
		fall_apex = maxf(fall_apex, global_position.y)
	var ground: float = session.stream.ground_at(global_position)
	wet_feet = global_position.y < 0.12 and ground < 0.08 and session.stream.water_at(global_position)
	var water_depth := maxf(0.0, -ground) if wet_feet else 0.0
	var was_swimming := swimming
	swimming = wet_feet and water_depth > (0.90 if swimming else 1.12) and global_position.y < -0.68
	floor_snap_length = 0.0 if swimming else 0.32
	if swimming and not was_swimming:
		velocity.y = maxf(velocity.y * 0.45, -4.4)
		foot_distance = 0.0
		session.audio.play_at("splash", Vector3(global_position.x, 0.02, global_position.z), 0.60)
		session.record_shawl_action("下水开始游泳了", self)
	elif was_swimming and not swimming:
		session.record_shawl_action("游到了浅水处" if wet_feet else "上岸了", self)
	var duck: bool = controls and session.action_held("crouch") and not swimming
	var entering_crouch := duck and crouch < 0.8
	if duck and session.action_pressed("crouch"): session.achievements.crouched(self,session.bag.current())
	if not duck and not _can_grow_to(1.78 * stature()):
		duck = true
	crouch = move_toward(crouch, 1.0 if duck else 0.0, delta * 6.5)
	if entering_crouch and crouch >= 0.8: session.record_shawl_action("蹲了下来", self)
	_apply_posture(false)
	if stamina <= 9.0:
		sprint_exhausted = true
	elif stamina >= 24.0:
		sprint_exhausted = false
	sprinting = not sprint_exhausted and fracture <= 0.0 and sprain <= 0.0 and controls and session.action_held("sprint") and drive.length_squared() > 0.12 and stamina > 9.0 and crouch < 0.2 and not swimming
	var speed := (7.3 if sprinting else 4.65) * lerpf(1.0, 0.52, crouch)
	if swimming:
		speed = 2.62
	elif wet_feet:
		speed *= lerpf(1.0, 0.60, smoothstep(0.0, 1.1, water_depth))
	if fracture > 0.0:
		speed *= 0.63
	elif sprain > 0.0:
		speed *= 0.82
	if body_temp < 33.5:
		speed *= 0.84
	var direction := transform.basis * Vector3(drive.x, 0, drive.y)
	step_wait = maxf(0.0, step_wait - delta)
	if step_point.is_finite() and (direction.dot(step_direction) < 0.2 or
			step_wait == 0.0 or
			(grounded and global_position.y >= step_point.y - 0.04) or (global_position - step_point).dot(step_direction) > 0.14):
		step_point = Vector3.INF
		if is_instance_valid(live_avatar): live_avatar.gait.stair_contact = Vector3.INF
	var desired := direction * speed
	if not session.stream.at_surface(global_position + desired * delta): desired = Vector3.ZERO
	var airborne := not grounded and not step_point.is_finite() and not swimming
	if swimming:
		_stop_ground_drive()
		velocity.x = move_toward(velocity.x, desired.x, delta * 31.0)
		velocity.z = move_toward(velocity.z, desired.z, delta * 31.0)
	elif airborne:
		_clear_step_targets()
		velocity = Vector3.ZERO
		if has_rig:
			ground_rig.set_airborne_drive()
			velocity = ground_rig.airborne_follow_velocity(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if has_rig and live_avatar.getup == null:
			live_avatar.gait.desired_travel = desired
			var normal := get_floor_normal() if is_on_floor() else sole_normal
			if normal.is_zero_approx(): normal = Vector3.UP
			ground_rig.set_ground_drive(desired, live_avatar.gait.supporting_ankles(), delta, normal)
			var follow := ground_rig.ground_follow_velocity(delta)
			# A rising slope shortens horizontal travel in move_and_slide unless the follow motion is tangent already.
			if grounded and normal.y > 0.48 and not step_point.is_finite():
				velocity.y = -(normal.x * follow.x + normal.z * follow.z) / normal.y
			velocity.x = follow.x
			velocity.z = follow.z
	if swimming or not controls:
		jump_buffer = 0.0
		ledge_grace = 0.0
	else:
		# A sprint stride can spend longer than a walking stride between loaded soles.
		# Carry a toe-off tap to the next real foot contact.
		if session.action_pressed("jump"):
			jump_buffer = 0.22 if sprinting else 0.12
		else:
			jump_buffer = maxf(0.0, jump_buffer - delta)
		ledge_grace = 0.09 if grounded else maxf(0.0, ledge_grace - delta)
	var jump_speed := 5.7 if fracture <= 0.0 else 4.0
	var jump_requested := not swimming and jump_buffer > 0.0 and ledge_grace > 0.0 and stamina >= 10.0
	if swimming:
		var surfacing := 1 if controls and session.action_held("jump") else 0
		var diving := 1 if controls and session.action_held("crouch") else 0
		var swim_y := clampf((-1.25 * stature() - global_position.y) * 3.0, -1.5, 1.05)
		if diving > surfacing:
			swim_y = -2.45
		elif surfacing > diving:
			swim_y = clampf((-1.06 * stature() - global_position.y) * 4.2, -1.5, 3.30)
		velocity.y = move_toward(velocity.y, swim_y, delta * 9.6)
	elif jump_requested and has_rig and live_avatar.getup == null and ground_rig.try_ground_jump(jump_speed):
		jump_buffer = 0.0
		ledge_grace = 0.0
		_clear_step_targets()
		ground_rig.set_airborne_drive()
		airborne = true
		sole_normal = Vector3.ZERO
		# The solver has received the takeoff impulse; its first airborne displacement arrives next tick.
		velocity = ground_rig.motion()
		stamina -= 8.0
		session.record_shawl_action("跳了起来", self)
	elif step_point.is_finite() and ground_rig != null and ground_rig.supports_step(step_point, step_direction):
		# Follow the planted leading foot vertically; the hip supplies all forward travel.
		velocity.y = clampf((step_point.y + 0.035 - global_position.y) / maxf(0.001, delta), 0.0, 3.7)
	elif not airborne:
		velocity.y -= 18.0 * delta
	if not session.stream.at_surface(global_position + Vector3(velocity.x,0,velocity.z) * delta):
		velocity.x = 0.0
		velocity.z = 0.0
	# The swept capsule can also be correcting an offset. Impact energy comes from body momentum.
	var incoming := ground_rig.motion() if airborne and has_rig else velocity
	var speed_before_landing := incoming.y
	var requested_travel := velocity * delta
	move_and_slide()
	if has_rig and not swimming and get_slide_collision_count() > 0:
		ground_rig.limit_blocked_travel((requested_travel - get_position_delta()).slide(Vector3.UP))
	var landed := is_on_floor() or sole_normal.y > 0.0
	fall_last = global_position
	if not swimming and not landed and speed_before_landing <= -9.0 and fall_apex - global_position.y >= 2.6 and not _fall_into_open_water(incoming):
		_release_into_fall(incoming)
		return
	if grounded and not step_point.is_finite() and controls and not swimming and not submerged and not duck and crouch<0.10 and speed_before_landing<=0.0 and drive.y< -0.18:
		var enabled:bool=session.network.current_input().get("auto_step",true) if session.remote_actor else session.options.display.get("auto_step",true)
		var advance := get_position_delta().dot(direction.normalized())
		if enabled and (is_on_wall() or advance < minf(0.025, desired.length() * delta * 0.35)):
			_step_ledge(direction.normalized())
	# A sole may arrest the rig before the follower capsule sweeps into the floor.
	if not swimming and landed and (air_momentum.is_finite() or airborne):
		var impact_motion := air_momentum if air_momentum.is_finite() else incoming
		if airborne and incoming.y < impact_motion.y: impact_motion = incoming
		if impact_motion.y < -3.5:
			hand.landing = clampf((-impact_motion.y - 3.5) / 9.0, 0.0, 1.0) * float(session.options.display.impact_motion)
		var impact_speed := 11.8
		var foot_contact := Vector3.INF
		for index in get_slide_collision_count():
			var hit := get_slide_collision(index)
			var normal := hit.get_normal()
			var closing_speed := -(impact_motion - hit.get_collider_velocity()).dot(normal)
			if normal.y >= 0.48 and closing_speed > impact_speed:
				impact_speed = closing_speed
				foot_contact = hit.get_position()
		if sole_normal.y > 0.0:
			var closing_speed := -(impact_motion - sole_velocity).dot(sole_normal)
			if closing_speed > impact_speed:
				impact_speed = closing_speed
				foot_contact = global_position
		air_momentum = Vector3.INF
		if foot_contact.is_finite():
			damage((impact_speed - 10.5) * 4.5, "fall", Vector3.INF, foot_contact)
			if is_knocked_down(): return
	else:
		air_momentum = incoming if airborne and has_rig and not landed else Vector3.INF
	if global_position.y < -42.0 and velocity.y < -12.0 and session.stream.below_terrain(global_position):
		damage(200.0, "fall")
	if sprinting:
		stamina = maxf(0.0, stamina - delta * 13.6 * (1.0-session.bag.gear_bonus("run_saving")))
		if landed and shawl_sprint_distance < 8.0:
			var stride := get_position_delta()
			shawl_sprint_distance += Vector2(stride.x, stride.z).length()
			if shawl_sprint_distance >= 8.0: session.record_shawl_action("一口气跑了八米", self)
	elif not guarding:
		stamina = minf(max_stamina(), stamina + delta * recovery_rate() * (0.4 if swimming else 1.0))
	if not sprinting: shawl_sprint_distance = 0.0
	var travel := get_real_velocity()
	var distance := Vector2(travel.x, travel.z).length()
	if distance > 0.3 and (landed or wet_feet):
		foot_distance += delta * distance
		if foot_distance >= (2.45 if sprinting else 1.72):
			foot_distance -= 2.45 if sprinting else 1.72
			_footstep()

func _fall_into_open_water(incoming: Vector3) -> bool:
	var height := global_position.y - WastelandTerrainGen.WATER_LEVEL
	if height < 0.0: return session.stream.water_at(global_position) and session.stream.ground_at(global_position) < -1.12
	var time := (incoming.y + sqrt(incoming.y * incoming.y + 36.0 * height)) / 18.0
	var entry := global_position + Vector3(incoming.x,0,incoming.z) * time
	entry.y = WastelandTerrainGen.WATER_LEVEL
	if not session.stream.water_at(entry) or session.stream.ground_at(entry) > entry.y - 1.12: return false
	var ray := PhysicsRayQueryParameters3D.create(global_position,entry + Vector3.UP * 0.02,1|2|8,[get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _release_into_fall(incoming: Vector3) -> void:
	knockdown_left = 1.0
	_set_ragdoll(RagdollMode.KNOCKED_DOWN, Vector3.ZERO, {"falling":true, "velocity":incoming})
	if not is_instance_valid(ragdoll_body): return
	fall_uncontrolled = true
	var rig := ragdoll_body.physics
	if not rig.landing_contact.is_connected(_on_fall_contact): rig.landing_contact.connect(_on_fall_contact)
	rig.watch_landing(true)
	ragdoll_changed.emit(ragdoll_mode,Vector3.ZERO)

func _on_fall_contact(bone: StringName, at: Vector3, _normal: Vector3, speed: float) -> void:
	if not fall_uncontrolled or not is_instance_valid(ragdoll_body) or session.replica: return
	fall_uncontrolled = false
	knockdown_left = clampf(0.46 + speed * 0.052, 0.65, 2.1)
	if speed <= 11.8: return
	damage((speed - 10.5) * 4.5, "fall", Vector3.INF, at, bone)

func _stop_ground_drive() -> void:
	_clear_step_targets()
	if is_instance_valid(live_avatar) and is_instance_valid(live_avatar.active_motion):
		live_avatar.active_motion.stop_ground_drive()

func _clear_step_targets() -> void:
	step_point = Vector3.INF
	step_wait = 0.0
	if not is_instance_valid(live_avatar): return
	live_avatar.gait.desired_travel = Vector3.ZERO
	live_avatar.gait.stair_contact = Vector3.INF

func _step_ledge(direction:Vector3)->bool:
	if direction.is_zero_approx() or not is_instance_valid(live_avatar): return false
	# The physical feet may meet a riser before the capsule reaches it.
	var face: Object
	for i in get_slide_collision_count():
		var contact:=get_slide_collision(i)
		if contact.get_normal().dot(direction)< -0.45 and absf(contact.get_normal().y)<0.48:
			face=contact.get_collider()
			break
	if not face:
		var shin := global_position + Vector3.UP * 0.10
		var probe := PhysicsRayQueryParameters3D.create(shin, shin + direction * (stand_shape.radius + 0.17), 1 | 2, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(probe)
		if hit.is_empty() or hit.normal.dot(direction) > -0.45 or absf(hit.normal.y) >= 0.48: return false
		face = hit.collider
	if not (face is StaticBody3D): return false
	var limit:=0.63
	var foot:=global_position
	var stride:=stand_shape.radius+0.17
	var center:=foot+direction*stride
	var space:=get_world_3d().direct_space_state
	var down:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*(limit+0.06),center+Vector3.UP*0.035,collision_mask,[get_rid()])
	var top:=space.intersect_ray(down)
	if top.is_empty() or top.normal.y<cos(floor_max_angle): return false
	var rise:float=top.position.y-foot.y
	if rise<0.07 or rise>limit: return false
	# The toes must still have floor ahead. This rejects a rail or a thin fence.
	down.from+=direction*0.13
	down.to+=direction*0.13
	var toes:=space.intersect_ray(down)
	if toes.is_empty() or toes.normal.y<cos(floor_max_angle) or absf(toes.position.y-top.position.y)>0.12: return false
	var lift:=Vector3.UP*(rise+0.045)
	if test_move(global_transform,lift): return false
	var raised:=global_transform.translated(lift)
	if test_move(raised,direction*stride): return false
	step_point = top.position
	step_direction = direction
	step_wait = 1.2
	live_avatar.gait.stair_contact = step_point
	live_avatar.gait.stair_direction = direction
	return true

func _footstep() -> void:
	var surface := "step_grass"
	if wet_feet:
		surface = "splash"
		if not submerged:
			session.fx.burst(Vector3(global_position.x,0.06,global_position.z), Color("#9cc7ca"), 0.63)
	else:
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.12, global_position + Vector3.DOWN * 0.55, 3, [get_rid()])
		var down := get_world_3d().direct_space_state.intersect_ray(ray)
		if not down.is_empty() and down.collider.collision_layer == 2:
			var floor_body:Object=down.collider
			var kind:=str(floor_body.get_meta("kind",""))
			if kind=="block":
				var info:Dictionary=session.construction.blocks.get(floor_body.get_meta("block"),{})
				surface="step_wood" if int(info.get("tier",0))<=1 else "step_stone"
			elif kind=="poi_wall":
				var cell:Vector2i=floor_body.get_meta("cell")
				var site:String=session.stream.generator.site_for(cell)
				var material:=str(floor_body.get_meta("salvage_material",preload("res://game/world/structural_salvage.gd")._material(site,floor_body.get_meta("site_id",""))))
				surface="step_wood" if material in ["wood","stick"] else "step_stone"
			else: surface="step_stone"
		elif session.stream.generator.biome(global_position.x, global_position.z) in [2,4]:
			surface = "step_stone"
		elif session.stream.generator.biome(global_position.x,global_position.z)==1:
			surface="step_leaves"
		elif session.stream.generator.region_kind(global_position.x,global_position.z)=="desert":
			surface="step_soil"
	session.audio.play_at(surface, global_position + Vector3.UP * 0.12, (0.86 if sprinting else 0.51) * (1.0-crouch*0.6), false)
	emit_noise(global_position + Vector3.UP * 0.28, footstep_radius())

func emit_noise(at:Vector3,radius:float)->void:
	session.hordes.add_noise(at,radius)
	if session.clock.elapsed>=noise_until or radius>=recent_noise:
		recent_noise=radius
		noise_until=session.clock.elapsed+1.0

func heard_radius()->float:
	return recent_noise if session.clock.elapsed<noise_until else 0.0

func footstep_radius()->float:
	return lerpf(10.0 if sprinting else 5.0,1.5,crouch)

func shot_spread()->float:
	var travel:=clampf(Vector2(velocity.x,velocity.z).length()/7.3,0,1)
	return (0.003+0.011*travel+hand.kick*0.030)*lerpf(1.0,0.62,crouch)

func _stick_look() -> Vector2:
	for device in Input.get_connected_joypads():
		var axes := Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
		if axes.length() > 0.18:
			return axes.normalized() * clampf((axes.length() - 0.18) / 0.82, 0.0, 1.0)
	return Vector2.ZERO

func _drive(delta: float, input: Vector2, controls: bool) -> void:
	velocity = Vector3.ZERO
	crouch = 0.0
	_apply_posture(true)
	var previous_yaw: float = mount_vehicle.rotation.y
	mount_vehicle.drive(delta, input, controls and session.action_held("sprint"))
	rotation.y = wrapf(rotation.y + angle_difference(previous_yaw, mount_vehicle.rotation.y), -PI, PI)
	global_position = mount_vehicle.global_position + Vector3.UP * mount_vehicle.seat_height()
	swimming = false
	wet_feet = false
	stamina = minf(max_stamina(), stamina + delta * recovery_rate())

func ride(vehicle: Node3D) -> void:
	if is_knocked_down() or vehicle.record.get("needs_repair", false):
		return
	_stop_ground_drive()
	air_momentum = Vector3.INF
	sole_normal = Vector3.ZERO
	mount_vehicle = vehicle
	sprinting = false
	shawl_sprint_distance = 0.0
	jump_buffer = 0.0
	ledge_grace = 0.0
	collision_layer = 0
	collision_mask = 0
	rotation.y = vehicle.rotation.y
	vehicle.occupied = true

func dismount(force_exit: bool = false) -> void:
	if not is_instance_valid(mount_vehicle):
		return
	var exit_point: Vector3 = mount_vehicle.global_position + mount_vehicle.global_basis.x * 1.64
	if mount_vehicle.record.type == "boat":
		var best_height := -INF
		var check := PhysicsShapeQueryParameters3D.new()
		check.shape = stand_shape
		check.collision_mask = 1 | 2 | 4 | 8
		check.exclude = [get_rid(), mount_vehicle.get_rid()]
		var found := false
		for offset in [Vector3.RIGHT * 1.68, Vector3.LEFT * 1.68, Vector3.BACK * 2.2, Vector3.FORWARD * 2.2]:
			var candidate: Vector3 = mount_vehicle.to_global(offset)
			if not session.stream.at_surface(candidate):
				continue
			var shore: float = session.stream.ground_at(candidate)
			if shore > mount_vehicle.global_position.y + 1.15 or shore <= best_height:
				continue
			candidate.y = maxf(shore + 0.10, -1.20 * stature()) if session.stream.water_at(candidate) else shore + 0.10
			check.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * stand_shape.height * 0.5)
			if get_world_3d().direct_space_state.intersect_shape(check, 1).is_empty():
				found = true
				exit_point = candidate
				best_height = shore
		if not found and not force_exit:
			session.notify("船边没有落脚处，换个方向靠岸")
			return
	else:
		exit_point.y = maxf(session.stream.ground_at(exit_point) + 0.08, mount_vehicle.global_position.y + 0.14)
	mount_vehicle.occupied = false
	mount_vehicle = null
	global_position = exit_point
	collision_layer = 4
	collision_mask = 1 | 2 | 8

func _survival(delta: float) -> void:
	survival_tick += delta
	if survival_tick < 0.30 or health <= 0.0:
		return
	var dt := survival_tick
	survival_tick = 0.0
	var warm: float = maxf(session.campfire_warmth(global_position), session.stream.mineral_warmth(global_position))
	var protection: float = session.bag.gear_bonus("warmth")+(6.0 if warm_drink_left>0.0 else 0.0)
	var climate: float = session.clock.temperature() - maxf(0.0, global_position.y - 11.0) * 0.14
	var regional_temperature: float = session.stream.generator.temperature_offset(global_position.x,global_position.z)
	climate += regional_temperature - preload("res://game/world/expedition_sites.gd").pass_wind(session.stream.generator,global_position)
	var cave: bool = session.stream.in_nest_cave(global_position)
	if cave:
		climate = minf(7.0, climate - 5.5)
	var from := global_position + Vector3.UP * 1.75
	var roof := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 5.0, 2, [get_rid()])
	var sheltered := cave or not get_world_3d().direct_space_state.intersect_ray(roof).is_empty()
	var soak: float = session.atmosphere.rain_strength * (0.08 if sheltered else 1.0)
	soak *= 1.0-session.bag.gear_bonus("rain_resist")
	var wet_target := 1.0 if swimming else maxf(0.55, soak) if wet_feet else soak
	wet = move_toward(wet, wet_target, dt * (0.32 if swimming else 0.12 if wet_feet or warm > 0.0 else 0.036))
	ambient = climate + warm + (1.5 if sheltered else 0.0)
	var exposure := maxf(0.0, 12.0 - (ambient + protection - wet * 8.0))
	var heat := maxf(0.0,climate-23.0)*(0.25 if sheltered or swimming else 1.0)
	heat *= 1.0-clampf(session.bag.gear_bonus("heat_resist"),0,1)
	var body_goal := 37.0 - exposure * 0.37 - wet * 1.4 + heat * 0.15 + (0.32 if sprinting else 0.0) - infection * 0.006
	body_goal += minf(warm * 0.045, 0.8)
	body_temp = lerpf(body_temp, body_goal, 1.0 - exp(-dt * 0.044))
	var efficiency: float = 1.0 - session.progress.rank("hardiness") * 0.09
	var metabolic := (1.42 if sprinting else 1.0) * (1.14 + exposure * 0.022)
	hunger = maxf(0.0, hunger - dt * 0.072 * metabolic * efficiency)
	hydration = maxf(0.0, hydration - dt * 0.100 * metabolic * efficiency * (1.0+heat*0.065))
	stamina = minf(stamina, max_stamina())
	bleed = maxf(0.0, bleed - dt * 0.045)
	fracture = maxf(0.0, fracture - dt * 0.24)
	sprain = maxf(0.0, sprain - dt)
	infection = minf(100.0, infection + dt * 0.051) if infection > 0.01 else 0.0
	var hazards := {
		"bleed": bleed * 0.034, "infection": maxf(0.0, infection - 53.0) * 0.019,
		"hunger": 1.1 if hunger <= 0.0 else 0.0, "thirst": 1.9 if hydration <= 0.0 else 0.0,
		"cold": maxf(0.0, 32.5 - body_temp) * 1.3,
		"drown": 5.0 if submerged and breath <= 0.0 else 0.0,
	}
	var drain := 0.0
	var dominant := ""
	var largest := 0.0
	for cause in hazards:
		var rate: float = hazards[cause]
		drain += rate
		if rate > largest:
			largest = rate
			dominant = cause
	if drain > 0:
		var loss := minf(health, drain * dt)
		health -= loss
		pending_drain += loss
		drain_time += dt
		if drain_time >= 1.15 or health <= 0.0:
			_report_damage(health + pending_drain, pending_drain, dominant, Vector3.ZERO, false)
			pending_drain = 0.0
			drain_time = 0.0
	else:
		pending_drain = 0.0
		drain_time = 0.0
		if hunger > 75.0 and hydration > 65.0:
			health = minf(max_health(), health + dt * (0.44 if warm > 0.0 else 0.19))
	if health <= 0.0:
		session.player_died(self)

func hurt_hand(amount: int, source: String) -> void:
	if amount <= 0 or health <= 0: return
	var before:=health
	health=maxf(0.0, health - amount)
	_report_damage(before,before-health,source,Vector3.ZERO,true)
	var recoil := global_basis.z * (0.45 + amount * 0.22)
	if health<=0:
		begin_death_ragdoll(recoil, Vector3.INF, &"hand_r")
		session.player_died(self)
	else:
		_push_part(recoil, Vector3.INF, &"hand_r")

func damage(amount: float, source: String, origin := Vector3.INF, hit_at := Vector3.INF, hit_bone: StringName = &"") -> void:
	if amount <= 0.0 or health <= 0.0 or (invulnerable > 0.0 and amount < 100.0 and source != "fall"):
		return
	if session.player!=self and is_instance_valid(session.network) and session.network.as_survivor(session,self,func():damage(amount,source,origin,hit_at,hit_bone)):
		return
	if guarding and session.bag.is_shield(session.bag.offhand) and origin.is_finite() and source in ["heavy","claw","boar","radiation","acid"]:
		var flat:=origin-global_position
		flat.y=0
		var cost:=5.0+minf(14.0,amount*0.32)
		if (-global_basis.z).dot(flat.normalized())>=0.5:
			if stamina>=cost:
				stamina-=cost
				amount*=0.25
				source="shield"
				hit_bone = &"hand_l"
				session.bag.wear_shield()
				if not session.bag.is_shield(session.bag.offhand):
					guarding=false
					session.notify("盾牌已经破损")
				session.audio.play_at("stone",global_position+Vector3.UP,0.72)
			else:
				stamina=0.0
				guarding=false
				guard_exhausted=true
	var protection := clampf(session.bag.gear_bonus("armor"), 0.0, 1.0)
	var before := health
	var loss := minf(health, amount * (1.0 - protection))
	if loss <= 0.0:
		return
	health -= loss
	invulnerable = 0.32
	if source in ["claw", "heavy", "acid", "radiation"]:
		var severity := clampf(loss / 18.0, 0.24, 1.0)
		if source in ["acid", "radiation"] or wound_rng.randf() < 0.34 * severity:
			infection = minf(100.0, infection + (8.5 if source in ["acid","radiation"] else 3.7))
		if wound_rng.randf() < 0.55 * severity:
			bleed = minf(50.0, bleed + 5.6)
		if source == "claw" and fracture <= 0.0 and wound_rng.randf() < 0.12 * severity:
			sprain = maxf(sprain, 55.0)
	if source in ["fall", "heavy", "timber"]:
		if loss >= 24.0 or (loss >= 15.0 and wound_rng.randf() < 0.42):
			fracture = 100.0
			sprain = 0.0
		elif fracture <= 0.0 and loss >= 8.0 and wound_rng.randf() < 0.51:
			sprain = maxf(sprain,65.0)
	var toward := Vector3.ZERO
	if origin.is_finite():
		var offset := origin - global_position
		toward = Vector3(offset.x, 0.0, offset.z).normalized()
	_report_damage(before, loss, source, toward, true)
	if not hit_at.is_finite() and hit_bone == &"":
		match source:
			"fall", "spikes": hit_at = global_position
			"debris": hit_at = surface_toward(origin, 0.94)
			"boar": hit_at = surface_toward(origin, 0.29)
			_: hit_at = surface_toward(origin, 0.56)
	var impact := _impact_velocity(source, loss, toward)
	if source == "fall" and is_knocked_down(): impact = Vector3.ZERO  # Contact has already transferred the impulse.
	if health <= 0.0:
		begin_death_ragdoll(impact, hit_at, hit_bone)
		session.player_died(self)
	elif not is_knocked_down() and _knockdown_hit(source, loss):
		knockdown_left = clampf(1.0 + loss * 0.025, 1.25, 2.1)
		_set_ragdoll(RagdollMode.KNOCKED_DOWN, impact, {"impact_at":hit_at, "impact_bone":hit_bone})
		ragdoll_changed.emit(ragdoll_mode, impact)
		if owns_view: session.notify("被击倒了，正在起身", knockdown_left)
	elif not impact.is_zero_approx():
		_push_part(impact * 0.62, hit_at, hit_bone)

func _knockdown_hit(source: String, loss: float) -> bool:
	var strength := loss
	match source:
		"fall": return loss >= 18.0
		"heavy","rupture","debris","timber": strength *= 1.52
		"boar": strength *= 1.22
		"claw": strength *= 0.78
		_: return false
	var threshold := 29.0*sqrt(max_health()/100.0)
	if fracture>0.0 or stamina<max_stamina()*0.18: threshold *= 0.9
	var active: WastelandActiveRagdoll = live_avatar.active_motion if is_instance_valid(live_avatar) else null
	impact_load = ImpactResistance.after_hit(impact_load,float(session.clock.elapsed),strength,threshold,active)
	return impact_load.x>=1.0

func _impact_velocity(source: String, loss: float, toward: Vector3) -> Vector3:
	var away := -toward if toward.length_squared() > 0.01 else global_basis.z
	if source == "fall":
		return away * 0.65 + Vector3.UP * clampf(loss * 0.12, 1.4, 4.8)
	var force := clampf(loss * 0.105, 0.6, 5.5)
	if source == "debris": return (away * 0.35 + Vector3.DOWN) * force
	return away * force + Vector3.UP * minf(1.9, force * 0.33)

func _report_damage(before: float, loss: float, source: String, bearing: Vector3, direct: bool) -> void:
	if is_instance_valid(session.network) and session.network.send_member_damage(self, before, loss, source, bearing, direct):
		return
	show_damage(before, loss, source, bearing, direct)

func show_damage(before: float, loss: float, source: String, bearing: Vector3, direct: bool) -> void:
	injury.record(before, loss, source, bearing, global_basis.x, direct)
	if direct:
		var clip := "hurt_impact"
		match source:
			"fall", "heavy", "boar", "rupture": clip = "hurt_heavy"
			"acid", "radiation", "residue": clip = "hurt_acid"
		session.audio.play_local(clip, lerpf(0.61, 0.92, clampf(loss / 26.0, 0.0, 1.0)))

func update_damage_feedback(delta: float) -> void:
	injury.advance(delta, health)
	var motion := clampf(float(session.options.display.impact_motion), 0.0, 1.0)
	impact_kick=maxf(0.0,impact_kick-delta)
	var pulse:=sin((0.105-impact_kick)*63.0)*impact_kick*0.14 if impact_kick>0.0 else 0.0
	var tilt := 0.0
	if is_instance_valid(live_avatar) and is_instance_valid(live_avatar.active_motion) and live_avatar.active_motion.balance:
		tilt = clampf(-global_basis.x.dot(live_avatar.active_motion.balance.lean) * 0.27, -0.045, 0.045)
	camera.rotation.z = (injury.roll()+pulse+tilt) * motion
	hand.hurt_dip = maxf(0.0, injury.kick_time / 0.38) * injury.kick_strength * motion
	var critical := max_health() * 0.26
	if health <= 0.0 or health >= critical:
		injury.heart_left = 0.0
		return
	injury.heart_left -= delta
	if injury.heart_left <= 0.0:
		var severity := 1.0 - health / critical
		injury.heart_left = lerpf(1.40, 0.71, severity)
		session.audio.play_local("heartbeat", lerpf(0.29, 0.65, severity))

func clear_damage_feedback() -> void:
	injury.reset(health)
	camera.rotation.z = 0.0
	hand.hurt_dip = 0.0
	pending_drain = 0.0
	drain_time = 0.0

func consume(id: String, source := WastelandBag.ANY) -> void:
	var item: Dictionary = session.catalog.items.get(id, {})
	var kind: String = item.get("kind", "")
	if kind not in ["food","med"] or not session.bag.spend({id: 1},source):
		return
	session.achievements.add("ate_"+id)
	if id=="herbal_tea" and session.stream.generator.region_kind(position.x,position.z)=="alpine":
		session.achievements.add("summit_tea")
	warm_drink_left=maxf(warm_drink_left,float(item.get("warm_seconds",0.0)))
	ration_left=maxf(ration_left,float(item.get("energy_seconds",0.0)))
	hunger = minf(100.0, hunger + float(item.get("food", 0.0)))
	hydration = minf(100.0, hydration + float(item.get("water", 0.0)))
	health = minf(max_health(), health + float(item.get("hp", 0.0)) * (1.0 + session.progress.rank("medicine") * 0.15))
	bleed = clampf(bleed + float(item.get("bleed", 0.0)), 0.0, 100.0)
	infection = clampf(infection + float(item.get("infection", 0.0)), 0.0, 100.0)
	fracture = maxf(0.0, fracture + float(item.get("fracture", 0.0)))
	if float(item.get("fracture", 0.0)) < 0.0:
		sprain = maxf(0.0, sprain + float(item.fracture))
	session.audio.play_at("search", eyes.global_position + Vector3.DOWN * 0.42, 0.49, false)
	session.record_shawl_action("用掉了" + session.catalog.title(id), self)
	var effect := " · 保暖 %d 秒" % ceili(warm_drink_left) if item.has("warm_seconds") else " · 耐力恢复提升 %d 秒" % ceili(ration_left) if item.has("energy_seconds") else ""
	session.notify("已使用 " + session.catalog.title(id) + effect, 1.9)
