extends "res://tools/verify_survivor_fall.gd"

var player: WastelandSurvivor

func run() -> void:
	WastelandSave.root_override = "user://verification/player-perspective-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 2817
	open_world({})
	session.options.storage_path = WastelandSave.root_override + "-options.cfg"
	session.options.load_options()
	player = session.player
	var floor_at := player.global_position + Vector3.UP * 12.0
	_slab(floor_at - Vector3.UP * 0.2, Vector3(16, 0.4, 16), false)
	player.global_position = floor_at + Vector3.UP * 0.06
	player.rotation.y = 0.0
	player.pitch = 0.0
	player.eyes.rotation.x = 0.0
	session.controls_enabled = true
	session.simulation_paused = false
	for tick in 55: await physics_frame
	var avatar := player.live_avatar
	var joint := avatar.active_motion.body_for(&"hips").get_rid()
	var shirt := avatar.undershirt
	var hidden := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	check(not player.third_person and player.camera.position.is_zero_approx() and player.hand.visible and shirt.cast_shadow == hidden, "new player starts at eye height with first-person hands")
	await _tap_view()
	for tick in 30: await physics_frame
	check(player.third_person and player.camera.position.z > 3.0 and player.camera.position.x > 0.5 and not player.hand.visible and shirt.cast_shadow != hidden and avatar.active_motion.body_for(&"hips").get_rid() == joint, "F5 reveals the same clothed physical body from the right shoulder")
	var stored := ConfigFile.new()
	check(stored.load(session.options.storage_path) == OK and stored.get_value("display","third_person",false), "camera preference survives a settings reload")

	var wall_at := player.eyes.global_position + Vector3.BACK * 1.28
	var wall := _aim_box(wall_at, Vector3(3.0, 3.0, 0.2))
	for tick in 3: await physics_frame
	var clearance := wall_at.z - 0.10 - player.camera.global_position.z
	check(clearance > 0.15 and clearance < 0.45 and player.camera.position.z > 0.60, "wall retracts the camera and clears its near plane (%.2f m)" % clearance)
	wall.free()
	await physics_frame
	check(player.camera.position.z < 2.65, "removing the wall eases the camera outward")
	for tick in 18: await physics_frame
	player.update_optics(0.35, true)
	check(player.camera.position.is_zero_approx() and not player.hand.visible and shirt.cast_shadow == hidden and player.camera.fov < 30.0, "binoculars look from eye level with no body in the lens")
	player.update_optics(0.35, false)
	check(player.third_person and player.camera.position.z > 2.9 and shirt.cast_shadow != hidden, "lowering binoculars restores shoulder view")
	await _tap_view()
	check(not player.third_person and player.camera.position.is_zero_approx() and player.hand.visible and shirt.cast_shadow == hidden, "second F5 restores the first-person render")
	await _tap_view()
	for tick in 40: await physics_frame
	await _verify_actions()
	await close_world()
	print("PLAYER PERSPECTIVE: %d passed, %d failed" % [passed, failures])
	quit(1 if failures else 0)

func _tap_view() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F5
	event.physical_keycode = KEY_F5
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for tick in 2: await physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame


func _verify_actions() -> void:
	var origin := player.action_origin()
	var ray := -player.camera.global_basis.z
	var eye := player.camera.global_position
	var crosshair := eye + ray * ((origin - eye).dot(ray) + 2.2)
	var target := _aim_box(crosshair, Vector3(0.18, 0.18, 0.16))
	for tick in 2: await physics_frame
	check(session._interaction_trace().get("collider") == target, "the shoulder crosshair selects a small target within arm's reach")
	check(session._trace(1.5, 3).is_empty(), "a short tool cannot reach the same target")

	var cover := _aim_box(origin.lerp(crosshair, 0.24), Vector3(0.16, 0.22, 0.12))
	for tick in 2: await physics_frame
	check(session._trace(3.0, 15, false, false, true).get("collider") == cover, "cover beside the shoulder intercepts a strike from the body")
	session.bag.set_loaded_rounds("pistol", 1)
	session._shoot("pistol", session.catalog.items.pistol)
	var fired := false
	for shot in session.fx.shots:
		if shot.kind != "bullet" or shot.owner != player: continue
		var start: Vector3 = shot.origin
		var path: Vector3 = shot.vel.normalized()
		var omit: Array[RID] = [player.get_rid(), cover.get_rid()]
		fired = start.distance_to(origin) < 0.025 and session.weapon_hit(start, start + path * 4.0, omit).get("collider") == target
		omit = [player.get_rid()]
		fired = fired and session.weapon_hit(start, start + path * 4.0, omit).get("collider") == cover
	check(fired, "the actual shot leaves the survivor on a line to the reticle and hits intervening cover")
	target.free()
	cover.free()

func _aim_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var box := StaticBody3D.new()
	box.collision_layer = 2
	WastelandLook.collider(box, size, Vector3.ZERO)
	session.add_child(box)
	box.global_position = at
	return box
