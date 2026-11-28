extends Node

const TouchControls := preload("res://game/ui/touch_controls.gd")

var options := WastelandSettings.new()
var catalog: WastelandCatalog
var world_view := SubViewport.new()
var hands_view := SubViewport.new()
var hands_camera := Camera3D.new()
var world_image := TextureRect.new()
var ui := CanvasLayer.new()
var ui_group := CanvasGroup.new()
var interface_root := Control.new()
var ui_paint := ShaderMaterial.new()
var pixel_paint := ShaderMaterial.new()
var hud := WastelandHUD.new()
var chat := preload("res://game/ui/chat_bar.gd").new()
var touch_controls: TouchControls
var shawl_subtitles := VBoxContainer.new()
var front := WastelandFront.new()
var panels := WastelandPanels.new()
var session: WastelandSession
var network := WastelandLan.new()
var pending_host_port := 0
var scene_height := 340
var frame_ms := 16.67
var monitor_time := 0.0
var low_periods := 0
var high_periods := 0
var load_in_progress := false
var boot_args: Array = []
var is_headless := false
var closing := false
var last_impact_level := Vector2.ZERO
var last_impact_tint := WastelandDamageFeedback.BASE_TINT
var submerged_env := Environment.new()
var water_light_band := -1

func _ready() -> void:
	get_tree().auto_accept_quit=false
	get_tree().quit_on_go_back=false
	var ui_font: FontFile = WastelandUIStyle.FONT
	ui_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	options.load_options()
	is_headless = DisplayServer.get_name() == "headless"
	if not is_headless:
		options.apply_display()
	catalog = WastelandCatalog.new()
	submerged_env.background_mode = Environment.BG_COLOR
	submerged_env.background_color = Color("#285d60")
	submerged_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	submerged_env.ambient_light_color = Color("#c4d9c7")
	submerged_env.ambient_light_energy = 0.85
	submerged_env.fog_enabled = true
	submerged_env.fog_light_color = Color("#467e77")
	submerged_env.fog_density = 0.035
	submerged_env.fog_sky_affect = 1.0
	network.name="Lan"
	network.game=self
	add_child(network)
	world_view.name = "PixelWorld"
	world_view.own_world_3d = true
	world_view.audio_listener_enable_3d = true
	world_view.msaa_3d = Viewport.MSAA_DISABLED
	world_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	world_view.use_taa = false
	world_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(world_view)
	_prepare_hands_view()
	world_image.name = "NearestNeighbour"
	world_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_image.stretch_mode = TextureRect.STRETCH_SCALE
	world_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_image.texture = world_view.get_texture()
	pixel_paint.shader = preload("res://shaders/palette.gdshader")
	pixel_paint.set_shader_parameter("lookup",WastelandLook.palette())
	pixel_paint.set_shader_parameter("hands_layer",hands_view.get_texture())
	world_image.material = pixel_paint
	add_child(world_image)
	add_child(ui)
	ui_group.name = "FrostedUI"
	ui_paint.shader = preload("res://shaders/ui_focus.gdshader")
	ui_group.material = ui_paint
	ui_group.fit_margin = 3.0
	ui_group.clear_margin = 3.0
	ui.add_child(ui_group)
	interface_root.name = "Interface"
	interface_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_group.add_child(interface_root)
	apply_ui_softness()
	hud.game = self
	interface_root.add_child(hud)
	hud.hide()
	if TouchControls.supported():
		touch_controls = TouchControls.new()
		touch_controls.name = "TouchControls"
		touch_controls.setup(self)
		hud.add_child(touch_controls)
	hud.add_child(chat)
	chat.submitted.connect(func(words: String): session.send_chat(words))
	chat.dismissed.connect(close_overlay)
	front.game = self
	interface_root.add_child(front)
	panels.game = self
	interface_root.add_child(panels)
	interface_root.add_child(shawl_subtitles)
	shawl_subtitles.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shawl_subtitles.alignment = BoxContainer.ALIGNMENT_END
	shawl_subtitles.grow_vertical = Control.GROW_DIRECTION_BEGIN
	shawl_subtitles.offset_top = -94
	shawl_subtitles.offset_bottom = -94
	shawl_subtitles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(resize_scene)
	resize_scene(true)
	boot_args = OS.get_cmdline_user_args()
	_show_title()

