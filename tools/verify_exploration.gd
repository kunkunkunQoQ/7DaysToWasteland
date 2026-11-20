extends SceneTree

var passed := 0
var failures := 0
var capture := false
var app: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("PASS ",what)
	else:
		failures += 1
		printerr("FAIL ",what)

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	WastelandSave.root_override = "user://verification/exploration-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	await process_frame
	await _wardrobe()
	var cfg: Dictionary = app._default_config()
	cfg.terrain_revision=2 # Historic Gray Bay coastal fixture.
	for terrain_seed: int in [int(cfg.seed), 182, -9251]:
		var gen := WastelandTerrainGen.new(terrain_seed,2)
		var original := WastelandTerrainGen.new(terrain_seed,1)
		var ridge := Vector2(34,-151+sin(34*0.026)*12)
		_check(gen.raw_height(ridge.x,ridge.y) - original.raw_height(ridge.x,ridge.y) > 20, "north ridge rises above the basin")
		var ford := gen.raw_height(gen.river_x(39),39)
		var pool := gen.raw_height(gen.river_x(98),98)
		_check(ford > -0.7 and ford < 0 and pool < -1.6, "ford connects the banks above the deep channel")
		_check(gen.water_basin(gen.river_x(98),98) and not original.water_basin(gen.river_x(98),98), "only new terrain has the inland waterway")
		_check(is_equal_approx(gen.raw_height(9,44),original.raw_height(9,44)),"starting camp approach remains dry")
	var legacy := cfg.duplicate()
	legacy.erase("terrain_revision")
	WastelandSave.write(1,{"settings":legacy})
	_check(WastelandSave.read(1).settings.terrain_revision == 1,"unversioned historical saves retain their terrain")
	app._enter_world(cfg,{},2,true)
	var session: WastelandSession = app.session
	for frame in 90: await physics_frame
	_check(WastelandSave.read(2).settings.terrain_revision == cfg.terrain_revision,"re-saved coastal world retains the selected historical terrain revision")
	var spot := Vector3(-18.6,0,50.5)
	var cell := WastelandTerrainGen.chunk_at(Vector2(spot.x,spot.z))
	var chunk: WastelandChunk = session.stream.active[cell]
	var boards := chunk.decoration_root.get_children().filter(func(node): return node.get_meta("kind","")=="trader")
	_check(boards.size()==1 and boards[0].get_child_count()>10,"lodge contains a mounted notice board")
	var route: Dictionary = app.hud.destination()
	_check(route.get("at") == WastelandSite.BOARD_POSITION,"a fresh survivor can follow the compass to the board")
	app.open_panel("trade")
	await _shot("13-notice-board")
	_check(app.panels.content.get_global_rect().end.y <= app.interface_root.size.y,"notice board fits inside the viewport")
	app.open_panel("survivor")
	await _shot("14-survivor")
	_check(is_instance_valid(app.panels.portrait) and app.panels.portrait.knees.size() == 2,"character sheet displays the articulated survivor")
	var picker: OptionButton = app.panels.content.find_child("OutfitPicker",true,false)
	for i in picker.item_count:
		picker.select(i)
		picker.item_selected.emit(i)
		var id: String = WastelandPartyAvatar.OUTFITS.keys()[i]
		_check(session.player.profile == id and session.player.hand.outfit == id and app.panels.portrait.outfit == id,"selected survivor reaches first and third person: "+id)
	app.open_panel("field")
	await _shot("15-field-notes")
	_check(app.panels.content.get_global_rect().end.y <= app.interface_root.size.y,"field journal fits inside the viewport")
	var guide: VBoxContainer = app.panels.body.get_children().filter(func(node): return node.get_script() == preload("res://game/ui/field_guide.gd"))[0]
	for group: String in ["野生动物","感染者"]:
		guide._populate(group)
		var ids: Array = WastelandHordes.KINDS.duplicate() if group == "感染者" else WastelandHordes.WILDLIFE.duplicate()
		if group == "野生动物": ids.append_array(guide.AQUATIC.keys())
		for id: String in ids:
			var forms := ["","armored","swift"] if group == "感染者" else ["","young","local"]
			if id == "heron": forms = ["","young"]
			if id in ["lake_fish","crayfish","pond_turtle"]: forms = ["","local"]
			for form: String in forms:
				guide._select(id,form)
				var mask := guide.details.find_child("AprilFace",true,false) as MeshInstance3D
				_check(is_instance_valid(mask) and mask.visible,"field guide preview has a live April face: "+id+" "+form)
				await process_frame
	app.close_overlay()
	if capture:
		var point := Vector3(27,-2.6,-14)
		session.stream.ensure_landing(point)
		session.player.global_position = point
		session.player.rotation.y = 0.0
		Input.action_press("crouch")
		for i in 95: await physics_frame
		Input.action_release("crouch")
		_check(session.player.submerged and session.player.breath < session.player.max_breath(),"diving triggers underwater visibility and the breath meter")
		var ruins := WastelandSunkenSites.landmarks(session.stream.generator)
		var wreck: Vector3 = ruins.ferry
		var view := wreck+Vector3(4.2,0.55,5.3)
		view.y = maxf(view.y,session.stream.ground_at(view)+0.10)
		session.player.global_position = view
		var look := wreck+Vector3.UP*1.08-session.player.camera.global_position
		session.player.rotation.y = atan2(-look.x,-look.z)
		session.player.pitch = asin(look.normalized().y)
		session.player.eyes.rotation.x = session.player.pitch
		await _shot("16-underwater")
		var vista := Vector3(-71,0,-27)
		session.stream.ensure_landing(vista)
		vista.y = session.stream.ground_at(vista) + 0.18
		session.player.global_position = vista
		session.player.rotation.y = -0.80
		session.player.pitch = -0.03
		session.player.eyes.rotation.x = session.player.pitch
		for i in 55: await physics_frame
		await _shot("17-ridge-and-lake")
	WastelandSave.delete_slot(1)
	WastelandSave.delete_slot(2)
	session.simulation_paused = true
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	print("EXPLORATION QA passed=%d failed=%d" % [passed,failures])
	quit(1 if failures else 0)

