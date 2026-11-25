extends "res://tools/verify_field_service.gd"

func run() -> void:
	WastelandSave.root_override = "user://verification/wound-survival-%d" % OS.get_process_id()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var config: Dictionary = app._default_config()
	config.start_id = "seeded"
	app._enter_world(config, {}, 1, false)
	s = app.session
	s.simulation_paused = true
	await physics_frame
	var p := s.player
	var home := p.global_position
	var full := p.max_stamina()
	p.hunger = 15.0
	p.stamina = full
	p._survival(0.3)
	check(p.max_stamina() < full * 0.71 and p.stamina <= p.max_stamina(), "halfway below the hunger threshold compresses usable stamina immediately")
	p.hunger = 90
	p.hydration = 100
	p.stamina = 15
	p._walk(0.20,Vector2.ZERO,false)
	var recovered := p.stamina - 15
	p.hydration = 12
	p.stamina = 15
	p._walk(0.20,Vector2.ZERO,false)
	check(p.stamina - 15 < recovered * 0.6, "dehydration reduces actual walking stamina recovery")
	p.wound_rng.seed = 321
	var exposed := 0
	var bleeding := 0
	var sprained := 0
	for i in 90:
		p.health = p.max_health()
		p.invulnerable = 0
		p.bleed = 0
		p.infection = 0
		p.sprain = 0
		p.damage(17.0, "claw", home + Vector3.BACK)
		exposed += int(p.infection > 0)
		bleeding += int(p.bleed > 0)
		sprained += int(p.sprain > 0)
	check(exposed > 0 and exposed < 90 and bleeding > 0 and bleeding < 90 and sprained > 0 and sprained < 90, "the authority rolls distinct bleeding, infection and sprain outcomes on claw hits")
	check(not p.is_knocked_down(), "ordinary claw hits do not interrupt movement with a knockdown")
	p.bleed = 16
	p.infection = 28
	p.sprain = 35
	p.stamina = full
	var health := p.health
	p._survival(1.0)
	check(p.health < health and p.infection > 28.0, "bleeding drains health while infection progresses")
	Input.action_press("up")
	Input.action_press("sprint")
	p.simulate(0.02, true)
	check(not p.sprinting and p.moving.length() > 0.9, "a sprain blocks real sprint input while permitting walking")
	s.bag.add("splint",2)
	s.ui_command("consume",["splint"])
	p.simulate(0.02,true)
	check(p.sprinting and p.sprain == 0.0, "splint consumption restores sprinting")
	_verify_live_parts(p)
	var platform := WastelandLook.solid(s, Vector3(7,0.2,7), home + Vector3.UP * 4, Color.BROWN)
	p.global_position = platform.position + Vector3.UP * 0.16
	p.invulnerable = 0
	p.damage(26, "heavy", home)
	p.simulate(0.02,true)
	check(p.fracture > 0 and not p.sprinting, "a fractured leg also blocks sprint input")
	var fallen := p.ragdoll_body
	check(is_instance_valid(fallen) and fallen.physics.find_children("*","RigidBody3D",true,false).size() >= 10
		and fallen.physics.find_children("*","Joint3D",true,false).size() >= 9
		and p.moving == Vector2.ZERO and not p.hand.visible and p.camera.top_level,
		"a heavy blow moves the equipped survivor into articulated physics with an external camera")
	Input.action_release("up")
	Input.action_release("sprint")
	for frame in 58:
		await physics_frame
		p.simulate(1.0 / 60.0, true)
	var roof := WastelandLook.solid(s, Vector3(7,0.15,7), platform.position + Vector3.UP * 1.05, Color.BROWN)
	for frame in 75:
		await physics_frame
		p.simulate(1.0 / 60.0, true)
	check(p.is_knocked_down(), "the player cannot get up through a floor with too little headroom")
	roof.position.y = platform.position.y + 1.56
	for frame in 240:
		if not p.is_knocked_down(): break
		await physics_frame
		p.simulate(1.0 / 60.0, true)
	check(not p.is_knocked_down() and p.ragdoll_body == null and not p.camera.top_level
		and p.hand.visible and p.collision_layer == 4 and p.crouch == 1.0 and p.stand_shape.height > 1.0
		and absf(p.global_position.y - platform.position.y) < 0.32,
		"the survivor gets up crouching on the landed platform and regains the first-person controls")
	roof.queue_free()
	platform.queue_free()
	s.bag.add("bandage",1)
	s.bag.add("honey",1)
	s.bag.add("antibiotic",1)
	p.infection = 42
	s.ui_command("consume",["honey"])
	check(p.infection == 30.0, "honey suppresses twelve infection points")
	s.ui_command("consume",["antibiotic"])
	s.ui_command("consume",["bandage"])
	s.ui_command("consume",["splint"])
	check(p.bleed == 0.0 and p.infection == 0.0 and p.fracture == 0.0, "bandage, antibiotic and splint treat their corresponding conditions")
	p.global_position = home + Vector3.UP * 8.0
	s.atmosphere.rain_strength = 0
	var dry := _temperature(false)
	var wading := _temperature(true)
	s.atmosphere.rain_strength = 1
	var rain := _temperature(false)
	check(wading < dry - 0.1 and rain < dry - 0.05, "wading and exposed rainfall both lower core temperature")
	s.atmosphere.rain_strength = 0
	await _natural_sources()
	p.hunger = 13.0
	p.hydration = 18.0
	p.stamina = p.max_stamina() * 0.57
	p.sprain = 40
	p.wet = 0.78
	p.body_temp = 34.6
	p.infection = 26
	p.bleed = 9
	var exact := p.snapshot()
	check(s.save_now(false) == OK, "wounded survivor writes through the regular save entry")
	var saved := WastelandSave.read(1)
	await s.stream.quiesce()
	app._enter_world(saved.settings,saved,1,false)
	s = app.session
	s.simulation_paused = true
	p = s.player
	check(p.sprain == exact.sprain and p.infection == exact.infection and p.bleed == exact.bleed and is_equal_approx(p.wet,exact.wet) and is_equal_approx(p.body_temp,exact.temp) and is_equal_approx(p.stamina,exact.stamina) and p.wound_rng.state == exact.wound_rng, "reloading restores injury, wetness, disease, nutrition-adjusted stamina and wound RNG")
	p.invulnerable = 0.0
	p.damage(20.0, "rupture", p.global_position + Vector3.LEFT)
	var corpse := p.ragdoll_body
	p.damage(500.0, "heavy", p.global_position + Vector3.BACK)
	check(s.death_screen and is_instance_valid(corpse) and p.ragdoll_body == corpse
		and corpse.remaining > 19.0 and p.collision_layer == 0, "a fatal follow-up keeps the already fallen body in place")
	s.respawn()
	check(is_instance_valid(corpse) and p.ragdoll_body == null and p.hand.visible and not p.is_knocked_down(),
		"respawning restores the player while their previous body stays in the world")
	if is_instance_valid(corpse):
		corpse._physics_process(3.0)
		var center := corpse.center()
		var cell := WastelandTerrainGen.chunk_at(Vector2(center.x, center.z))
		s.stream.ensure_landing(center)
		# Match streaming's removal of the chunk from the active surface set.
		var chunk: WastelandChunk = s.stream.active[cell]
		s.stream.active.erase(cell)
		corpse._physics_process(0.1)
		check(corpse.outside_stream and corpse.physics.is_settled(), "unloading the terrain freezes the corpse before it can fall through")
		s.stream.active[cell] = chunk
		corpse._physics_process(0.1)
		check(not corpse.outside_stream and not corpse.physics.is_settled(), "the returning terrain resumes corpse contacts")
		corpse.physics.settle()
		var before_save := corpse.physics.pose_snapshot()
		var remaining := corpse.remaining
		check(s.save_now(false) == OK, "survivor corpse saves through the regular world checkpoint")
		var with_corpse := WastelandSave.read(1)
		await s.stream.quiesce()
		app._enter_world(with_corpse.settings, with_corpse, 1, false)
		s = app.session
		s.simulation_paused = true
		var bodies := s.find_children("*", "", true, false).filter(func(n): return n is WastelandSurvivor.SurvivorBody)
		corpse = bodies[0] if bodies.size() == 1 else null
		check(is_instance_valid(corpse) and absf(corpse.remaining - remaining) < 0.03
			and _same_pose(corpse.physics.pose_snapshot(), before_save),
			"world load resumes the exact retained pose and remaining time after the survivor respawned")
	if is_instance_valid(corpse):
		corpse._physics_process(corpse.remaining - 0.2)
		check(not corpse.is_queued_for_deletion(), "the corpse survives until the end of its retention time")
		corpse._physics_process(0.21)
		await process_frame
		await process_frame
		check(not is_instance_valid(corpse), "the expired corpse and its physics rig are released")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	print("WOUND SURVIVAL failures=",failed)
	quit(1 if failed else 0)

