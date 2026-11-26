extends SceneTree

const Garment := preload("res://game/art/garment_motion.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func avatar() -> WastelandPartyAvatar:
	var person := WastelandPartyAvatar.new()
	person.show_tag = false
	root.add_child(person)
	person.wear_loadout({"back":"meme_shawl"})
	person.set_physics_process(false)
	return person

func garment(person: WastelandPartyAvatar, piece_name: StringName) -> Garment:
	for item in person.garment_motion:
		if item.piece.name == piece_name: return item
	return null

func uniform_motion(item: Garment) -> Vector4:
	var value: Variant = item.material.get_shader_parameter("hem_motion")
	return value if value is Vector4 else Vector4.ZERO

func run() -> void:
	var wearer := avatar()
	var other := avatar()
	var shawl := garment(wearer, &"meme_shawl")
	var second := garment(other, &"meme_shawl")
	check(shawl.piece.mesh == second.piece.mesh and shawl.material != second.material, "two wearers share geometry but own their cloth response")
	wearer._physics_process(STEP)
	other._physics_process(STEP)
	for tick in 15:
		wearer.position.x += 0.085
		wearer._physics_process(STEP)
	check(shawl.displacement.x < -0.01 and uniform_motion(shawl).x < -0.01, "the rendered shawl trails the wearer's motion")
	check(second.displacement.is_zero_approx() and uniform_motion(second) == Vector4.ZERO, "the stationary player's shawl stays still")
	for tick in 8:
		wearer.rotate_y(0.12)
		wearer._physics_process(STEP)
	check(absf(shawl.turn) > 0.015, "turning the torso twists its hanging hem")
	for tick in 100: wearer._physics_process(STEP)
	var resting := (shawl.previous_basis.transposed() * Vector3.DOWN - Vector3.DOWN) * 0.31 * shawl.reach
	check(shawl.at_rest and shawl.displacement.distance_to(resting) < 0.0002 and absf(shawl.turn) < 0.0005, "cloth relaxes to the upright character's slight natural lean")
	wearer.rotation.z = 1.0
	for tick in 120: wearer._physics_process(STEP)
	check(shawl.at_rest and shawl.displacement.length() > 0.012, "a tilted motionless wearer settles under gravity")
	wearer.position.z += 7
	wearer._physics_process(STEP)
	check(shawl.displacement == Vector3.ZERO and uniform_motion(shawl) == Vector4.ZERO, "teleport clears even a sleeping gravity offset")
	wearer.hide()
	check(not shawl.previous_pin.is_finite(), "hiding a wearer resets the sample history")
	wearer.show()
	wearer._physics_process(STEP)
	check(shawl.previous_pin.is_finite() and shawl.displacement.is_zero_approx(), "the first visible frame reseeds in place")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,1,55)
	camera.make_current()
	wearer._physics_process(STEP)
	check(not shawl.previous_pin.is_finite(), "out-of-range clothing suspends")
	camera.position.z = 13
	camera.look_at(wearer.position + Vector3.UP)
	wearer._physics_process(STEP)
	check(shawl.previous_pin.is_finite(), "approaching the wearer enables cloth again")
	camera.rotate_y(PI)
	wearer._physics_process(STEP)
	check(not shawl.previous_pin.is_finite(), "offscreen cloth suspends")
	camera.free()
	wearer.wear_loadout({"head":"alpine_cap","hands":"work_gloves","back":"meme_clock","body":"armor"})
	var clock := garment(wearer, &"meme_clock")
	check(clock != null and clock.rigid and garment(wearer, &"meme_shawl") == null, "changing equipment rebinds the correct hanging piece")
	check(garment(wearer, &"AlpineCap") != null and garment(wearer, &"WorkGlove") != null and garment(wearer, &"ArmorPlates") == null, "knitwear and leather flex while armor stays rigid")
	for tick in 20:
		wearer.position.x += 0.09
		wearer._physics_process(STEP)
	check(not clock.piece.basis.is_equal_approx(clock.rest_pose.basis) and (clock.piece.transform * clock.anchor).distance_to(clock.rest_pose * clock.anchor) < 0.00001, "the clock swings as one solid piece about its hook")
	wearer.free()
	other.free()
	if DisplayServer.get_name() != "headless": await rendered_hem()
	await process_frame
	print("GARMENT MOTION checks=%d failures=%d" % [checks,failures])
	quit(int(failures != 0))

func rendered_hem() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(400,400)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var cam := Camera3D.new()
	view.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.80
	cam.position = Vector3(0,-0.12,1.6)
	cam.environment = Environment.new()
	cam.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	cam.environment.ambient_light_color = Color.WHITE
	var holder := Node3D.new()
	view.add_child(holder)
	var piece := MeshInstance3D.new()
	piece.name = "meme_shawl"
	piece.mesh = preload("res://game/art/meme_gear.gd").mesh("meme_shawl")
	holder.add_child(piece)
	var motion := Garment.new(piece)
	await RenderingServer.frame_post_draw
	var before := view.get_texture().get_image()
	motion.step(STEP, false)
	for i in 10:
		holder.position.x += 0.14
		motion.step(STEP, false)
	# Track the wearer exactly, so the two images differ only by vertex deformation.
	cam.position.x = holder.position.x
	await RenderingServer.frame_post_draw
	var after := view.get_texture().get_image()
	var pin_row := floori(cam.unproject_position(holder.to_global(Vector3(0,-0.105,0))).y) - 2
	var fixed_pixels := 0
	var changed_collar := 0
	var changed_hem := 0
	for y in before.get_height():
		for x in before.get_width():
			var color := before.get_pixel(x,y)
			if y < pin_row and color.a > 0.9: fixed_pixels += 1
			if absf(color.a - after.get_pixel(x,y).a) < 0.2: continue
			if y < pin_row: changed_collar += 1
			else: changed_hem += 1
	check(fixed_pixels > 100 and changed_collar <= 3 and changed_hem > 120, "GPU silhouette keeps the collar fixed and moves the loose edge")
	print("Shawl silhouette: collar pixels=",fixed_pixels," changed collar=",changed_collar," changed hem=",changed_hem)
	view.free()