func _process(delta: float) -> void:
	if is_headless:
		return
	if is_instance_valid(session) and session.preview_only:
		var showing := world_image.is_visible_in_tree() and get_window().can_draw()
		var mode := Node.PROCESS_MODE_INHERIT if showing else Node.PROCESS_MODE_DISABLED
		if session.process_mode != mode:
			session.process_mode = mode
			world_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if showing else SubViewport.UPDATE_DISABLED
		if not showing:
			return
	_update_impact_vignette()
	frame_ms = lerpf(frame_ms, delta * 1000.0, 0.035)
	hud.last_frame_ms = frame_ms
	monitor_time += delta
	if monitor_time < 1.8:
		return
	monitor_time = 0.0
	if not options.display.dynamic or load_in_progress:
		return
	var target_ms := 1000.0 / maxf(30.0, float(options.display.fps))
	low_periods = low_periods + 1 if frame_ms > target_ms * 1.19 else 0
	high_periods = high_periods + 1 if frame_ms < target_ms * 1.075 else 0
	if low_periods >= 2 and scene_height > 238:
		scene_height = maxi(238,scene_height-34)
		low_periods = 0
		resize_scene()
	elif high_periods >= 6 and scene_height < int(options.display.pixel_height):
		scene_height = mini(int(options.display.pixel_height),scene_height+34)
		high_periods = 0
		resize_scene()

func _update_impact_vignette() -> void:
	var level := Vector2.ZERO
	if is_instance_valid(session) and is_instance_valid(session.player) and not session.death_screen and not session.simulation_paused:
		var player := session.player
		var underwater := player.submerged
		if player.third_person or player.is_knocked_down():
			var camera_at := player.camera.global_position
			var waterline := 0.035 if player.camera.environment == submerged_env else -0.065
			underwater = camera_at.y < waterline and session.stream.water_at(camera_at)
		if underwater != (player.camera.environment == submerged_env):
			player.camera.environment = submerged_env if underwater else null
			session.atmosphere.distant_basin.visible = not underwater
			pixel_paint.set_shader_parameter("underwater", underwater)
			session.audio.set_underwater(underwater)
			water_light_band = -1
		if underwater:
			var band := clampi(floori(-player.camera.global_position.y*2.0),0,36)
			var daylight := roundi(session.atmosphere.sun_strength*8)
			if band*10+daylight != water_light_band:
				water_light_band = band*10+daylight
				var deep := smoothstep(0,28,band)
				submerged_env.fog_density = lerpf(0.027,0.053,deep)
				submerged_env.fog_light_color = Color("#54887e").lerp(Color("#245759"),deep)
				submerged_env.ambient_light_energy = (0.65+daylight*0.079)*(1.0-deep*0.28)
		level.x = player.injury.pulse
		level.y = (1.0 - smoothstep(0.0,0.26,player.health / player.max_health())) * 0.57
		if player.injury.tint != last_impact_tint:
			last_impact_tint = player.injury.tint
			pixel_paint.set_shader_parameter("impact_color", last_impact_tint)
	if level != last_impact_level:
		last_impact_level = level
		pixel_paint.set_shader_parameter("impact_level", level)

func resize_scene(reset: bool = false) -> void:
	if reset:
		scene_height = int(options.display.pixel_height)
	var dimensions := get_viewport().get_visible_rect().size
	if dimensions.y <= 0.0:
		return
	interface_root.size = dimensions
	world_view.size = Vector2i(maxi(2,roundi(scene_height * dimensions.x / dimensions.y)),scene_height)
	hands_view.size=world_view.size
	hud.scale_height = scene_height

func apply_ui_softness() -> void:
	ui_paint.set_shader_parameter("strength",clampf(float(options.display.ui_softness),0.0,0.8))

func set_player_name(raw: String) -> void:
	var value := WastelandSettings.clean_player_name(raw)
	if options.player_name != value:
		options.player_name = value
		options.save_options()
		network.player_name_changed(value)

func set_appearance(id: String) -> void:
	if not WastelandPartyAvatar.OUTFITS.has(id):
		return
	options.appearance = id
	options.save_options()
	if is_instance_valid(session) and is_instance_valid(session.player):
		session.player.set_profile(id)
		var hand := session.player.hand
		hand.outfit = id
		hand.model_id = "?"
		var item := session.bag.current()
		hand.hold(item,catalog.items.get(item,{}))
	network.appearance_changed(id)

func show_depth_of_field(mode: int) -> void:
	pixel_paint.set_shader_parameter("backdrop",mode)

func _prepare_hands_view() -> void:
	hands_view.name="FirstPersonModel"
	hands_view.transparent_bg=true
	hands_view.own_world_3d=true
	hands_view.msaa_3d=Viewport.MSAA_DISABLED
	hands_view.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	hands_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(hands_view)
	hands_camera.fov=76.0
	hands_camera.near=0.05
	hands_camera.far=5.4
	hands_view.add_child(hands_camera)
	hands_camera.make_current()
	WastelandAtmosphere.add_outline(hands_view)