func _same_pose(left: PackedFloat32Array, right: PackedFloat32Array) -> bool:
	if left.size() != right.size() or left.is_empty(): return false
	for i in range(0, left.size(), 7):
		var a := Vector3(left[i], left[i + 1], left[i + 2])
		var b := Vector3(right[i], right[i + 1], right[i + 2])
		var qa := Quaternion(left[i + 3], left[i + 4], left[i + 5], left[i + 6])
		var qb := Quaternion(right[i + 3], right[i + 4], right[i + 5], right[i + 6])
		if a.distance_to(b) > 0.001 or absf(qa.dot(qb)) < 0.99999: return false
	return true

func _verify_live_parts(p: WastelandSurvivor) -> void:
	var avatar := p.live_avatar
	check(is_instance_valid(avatar) and is_instance_valid(avatar.active_motion) and avatar.first_person_body,
		"the upright first-person survivor has a physical world body")
	if not is_instance_valid(avatar) or not is_instance_valid(avatar.active_motion): return
	var rig := avatar.active_motion
	var shapes := rig.find_children("*","RigidBody3D",true,false)
	var meshes := avatar.find_children("*","MeshInstance3D",true,false)
	check(shapes.size() == 15 and not meshes.is_empty() and meshes.all(func(m): return m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		and p.hand.visible and not p.camera.top_level,
		"fifteen driven anatomical bodies cast the local shadow without obscuring the first-person camera")
	var hand := rig.body_for(&"hand_l")
	var foot := rig.body_for(&"ankle_r")
	var hand_before := hand.linear_velocity
	var foot_before := foot.linear_velocity
	p.invulnerable = 0.0
	p.damage(7.0, "claw", hand.global_position + Vector3.LEFT, hand.global_position, &"hand_l")
	check(not p.is_knocked_down() and hand.linear_velocity.distance_to(hand_before) > 0.28 and foot.linear_velocity.is_equal_approx(foot_before),
		"a nonlethal hand strike imparts momentum to the living left hand before the joints transfer it")
	hand_before = hand.linear_velocity
	p.invulnerable = 0.0
	p.damage(7.0, "claw", foot.global_position + Vector3.BACK, foot.global_position, &"ankle_r")
	check(not p.is_knocked_down() and hand.linear_velocity.is_equal_approx(hand_before) and foot.linear_velocity.distance_to(foot_before) > 0.28,
		"a right-foot impact reaches that foot independently of the left hand")

func _temperature(wading: bool) -> float:
	var p := s.player
	p.swimming = false
	p.wet_feet = wading
	p.wet = 0.0
	p.sprinting = false
	p.body_temp = 36.7
	for i in 45: p._survival(0.4)
	return p.body_temp

func _natural_sources() -> void:
	var terrain := s.stream.generator
	var spring: WastelandChunk
	for dz in range(-22,23):
		for dx in range(-22,23):
			var cell := Vector2i(dx,dz)
			if posmod(terrain.seed_at(cell,72821),18) != 0 or posmod(terrain.seed_at(cell,9237),3) != 0: continue
			var center := Vector3(dx * 32 + 16,0,dz * 32 + 16)
			if terrain.site_for(cell) != "" or terrain.ground(center.x,center.z) < 1.0: continue
			s.stream.ensure_landing(center)
			var chunk: WastelandChunk = s.stream.active.get(cell)
			if chunk != null and chunk.spring_at.is_finite():
				spring = chunk
				break
		if spring != null: break
	check(spring != null,"the generated world includes a thermal spring by a deep cave")
	if spring == null: return
	await physics_frame
	var p := s.player
	var deep := spring.position + spring.cave_origin + Vector3.FORWARD * 3.2
	deep.y = s.stream.ground_at(deep) + 0.1
	p.global_position = deep
	var cold := _temperature(false)
	check(s.stream.in_nest_cave(deep) and cold < 36.7, "a generated cave interior chills the survivor")
	p.global_position = spring.spring_at
	check(s.stream.mineral_warmth(p.global_position) > 0.0 and _temperature(false) > cold + 0.4, "standing in the natural spring raises core temperature")
	s.bag.add("campfire",1)
	s.bag.add("wood",1)
	var placed := false
	for dz in range(4,9):
		for dx in range(-5,6):
			var spot := deep + Vector3(dx,0,dz)
			var cell := Vector3i(floori(spot.x),0,floori(spot.z))
			cell.y = roundi(s.stream.ground_at(WastelandConstruction.position_of(cell)))
			if not s.construction.place(cell,"campfire",0,0,p.global_position): continue
			p.global_position = WastelandConstruction.position_of(cell) + Vector3.RIGHT
			var before := _temperature(false)
			s.refuel(cell)
			check(s.campfire_warmth(p.global_position) > 0.0 and _temperature(false) > before + 0.1, "fueling a placed campfire warms the nearby survivor")
			placed = true
			break
		if placed: break
	check(placed, "the campfire fixture uses actual placement on the cave approach")
