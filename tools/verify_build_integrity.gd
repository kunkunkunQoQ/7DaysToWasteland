extends SceneTree

var s: WastelandSession
var con: WastelandConstruction
var failures := 0
var passed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures += 1
	print("PASS " if ok else "FAIL ", label)

func aim(cell: Vector3i) -> void:
	s.player.global_position = con.position_of(cell) + Vector3(0, -s.player.eyes.position.y, 2.0)
	s.player.rotation.y = 0.0
	s.player.pitch = 0.0
	s.player.eyes.rotation.x = 0.0
	await physics_frame

func run() -> void:
	WastelandSave.root_override = "user://verification/build-integrity-%d" % OS.get_process_id()
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	var flags := OS.get_cmdline_user_args()
	if "--host" in flags or "--guest" in flags:
		await check_party(app, "--host" in flags)
		quit(1 if failures else 0)
		return
	var cfg: Dictionary = app._default_config()
	cfg.seed = 2817
	cfg.spawn_roll = 644
	app._enter_world(cfg, {}, 1, false)
	s = app.session
	s.simulation_paused = true
	con = s.construction
	await physics_frame
	var home := s.start_position()
	s.bag.add("frame", 40)
	var base := Vector3i.ZERO
	var placed := false
	for i in 72:
		var p := home + Vector3.FORWARD.rotated(Vector3.UP, i * 2.39996) * (4.0 + i / 16.0)
		p.y = roundf(s.stream.ground_at(p))
		base = con.cell_at(p)
		if con.place(base, "frame", 0, 0, home):
			placed = true
			break
	check(placed, "place 50 HP wood frame on terrain")
	if not placed:
		quit(1)
		return
	check(con.blocks[base].hp == 50 and con.is_support_column(base), "wood frame and column classification")
	await aim(base)
	var count := s.bag.count("frame")
	s._use()
	check(not con.blocks.has(base) and s.bag.count("frame") == count + 1, "E recovers exactly one frame")
	s.player.global_position = home
	await physics_frame
	con.place(base, "frame", 0, 0, home)
	s.bag.add("stone_axe", 1)
	s.bag.assign("stone_axe", s.bag.active)
	s.bag.add("wood", 160)
	var intact: ShaderMaterial = con.nodes[base].get_child(0).material_override
	con.damage(base, 35)
	var info: Dictionary = con.blocks[base]
	var chipped: ShaderMaterial = con.nodes[base].get_child(0).material_override
	check(chipped.get_shader_parameter("wear_offset") == intact.get_shader_parameter("wear_offset")
		and chipped.get_shader_parameter("patina") == preload("res://game/art/weather_noise.tres"),
		"damage retains the block's weathered surface beneath its new cracks")
	check(con.crack_stage(info) == 2, "below 35 percent shows two crack branches")
	var wood := s.bag.count("wood")
	await aim(base)
	Input.action_press("alternate")
	await physics_frame
	s._process_controls(1.0 / 60.0)
	Input.action_release("alternate")
	check(not con.tool_jobs.is_empty() and info.hp == 15 and s.bag.count("wood") == wood, "right click begins a timed hammer strike")
	con.tick_work(0.25, "stone_axe")
	check(info.hp == 15 and s.hint.contains("%"), "progress appears before the repair hits")
	con.tick_work(0.30, "stone_axe")
	check(info.tier == 0 and info.hp == 25 and s.bag.count("wood") == wood - 1 and con.crack_stage(info) == 1, "repair spends one wood, clears deep crack, preserves tier")
	con.begin_work(base, "stone_axe")
	con.tick_work(1.0, "salvage_wrench")
	check(info.hp == 25 and s.bag.count("wood") == wood - 1, "switching tools cancels work without charging")
	for i in 3: con.upgrade(base)
	check(info.hp == 50 and con.crack_stage(info) == 0, "repairs stop at full health")
	check(con.nodes[base].get_child(0).material_override == intact, "full repair restores the same salvaged board finish")
	for tier in 4:
		for key: String in con.UPGRADE[tier]:
			s.bag.add(key, con.UPGRADE[tier][key])
		con.upgrade(base)
		check(info.tier == tier + 1 and info.hp == con.HP[tier + 1], "one material tier per completed strike %d" % (tier + 1))
	con.damage(base, 321)
	check(s.save_now(false) == OK, "write integrity version and current durability")
	var saved := WastelandSave.read(1)
	app._enter_world(saved.settings, saved, 1, false)
	s = app.session
	s.simulation_paused = true
	con = s.construction
	check(con.blocks[base].tier == 4 and con.blocks[base].hp == 4679, "disk reload keeps exact material and remaining health")
	var legacy := saved.duplicate(true)
	legacy.construction.erase("integrity_version")
	legacy.construction.blocks[base].hp = 1200.0
	app._enter_world(legacy.settings, legacy, 1, false)
	s = app.session
	s.simulation_paused = true
	con = s.construction
	check(con.blocks[base].tier == 4 and con.blocks[base].hp == 2500.0, "old steel record retains its half-health condition in the five-tier scale")
	s.player.global_position = home
	await physics_frame
	var cap := base + Vector3i.UP * 11
	var ok := true
	for level in range(1, 12):
		ok = con.place(base + Vector3i.UP * level, "frame", 0, 0, home) and ok
	con.upgrade(cap)
	check(ok and con.is_support_column(cap), "eleven vertical frame blocks transmit direct ground support")
	for step in range(1, 9):
		var cell := cap + Vector3i.RIGHT * step
		ok = con.place(cell, "frame", 0, 0, home) and ok
		con.upgrade(cell)
	check(ok and not con.is_support_column(cap + Vector3i.RIGHT) and con.blocks.has(cap + Vector3i.RIGHT * 8), "wood bearing supports eight 5-mass wood blocks")
	var ninth := cap + Vector3i.RIGHT * 9
	check(not con.place(ninth, "frame", 0, 0, home) and not con.blocks.has(ninth), "a ninth block exceeds the wood bearing capacity of 40")
	var victim_at := con.position_of(cap + Vector3i.RIGHT * 6) - Vector3.UP * 4.0
	var enemy_at := con.position_of(cap + Vector3i.RIGHT * 3) - Vector3.UP * 4.0
	s.player.global_position = victim_at
	s.player.invulnerable = 0.0
	s.hordes._spawn("walker", enemy_at, false)
	var enemy := s.hordes.alive.back() as WastelandCreature
	var health := s.player.health
	var enemy_hp := enemy.hp
	await physics_frame
	s.stream.nav_dirty.clear()
	con.damage(base + Vector3i.UP, 9999)
	check(not con.blocks.has(cap) and not con.blocks.has(cap + Vector3i.RIGHT * 8) and con.blocks.has(base), "cutting pillar drops beam and preserves surviving footing")
	var dirty := s.stream.nav_dirty.size()
	check(dirty >= 1 and dirty <= 2 and get_nodes_in_group("falling_structure").size() >= 8, "only affected navigation chunks and physical debris are produced")
	for i in 95: await physics_frame
	check(s.player.health < health and s.player.injury.last_source == "debris", "falling rigid beam damages the survivor by contact")
	check(enemy.hp < enemy_hp, "falling rigid beam damages an infected actor")
	await trap_checks(base + Vector3i.UP, home, enemy)
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.free()
	print("BUILD INTEGRITY ", passed, " passed / ", failures, " failed")
	quit(1 if failures else 0)