func _wardrobe() -> void:
	_check(not app.options.april_faces and app.options.appearance == "ranger","fresh preferences select original survivor and natural fauna")
	app.front.settings("title")
	var tabs := app.front.shell.find_children("*","TabContainer",true,false)[0] as TabContainer
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("外观与趣味"))
	var picker: OptionButton = app.front.shell.find_child("OutfitPicker",true,false)
	_check(picker.item_count == WastelandPartyAvatar.OUTFITS.size() and picker.item_count >= 7,"settings offer every selectable survivor")
	var avatar := tabs.find_children("*","Node3D",true,false).filter(func(node): return node is WastelandPartyAvatar)[0] as WastelandPartyAvatar
	var nickname:=tabs.find_child("PlayerNameInput",true,false) as LineEdit
	_check(nickname!=null,"appearance settings expose the independent player nickname")
	if nickname!=null:
		nickname.grab_focus()
		nickname.text="  岸边来客  "
		nickname.text_submitted.emit(nickname.text)
		_check(app.options.player_name=="岸边来客","Enter commits a trimmed nickname")
	var names:Dictionary={}
	var countries:Dictionary={}
	var meshes := []
	for i in picker.item_count:
		picker.select(i)
		picker.item_selected.emit(i)
		var id:=avatar.outfit
		var fixed_name:String=WastelandPartyAvatar.NAMES[id]
		var origin:String=WastelandPartyAvatar.ORIGINS[id]
		_check(not fixed_name.strip_edges().is_empty() and not names.has(fixed_name) and not origin.strip_edges().is_empty() and not WastelandPartyAvatar.STORIES[id].strip_edges().is_empty(),"survivor has a distinct fixed name, origin and story: "+id)
		names[fixed_name]=true
		countries[origin]=true
		_check(app.options.player_name=="岸边来客","changing survivor preserves the nickname: "+id)
		var face := avatar.find_child("SculptedFace",true,false) as MeshInstance3D
		var valid := face != null and face.material_override.albedo_texture != null and face.mesh not in meshes
		_check(valid,"unique textured three-dimensional face: "+avatar.outfit)
		if face != null: meshes.append(face.mesh)
		if avatar.outfit in ["surveyor","climber"]:
			var hair := avatar.find_child("StyledLocks",true,false) as MeshInstance3D
			_check(hair != null and hair.mesh != null and hair.mesh.get_surface_count() > 0,"swept hair and tied locks are present: "+avatar.outfit)
	_check(names.size()==picker.item_count and countries.size()==picker.item_count and names.has("杰伦·六码"),"all named survivors have distinct origins, including the Bronx survivor")
	var teammate:=WastelandPartyAvatar.new()
	root.add_child(teammate)
	teammate.set_player_name(app.options.player_name)
	for id:String in WastelandPartyAvatar.OUTFITS:
		teammate.apply_outfit(id)
		_check(teammate.name_tag.text.contains("岸边来客") and teammate.name_tag.text.contains(WastelandPartyAvatar.NAMES[id]),"party tag displays nickname with selected character name: "+id)
	teammate.queue_free()
	if nickname!=null:
		nickname.grab_focus()
		nickname.text="   "
		nickname.release_focus()
		_check(app.options.player_name=="幸存者","leaving a blank nickname restores the default")
		nickname.grab_focus()
		nickname.text="远渡"
		nickname.release_focus()
		_check(app.options.player_name=="远渡","focus loss commits an edited nickname")
	var toggle: CheckButton = tabs.find_children("*","CheckButton",true,false).filter(func(control): return control.text == "愚人节模式")[0]
	toggle.button_pressed = true
	await _shot("18-appearance")
	var avatar_style:=avatar.outfit
	app.front._settings_back()
	var stored := WastelandSettings.new()
	stored.storage_path = app.options.storage_path
	stored.load_options()
	_check(stored.player_name=="远渡","nickname reloads independently from the character profile")
	_check(stored.appearance == avatar_style and stored.april_faces,"character and April mode persist through the settings menu")
	await process_frame
	app.front.creation()
	var create_picker: OptionButton = app.front.shell.find_child("OutfitPicker",true,false)
	create_picker.select(1)
	create_picker.item_selected.emit(1)
	_check(app.options.player_name=="远渡","world creator keeps the saved nickname across character changes")
	_check(app.options.appearance == "ferryman","world creator selects the next survivor")

func _shot(title: String) -> void:
	for i in 4: await process_frame
	if capture:
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("res://build/qa/"+title+".png") == OK,"capture "+title)
