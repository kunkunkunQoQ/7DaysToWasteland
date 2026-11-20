class_name WastelandSurvivor
extends CharacterBody3D

const Profiles := preload("res://game/core/survivor_profiles.gd")
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

func configure(owner_session: Node3D, save: Dictionary, initial: Vector3, local_camera: bool = true, remote_profile: String = "ranger", initial_bag: WastelandBag = null) -> void:
	session = owner_session
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
	camera.add_child(headlamp)
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
	body_temp = float(save.get("temp", body_temp))
	bleed = float(save.get("bleed", 0.0))
	infection = float(save.get("infection", 0.0))
	fracture = float(save.get("fracture", 0.0))
	sprain = float(save.get("sprain", 0.0))
	wet = clampf(float(save.get("wet", 0.0)), 0.0, 1.0)
	var inventory: WastelandBag = initial_bag if initial_bag != null else session.bag
	flashlight = bool(save.get("lamp", false)) and inventory.count("torch") > 0
	torch_in_hand = bool(save.get("torch_in_hand", false))
	eyes.rotation.x = pitch
	injury.reset(health)

func snapshot() -> Dictionary:
	return {"point": global_position, "yaw": rotation.y, "pitch": pitch, "health": health,
		"profile":profile, "limits":Vector3(max_health(),max_stamina(),max_breath()),
		"crouch":crouch, "body_height":stand_shape.height, "eye_height":eyes.position.y, "torch_in_hand":torch_in_hand,
		"provisions":Vector2(warm_drink_left,ration_left), "stamina": stamina, "hunger": hunger, "hydration": hydration, "temp": body_temp,
		"bleed": bleed, "infection": infection, "fracture": fracture, "sprain": sprain, "wet": wet, "wound_rng": wound_rng.state,
		"lamp": flashlight, "breath": breath}

func reset_water_state() -> void:
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
	if camera.fov<74.0:
		relative *= tan(deg_to_rad(camera.fov*0.5))/tan(deg_to_rad(38.0))
	rotation.y = wrapf(rotation.y - relative.x, -PI, PI)
	pitch = clampf(pitch - relative.y, -1.49, 1.49)
	eyes.rotation.x = pitch

func update_optics(delta: float, aiming: bool) -> void:
	if camera.current:
		camera.fov = move_toward(camera.fov,29.2 if aiming else 76.0,delta*220.0)
		hand.visible = not aiming

func simulate(delta: float, controls: bool) -> void:
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
		var stick := _stick_look()
		look(stick * Vector2(2.7, 2.16 * invert) * delta)
	var holding: String = session.bag.current()
	update_optics(delta,controls and session.optics_active())
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
	submerged = wet_feet and camera.global_position.y < (0.035 if submerged else -0.065)
	breath = move_toward(breath, 0.0 if submerged else max_breath(), delta * (1.0 if submerged else 3.0))
	_survival(delta)
	session.achievements.sample(self,delta,controls,drive)
	if session.audio.listener == camera:
		update_damage_feedback(delta)
	var secondary:String=session.bag.gear.get("offhand","")
	if not session.remote_actor:
		hand.set_offhand(secondary,bool(get("guarding")),flashlight and not submerged)
		preload("res://game/art/offhand_art.gd").sync_world_light(camera,secondary,flashlight and not submerged)
	hand.swimming = swimming
	hand.search_ratio = session.loot_ratio if controls else 0.0
	hand.animate(delta, minf(3.0, Vector2(velocity.x, velocity.z).length() * 0.44), crouch,
		session.atmosphere.sun_strength + (0.35 if headlamp.visible else 0.0), hit_stop)
	hit_stop=maxf(0.0,hit_stop-delta)