func trap_checks(cell: Vector3i, home: Vector3, enemy: WastelandCreature) -> void:
	s.player.global_position = home
	var center := con.position_of(cell)
	for id: String in ["spikes", "barbed"]:
		enemy.global_position = home + Vector3.RIGHT * 2.5
		await physics_frame
		s.bag.add(id, 1)
		if not con.place(cell, id, 0, 0, home):
			check(false, "place " + id)
			return
		var trap: Dictionary = con.blocks[cell]
		var old_hp := enemy.hp
		enemy.global_position = center + Vector3.DOWN * 0.05
		await physics_frame
		await physics_frame
		con._trap(cell, trap)
		check(enemy.hp < old_hp and enemy.trap_left > 0.9 and trap.hp < 260.0, id + " deals contact damage, slows actor and loses durability")
		var worn := float(trap.hp)
		con._trap(cell, trap)
		check(trap.hp == worn, id + " cannot deal another hit before the next period")
		if id == "spikes":
			enemy.global_position = home + Vector3.RIGHT * 2.5
			s.player.global_position = center
			s.player.invulnerable = 0.0
			var before := s.player.health
			s.clock.elapsed += 1.0
			await physics_frame
			await physics_frame
			con._trap(cell, trap)
			check(s.player.health < before and s.player.injury.last_source == "spikes", "stepping on wood spikes hurts and identifies the injury")
			s.player.global_position = home
		enemy.global_position = center
		await physics_frame
		await physics_frame
		trap.hp = 1.0
		s.clock.elapsed += 1.0
		con._trap(cell, trap)
		check(not con.blocks.has(cell), id + " breaks at zero durability")

