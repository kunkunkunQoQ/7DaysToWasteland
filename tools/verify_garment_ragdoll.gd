extends "res://tools/verify_harvest.gd"

const Motion := preload("res://game/art/garment_motion.gd")
const LOADOUT := {"head":"hardhat", "body":"armor", "back":"meme_shawl", "legs":"quilted_pants", "eyes":"meme_shades"}

var witness: Camera3D
var frames_dir := ""
var frame_number := 0

func run() -> void:
	WastelandSave.root_override = "user://verification/garment-ragdoll-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 2817
	config.terrain_revision = 2
	open_world({})
	session.options.load_options()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames_dir = arg.trim_prefix("--frames=")
	if not frames_dir.is_empty():
		if DisplayServer.get_name() == "headless" or DirAccess.make_dir_recursive_absolute(frames_dir) != OK:
			check(false, "frame export requires a renderer and a writable directory")
			await _finish_test()
			return
	var player := session.player
	session.bag.gear.merge(LOADOUT, true)
	session.clock.hours = 13.0
	session.atmosphere.sync(session.clock, 1.0, player.global_position, Vector3.FORWARD, session.audio)
	for i in 12:
		await physics_frame
		player.simulate(1.0 / Engine.physics_ticks_per_second, false)
	var live := player.live_avatar
	if not is_instance_valid(live) or not is_instance_valid(live.active_motion):
		check(false, "the playable survivor has a live articulated rig")
		await _finish_test()
		return
	var live_rig := live.active_motion
	var first := _cloth(live, &"meme_shawl")
	var first_plate := live.equipment.get_node_or_null("ArmorPlates") as MeshInstance3D
	if first == null or first_plate == null:
		check(false, "armor and shawl are present on the playable survivor")
		await _finish_test()
		return
	check(not live.undershirt.visible and first.piece.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "the armor hides the undershirt and the local player's shawl only casts shadows")
	# The optional spectator camera makes the first-person shadow body visible for the recording.
	if not frames_dir.is_empty():
		_setup_camera(player)
		for mesh: GeometryInstance3D in live.find_children("*", "GeometryInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Input.action_press("right")
	for i in 18:
		await physics_frame
		player.simulate(1.0 / Engine.physics_ticks_per_second, true)
		if i % 3 == 0: _capture(player.global_position + Vector3.UP * 0.85)
	Input.action_release("right")
	var donor := _snapshot(live)
	var left := _cloth(live, &"TrouserLeg", 0)
	var right := _cloth(live, &"TrouserLeg", 1)
	check(first.displacement.length() > 0.001 and first.previous_pin.is_finite(), "real player movement drives the standing shawl")
	check(left != null and right != null and left.piece.get_parent() == live.leg_rigs[0] and right.piece.get_parent() == live.leg_rigs[1], "left and right trouser legs bind to separate live skeletons")
	var before_head := live_rig.body_for(&"head").global_transform
	var before_hips := live_rig.body_for(&"hips").global_transform
	var health := player.health
	player.damage(35.0, "boar", player.global_position + Vector3.FORWARD, live_rig.center(), &"hips")
	var fallen := player.ragdoll_body
	check(player.ragdoll_mode == player.RagdollMode.KNOCKED_DOWN and health > player.health and is_instance_valid(fallen), "gameplay damage enters knockdown through SurvivorBody.spawn")
	if not is_instance_valid(fallen):
		await _finish_test()
		return
	var rig := fallen.physics
	var passive := fallen.avatar
	var shawl := _cloth(passive, &"meme_shawl")
	var plate := passive.equipment.get_node_or_null("ArmorPlates") as MeshInstance3D
	var hat := _helmet(passive)
	if shawl == null or plate == null or hat == null:
		check(false, "the fallen avatar rebuilt its shawl, helmet, and chest plates")
		await _finish_test()
		return
	check(rig.body_for(&"hips").global_transform.is_equal_approx(before_hips) and rig.body_for(&"head").global_transform.is_equal_approx(before_head), "passive hip and head rigid bodies start at the active rig's last transforms")
	check(_matches(passive, donor), "every matching cloth piece retains world-space displacement, velocity and twist on the first fallen frame")
	check(shawl.piece.mesh == first.piece.mesh and shawl.material != first.material and shawl.material.shader == first.material.shader, "both bodies share the shawl geometry and shader and hold separate spring uniforms")
	check(_cloth(passive, &"TrouserLeg", 0).piece.get_parent() == passive.leg_rigs[0] and _cloth(passive, &"TrouserLeg", 1).piece.get_parent() == passive.leg_rigs[1], "the fallen avatar retains the anatomical left/right order of identically named trouser legs")
	check(shawl.piece.visible and shawl.piece.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and not passive.undershirt.visible and not live.visible and passive.skull.has_node("meme_shades"), "the fallen body shows the same equipped layers and glasses while the first-person body is hidden")
	var plate_rest := plate.transform
	var hat_rest := hat.transform
	var change := 0.0
	var sampled := 0
	var maximum_pin_error := 0.0
	var after_push := Vector3.ZERO
	var push_change := 0.0
	var hip_start := rig.center()
	var plate_axes := plate.global_basis
	var rigid := true
	var previous := shawl.displacement
	var prior_pin := shawl.previous_pin
	var restored := false
	var dt := 1.0 / Engine.physics_ticks_per_second
	for tick in 240:
		await physics_frame
		var before_recovery := _snapshot(passive)
		player.simulate(dt, false)
		if not player.is_knocked_down():
			restored = _matches(live, before_recovery)
			break
		if tick == 30:
			var hand := rig.body_for(&"hand_r")
			var velocity := hand.linear_velocity
			var before_repeat := player.health
			player.damage(16.0, "claw", player.global_position + Vector3.LEFT, hand.global_position, &"hand_r")
			check(player.ragdoll_body == fallen and player.health < before_repeat and hand.linear_velocity.distance_to(velocity) > 0.25 and fallen.appearance.impact_bone == &"hand_r", "a second gameplay hit imparts velocity to the existing fallen right hand")
			after_push = shawl.displacement
		if tick > 30: push_change = maxf(push_change, after_push.distance_to(shawl.displacement))
		if not prior_pin.is_equal_approx(shawl.previous_pin):
			sampled += 1
			var anchor_frame := shawl.piece.get_parent_node_3d().global_transform * shawl.rest_pose
			maximum_pin_error = maxf(maximum_pin_error, shawl.previous_pin.distance_to(anchor_frame * shawl.anchor))
			prior_pin = shawl.previous_pin
		change = maxf(change, previous.distance_to(shawl.displacement))
		rigid = rigid and plate.transform.is_equal_approx(plate_rest) and hat.transform.is_equal_approx(hat_rest)
		if tick % 3 == 0: _capture(rig.center())
		if tick == 42:
			check(hip_start.y - rig.center().y > 0.15 and not plate.global_basis.is_equal_approx(plate_axes), "groundward hip travel and rotating chest plates come from the real falling rig")
	check(sampled >= 8 and maximum_pin_error < 0.001, "cloth sampled the written-back physical shoulder pose (%d moving samples, %.4f m error)" % [sampled, maximum_pin_error])
	check(change > 0.002 and push_change > 0.002, "the visible shawl changes throughout the fall and after the second hit (%.1f / %.1f mm)" % [change * 1000, push_change * 1000])
	check(rigid and plate.material_override == first_plate.material_override and hat.material_override == WastelandPartyAvatar.body_material and _cloth(passive, &"ArmorPlates") == null, "hard armor and the helmet stay rigid on their moving attachments")
	check(not player.is_knocked_down() and player.ragdoll_body == null and player.hand.visible and live.visible, "normal ground clearance and knockdown timeout return control to the live survivor")
	check(restored, "automatic recovery preserves the last passive spring state without swapping trouser sides")
	if not frames_dir.is_empty() and not player.is_knocked_down():
		for tick in 66:
			await physics_frame
			player.simulate(dt, false)
			if tick % 3 == 0: _capture(player.global_position + Vector3.UP * 0.85)
	if not player.is_knocked_down():
		await _strike_resting_corpse(player)
	await _finish_test()

func _strike_resting_corpse(player: WastelandSurvivor) -> void:
	# Falling debris has a primarily downward impulse so the body can settle on this hillside.
	player.camera.make_current()
	for tick in 6:
		await physics_frame
		player.simulate(1.0 / Engine.physics_ticks_per_second, false)
	player.damage(600.0, "debris", player.global_position + Vector3.LEFT)
	var corpse := player.ragdoll_body
	if not is_instance_valid(corpse) or not session.death_screen:
		check(false, "a lethal blow leaves a physical survivor corpse")
		return
	for tick in 720:
		await physics_frame
		if corpse.physics.is_settled(): break
	var shawl := _cloth(corpse.avatar, &"meme_shawl")
	var target := corpse.physics.body_for(&"torso").global_position
	var from := target + Vector3(2.0, 1.0, 0.10)
	var hit := session.weapon_hit(from, target, [player.get_rid()])
	var struck := hit.get("collider") as RigidBody3D
	if not corpse.physics.is_settled():
		check(false, "the corpse naturally settles on its support")
		return
	if not is_instance_valid(struck) or struck.get_parent() != corpse.physics:
		check(false, "a weapon ray reaches the settled corpse at %s (hit %s)" % [target, hit.get("collider")])
		return
	# Let the spring finish damping after the solver has put the limbs to sleep.
	for tick in 90: await physics_frame
	var initial := shawl.displacement
	var drift := 0.0
	for tick in 12:
		await physics_frame
		drift = maxf(drift, initial.distance_to(shawl.displacement))
	session.projectile_hit("arrow", 70.0, hit, null, from)
	check(not corpse.physics.is_settled() and struck.linear_velocity.length() > 1.0, "a projectile on the corpse collision layer wakes the struck rigid body")
	var response := 0.0
	for tick in 22:
		await physics_frame
		response = maxf(response, initial.distance_to(shawl.displacement))
	check(drift < 0.0005 and response > 0.001, "a rested shawl responds to the new impulse (%.3f mm before, %.2f mm after)" % [drift * 1000, response * 1000])

func _cloth(avatar: WastelandPartyAvatar, id: StringName, index := 0) -> Motion:
	for cloth in avatar.garment_motion:
		if cloth.piece.name == id:
			if index == 0: return cloth
			index -= 1
	return null

func _helmet(avatar: WastelandPartyAvatar) -> MeshInstance3D:
	for piece in avatar.sleeves:
		if piece.get_parent() == avatar.skull and piece.name != &"meme_shades": return piece
	return null

func _snapshot(avatar: WastelandPartyAvatar) -> Array:
	var rows := []
	for cloth in avatar.garment_motion:
		rows.append([cloth.piece.name, cloth.previous_basis * cloth.displacement, cloth.previous_basis * cloth.velocity, cloth.turn, cloth.turn_speed, cloth.previous_speed])
	return rows

func _matches(avatar: WastelandPartyAvatar, rows: Array) -> bool:
	if rows.size() != avatar.garment_motion.size() or rows.is_empty(): return false
	for i in rows.size():
		var cloth := avatar.garment_motion[i]
		var r: Array = rows[i]
		if cloth.piece.name != r[0] or not cloth.previous_pin.is_finite(): return false
		if (cloth.previous_basis * cloth.displacement).distance_to(r[1]) > 0.0001: return false
		if (cloth.previous_basis * cloth.velocity).distance_to(r[2]) > 0.0001: return false
		if absf(cloth.turn - r[3]) + absf(cloth.turn_speed - r[4]) > 0.0001 or not cloth.previous_speed.is_equal_approx(r[5]): return false
		var shader_motion: Vector4 = cloth.material.get_shader_parameter("hem_motion")
		if not shader_motion.is_equal_approx(Vector4(cloth.displacement.x, cloth.displacement.y, cloth.displacement.z, cloth.turn)): return false
	return true

func _setup_camera(player: WastelandSurvivor) -> void:
	for x in range(-1, 2):
		for z in range(-1, 2):
			session.stream.ensure_landing(player.global_position + Vector3(x, 0, z) * WastelandTerrainGen.SIZE)
	witness = Camera3D.new()
	session.add_child(witness)
	witness.fov = 32.0
	witness.global_position = player.global_position + player.global_basis * Vector3(-1.40, 2.8, 2.35)
	witness.global_position.y = maxf(witness.global_position.y, session.stream.ground_at(witness.global_position) + 1.7)
	witness.look_at(player.global_position + Vector3.UP * 0.95)
	witness.make_current()

func _capture(at: Vector3) -> void:
	if frames_dir.is_empty(): return
	witness.look_at(at)
	var hand_visible := session.player.hand.visible
	session.player.hand.hide()
	RenderingServer.force_draw(false)
	var screenshot := root.get_texture().get_image()
	session.player.hand.visible = hand_visible
	var error := screenshot.save_png(frames_dir.path_join("%03d.png" % frame_number))
	if error != OK: check(false, "save ragdoll screenshot %d" % frame_number)
	frame_number += 1

func _finish_test() -> void:
	await close_world()
	print("GARMENT RAGDOLL: %d passed, %d failed" % [passed, failures])
	quit(1 if failures else 0)
