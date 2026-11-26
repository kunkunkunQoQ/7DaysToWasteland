extends "res://tools/verify_harvest.gd"

const DT := 1.0 / 60.0
var frames_dir := ""
var frame_index := 0

func run() -> void:
	WastelandSave.root_override = "user://verification/survivor-fall-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 2817
	config.terrain_revision = 2
	var high_only := OS.get_cmdline_user_args().has("--high-only")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="): frames_dir = arg.trim_prefix("--frames=")
	if not frames_dir.is_empty() and (DisplayServer.get_name() == "headless" or DirAccess.make_dir_recursive_absolute(frames_dir) != OK):
		check(false, "frame capture requires a renderer and a writable destination")
		quit(1)
		return
	if not high_only:
		await _trial("stair", 0.28)
		await _trial("jump", 0.0)
		await _trial("low ledge", 2.15)
	await _trial("high ledge", 8.0)
	if not high_only: await _trial("deep water", 8.0)
	print("SURVIVOR FALL: %d passed, %d failed" % [passed, failures])
	quit(1 if failures else 0)

func _trial(label: String, height: float) -> void:
	open_world({})
	session.options.load_options()
	var player := session.player
	var water := label == "deep water"
	var film := label == "high ledge" and not frames_dir.is_empty()
	var origin := player.position
	if water:
		origin = _deep_water(origin)
		if not origin.is_finite():
			check(false, "find a deep-water landing in the seeded world")
			await close_world()
			return
	else:
		# The landing field is a level surface in the real world. The raised ledge ends at x=0.
		origin.y = maxf(session.stream.ground_at(origin), session.stream.ground_at(origin + Vector3.RIGHT * 9.0)) + 0.7
		_slab(origin + Vector3(3,-0.16,0), Vector3(19,0.32,8), film)
	session.stream.ensure_landing(origin)
	if height > 0.0: _slab(origin + Vector3(-1.5,height - 0.15,0), Vector3(3,0.3,2.0), false)
	if film: _scaffold(origin, height)
	player.global_position = origin + Vector3(-1.02, height + 0.06, 0)
	player.rotation.y = 0.0
	session.clock.hours = 12.0
	session.atmosphere.sync(session.clock, 1.0, player.position, Vector3.FORWARD, session.audio)
	for tick in 24:
		await physics_frame
		player.simulate(DT, false)
	var live := player.live_avatar
	if not is_instance_valid(live) or not is_instance_valid(live.active_motion):
		check(false, "standing survivor has a motor-driven physical body on " + label)
		await close_world()
		return
	check(player.is_on_floor(), label + " starts on a solid surface")
	var pelvis := live.active_motion.body_for(&"hips").get_rid()
	var ankle := live.active_motion.body_for(&"ankle_l").get_rid()
	var spectator: Camera3D
	if film:
		for mesh: GeometryInstance3D in live.find_children("*","GeometryInstance3D",true,false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		spectator = Camera3D.new()
		session.add_child(spectator)
		spectator.fov = 44.0
		spectator.position = player.position + Vector3(2.6, 3.2, -4.3)
		spectator.look_at(player.position + Vector3.UP * 0.85)
		spectator.make_current()
	var initial_hp := player.health
	var launched := false
	var released := false
	var uncontrolled := false
	var submerged_safely := false
	var reused := false
	var before_contact := true
	var noted_damage := false
	var regained := false
	var loss_height := INF
	var free_height := -1.0
	var free_speed := 0.0
	var max_spread := 0.0
	var max_brace := 0.0
	var compression := 0.0
	var apex := player.position.y
	var fastest := 0.0
	var after_land := 0
	var camera_target := player.position + Vector3.UP * 0.85
	if label == "jump": Input.action_press("jump")
	else: Input.action_press("right")
	for tick in 360:
		await physics_frame
		player.simulate(DT, true)
		if tick == 0 and label == "jump": Input.action_release("jump")
		if player.position.x > origin.x + 2.2: Input.action_release("right")
		var passive := player.ragdoll_body
		uncontrolled = uncontrolled or player.get("fall_uncontrolled") == true
		if is_instance_valid(passive):
			if not released:
				released = true
				free_height = passive.center().y - origin.y
				free_speed = passive.physics.body_for(&"hips").linear_velocity.y
				reused = passive.physics.body_for(&"hips").get_rid() == pelvis and passive.physics.body_for(&"ankle_l").get_rid() == ankle
			if passive.center().y - origin.y > 1.45 and player.health < initial_hp: before_contact = false
		else:
			apex = maxf(apex, player.position.y)
			fastest = maxf(fastest, -player.get_real_velocity().y)
			if released and not player.is_knocked_down(): regained = true
		max_spread = maxf(max_spread, live.gait.fall_spread)
		max_brace = maxf(max_brace, live.gait.fall_brace)
		compression = maxf(compression, live.gait.landing)
		if not player.is_on_floor(): launched = true
		if player.health < initial_hp and not noted_damage:
			noted_damage = true
			loss_height = passive.center().y - origin.y if is_instance_valid(passive) else player.position.y - origin.y
		if player.swimming and player.position.y < -0.65: submerged_safely = true
		if film and tick > 0 and tick % 2 == 0:
			var center := passive.center() if is_instance_valid(passive) else player.position + Vector3.UP * 0.85
			camera_target = camera_target.lerp(center, 0.32)
			_capture(spectator, camera_target, origin, player)
		if launched and (player.is_on_floor() or submerged_safely) and not player.is_knocked_down():
			after_land += 1
			if after_land >= 66: break
	Input.action_release("jump")
	Input.action_release("right")
	print("FALL ", label, " down %.2f m/s, released %.2f m (vy %.2f), brace %.2f / spread %.2f, damage %.2f at %.2f m" % [fastest,free_height,free_speed,max_brace,max_spread,initial_hp-player.health,loss_height])
	if label == "high ledge":
		check(launched and uncontrolled and released and free_height > 2.0 and free_speed < -5.0 and reused, "dangerous descent releases the same physical hips and ankle above ground with downward momentum")
		check(max_spread > 0.18, "arms begin to spread before the active motors release")
		check(before_contact and noted_damage and loss_height < 1.45, "the fall costs health on ground contact and preserves health during airborne release")
		var original_rig := is_instance_valid(live.active_motion) and live.active_motion.body_for(&"hips").get_rid() == pelvis and live.active_motion.body_for(&"ankle_l").get_rid() == ankle
		check(regained and player.health > 0.0 and not player.is_knocked_down() and original_rig, "the survivor gets up on the original physical hips and ankle after a nonlethal high fall")
	elif water:
		check(submerged_safely and not released and not uncontrolled and not noted_damage and max_brace < 0.30, "a high drop into deep water reaches swimming without bracing for the lakebed or taking ground injury")
	elif label == "low ledge":
		check(launched and not released and not noted_damage and max_spread > 0.10, "manageable drop spreads the arms while keeping the active rig and full health")
		check(player.is_on_floor() and absf(player.position.y-origin.y) < 0.16 and max_brace > 0.10 and compression > 0.06, "predicted solid ground brings the forearms forward and the knees absorb the landing")
	else:
		check(not released and not noted_damage and max_spread < 0.03 and max_brace < 0.03, "ordinary %s retains control and does not invoke the high-fall protective pose" % label)
		if label == "stair": check(player.is_on_floor() and player.position.x > origin.x + 0.5 and absf(player.position.y-origin.y) < 0.16, "the survivor steps off the upper slab onto the lower floor")
		if label == "jump": check(launched and apex - origin.y > 0.5 and compression > 0.025, "a normal jump lifts off and bends the knees on return")
	await close_world()

func _slab(center: Vector3, size: Vector3, visible_in_film: bool) -> void:
	var slab := StaticBody3D.new()
	slab.collision_layer = 2
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	slab.add_child(collision)
	if visible_in_film:
		var visual := MeshInstance3D.new()
		var deck := BoxMesh.new()
		deck.size = size
		visual.mesh = deck
		visual.material_override = session.construction._material(1)
		slab.add_child(visual)
	session.add_child(slab)
	slab.global_position = center

func _scaffold(origin: Vector3, height: float) -> void:
	for row in int(height):
		for x in 3:
			for z in 2:
				if row < int(height)-1 and x == 1: continue
				var block := MeshInstance3D.new()
				block.mesh = session.construction._mesh(0, 0, "", false)
				block.material_override = session.construction._material(0, 0, (row+x+z)%8)
				session.add_child(block)
				block.global_position = origin + Vector3(-0.5 - x, row + 0.5, z - 0.5)

func _deep_water(center: Vector3) -> Vector3:
	for radius in range(8, 120, 8):
		for i in 24:
			var a := TAU * float(i) / 24.0
			var p := center + Vector3(cos(a), 0, sin(a)) * radius
			p.y = 0
			var safe := true
			for dx: int in [-2, 0, 3, 6, 10]:
				var at := p + Vector3.RIGHT * dx
				if not session.stream.generator.water_basin(at.x,at.z) or session.stream.ground_at(at) > -3.5:
					safe = false
					break
			if safe: return p
	return Vector3.INF

func _capture(camera: Camera3D, at: Vector3, origin: Vector3, player: WastelandSurvivor) -> void:
	var above := clampf((at.y-origin.y)/8.0, 0.0, 1.0)
	camera.position = at + Vector3(2.3, 2.1, -3.8) * (1.0 + 0.18 * above)
	camera.position.y = maxf(camera.position.y, session.stream.ground_at(camera.position) + 1.4)
	camera.look_at(at)
	var visible_before := player.hand.visible
	player.hand.hide()
	RenderingServer.force_draw(false)
	var frame := root.get_texture().get_image()
	player.hand.visible = visible_before
	if frame.save_png(frames_dir.path_join("%03d.png" % frame_index)) != OK:
		check(false, "save the high-fall frame")
	frame_index += 1
