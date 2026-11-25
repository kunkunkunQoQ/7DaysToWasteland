extends SceneTree

const Landscapes := preload("res://game/world/title_landscapes.gd")
const REGIONS := ["basin", "alpine", "desert", "canyon"]
const SPECIES := {"basin": "heron", "alpine": "argali", "desert": "jerboa", "canyon": "boar"}
var failed := 0
var capture := false
var app: Node
var pictures: Array[Image] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ")+text)
	if not ok: failed += 1

func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
	await process_frame

func _button(caption: String) -> Button:
	return app.front.shell.find_children("*","Button",true,false).filter(func(b):return b.text==caption)[0]

func _wait_for_terrain(stream: WastelandStream) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while not stream.queued.is_empty() or not stream.jobs.is_empty():
		if Time.get_ticks_msec() > deadline:
			_check(false, "scenery stream finished loading")
			return
		await process_frame

func _visible_ground_loaded(session: WastelandSession) -> bool:
	var camera := session.preview_camera
	var size := camera.get_viewport().get_visible_rect().size
	var origin := Vector2(camera.position.x, camera.position.z)
	for fraction: float in [0.04, 0.5, 0.96]:
		var ray := camera.project_ray_normal(size * Vector2(fraction, 0.68))
		var forward := Vector2(ray.x, ray.z).normalized()
		for depth: float in [24.0, 62.0]:
			if not session.stream.active.has(WastelandTerrainGen.chunk_at(origin + forward * depth)):
				return false
	return true

func _landscape_sample() -> Image:
	var image := root.get_texture().get_image()
	var size := Vector2(image.get_size())
	# The centre of the menu exposes the landscape between the buttons and the survivor.
	var sample := image.get_region(Rect2i(Vector2i(size * Vector2(0.42, 0.32)), Vector2i(size * Vector2(0.32, 0.48))))
	sample.resize(96, 54, Image.INTERPOLATE_BILINEAR)
	return sample

func _check_rendered_motion(label: String) -> void:
	await RenderingServer.frame_post_draw
	var first := _landscape_sample()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var second := _landscape_sample()
	var changed := 0
	for y in first.get_height():
		for x in first.get_width():
			var diff := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(diff.r), maxf(absf(diff.g), absf(diff.b))) > 0.025:
				changed += 1
	_check(changed > first.get_width() * first.get_height() * 0.01, label + " changes visible scenery pixels")

func _animal_pose(animal: Node3D) -> Array[Transform3D]:
	var pose: Array[Transform3D] = [animal.transform]
	for part: Node3D in animal.find_children("*", "Node3D", true, false):
		pose.append(part.transform)
	return pose