func wait_for(condition: Callable, seconds := 12.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call(): return true
		await process_frame
	return false

func check_party(app: Node, hosting: bool) -> void:
	Engine.max_fps = 90
	if hosting:
		var cfg: Dictionary = app._default_config()
		cfg.seed = 2817
		cfg.spawn_roll = 644
		app._enter_world(cfg, {}, 1, false)
		s = app.session
		con = s.construction
		s.hordes.next_patrol = 99999
		s.hordes.next_herd = 99999
		var home := s.start_position()
		s.bag.add("frame", 2)
		s.bag.add("wood", 9)
		var base := Vector3i.ZERO
		await physics_frame
		for i in 72:
			var p := home + Vector3.FORWARD.rotated(Vector3.UP, i * 2.39996) * (4.0 + i / 16.0)
			p.y = roundf(s.stream.ground_at(p))
			base = con.cell_at(p)
			if con.place(base, "frame", 0, 0, home): break
		var wall := base + Vector3i.UP
		check(con.place(wall, "frame", 0, 0, home), "host places upper frame")
		con.damage(wall, 10.0)
		check(app.network.listen(19481) == OK, "construction loopback starts")
		if await wait_for(func(): return not app.network.joined_members().is_empty()):
			var guest: WastelandLan.MemberState = app.network.joined_members()[0]
			guest.bag.add("iron_hammer", 1)
			guest.bag.assign("iron_hammer", 3)
			guest.bag.active = 3
			guest.bag.add("wood", 9)
			var eye := con.position_of(wall) + Vector3.BACK * 2.1
			app.network.joined_members()[0].survivor.global_position = eye - Vector3.UP * app.network.joined_members()[0].survivor.eyes.position.y
			check(await wait_for(func(): return con.blocks[wall].tier == 1), "guest completes damaged-frame repair and upgrade on authority")
			check(guest.bag.count("wood") == 0 and s.bag.count("wood") == 9 and con.blocks[wall].hp == 250.0, "only the builder pays for the two strikes")
			await create_timer(1.4).timeout
			con.damage(base, 999.0)
			check(not con.blocks.has(wall), "host removes unsupported guest-built wall")
			await wait_for(func(): return app.network.joined_members().is_empty(), 6.0)
		else: check(false, "guest handshake")
	else:
		check(app.network.connect_to("127.0.0.1", 19481) == OK, "construction replica connects")
		if await wait_for(func(): return is_instance_valid(app.session) and app.session.replica and app.session.construction.blocks.size() == 2):
			s = app.session
			con = s.construction
			var wall: Vector3i = con.blocks.keys()[0]
			if con.blocks[wall].hp != 40.0: wall = con.blocks.keys()[1]
			var deadline := Time.get_ticks_msec() + 10000
			var next_click := 0
			while Time.get_ticks_msec() < deadline and con.blocks.has(wall) and con.blocks[wall].tier != 1:
				var offset := con.position_of(wall) - s.player.camera.global_position
				s.player.rotation.y = atan2(-offset.x, -offset.z)
				s.player.pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
				s.player.eyes.rotation.x = s.player.pitch
				if s.bag.current() == "iron_hammer" and Time.get_ticks_msec() >= next_click:
					Input.action_press("alternate")
					next_click = Time.get_ticks_msec() + 960
				elif Time.get_ticks_msec() > next_click - 840:
					Input.action_release("alternate")
				await physics_frame
			Input.action_release("alternate")
			check(con.blocks.has(wall) and con.blocks[wall].tier == 1 and con.blocks[wall].hp == 250.0, "replica receives upgraded material and HP")
			check(await wait_for(func(): return not con.blocks.has(wall) and get_node_count_in_group("falling_structure") > 0), "replica sees falling wall and invalidated grid after host cuts support")
		else: check(false, "guest receives block layout")
	app.network.stop()
	if is_instance_valid(s):
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.free()