func _default_config() -> Dictionary:
	var config := WastelandSave.default_world()
	config.seed = WastelandSave.seed_number(str(config.seed_label))
	return config

func _show_title() -> void:
	network.stop()
	_remove_session()
	world_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	session = WastelandSession.new()
	world_view.add_child(session)
	var backdrop_world := _default_config()
	backdrop_world.seed = preload("res://game/world/title_landscapes.gd").SEED
	session.configure(backdrop_world,{},0,catalog,options,true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide()
	panels.hide()
	front.title()

func _remove_session() -> void:
	chat.reset()
	for subtitle in shawl_subtitles.get_children():
		shawl_subtitles.remove_child(subtitle)
		subtitle.queue_free()
	pixel_paint.set_shader_parameter("underwater", false)
	water_light_band = -1
	for instance in hands_camera.get_children():
		hands_camera.remove_child(instance)
		instance.queue_free()
	pixel_paint.set_shader_parameter("hands_visible",false)
	hands_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if is_instance_valid(session):
		hud.session = null
		world_view.remove_child(session)
		session.queue_free()
		session = null

func create_world(config: Dictionary, slot: int) -> void:
	if not load_in_progress:
		load_in_progress = true
		_enter_world.call_deferred(config,{},slot,true)

func open_world(slot: int) -> void:
	if load_in_progress:
		return
	var snapshot := WastelandSave.read(slot)
	if snapshot.is_empty():
		front.slots()
		return
	load_in_progress = true
	_enter_world.call_deferred(snapshot.settings,snapshot,slot,false)

func host_world(slot: int, port: int) -> void:
	if WastelandSave.read(slot).is_empty():
		connection_notice("无法读取所选世界")
		return
	pending_host_port=port
	open_world(slot)

func set_world_shared(enable: bool) -> Error:
	if not is_instance_valid(session) or session.preview_only or session.replica or session.slot<=0:
		return ERR_UNCONFIGURED
	var saved := session.save_now(false)
	if saved!=OK: return saved
	if enable:
		if network.server(): return OK
		var result := network.listen(WastelandLan.DEFAULT_PORT)
		if result==OK: session.simulation_paused=false
		return result
	network.stop()
	session.simulation_paused=front.visible
	return OK

func connection_notice(words: String) -> void:
	if front.visible and is_instance_valid(front.menu_notice):
		front.menu_notice.text=words
	else:
		_notify(words,4.0)

func _enter_world(config: Dictionary, snapshot: Dictionary, slot: int, save_initial: bool) -> void:
	_remove_session()
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	session = WastelandSession.new()
	world_view.add_child(session)
	session.configure(config,snapshot,slot,catalog,options)
	session.network=network
	session.player.hand.outfit = options.appearance
	session.player.hand.model_id = "?"
	session.player.hand.reparent(hands_camera,false)
	session.player.hand.visibility_changed.connect(_update_hands_view)
	_update_hands_view()
	session.message.connect(_notify)
	session.chat_received.connect(chat.receive)
	session.shawl_spoke.connect(_shawl_subtitle)
	session.panel.connect(open_panel)
	session.failed.connect(_failure)
	hud.tracked_marker_id = -1
	hud.tracked_expedition = ""
	hud.enter_world(session)
	hud.toast_left = 0.0
	close_overlay()
	load_in_progress = false
	if save_initial:
		var result := session.save_now(true)
		if result==OK and snapshot.is_empty():
			_notify("空拳打树会伤手，每拳损失 2 点生命，打岩石或金属伤得更重。按 [%s] 捡地上的枯枝和碎石。" % options.action_name("use"),5.5)
	if pending_host_port!=0:
		var port:=pending_host_port
		pending_host_port=0
		var error:=network.listen(port)
		_notify("局域网已开放 · 端口 %d" % port if error==OK else "开放联机失败 · 错误 %d" % error,5.0)

func _update_hands_view() -> void:
	var show_hands := is_instance_valid(session) and is_instance_valid(session.player) and session.player.hand.is_visible_in_tree()
	hands_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_hands else SubViewport.UPDATE_DISABLED
	pixel_paint.set_shader_parameter("hands_visible", show_hands)

func close_overlay() -> void:
	if session == null or session.preview_only:
		return
	_close_chest()
	chat.close_input()
	front.hide()
	panels.hide()
	hud.show()
	if touch_controls != null: touch_controls.show()
	show_depth_of_field(0)
	session.controls_enabled = true
	session.simulation_paused = false
	if not is_headless:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if TouchControls.supported() else Input.MOUSE_MODE_CAPTURED

func open_chat() -> void:
	if not is_instance_valid(session) or not session.controls_enabled or session.death_screen or not hud.visible:
		return
	session.controls_enabled = false
	session.reset_forward_taps()
	if touch_controls != null: touch_controls.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chat.open_input()

func leave_world() -> void:
	if is_instance_valid(session) and not session.preview_only and session.slot > 0:
		var error := session.save_now(false)
		if error != OK:
			_notify("保存失败 · 错误 %d" % error,4.0)
			if is_instance_valid(front.menu_notice):
				front.menu_notice.text = "保存失败 · 错误 %d" % error
			return
	_show_title.call_deferred()

func open_panel(id: String, context: Variant = null) -> void:
	if session == null or session.preview_only or session.death_screen:
		return
	if id == "":
		close_overlay()
		return
	if chat.editing: chat.close_input()
	if id!="chest": _close_chest()
	session.controls_enabled = false
	session.simulation_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	front.hide()
	hud.hide()
	show_depth_of_field(2)
	panels.show_panel(id,session,context)

func _close_chest() -> void:
	if panels.visible and panels.active=="chest" and panels.session==session:
		session.ui_command("chest_close",[panels.current_context])
		session.replica_chest={}

func _pause() -> void:
	if chat.editing: chat.close_input()
	session.controls_enabled = false
	session.simulation_paused = not network.active()
	hud.hide()
	panels.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	front.pause()

func _failure() -> void:
	chat.close_input()
	_close_chest()
	hud.hide()
	panels.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	front.died()

func _notify(words: String, duration: float) -> void:
	hud.say(words,duration)
	if panels.visible:
		panels.update_status(words,duration)

func _shawl_subtitle(words: String) -> void:
	if shawl_subtitles.get_child_count() >= 3:
		var oldest := shawl_subtitles.get_child(0)
		shawl_subtitles.remove_child(oldest)
		oldest.queue_free()
	var line := WastelandUIStyle.label(words, 17, Color("#f7dfae"))
	line.add_theme_font_override("font", WastelandUIStyle.FONT)
	line.add_theme_constant_override("outline_size", 6)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shawl_subtitles.add_child(line)
	var fade := line.create_tween()
	fade.tween_interval(3.2)
	fade.tween_property(line, "modulate:a", 0.0, 0.3)
	fade.tween_callback(line.queue_free)

func _input(event: InputEvent) -> void:
	if chat.editing:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close_overlay()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if is_instance_valid(session) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# The world SubViewport is displayed by a TextureRect. Mouse events belong to this window.
			session.mouse_look(event.screen_relative)
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(front) and front.visible and front.try_binding(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_echo() or session == null:
		return
	if hud.visible and session.controls_enabled and event.is_action_pressed("chat"):
		open_chat()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and not front.visible and not panels.visible and not get_viewport().gui_get_focus_owner() is LineEdit:
		session.forward_key(event)
	if event.is_action_pressed("pause_game"):
		_handle_back()
		get_viewport().set_input_as_handled()
	elif not front.visible:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		if event is InputEventKey and panels.visible and panels.active=="bag" and event.is_action_pressed("discard"):
			panels.discard_selected()
			get_viewport().set_input_as_handled()
			return
		var id := ""
		if event.is_action_pressed("inventory"): id = "bag"
		if event.is_action_pressed("map"): id = "map"
		if event.is_action_pressed("journal"): id = "journal"
		if id != "":
			if panels.visible and panels.active==id: close_overlay()
			else: open_panel(id)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_instance_valid(session):
		session.reset_forward_taps()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit.call_deferred()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(front) and front.visible and front.screen == "title":
			request_quit.call_deferred()
		else:
			_handle_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED and OS.has_feature("android"):
		if closing or load_in_progress or not is_instance_valid(session) or session.preview_only:
			return
		if session.controls_enabled and not session.death_screen:
			_pause()
		if session.replica:
			network.send_request("save", [])
		elif session.slot > 0:
			var result := session.save_now(false)
			if result != OK:
				_notify("后台保存失败 · 错误 %d" % result, 5.0)

func _handle_back() -> void:
	if closing or load_in_progress or not is_instance_valid(session):
		return
	if chat.editing:
		close_overlay()
	elif front.visible:
		front.handle_back()
	elif panels.visible and panels.active=="sources":
		panels.return_from_sources()
	elif panels.visible:
		close_overlay()
	else:
		_pause()

func request_quit() -> void:
	if closing:
		return
	closing=true
	load_in_progress=true
	if is_instance_valid(session):
		session.controls_enabled=false
		session.simulation_paused=true
		if not session.preview_only and not session.replica:
			session.save_now(false)
		await session.stream.quiesce()
		if is_instance_valid(session.audio):
			await session.audio.finish_playback()
	network.stop()
	get_tree().quit()