func _animal_silhouette(animal: Node3D, camera: Camera3D) -> Dictionary:
	# Keep cast shadows in the comparison frame so only the visible animal contributes.
	RenderingServer.force_draw(false)
	var visible_image := root.get_texture().get_image()
	var shadow_modes := {}
	for mesh: GeometryInstance3D in animal.find_children("*", "GeometryInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		shadow_modes[mesh] = mesh.cast_shadow
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mesh.hide()
		else:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	RenderingServer.force_draw(false)
	var hidden_image := root.get_texture().get_image()
	for mesh: GeometryInstance3D in shadow_modes:
		mesh.cast_shadow = shadow_modes[mesh]
		mesh.show()
	RenderingServer.force_draw(false)
	var restored_image := root.get_texture().get_image()
	var size := visible_image.get_size()
	var at := camera.unproject_position(animal.global_position) / camera.get_viewport().get_visible_rect().size
	var span := roundi(size.y * 0.25)
	var area := Rect2i(Vector2i(at * Vector2(size)) - Vector2i.ONE * span, Vector2i.ONE * span * 2)
	area = area.intersection(Rect2i(Vector2i.ZERO, size))
	var changed := 0
	var low := area.end
	var high := area.position
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var hidden_color := hidden_image.get_pixel(x, y)
			var diff := visible_image.get_pixel(x, y) - hidden_color
			var restored := restored_image.get_pixel(x, y) - hidden_color
			if maxf(diff.r * restored.r, maxf(diff.g * restored.g, diff.b * restored.b)) > 0.05 * 0.05:
				changed += 1
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return {"pixels": changed, "size": high - low + Vector2i.ONE if changed else Vector2i.ZERO}

func _check_wildlife(session: WastelandSession, label: String, region: String) -> void:
	var wildlife: Node3D = session.preview_wildlife
	if not is_instance_valid(wildlife) or wildlife.get_child_count() == 0:
		_check(false, label + " contains wildlife")
		return
	var poses := {}
	for animal: Node3D in wildlife.get_children():
		var route: Dictionary = animal.get("route")
		_check(route.species == SPECIES.get(region), label + " features " + str(route.species))
		poses[animal] = _animal_pose(animal)
	await create_timer(0.3).timeout
	for animal: Node3D in poses:
		var name_and_scene := label + " " + str(animal.name)
		_check(session.preview_camera.is_position_in_frustum(animal.global_position) and animal.is_visible_in_tree(), name_and_scene + " is in view")
		_check(_animal_pose(animal) != poses[animal], name_and_scene + " animates")
		if DisplayServer.get_name() != "headless":
			var silhouette := _animal_silhouette(animal, session.preview_camera)
			var scale_factor := root.size.y / 720.0
			var min_pixels := 800.0 if region == "desert" else 96.0
			var legible: bool = silhouette.pixels >= min_pixels * scale_factor * scale_factor
			if region == "desert":
				var size_at_720p := Vector2(silhouette.size) / scale_factor
				legible = legible and size_at_720p.x >= 24 and size_at_720p.y >= 40
			_check(legible, "%s visible silhouette %s, %d pixels" % [name_and_scene, silhouette.size, silhouette.pixels])

func _check_hidden_preview(session: WastelandSession) -> void:
	app.world_image.hide()
	await process_frame
	await process_frame
	var stopped := session.preview_time
	var wildlife: Node3D = session.preview_wildlife
	var pose := _animal_pose(wildlife)
	await process_frame
	await process_frame
	_check(session.preview_time == stopped and app.world_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden scenery suspends updates and drawing")
	_check(_animal_pose(wildlife) == pose, "hidden wildlife stops moving")
	app.world_image.show()
	await process_frame
	await process_frame
	_check(session.preview_time > stopped and _animal_pose(wildlife) != pose and app.world_view.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "showing the menu resumes the landscape and wildlife")

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	WastelandSave.root_override="user://verification/title-landscapes-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	app.options.display.dynamic = false
	await process_frame
	var session:WastelandSession=app.session
	var before: WeakRef = weakref(session)
	_check(session.preview_camera == app.world_view.get_camera_3d() and app.world_image.texture == app.world_view.get_texture(), "menu displays the active world camera")
	var expected := RandomNumberGenerator.new()
	var selected := {}
	_check(Landscapes.TITLES.size() == REGIONS.size() and not Landscapes.TITLES.any(func(title): return "山麓林场" in title), "title offers the four remaining landscapes")
	if capture:
		pictures.resize(Landscapes.TITLES.size())
	for seed_number in range(200):
		expected.seed=seed_number
		var id:=expected.randi_range(0,Landscapes.TITLES.size()-1)
		if selected.has(id): continue
		selected[id]=true
		app.front.cover_rng.seed=seed_number
		app.front.title(false)
		var label: String=Landscapes.TITLES[id]
		_check(app.front.landscape_index==id and session.preview_index==id and app.front.shell.find_children("*","Label",true,false).any(func(n):return n.text==label),label+" matches selected view")
		var initial:Vector3=session.preview_camera.position
		var hour:=session.clock.hours
		for i in 12: await physics_frame
		_check(session.preview_camera.position.distance_to(initial)>0.0001 and session.clock.hours!=hour,label+" camera and daylight move")
		var stream:=session.stream
		await _wait_for_terrain(stream)
		var gen:=stream.generator
		var at:=session.preview_eye
		var kind:=gen.region_kind(at.x,at.z)
		var target:=session.preview_target
		var physical:=stream.active.has(gen.chunk_at(Vector2(at.x,at.z))) and _visible_ground_loaded(session)
		var forward := Vector2(target.x - at.x, target.z - at.z).normalized()
		var behind := gen.chunk_at(Vector2(at.x, at.z) - forward * 85.0)
		_check(stream.active.size() < 49 and not stream.active.has(behind), "%s skips terrain behind the camera (%d active chunks)" % [label, stream.active.size()])
		if kind=="basin": physical=physical and stream.active.has(Vector2i.ZERO)
		if kind=="desert": physical=physical and gen.water_basin(target.x,target.z) and gen.ground(target.x,target.z)<0
		_check(physical and id < REGIONS.size() and kind==REGIONS[id],label+" uses its real terrain and bounded stream")
		if DisplayServer.get_name() != "headless":
			await _check_rendered_motion(label)
		await _check_wildlife(session, label, kind)
		if capture:
			var pic:=root.get_texture().get_image()
			pic.resize(768,432,Image.INTERPOLATE_LANCZOS)
			pic.convert(Image.FORMAT_RGBA8)
			pictures[id]=pic
		if selected.size()==Landscapes.TITLES.size(): break
	_check(selected.size()==REGIONS.size(),"all four menu views reachable")
	if DisplayServer.get_name() != "headless":
		await _check_hidden_preview(session)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,810)]:
		root.size=dimensions
		await process_frame
		await process_frame
		await _wait_for_terrain(session.stream)
		_check(_visible_ground_loaded(session), "visible ground reaches both sides at " + str(dimensions))
		var id:=session.preview_index
		await _click(_button("系统设置"))
		_check(app.front.screen=="settings","mouse opens settings at "+str(dimensions))
		if app.front.screen != "settings": continue
		await _click(_button("保存设置并返回"))
		_check(app.front.screen=="title" and session.preview_index==id,"settings keeps active landscape")
	if capture:
		var tile := pictures[0].get_size()
		var poster:=Image.create_empty(tile.x * 2, tile.y * ceili(pictures.size() / 2.0),false,Image.FORMAT_RGBA8)
		for i in pictures.size():
			poster.blit_rect(pictures[i], Rect2i(Vector2i.ZERO, tile), Vector2i(i % 2, i / 2) * tile)
		var folder := ProjectSettings.globalize_path("res://build/qa")
		var made_folder := DirAccess.make_dir_recursive_absolute(folder)
		_check(made_folder == OK and poster.save_png(folder.path_join("title-landscapes.png")) == OK, "saved the four landscape captures")
	var wildlife_ref: WeakRef = weakref(session.preview_wildlife)
	app._enter_world(app._default_config(),{},0,false)
	await process_frame
	_check(not is_instance_valid(before.get_ref()) and not app.session.preview_only and app.session.preview_camera==null,"entering gameplay releases scenery camera and preview session")
	_check(wildlife_ref.get_ref() == null and app.session.preview_wildlife == null, "entering gameplay releases the title animals")
	var gameplay: WastelandStream = app.session.stream
	var rear_corner := gameplay.center - Vector2i.ONE * gameplay.radius
	_check(gameplay.active.has(rear_corner) or gameplay.queued.has(rear_corner) or gameplay.jobs.has(rear_corner), "gameplay streams the full player neighbourhood")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.leave_world()
	await process_frame
	await process_frame
	_check(app.front.screen == "title" and app.front.visible and app.session.preview_only and app.world_view.get_camera_3d() == app.session.preview_camera, "leaving gameplay restores the live menu camera")
	_check(is_instance_valid(app.session.preview_wildlife) and app.session.preview_wildlife.get_child_count() > 0, "returning to the menu restores its wildlife")
	await app.session.stream.quiesce()
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