func _walk(delta: float, drive: Vector2, controls: bool) -> void:
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
	var duck: bool = controls and session.action_held("crouch") and not swimming
	if duck and session.action_pressed("crouch"): session.achievements.crouched(self,session.bag.current())
	if not duck and not _can_grow_to(1.78 * stature()):
		duck = true
	crouch = move_toward(crouch, 1.0 if duck else 0.0, delta * 6.5)
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
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 31.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 31.0)
	var grounded := is_on_floor()
	if swimming or not controls:
		jump_buffer = 0.0
		ledge_grace = 0.0
	else:
		jump_buffer = 0.12 if session.action_pressed("jump") else maxf(0.0, jump_buffer - delta)
		ledge_grace = 0.09 if grounded else maxf(0.0, ledge_grace - delta)
	if swimming:
		var surfacing := 1 if controls and session.action_held("jump") else 0
		var diving := 1 if controls and session.action_held("crouch") else 0
		var swim_y := clampf((-1.25 * stature() - global_position.y) * 3.0, -1.5, 1.05)
		if diving > surfacing:
			swim_y = -2.45
		elif surfacing > diving:
			swim_y = clampf((-1.06 * stature() - global_position.y) * 4.2, -1.5, 3.30)
		velocity.y = move_toward(velocity.y, swim_y, delta * 9.6)
	elif jump_buffer > 0.0 and ledge_grace > 0.0 and stamina >= 10.0:
		jump_buffer = 0.0
		ledge_grace = 0.0
		velocity.y = 5.7 if fracture <= 0.0 else 4.0
		stamina -= 8.0
	else:
		velocity.y -= 18.0 * delta
	if not session.stream.at_surface(global_position + Vector3(velocity.x,0,velocity.z) * delta):
		velocity.x = 0.0
		velocity.z = 0.0
	var speed_before_landing := velocity.y
	move_and_slide()
	if grounded and is_on_wall() and controls and not swimming and not submerged and not duck and crouch<0.10 and speed_before_landing<=0.0 and drive.y< -0.18:
		var enabled:bool=session.network.current_input().get("auto_step",true) if session.remote_actor else session.options.display.get("auto_step",true)
		if enabled: _step_ledge(direction.normalized())
	if is_on_floor() and not grounded and not swimming and speed_before_landing < -3.5:
		hand.landing = clampf((-speed_before_landing - 3.5) / 9.0, 0.0, 1.0) * float(session.options.display.impact_motion)
	if is_on_floor() and speed_before_landing < -11.8:
		damage((absf(speed_before_landing) - 10.5) * 4.5, "fall")
	if global_position.y < -42.0 and velocity.y < -12.0 and session.stream.below_terrain(global_position):
		damage(200.0, "fall")
	if sprinting:
		stamina = maxf(0.0, stamina - delta * 13.6 * (1.0-session.bag.gear_bonus("run_saving")))
	elif not guarding:
		stamina = minf(max_stamina(), stamina + delta * recovery_rate() * (0.4 if swimming else 1.0))
	var distance := Vector2(velocity.x, velocity.z).length()
	if distance > 0.3 and (is_on_floor() or wet_feet):
		foot_distance += delta * distance
		if foot_distance >= (2.45 if sprinting else 1.72):
			foot_distance -= 2.45 if sprinting else 1.72
			_footstep()

func _step_ledge(direction:Vector3)->bool:
	# Only climb a face actually hit this tick. A walkable slope needs no correction.
	var face:KinematicCollision3D
	for i in get_slide_collision_count():
		var contact:=get_slide_collision(i)
		if contact.get_normal().dot(direction)< -0.45 and absf(contact.get_normal().y)<0.48:
			face=contact
			break
	if not face: return false
	var solid:=face.get_collider() as StaticBody3D
	if not solid: return false
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
	global_position=center+lift
	velocity.y=0.0
	apply_floor_snap()
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
	if vehicle.record.get("needs_repair", false):
		return
	mount_vehicle = vehicle
	sprinting = false
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

func bark_scrape() -> void:
	if health<=0: return
	var before:=health
	health=maxf(0.0,health-2.0)
	_report_damage(before,before-health,"bark",Vector3.ZERO,true)
	if health<=0: session.player_died(self)

func damage(amount: float, source: String, origin: Vector3 = Vector3.INF) -> void:
	if amount <= 0.0 or health <= 0.0 or (invulnerable > 0.0 and amount < 100.0):
		return
	if session.player!=self and is_instance_valid(session.network) and session.network.as_survivor(session,self,func():damage(amount,source,origin)):
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
	if health <= 0.0:
		session.player_died(self)

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
	camera.rotation.z = (injury.roll()+pulse) * motion
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

func consume(id: String) -> void:
	var item: Dictionary = session.catalog.items.get(id, {})
	var kind: String = item.get("kind", "")
	if kind not in ["food","med"] or not session.bag.spend({id: 1}):
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
	session.audio.play_at("search", camera.global_position + Vector3.DOWN * 0.42, 0.49, false)
	var effect := " · 保暖 %d 秒" % ceili(warm_drink_left) if item.has("warm_seconds") else " · 耐力恢复提升 %d 秒" % ceili(ration_left) if item.has("energy_seconds") else ""
	session.notify("已使用 " + session.catalog.title(id) + effect, 1.9)
