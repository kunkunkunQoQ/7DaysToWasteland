extends SceneTree

const Landscapes := preload("res://game/world/title_landscapes.gd")
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
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame

func _button(caption: String) -> Button:
	return app.front.shell.find_children("*","Button",true,false).filter(func(b):return b.text==caption)[0]

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	WastelandSave.root_override="user://verification/title-landscapes-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var session:WastelandSession=app.session
	var before: WeakRef = weakref(session)
	var expected := RandomNumberGenerator.new()
	var selected := {}
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
		var deadline := Time.get_ticks_msec()+20000
		while not stream.queued.is_empty() or not stream.jobs.is_empty():
			if Time.get_ticks_msec()>deadline: break
			await process_frame
		var gen:=stream.generator
		var at:=session.preview_eye
		var kind:=gen.region_kind(at.x,at.z)
		var target:=session.preview_target
		var physical:=stream.active.has(gen.chunk_at(Vector2(at.x,at.z))) and stream.active.size()==49
		var kinds:=["basin","taiga","alpine","desert","canyon"]
		if id==0: physical=physical and stream.active.has(Vector2i.ZERO)
		if id==1: physical=physical and stream.active[gen.starting_outpost("foothills")].site=="lodge"
		if id==3: physical=physical and gen.water_basin(target.x,target.z) and gen.ground(target.x,target.z)<0
		_check(physical and kind==kinds[id],label+" uses its real terrain and bounded stream")
		if capture:
			await RenderingServer.frame_post_draw
			var pic:=root.get_texture().get_image()
			pic.resize(480,270,Image.INTERPOLATE_LANCZOS)
			pic.convert(Image.FORMAT_RGBA8)
			if pictures.size()==0: pictures.resize(5)
			pictures[id]=pic
		if selected.size()==5: break
	_check(selected.size()==5,"all five menu views reachable")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,810)]:
		root.size=dimensions
		await process_frame
		var id:=session.preview_index
		await _click(_button("系统设置"))
		_check(app.front.screen=="settings","mouse opens settings at "+str(dimensions))
		await _click(_button("保存设置并返回"))
		_check(app.front.screen=="title" and session.preview_index==id,"settings keeps active landscape")
	if capture:
		var poster:=Image.create_empty(1440,540,false,Image.FORMAT_RGBA8)
		poster.fill(Color("#202827"))
		for i in pictures.size():
			poster.blit_rect(pictures[i],Rect2i(0,0,480,270),Vector2i(i%3*480+(240 if i>=3 else 0),i/3*270))
		poster.save_png("res://build/qa/title-landscapes.png")
	app._enter_world(app._default_config(),{},0,false)
	await process_frame
	_check(not is_instance_valid(before.get_ref()) and not app.session.preview_only and app.session.preview_camera==null,"entering gameplay releases scenery camera and preview session")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
